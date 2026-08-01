# Docker repo for backend + frontend images, and a separate repo for Helm charts pushed as
# OCI artifacts (Helm OCI push targets a DOCKER-format Artifact Registry repository).

resource "google_artifact_registry_repository" "docker_images" {
  project       = var.project_id
  location      = var.region
  repository_id = var.artifact_registry_docker_repo_id
  description   = "Docker images for employee-app backend and frontend, tagged by git commit SHA"
  format        = "DOCKER"

  depends_on = [google_project_service.apis]
}

resource "google_artifact_registry_repository" "helm_charts" {
  project       = var.project_id
  location      = var.region
  repository_id = var.artifact_registry_helm_repo_id
  description   = "Helm charts (backend, frontend) pushed as OCI artifacts"
  format        = "DOCKER"

  depends_on = [google_project_service.apis]
}
