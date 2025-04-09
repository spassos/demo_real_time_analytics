# Configuração da Rede VPC para acesso privado
resource "google_compute_network" "vpc_network" {
  project                 = var.project_id
  name                    = var.vpc_network_name
  auto_create_subnetworks = false
  depends_on              = [time_sleep.wait_compute_api]
}

resource "google_compute_subnetwork" "private_subnetwork" {
  name          = var.subnet_name
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc_network.id
  depends_on    = [google_compute_network.vpc_network]
}

# Cloud Router
resource "google_compute_router" "router" {
  name    = var.router_name
  region  = var.region
  network = google_compute_network.vpc_network.id
}

# Reservar IPs estáticos para o Cloud NAT
resource "google_compute_address" "nat_ip" {
  count   = var.nat_num_static_ips
  name    = "${var.nat_name}-ip-${count.index}"
  region  = var.region
  project = var.project_id

  depends_on = [time_sleep.wait_compute_api]
}

# Cloud NAT
resource "google_compute_router_nat" "nat" {
  name                               = var.nat_name
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = var.nat_ip_allocate_option
  nat_ips                            = google_compute_address.nat_ip.*.self_link
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Instância Cloud SQL PostgreSQL com IP público controlado
resource "google_sql_database_instance" "postgres_instance" {
  name             = var.instance_name
  database_version = "POSTGRES_15"
  region           = var.region
  project          = var.project_id

  settings {
    tier = var.db_tier

    # Configuração com IP público controlado
    ip_configuration {
      ipv4_enabled                                  = true  # Ativar IP público
      private_network                               = null  # Sem IP privado
      enable_private_path_for_google_cloud_services = false # Sem caminho privado

      # Configurar regras de autorização para permitir apenas o tráfego do Cloud NAT
      authorized_networks {
        name  = "cloud-nat"
        value = var.cloud_nat_cidr
      }

      # Adicionar IP da máquina executando Terraform
      authorized_networks {
        name  = "terraform-executor-ip"
        value = "${chomp(data.http.my_public_ip.response_body)}/32"
      }

      # Adicionar o IP estático do Cloud NAT às redes autorizadas
      dynamic "authorized_networks" {
        for_each = google_compute_address.nat_ip
        content {
          name  = "nat-static-ip-${authorized_networks.key}"
          value = "${authorized_networks.value.address}/32"
        }
      }
    }

    # Remover configuração de backup e HA para simplificar a demo

    database_flags {
      name  = "cloudsql.logical_decoding"
      value = "on"
    }

    database_flags {
      name  = "cloudsql.enable_pglogical"
      value = "on"
    }

    database_flags {
      name  = "max_replication_slots"
      value = "10"
    }

    database_flags {
      name  = "max_wal_senders"
      value = "10"
    }

    database_flags {
      name  = "cloudsql.iam_authentication"
      value = "on"
    }
  }

  # Simples dependência do firewall
  depends_on = [
    google_compute_firewall.allow_datastream_to_sql,
    google_compute_router_nat.nat
  ]

  deletion_protection = false
}

# Banco de dados dentro da instância
resource "google_sql_database" "database" {
  name     = var.db_name
  instance = google_sql_database_instance.postgres_instance.name
  project  = var.project_id
}

# Usuário do banco de dados
resource "google_sql_user" "db_user" {
  name     = var.db_user
  password = var.db_password
  instance = google_sql_database_instance.postgres_instance.name
  project  = var.project_id
}

# Espera após a criação do SQL para garantir que esteja pronto
resource "time_sleep" "wait_postgres_ready" {
  create_duration = "180s" # Ajuste conforme necessário
  depends_on = [
    google_sql_database_instance.postgres_instance,
    google_sql_user.db_user,
    google_sql_database.database
  ]
}

# VM para proxy reverso entre Datastream e Cloud SQL
resource "google_compute_instance" "proxy_vm" {
  name         = var.proxy_vm_name
  machine_type = var.proxy_vm_machine_type
  zone         = var.zone
  project      = var.project_id

  boot_disk {
    initialize_params {
      image = var.proxy_vm_image
    }
  }

  network_interface {
    network    = google_compute_network.vpc_network.id
    subnetwork = google_compute_subnetwork.private_subnetwork.id
    network_ip = "10.0.0.2" # IP interno fixo para a VM proxy
  }

  # Adicionar chave SSH se fornecida (mantido para acesso manual se necessário)
  metadata = {
    ssh-keys = var.ssh_public_key != "" ? "ubuntu:${var.ssh_public_key}" : null # Ajuste 'ubuntu' se necessário para o usuário/formato da chave
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
    set -e # Sair em erro
    set -x # Mostrar comandos

    # -- Variáveis (serão substituídas pelo Terraform) --
    DB_HOST="${google_sql_database_instance.postgres_instance.public_ip_address}"
    DB_USER="${var.db_user}"
    DB_PASSWORD="${var.db_password}"
    DB_NAME="${var.db_name}"
    STREAM_ID="${var.datastream_stream_id}"
    PG_PORT="${var.postgres_port}"
    PGSSLMODE="disable" # Ou require

    # -- Instalação de Pacotes --
    export DEBIAN_FRONTEND=noninteractive # Evitar prompts interativos
    echo "Waiting for apt locks..." 
    while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do 
      echo "... apt lock held, waiting..." ;
      sleep 2 ;
    done
    apt update -y
    apt install -y haproxy netcat postgresql-client

    # -- Configuração HAProxy --
    echo "Configuring HAProxy..."
    cat > /etc/haproxy/haproxy.cfg <<EOF
    global
        daemon
        maxconn 256
        log /dev/log local0 notice

    defaults
        mode tcp
        option tcplog
        log global
        timeout connect 10s
        timeout client 300s
        timeout server 300s
        option redispatch
        retries 3

    frontend pgsql_frontend
        bind 0.0.0.0:$PG_PORT
        default_backend pgsql_backend

    backend pgsql_backend
        # option pgsql-check user $DB_USER # Removido para teste
        # Usar health check TCP básico
        server cloudsql $DB_HOST:$PG_PORT check inter 5s fall 3 rise 2 maxconn 100
    EOF

    systemctl restart haproxy
    systemctl enable haproxy
    echo "HAProxy configured and started."

    # -- Finalização --
    echo "Startup script completed." > /tmp/startup_script.log
  EOT

  tags = [var.proxy_vm_tag]

  depends_on = [
    # VM depende do SQL estar pronto para pegar o IP publico no startup
    time_sleep.wait_postgres_ready,
    google_compute_router_nat.nat,
  ]
}

# Regra de Firewall para permitir o Datastream acessar o proxy (HAProxy na porta 5432)
resource "google_compute_firewall" "allow_datastream_to_sql" {
  project     = var.project_id
  name        = "allow-datastream-to-proxy"
  network     = google_compute_network.vpc_network.id
  description = "Permite conexões do Datastream para o servidor proxy (HAProxy)"

  direction = "INGRESS"

  # Permite tráfego da subnet de peering E do range público do Datastream
  source_ranges = [
    var.datastream_subnet_cidr, # Ex: 10.0.1.0/29
    var.datastream_ip_range     # Ex: 35.199.192.0/19
  ]

  allow {
    protocol = "tcp"
    ports    = [var.postgres_port] # Porta 5432
  }

  # Aplicar à VM com a tag correta
  target_tags = [var.proxy_vm_tag]

  priority = var.firewall_priority # Prioridade padrão

  depends_on = [
    google_compute_network.vpc_network
  ]
}

# Regra de Firewall para SSH para a VM Proxy (mantida para acesso manual)
data "http" "my_public_ip" {
  url = "https://ipv4.icanhazip.com" # Serviço para obter o IP público
}

resource "google_compute_firewall" "allow_ssh_to_vm" {
  name    = "allow-ssh-to-proxy"
  network = google_compute_network.vpc_network.id
  project = var.project_id

  direction = "INGRESS"
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # Permite acesso SSH apenas do IP da máquina que executa o Terraform
  source_ranges = ["${chomp(data.http.my_public_ip.response_body)}/32"]
  target_tags   = [var.proxy_vm_tag]
}

# Recurso nulo para executar o script de configuração de replicação
resource "null_resource" "setup_replication_script" {
  depends_on = [time_sleep.wait_postgres_ready]

  triggers = {
    # Re-executa se o script mudar ou os detalhes da conexão mudarem
    script_hash = filemd5("${path.module}/scripts/setup_replication.sql")
    db_host     = google_sql_database_instance.postgres_instance.public_ip_address
    db_name     = var.db_name
    db_user     = var.db_user
    # Não incluir a senha diretamente nos triggers por segurança
  }

  provisioner "local-exec" {
    # Executa psql para aplicar o script de configuração.
    # Requer que 'psql' esteja instalado e no PATH da máquina que executa Terraform.
    # -v ON_ERROR_STOP=1 garante que o script pare no primeiro erro.
    command = "psql -h ${google_sql_database_instance.postgres_instance.public_ip_address} -p ${var.postgres_port} -U ${var.db_user} -d ${var.db_name} -f \"${path.module}/scripts/setup_replication.sql\" -v ON_ERROR_STOP=1"

    environment = {
      # Passa a senha via variável de ambiente para segurança
      PGPASSWORD = var.db_password
    }

    # Opcional: Descomente e ajuste se psql não estiver no PATH padrão
    # interpreter = ["bash", "-c"]
  }
}

