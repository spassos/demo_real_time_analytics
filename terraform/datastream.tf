# Esperar pela estabilização da rede
resource "time_sleep" "wait_network_stable_for_datastream" {
  create_duration = "300s" # 5 minutos para garantir que o peering e rotas estejam estabelecidos
  depends_on = [
    google_datastream_private_connection.datastream_private_conn,
    google_compute_firewall.allow_datastream_to_sql, # Firewall para HAProxy
    google_compute_instance.proxy_vm # Espera a VM (e seu startup script completo) estar pronta
  ]
}

# Configuração da conexão privada do Datastream
resource "google_datastream_private_connection" "datastream_private_conn" {
  display_name          = "datastream-private-connection"
  location              = var.region
  private_connection_id = "datastream-private-conn-id"
  project               = var.project_id

  vpc_peering_config {
    vpc     = google_compute_network.vpc_network.id
    subnet  = var.datastream_subnet_cidr # CIDR reservado para o Datastream (ex: 10.0.1.0/29)
  }

  labels = var.labels

  depends_on = [
    time_sleep.wait_datastream_api,
    google_compute_network.vpc_network,
    # Depende da permissão IAM também
    time_sleep.wait_after_iam_permission
  ]
}

# Perfil de Conexão Datastream - Fonte (PostgreSQL)
resource "google_datastream_connection_profile" "pg_source_profile" {
  project               = var.project_id
  location              = var.region
  connection_profile_id = var.datastream_connection_profile_pg_id
  display_name          = "PostgreSQL Source Connection Profile (Private via Proxy)"

  postgresql_profile {
    # Conectar ao IP interno da VM Proxy via HAProxy
    hostname = google_compute_instance.proxy_vm.network_interface[0].network_ip # IP interno da VM (10.0.0.2)
    port     = var.postgres_port # Porta do HAProxy (5432)
    username = google_sql_user.db_user.name
    password = google_secret_manager_secret_version.db_password_version.secret_data
    database = google_sql_database.database.name
  }

  # Usar a conexão privada configurada acima
  private_connectivity {
    private_connection = google_datastream_private_connection.datastream_private_conn.id
  }

  depends_on = [
    # Depender da estabilização da rede/peering
    time_sleep.wait_network_stable_for_datastream,
    google_compute_instance.proxy_vm,
    google_datastream_private_connection.datastream_private_conn
  ]
}

# Tempo de espera após criação dos perfis
resource "time_sleep" "wait_after_profiles" {
  create_duration = "${var.wait_profiles_time}s"
  depends_on      = [
    google_datastream_connection_profile.pg_source_profile,
    google_datastream_connection_profile.bq_destination_profile
  ]
}

# Perfil de Conexão Datastream - Destino (BigQuery)
resource "google_datastream_connection_profile" "bq_destination_profile" {
  project               = var.project_id
  location              = var.region
  connection_profile_id = var.datastream_connection_profile_bq_id
  display_name          = "BigQuery Destination Connection Profile"

  labels = var.labels

  bigquery_profile {}

  depends_on = [
    time_sleep.wait_datastream_api, 
    google_project_service.bigquery
  ]
}

# Stream do Datastream (PostgreSQL para BigQuery)
resource "google_datastream_stream" "pg_to_bq_stream" {
  project                 = var.project_id
  location                = var.region
  stream_id               = var.datastream_stream_id
  display_name            = "PostgreSQL to BigQuery Stream"

  labels = var.labels

  source_config {
    source_connection_profile = google_datastream_connection_profile.pg_source_profile.id
    postgresql_source_config {
      include_objects {
        postgresql_schemas {
          schema = "public"
        }
      }
      publication = "ds_publication_for_${var.datastream_stream_id}"
      replication_slot = "ds_replication_slot_for_${var.datastream_stream_id}"
    }
  }

  destination_config {
    destination_connection_profile = google_datastream_connection_profile.bq_destination_profile.id
    bigquery_destination_config {
      data_freshness = var.datastream_data_freshness
      source_hierarchy_datasets {
         dataset_template {
            location = var.region
            dataset_id_prefix = var.bq_dataset_id
         }
      }
    }
  }

  desired_state = "RUNNING"

  backfill_all {
    postgresql_excluded_objects {
       postgresql_schemas {
         schema = ""
       }
    }
  }

  depends_on = [
    time_sleep.wait_after_profiles,
    google_datastream_connection_profile.pg_source_profile,
    google_datastream_connection_profile.bq_destination_profile,
    null_resource.setup_replication_script
  ]
} 