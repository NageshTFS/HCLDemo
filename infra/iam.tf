# Required project APIs, Workload Identity binding for the backend, and the least-privilege
# service accounts for Jenkins and the GKE node pool.

locals {
  required_apis = [
    "compute.googleapis.com",
    "container.googleapis.com",
    "sqladmin.googleapis.com",
    "servicenetworking.googleapis.com",
    "artifactregistry.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iap.googleapis.com",
  ]
}

resource "google_project_service" "apis" {
  for_each = toset(local.required_apis)

  project                    = var.project_id
  service                    = each.value
  disable_dependent_services = false
  disable_on_destroy         = false
}

############################
# Workload Identity: backend KSA -> GCP service account (roles/cloudsql.client)
############################

resource "google_service_account" "backend_workload_identity" {
  project      = var.project_id
  account_id   = "${var.name_prefix}-backend-wi"
  display_name = "employee-app backend Workload Identity SA (Cloud SQL client)"

  depends_on = [google_project_service.apis]
}

resource "google_project_iam_member" "backend_cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.backend_workload_identity.email}"
}

# Allows the Kubernetes ServiceAccount "backend" in namespace "employee-app-poc" to impersonate
# this GCP service account. The KSA itself (and its annotation
# iam.gke.io/gcp-service-account=<this SA email>) is created by the backend Helm chart, not here.
resource "google_service_account_iam_member" "backend_workload_identity_binding" {
  service_account_id = google_service_account.backend_workload_identity.name
  role                = "roles/iam.workloadIdentityUser"
  member              = "serviceAccount:${var.project_id}.svc.id.goog[${var.gke_namespace}/${var.backend_ksa_name}]"
}

############################
# Jenkins VM service account — least privilege, NOT project editor/owner/GKE admin.
############################

resource "google_service_account" "jenkins" {
  project      = var.project_id
  account_id   = "${var.name_prefix}-jenkins"
  display_name = "Jenkins CI/CD VM service account (least privilege)"

  depends_on = [google_project_service.apis]
}

resource "google_project_iam_member" "jenkins_artifact_registry_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.jenkins.email}"
}

# Deploy access to GKE workloads without full cluster-admin.
resource "google_project_iam_member" "jenkins_container_developer" {
  project = var.project_id
  role    = "roles/container.developer"
  member  = "serviceAccount:${google_service_account.jenkins.email}"
}

# Lets the pipeline's smoke-test / migration-adjacent tooling reach Cloud SQL via the Auth Proxy
# if ever needed from the Jenkins VM itself (in addition to the in-cluster Workload Identity path).
resource "google_project_iam_member" "jenkins_cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.jenkins.email}"
}

# Optional: grant specific operators IAP-tunneled SSH access to the Jenkins VM.
# Empty by default (var.iap_tunnel_admins) — nothing is granted until explicitly configured.
resource "google_project_iam_member" "iap_tunnel_admins" {
  for_each = toset(var.iap_tunnel_admins)

  project = var.project_id
  role    = "roles/iap.tunnelResourceAccessor"
  member  = each.value
}

############################
# GKE node pool service account — least privilege, NOT the default Compute Engine SA.
############################

resource "google_service_account" "gke_node" {
  project      = var.project_id
  account_id   = "${var.name_prefix}-gke-node"
  display_name = "employee-app-poc GKE node pool service account (least privilege)"

  depends_on = [google_project_service.apis]
}

resource "google_project_iam_member" "gke_node_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gke_node.email}"
}

resource "google_project_iam_member" "gke_node_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gke_node.email}"
}

resource "google_project_iam_member" "gke_node_monitoring_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.gke_node.email}"
}

# Nodes need to pull backend/frontend images from Artifact Registry.
resource "google_project_iam_member" "gke_node_artifact_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.gke_node.email}"
}
