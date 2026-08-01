terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # POC note: no backend configured yet — state is local by default, which is fine for
  # authoring but NOT for any real apply (no locking, no shared state, nothing durable).
  # Before the first real `terraform init`, configure a remote backend, e.g.:
  #
  # backend "gcs" {
  #   bucket = "REPLACE_WITH_A_REAL_TF_STATE_BUCKET"
  #   prefix = "employee-app-poc/infra"
  # }
  #
  # See infra/README.md for the full prerequisites/setup checklist.
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
  # Credentials: relies on Application Default Credentials
  # (`gcloud auth application-default login`) — nothing is hardcoded here.
}
