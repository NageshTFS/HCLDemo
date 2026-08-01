# VPC + subnet + Private Service Access (for Cloud SQL private IP) + Cloud NAT
# (GKE nodes have no public IP, so their egress needs NAT; the Jenkins VM has a public IP but
# still routes through the same NAT for its internal-subnet-sourced traffic).

resource "google_compute_network" "vpc" {
  project                 = var.project_id
  name                    = "${var.name_prefix}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"

  depends_on = [google_project_service.apis]
}

resource "google_compute_subnetwork" "subnet" {
  project                  = var.project_id
  name                     = "${var.name_prefix}-subnet"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true # lets private nodes/VM reach Google APIs (Artifact Registry, GCS, etc.) without a public IP

  secondary_ip_range {
    range_name    = var.pods_range_name
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = var.services_range_name
    ip_cidr_range = var.services_cidr
  }

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

############################
# Private Service Access (VPC peering) for Cloud SQL private IP
############################

resource "google_compute_global_address" "private_service_access_range" {
  project       = var.project_id
  name          = "${var.name_prefix}-psa-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id

  depends_on = [google_project_service.apis]
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_access_range.name]

  depends_on = [google_project_service.apis]
}

############################
# Cloud Router + Cloud NAT
# Needed because GKE nodes (enable_private_nodes) have no public IPs but still need outbound
# internet (pull base images, apt/gcloud updates, reach GitHub, etc.). The Jenkins VM has its
# own public IP for inbound (jenkins-vm.tf) but this doesn't change its outbound path.
############################

resource "google_compute_router" "router" {
  project = var.project_id
  name    = "${var.name_prefix}-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  project                             = var.project_id
  name                                = "${var.name_prefix}-nat"
  router                              = google_compute_router.router.name
  region                              = var.region
  nat_ip_allocate_option              = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat  = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

############################
# Firewall
############################

# Internal traffic within the VPC (subnet + GKE pod/service secondary ranges) — required
# because a custom-mode VPC has no implied allow-internal rule.
resource "google_compute_firewall" "allow_internal" {
  project = var.project_id
  name    = "${var.name_prefix}-allow-internal"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = [
    var.subnet_cidr,
    var.pods_cidr,
    var.services_cidr,
  ]
}

# SSH to the Jenkins VM only via IAP TCP forwarding — even though the VM has a public IP
# (jenkins-vm.tf, for the Jenkins/SonarQube UIs), port 22 is not opened to it at all; this also
# blocks SSH from other internal sources.
resource "google_compute_firewall" "allow_iap_ssh" {
  project = var.project_id
  name    = "${var.name_prefix}-allow-iap-ssh"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # Google-owned range used exclusively for IAP TCP forwarding.
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["jenkins"]
}

# Jenkins UI (:8080) — admin access + GitHub webhook delivery. The Jenkins VM has a public IP
# (jenkins-vm.tf), so this rule is live, not a placeholder: only these source ranges can reach
# port 8080 on the VM at all.
resource "google_compute_firewall" "allow_jenkins_admin_and_webhook" {
  project = var.project_id
  name    = "${var.name_prefix}-allow-jenkins-http"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  source_ranges = concat(var.jenkins_admin_ips, var.github_webhook_ip_ranges)
  target_tags   = ["jenkins"]
}

# SonarQube UI (:9000) — admin/browser access only. Unlike Jenkins, nothing external needs to
# reach SonarQube directly: the pipeline talks to it over localhost (both run on the same VM),
# so GitHub's webhook ranges are deliberately NOT included here.
resource "google_compute_firewall" "allow_sonarqube_admin" {
  project = var.project_id
  name    = "${var.name_prefix}-allow-sonarqube-http"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["9000"]
  }

  source_ranges = var.jenkins_admin_ips
  target_tags   = ["jenkins"]
}
