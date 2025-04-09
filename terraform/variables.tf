variable "project_id" {
  description = "O ID do seu projeto GCP."
  type        = string
}

variable "region" {
  description = "A região GCP onde os recursos serão criados."
  type        = string
}

variable "zone" {
  description = "A zona GCP onde alguns recursos serão criados."
  type        = string
}

variable "db_name" {
  description = "Nome do banco de dados PostgreSQL."
  type        = string
}

variable "db_user" {
  description = "Usuário do banco de dados PostgreSQL."
  type        = string
}

variable "db_password" {
  description = "Senha para o usuário do banco de dados PostgreSQL."
  type        = string
  sensitive   = true
  # Não defina um valor padrão para a senha no controle de versão!
  # Passe via -var="db_password=sua_senha_segura" ou um arquivo .tfvars
}

variable "instance_name" {
  description = "Nome da instância Cloud SQL."
  type        = string
}

variable "bq_dataset_id" {
  description = "ID do dataset do BigQuery."
  type        = string
}

variable "datastream_stream_id" {
  description = "ID do stream do Datastream."
  type        = string
}

variable "datastream_connection_profile_pg_id" {
  description = "ID do perfil de conexão do Datastream para o PostgreSQL."
  type        = string
}

variable "datastream_connection_profile_bq_id" {
  description = "ID do perfil de conexão do Datastream para o BigQuery."
  type        = string
}

variable "cloud_run_service_name" {
  description = "Nome do serviço Cloud Run para o gerador de dados."
  type        = string
  default     = "data-generator-service"
}

variable "db_password_secret_id" {
  description = "ID do segredo no Secret Manager para armazenar a senha do banco de dados."
  type        = string
  default     = "db-password-secret"
}

# Novas variáveis para valores anteriormente hardcoded

variable "vpc_network_name" {
  description = "Nome da rede VPC."
  type        = string
  default     = "private-network"
}

variable "subnet_name" {
  description = "Nome da sub-rede."
  type        = string
  default     = "private-subnetwork"
}

variable "subnet_cidr" {
  description = "Range CIDR da sub-rede."
  type        = string
  default     = "10.0.0.0/24"
}

variable "router_name" {
  description = "Nome do Cloud Router"
  type        = string
  default     = "cloud-router"
}

variable "nat_name" {
  description = "Nome do Cloud NAT"
  type        = string
  default     = "cloud-nat"
}

variable "cloud_nat_cidr" {
  description = "CIDR do Cloud NAT para regras de autorização."
  type        = string
  default     = "35.235.240.0/20"
}

variable "db_tier" {
  description = "Tier da instância Cloud SQL."
  type        = string
  default     = "db-f1-micro"
}

variable "proxy_vm_name" {
  description = "Nome da VM que irá atuar como proxy."
  type        = string
  default     = "sql-proxy-vm"
}

variable "proxy_vm_machine_type" {
  description = "Tipo de máquina para a VM proxy."
  type        = string
  default     = "e2-small"
}

variable "proxy_vm_image" {
  description = "Imagem a ser usada na VM proxy."
  type        = string
  default     = "debian-cloud/debian-11"
}

variable "proxy_vm_tag" {
  description = "Tag para a VM proxy."
  type        = string
  default     = "proxy-vm"
}

variable "datastream_subnet_cidr" {
  description = "Range CIDR dedicado para o Datastream."
  type        = string
  default     = "10.0.1.0/29"
}

variable "datastream_ip_range" {
  description = "Range de IPs potenciais usados pelo serviço Datastream."
  type        = string
  default     = "35.199.192.0/19"
}

variable "postgres_port" {
  description = "Porta usada pelo PostgreSQL."
  type        = number
  default     = 5432
}

variable "wait_postgres_proxy_time" {
  description = "Tempo de espera para PostgreSQL e proxy estarem prontos (em segundos)."
  type        = number
  default     = 180
}

variable "wait_network_time" {
  description = "Tempo de espera para estabilização da rede (em segundos)."
  type        = number
  default     = 180
}

variable "wait_profiles_time" {
  description = "Tempo de espera após criação dos perfis (em segundos)."
  type        = number
  default     = 30
}

variable "wait_compute_api_time" {
  description = "Tempo de espera após habilitar Compute API (em segundos)."
  type        = number
  default     = 60
}

variable "wait_datastream_api_time" {
  description = "Tempo de espera após habilitar Datastream API (em segundos)."
  type        = number
  default     = 180
}

variable "datastream_data_freshness" {
  description = "Valor de data_freshness para o Datastream."
  type        = string
  default     = "900s"
}

variable "firewall_priority" {
  description = "Prioridade para as regras de firewall."
  type        = number
  default     = 900
}

variable "labels" {
  description = "Labels a serem aplicados nos recursos."
  type        = map(string)
  default     = {
    demo = "gather_abril_sergio_passos"
  }
}

variable "ssh_public_key" {
  description = "Chave SSH pública para acesso à VM de proxy. Se vazia, nenhuma chave será adicionada."
  type        = string
  default     = ""
}

variable "db_availability_type" {
  description = "Tipo de disponibilidade da instância Cloud SQL (ZONAL ou REGIONAL)"
  type        = string
  default     = "ZONAL"
}

variable "nat_ip_allocate_option" {
  description = "Método de alocação de IPs para o Cloud NAT (MANUAL_ONLY ou AUTO_ONLY)"
  type        = string
  default     = "MANUAL_ONLY"
}

variable "nat_num_static_ips" {
  description = "Número de IPs estáticos a serem alocados para o Cloud NAT"
  type        = number
  default     = 1
}

# --- Cloud Scheduler Variables ---

variable "cloud_run_service_url" {
  description = "The full HTTPS URL of the deployed Cloud Run service to be triggered (e.g., https://service-name-hash-uc.a.run.app)."
  type        = string
  # No default, must be provided.
}

variable "scheduler_job_schedule" {
  description = "Cron schedule for the Cloud Scheduler job (e.g., '*/5 * * * *' for every 5 minutes)."
  type        = string
  default     = "*/5 * * * *"
}

variable "scheduler_job_name" {
  description = "Name for the Cloud Scheduler job."
  type        = string
  default     = "invoke-data-generator"
}

variable "scheduler_service_account_id" {
  description = "ID for the service account used by the Cloud Scheduler job."
  type        = string
  default     = "cloud-scheduler-invoker"
}