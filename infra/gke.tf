# GKE Standard (not Autopilot), single-zone cluster, one autoscaling node pool.
# Private nodes (no public node IPs); control-plane public endpoint restricted to admin IPs.

resource "google_container_cluster" "primary" {
  project  = var.project_id
  name     = var.gke_cluster_name
  location = var.zone # single zone, not a regional cluster

  # Manage nodes via a dedicated google_container_node_pool instead of the built-in default pool.
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = google_compute_network.vpc.id
  subnetwork = google_compute_subnetwork.subnet.id

  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false # public endpoint stays reachable, but gated below
    master_ipv4_cidr_block  = var.gke_master_ipv4_cidr_block
  }

  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.jenkins_admin_ips
      content {
        cidr_block   = cidr_blocks.value
        display_name = "admin-${cidr_blocks.key}"
      }
    }
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  release_channel {
    channel = "REGULAR"
  }

  # POC: no need to retain the cluster if it's torn down; flip this before anything durable
  # depends on it.
  deletion_protection = false

  # Cloud Logging/Monitoring left at GKE defaults (passive log capture only) —
  # matches ARCHITECTURE.md section 2/9: no dedicated observability stack for this POC.

  depends_on = [google_project_service.apis]
}

resource "google_container_node_pool" "primary_nodes" {
  project  = var.project_id
  name     = "${var.gke_cluster_name}-node-pool"
  location = var.zone
  cluster  = google_container_cluster.primary.name

  autoscaling {
    min_node_count = var.gke_node_min_count
    max_node_count = var.gke_node_max_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type    = var.gke_machine_type
    service_account = google_service_account.gke_node.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      mode = "GKE_METADATA" # required for Workload Identity
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    labels = {
      app         = "employee-app-poc"
      environment = var.environment
    }

    tags = ["gke-node"]
  }
}
