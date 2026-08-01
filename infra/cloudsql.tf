# Cloud SQL for PostgreSQL — private IP only (no public IP), reachable only from within the
# VPC (i.e. via the Cloud SQL Auth Proxy sidecar running in the backend pod on GKE).

resource "google_sql_database_instance" "postgres" {
  project             = var.project_id
  name                = "${var.name_prefix}-db"
  region              = var.region
  database_version    = var.db_version
  deletion_protection = var.db_deletion_protection

  settings {
    tier              = var.db_tier
    availability_type = "ZONAL" # POC: no cross-zone HA per ARCHITECTURE.md section 2

    ip_configuration {
      ipv4_enabled                                 = false # no public IP, ever
      private_network                              = google_compute_network.vpc.id
      enable_private_path_for_google_cloud_services = true
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7

      backup_retention_settings {
        retained_backups = 7
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day  = 7 # Sunday
      hour = 3
    }
  }

  # Private IP requires the VPC peering (Private Service Access) range to exist first.
  depends_on = [google_service_networking_connection.private_vpc_connection]
}

resource "google_sql_database" "employeedb" {
  project  = var.project_id
  name     = var.db_name
  instance = google_sql_database_instance.postgres.name
}

resource "google_sql_user" "app_user" {
  project  = var.project_id
  name     = var.db_user
  instance = google_sql_database_instance.postgres.name
  password = var.db_password
}
