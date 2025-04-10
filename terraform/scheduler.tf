# scheduler.tf

# Enable Cloud Scheduler API
resource "google_project_service" "scheduler" {
  project            = var.project_id
  service            = "cloudscheduler.googleapis.com"
  disable_on_destroy = false # Keep enabled
}

# Adicionar delay após habilitar Scheduler API
resource "time_sleep" "wait_scheduler_api" {
  create_duration = "60s"
  depends_on      = [google_project_service.scheduler]
}

# Service Account for the Scheduler job to invoke Cloud Run
resource "google_service_account" "scheduler_invoker" {
  project      = var.project_id
  account_id   = var.scheduler_service_account_id
  display_name = "Service Account for Cloud Scheduler Invoker"
}

# Cloud Scheduler Job to trigger the data generator endpoint
resource "google_cloud_scheduler_job" "invoke_data_generator" {
  project   = var.project_id
  region    = var.region # Scheduler jobs are regional
  name      = var.scheduler_job_name
  schedule  = var.scheduler_job_schedule
  time_zone = "Etc/UTC" # Or your preferred timezone

  http_target {
    http_method = "GET"
    uri         = "${var.cloud_run_service_url}/generate" # Target endpoint

    oidc_token {
      service_account_email = google_service_account.scheduler_invoker.email
      audience              = var.cloud_run_service_url # Audience is the base URL of the Cloud Run service
    }
  }

  # Optional: Configure retry behavior
  retry_config {
    retry_count = 3
  }

  depends_on = [
    time_sleep.wait_scheduler_api,
    google_service_account.scheduler_invoker
    # Implicit dependency on the Cloud Run service existing, but not managed here.
  ]
}