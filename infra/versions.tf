terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # Partial backend config on purpose: bucket/prefix are supplied at `terraform init` time via
  # -backend-config flags (see infra/Jenkinsfile stage 2, and jenkins-vm-manual-setup.md step 2
  # for creating the bucket), not hardcoded here — a real bucket name shouldn't sit in git, and
  # this way the same config works whether you're running init from the pipeline or locally
  # with your own -backend-config flags. Requires the bucket to already exist (Terraform can't
  # create the bucket it's about to store its own state in).
  backend "gcs" {}
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
  # Credentials: relies on Application Default Credentials
  # (`gcloud auth application-default login` locally, or GOOGLE_APPLICATION_CREDENTIALS set to
  # a service account key file — see infra/Jenkinsfile) — nothing is hardcoded here.
}
