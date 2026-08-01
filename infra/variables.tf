############################
# Core / project
############################

variable "project_id" {
  description = "Real GCP project ID to provision into. No default on purpose — must be supplied explicitly (tfvars/-var/CI variable), never hardcoded."
  type        = string
}

variable "region" {
  description = "GCP region for regional resources (subnet, Cloud SQL, Artifact Registry, Cloud NAT/Router)."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone for the single-zone GKE cluster and the Jenkins VM. Must fall within `region`."
  type        = string
  default     = "us-central1-a"
}

variable "name_prefix" {
  description = "Prefix applied to all resource names for this POC (keeps resources identifiable/groupable)."
  type        = string
  default     = "employee-app-poc"
}

variable "environment" {
  description = "Environment label applied to resources."
  type        = string
  default     = "poc"
}

############################
# Networking
############################

variable "subnet_cidr" {
  description = "Primary IP range for the GKE/Jenkins subnet."
  type        = string
  default     = "10.10.0.0/20"
}

variable "pods_range_name" {
  description = "Name of the secondary IP range used for GKE pod IPs (VPC-native cluster)."
  type        = string
  default     = "gke-pods"
}

variable "pods_cidr" {
  description = "Secondary IP range for GKE pods."
  type        = string
  default     = "10.20.0.0/16"
}

variable "services_range_name" {
  description = "Name of the secondary IP range used for GKE service IPs (VPC-native cluster)."
  type        = string
  default     = "gke-services"
}

variable "services_cidr" {
  description = "Secondary IP range for GKE services."
  type        = string
  default     = "10.30.0.0/20"
}

variable "gke_master_ipv4_cidr_block" {
  description = "/28 CIDR for the GKE private control-plane endpoint. Must not overlap any other range in the VPC."
  type        = string
  default     = "172.16.0.0/28"
}

variable "jenkins_admin_ips" {
  description = <<-EOT
    CIDR blocks (e.g. "203.0.113.4/32") allowed to reach the Jenkins VM's HTTP(S) port and the
    GKE public control-plane endpoint (kubectl). Also used as the firewall source for the
    Jenkins admin-access rule. Must be supplied explicitly — empty by default so nothing is
    accidentally left open.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.jenkins_admin_ips : can(cidrhost(c, 0))])
    error_message = "Each entry in jenkins_admin_ips must be a valid CIDR block, e.g. \"203.0.113.4/32\"."
  }
}

variable "github_webhook_ip_ranges" {
  description = <<-EOT
    CIDR blocks for GitHub's webhook ("hooks") source IPs, allowed to reach the Jenkins VM's
    webhook listener port. GitHub's published ranges change over time and are NOT hardcoded
    here — fetch the current list from https://api.github.com/meta (the "hooks" key) before
    applying and pass it via tfvars/CI variable. Empty by default.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.github_webhook_ip_ranges : can(cidrhost(c, 0))])
    error_message = "Each entry in github_webhook_ip_ranges must be a valid CIDR block."
  }
}

############################
# GKE
############################

variable "gke_cluster_name" {
  description = "Name of the GKE Standard cluster."
  type        = string
  default     = "employee-app-poc-gke"
}

variable "gke_machine_type" {
  description = "Machine type for the single GKE node pool."
  type        = string
  default     = "e2-standard-2"
}

variable "gke_node_min_count" {
  description = "Minimum node count for the autoscaling node pool."
  type        = number
  default     = 1
}

variable "gke_node_max_count" {
  description = "Maximum node count for the autoscaling node pool."
  type        = number
  default     = 3
}

variable "gke_namespace" {
  description = "Kubernetes namespace the app is deployed into. The namespace object itself is created by Helm/kubectl, not Terraform — this is only used here to build the Workload Identity member string."
  type        = string
  default     = "employee-app-poc"
}

variable "backend_ksa_name" {
  description = "Name of the Kubernetes ServiceAccount (created by the backend Helm chart) that is bound to the backend's GCP service account via Workload Identity."
  type        = string
  default     = "backend"
}

############################
# Cloud SQL
############################

variable "db_version" {
  description = "Cloud SQL PostgreSQL engine version."
  type        = string
  default     = "POSTGRES_15"
}

variable "db_tier" {
  description = "Cloud SQL machine tier. Small custom tier is sufficient for POC load."
  type        = string
  default     = "db-custom-1-3840"
}

variable "db_name" {
  description = "Application database name."
  type        = string
  default     = "employeedb"
}

variable "db_user" {
  description = "Application DB user (distinct from the Postgres superuser)."
  type        = string
  default     = "employeeapp"
}

variable "db_password" {
  description = "Password for the application DB user. No default — must be supplied via a gitignored tfvars file or a CI secret variable, never committed."
  type        = string
  sensitive   = true
}

variable "db_deletion_protection" {
  description = "Whether Cloud SQL deletion protection is enabled. Default false for POC ease of teardown; flip to true before this is anything but a throwaway environment."
  type        = bool
  default     = false
}

############################
# Artifact Registry
############################

variable "artifact_registry_docker_repo_id" {
  description = "Artifact Registry repository ID for backend + frontend Docker images."
  type        = string
  default     = "employee-app"
}

variable "artifact_registry_helm_repo_id" {
  description = "Artifact Registry repository ID for Helm charts pushed as OCI artifacts."
  type        = string
  default     = "employee-app-charts"
}

############################
# Jenkins VM
#
# NOT consumed by any resource in this module — the Jenkins VM is created manually, not by
# Terraform (see jenkins-vm-manual-setup.md), to avoid the bootstrap problem of Jenkins having
# to create the VM it runs on. These four variables are kept only as the documented reference
# values that manual setup guide's `gcloud compute instances create` command uses — change them
# here AND in the command you actually run, they don't stay in sync automatically.
############################

variable "jenkins_machine_type" {
  description = "Reference value for the Jenkins GCE VM's machine type — see jenkins-vm-manual-setup.md."
  type        = string
  default     = "e2-medium"
}

variable "jenkins_boot_image_family" {
  description = "Reference value for the Jenkins GCE VM's boot image family (--image-family) — see jenkins-vm-manual-setup.md."
  type        = string
  default     = "ubuntu-2404-lts-amd64"
}

variable "jenkins_boot_image_project" {
  description = "Reference value for the Jenkins GCE VM's boot image project (--image-project) — see jenkins-vm-manual-setup.md."
  type        = string
  default     = "ubuntu-os-cloud"
}

variable "jenkins_boot_disk_size_gb" {
  description = "Reference value for the Jenkins GCE VM's boot disk size (GB, needs headroom for Docker images, SonarQube, build workspaces) — see jenkins-vm-manual-setup.md."
  type        = number
  default     = 100
}

variable "iap_tunnel_admins" {
  description = "Optional list of IAM members (e.g. \"user:alice@example.com\", \"group:admins@example.com\") granted roles/iap.tunnelResourceAccessor for IAP-tunneled SSH to the Jenkins VM. Empty by default — grant explicitly per operator."
  type        = list(string)
  default     = []
}
