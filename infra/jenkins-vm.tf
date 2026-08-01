# Jenkins CI/CD VM — has a public IP (deliberate trade-off, chosen for direct browser access
# to Jenkins :8080 and SonarQube :9000 without an IAP tunnel). SSH still IAP-tunnel-only,
# least-privilege service account, HTTP restricted to admin IPs (+ GitHub webhook ranges on
# 8080 only) — see networking.tf. Jenkins and SonarQube run as native services on this VM
# (see jenkins-startup.sh), not in Docker — Docker itself is still installed, but only for the
# pipeline's own `docker build`/`push`/Trivy/Gitleaks steps.

resource "google_compute_instance" "jenkins" {
  project      = var.project_id
  name         = "${var.name_prefix}-jenkins"
  zone         = var.zone
  machine_type = var.jenkins_machine_type
  tags         = ["jenkins"]

  boot_disk {
    initialize_params {
      image = var.jenkins_boot_image
      size  = var.jenkins_boot_disk_size_gb
      type  = "pd-balanced"
    }
  }

  network_interface {
    network    = google_compute_network.vpc.id
    subnetwork = google_compute_subnetwork.subnet.id

    # Ephemeral public IP so Jenkins (:8080) and SonarQube (:9000) are reachable directly at
    # <this IP>:<port> from a browser — see infra/outputs.tf's jenkins_vm_external_ip and
    # jenkins/README.md. Access is still gated by the firewall rules below (admin IPs only,
    # except GitHub's webhook ranges on 8080), not by IP obscurity.
    access_config {}
  }

  service_account {
    email = google_service_account.jenkins.email
    # Broad "cloud-platform" scope is standard practice here: the actual authorization boundary
    # is the SA's IAM role bindings (iam.tf), not the OAuth scope.
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = {
    enable-oslogin = "TRUE" # IAM-managed SSH (IAP tunnel), no baked-in SSH keys
  }

  metadata_startup_script = file("${path.module}/jenkins-startup.sh")

  allow_stopping_for_update = true

  labels = {
    app         = "employee-app-poc"
    role        = "jenkins"
    environment = var.environment
  }

  depends_on = [google_project_service.apis]
}
