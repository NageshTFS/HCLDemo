output "network_name" {
  description = "VPC network name."
  value       = google_compute_network.vpc.name
}

output "subnet_name" {
  description = "Subnet name."
  value       = google_compute_subnetwork.subnet.name
}

output "gke_cluster_name" {
  description = "GKE cluster name."
  value       = google_container_cluster.primary.name
}

output "gke_cluster_endpoint" {
  description = "GKE cluster control-plane endpoint (public, but restricted via master_authorized_networks)."
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}

output "gke_cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate, for kubeconfig generation."
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "cloudsql_instance_name" {
  description = "Cloud SQL instance name."
  value       = google_sql_database_instance.postgres.name
}

output "cloudsql_connection_name" {
  description = "Cloud SQL instance connection name (PROJECT:REGION:INSTANCE) — feed this into the Cloud SQL Auth Proxy sidecar / Helm values.cloudsql.instanceConnectionName."
  value       = google_sql_database_instance.postgres.connection_name
}

output "cloudsql_private_ip_address" {
  description = "Cloud SQL private IP address."
  value       = google_sql_database_instance.postgres.private_ip_address
}

output "artifact_registry_docker_repo_url" {
  description = "Artifact Registry Docker repo URL (backend + frontend images) — REGION-docker.pkg.dev/PROJECT_ID/REPO."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.docker_images.repository_id}"
}

output "artifact_registry_helm_repo_url" {
  description = "Artifact Registry OCI repo URL for Helm charts — oci://REGION-docker.pkg.dev/PROJECT_ID/REPO."
  value       = "oci://${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.helm_charts.repository_id}"
}

output "jenkins_vm_internal_ip" {
  description = "Jenkins VM internal IP (used for the GitHub webhook / kubectl / VPC-internal access)."
  value       = google_compute_instance.jenkins.network_interface[0].network_ip
}

output "jenkins_vm_external_ip" {
  description = "Jenkins VM public IP — browse http://<this>:8080 (Jenkins) and http://<this>:9000 (SonarQube). Only reachable from var.jenkins_admin_ips (+ var.github_webhook_ip_ranges on :8080), per the firewall rules in networking.tf."
  value       = google_compute_instance.jenkins.network_interface[0].access_config[0].nat_ip
}

output "jenkins_service_account_email" {
  description = "Jenkins VM's GCP service account email."
  value       = google_service_account.jenkins.email
}

output "backend_workload_identity_sa_email" {
  description = "GCP service account bound to the backend KSA via Workload Identity — annotate the Kubernetes ServiceAccount \"backend\" in namespace \"employee-app-poc\" with iam.gke.io/gcp-service-account=<this value>."
  value       = google_service_account.backend_workload_identity.email
}
