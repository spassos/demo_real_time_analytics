terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
  required_version = ">= 1.0"
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Obter informações do projeto para usar o project_number
data "google_project" "project" {
  project_id = var.project_id
}

# Blocos de habilitação de API removidos novamente para evitar erro de permissão 'serviceusage.services.list'.
# !!! IMPORTANTE: HABILITE MANUALMENTE AS SEGUINTES APIS NO SEU PROJETO GCP ANTES DO APPLY !!!
# - compute.googleapis.com
# - sqladmin.googleapis.com
# - servicenetworking.googleapis.com
# - bigquery.googleapis.com
# - datastream.googleapis.com

# Nota: APIs para Cloud Run, Artifact Registry, Cloud Build não foram readicionadas neste momento,
# podem ser incluídas se a implantação do Cloud Run for gerenciada pelo Terraform.

# Blocos de habilitação de API removidos conforme solicitado.
# Certifique-se de que as seguintes APIs estejam habilitadas manualmente no projeto:
# - sqladmin.googleapis.com
# - compute.googleapis.com
# - servicenetworking.googleapis.com
# - bigquery.googleapis.com
# - datastream.googleapis.com
# - run.googleapis.com
# - artifactregistry.googleapis.com
# - cloudbuild.googleapis.com

# --- Habilitação de APIs ---

# Habilitar Compute Engine API
resource "google_project_service" "compute" {
  project = var.project_id
  service = "compute.googleapis.com"
  disable_on_destroy = true # Desabilitar ao destruir
}

# Adicionar delay após habilitar Compute API
resource "time_sleep" "wait_compute_api" {
  create_duration = "${var.wait_compute_api_time}s"
  depends_on      = [google_project_service.compute]
}

# Habilitar Cloud SQL Admin API
resource "google_project_service" "sqladmin" {
  project = var.project_id
  service = "sqladmin.googleapis.com"
  disable_on_destroy = true # Desabilitar ao destruir
}

# Habilitar Cloud DNS API (recomendado para PSC)
resource "google_project_service" "dns" {
  project = var.project_id
  service = "dns.googleapis.com"
  disable_on_destroy = true # Desabilitar ao destruir
}

# Habilitar BigQuery API
resource "google_project_service" "bigquery" {
  project = var.project_id
  service = "bigquery.googleapis.com"
  disable_on_destroy = false # Alterado para false para evitar erro de dependência
}

# Habilitar Datastream API
resource "google_project_service" "datastream" {
  project = var.project_id
  service = "datastream.googleapis.com"
  disable_on_destroy = true # Desabilitar ao destruir
}

# Adicionar delay após habilitar Datastream API
resource "time_sleep" "wait_datastream_api" {
  create_duration = "${var.wait_datastream_api_time}s"
  depends_on      = [google_project_service.datastream]
}

# Habilitar Secret Manager API
resource "google_project_service" "secretmanager" {
  project            = var.project_id
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false # Manter habilitada
}

# Adicionar delay após habilitar Secret Manager API
resource "time_sleep" "wait_secretmanager_api" {
  create_duration = "180s"
  depends_on      = [google_project_service.secretmanager]
}

# Adicionar permissão IAM para o Datastream acessar o Cloud SQL
resource "google_project_iam_member" "datastream_cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-datastream.iam.gserviceaccount.com"
  
  depends_on = [
    google_project_service.datastream
  ]
}

# Adicionar uma espera extra após a concessão da permissão IAM para garantir propagação
resource "time_sleep" "wait_after_iam_permission" {
  create_duration = "60s"
  depends_on      = [google_project_iam_member.datastream_cloudsql_client]
}
