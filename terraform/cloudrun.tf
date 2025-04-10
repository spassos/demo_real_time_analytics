# cloudrun.tf
resource "google_secret_manager_secret" "db_password" {
  project   = var.project_id
  secret_id = var.db_password_secret_id

  replication {
    user_managed {
      replicas {
        location = "us-central1"
      }
    }
  }
}

resource "google_secret_manager_secret_version" "db_password_version" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = var.db_password


  lifecycle {
    create_before_destroy = true
  }
}


locals {
  compute_engine_sa_email = "${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}

resource "google_secret_manager_secret_iam_member" "cloud_run_secret_accessor" {
  project   = google_secret_manager_secret.db_password.project
  secret_id = google_secret_manager_secret.db_password.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${local.compute_engine_sa_email}"

  depends_on = [google_secret_manager_secret.db_password]
}

resource "google_project_iam_member" "cloud_run_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${local.compute_engine_sa_email}"
}

# --- Serviço Cloud Run (REMOVIDO - Será implantado manualmente) --- 

# Habilitar API do Cloud Run (Mantido)
resource "google_project_service" "run" {
  project                    = var.project_id
  service                    = "run.googleapis.com"
  disable_dependent_services = true
  disable_on_destroy         = false # Manter API habilitada ao destruir
}

# Adicionar delay após habilitar Cloud Run API (Opcional mas recomendado)
resource "time_sleep" "wait_run_api" {
  create_duration = "60s"
  depends_on      = [google_project_service.run]
}

# Habilitar API do Cloud Build (Adicionado)
resource "google_project_service" "cloudbuild" {
  project                    = var.project_id
  service                    = "cloudbuild.googleapis.com"
  disable_dependent_services = true
  disable_on_destroy         = false # Manter API habilitada ao destruir
}

# Adicionar delay após habilitar Cloud Build API (Adicionado)
resource "time_sleep" "wait_cloudbuild_api" {
  create_duration = "60s"
  depends_on      = [google_project_service.cloudbuild]
}
