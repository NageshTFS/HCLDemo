# infra/ — Terraform (authored, not applied)

This Terraform provisions the base GCP infrastructure for the Employee Management POC:
VPC/subnet + Private Service Access + Cloud NAT, GKE Standard (single-zone, one autoscaling
node pool), Cloud SQL for PostgreSQL (private IP only), Artifact Registry (Docker images +
Helm OCI charts), the Jenkins CI/CD VM, and the IAM/Workload Identity bindings that tie it
together.

**Status: authored, not applied.** Nothing here has been run against real GCP — there are no
credentials in this environment and provisioning real cloud infrastructure was explicitly out
of scope for this pass. Treat every file under `infra/` as reviewed-but-unexecuted IaC. Do not
assume any resource described here actually exists until someone with real GCP credentials
runs `terraform init` / `plan` / `apply` and reviews the plan output.

**See [manualsteps.md](./manualsteps.md)** for the full split of what `terraform apply`
creates automatically vs. what still needs a human afterward (Kubernetes objects, Jenkins/
SonarQube app config, credentials, the GitHub webhook) and the suggested order to do them in.

## Files

| File | Contents |
|---|---|
| `versions.tf` | Terraform/provider version constraints, `provider "google"` block, commented-out remote backend example |
| `variables.tf` | All inputs — no hardcoded project ID or credentials anywhere |
| `networking.tf` | VPC, subnet + secondary ranges, Private Service Access (VPC peering) for Cloud SQL, Cloud Router + Cloud NAT, firewall rules |
| `artifact-registry.tf` | Docker repo (backend/frontend images) + Helm OCI repo |
| `cloudsql.tf` | Cloud SQL for PostgreSQL, private IP only, `employeedb` database |
| `gke.tf` | GKE Standard, single-zone, one autoscaling node pool (min 1 / max 3, `e2-standard-2`) |
| `iam.tf` | Required API enablement, Workload Identity binding (backend KSA → GSA), least-privilege service accounts for Jenkins and GKE nodes |
| `jenkins-vm.tf` / `jenkins-startup.sh` | Jenkins GCE VM (public IP, SSH still IAP-only) + bootstrap script — installs Jenkins and SonarQube as native systemd services (not Docker), plus Docker/gcloud/kubectl/Helm/git/Maven/Trivy for the pipeline itself |
| `outputs.tf` | Cluster name/endpoint, Cloud SQL connection name, Artifact Registry repo URLs, Jenkins VM internal + external IP, Workload Identity SA email |

## IAM / Permissions Map

Who talks to whom, and with what role. All defined in `iam.tf` unless noted.

### Service accounts

| Service account | Attached to | Roles | Why |
|---|---|---|---|
| `employee-app-poc-backend-wi` | Nothing directly — impersonated via Workload Identity | `roles/cloudsql.client` (project) | Lets the backend pod's Cloud SQL Auth Proxy sidecar open the encrypted tunnel to Cloud SQL |
| `employee-app-poc-jenkins` | Jenkins GCE VM | `roles/artifactregistry.writer`, `roles/container.developer`, `roles/cloudsql.client` | Push images/Helm charts to Artifact Registry; deploy to GKE without full cluster-admin; optional direct Cloud SQL reach from the VM itself |
| `employee-app-poc-gke-node` | GKE node pool | `roles/logging.logWriter`, `roles/monitoring.metricWriter`, `roles/monitoring.viewer`, `roles/artifactregistry.reader` | Nodes ship logs/metrics and pull backend/frontend images |

None of these is the default Compute Engine service account, and none has Editor/Owner —
each is scoped to exactly what it needs.

### How the backend pod actually reaches Cloud SQL (two-hop trust chain)

Split across Terraform and Helm — both halves are required, neither alone is enough:

1. **Terraform** (here) grants `roles/iam.workloadIdentityUser` on the `backend-wi` GCP
   service account to the *Kubernetes* identity
   `<project>.svc.id.goog[employee-app-poc/backend]` — i.e. "the KSA named `backend` in
   namespace `employee-app-poc` is allowed to impersonate this GSA."
2. **Helm** (`helm/backend`, NOT this Terraform module) creates that Kubernetes
   ServiceAccount `backend` and annotates it
   `iam.gke.io/gcp-service-account=<backend-wi email>` (Terraform output
   `backend_workload_identity_sa_email`).

If you `terraform apply` but the Helm chart's KSA annotation is missing or wrong, the backend
pod silently has no path to Cloud SQL — there's no error at apply time, it just fails at
runtime when the Auth Proxy sidecar tries to authenticate.

### Human / operator access (IAM members you supply, not service accounts)

| Variable | Grants access to | Default |
|---|---|---|
| `jenkins_admin_ips` | Jenkins `:8080`, SonarQube `:9000` (firewall), GKE public control-plane endpoint via `master_authorized_networks` (so `kubectl` works from your machine) | `[]` — nothing allowed until you set real CIDRs |
| `iap_tunnel_admins` | `roles/iap.tunnelResourceAccessor`, for IAP-tunneled SSH (`:22`) to the Jenkins VM | `[]` — nobody has SSH until you list specific `user:`/`group:` principals |
| `github_webhook_ip_ranges` | Jenkins `:8080` only (webhook delivery) — firewall allow-list, not IAM | `[]` — fetch current values from `https://api.github.com/meta` |

### The one credential Terraform deliberately doesn't create

Terraform creates the `jenkins` service account but not a *key* for it — long-lived SA keys
aren't something Terraform should manage. Generate one manually once (see
`jenkins/README.md` step 7):

```bash
gcloud iam service-accounts keys create jenkins-sa-key.json \
  --iam-account=<jenkins-sa-email-from-terraform-output>
```

Upload it as the Jenkins credential `gcp-sa-key` — that's what `gcloud auth
activate-service-account` (Jenkinsfile stage 9, pushing images) and `gcloud container
clusters get-credentials` (stage 11, deploying) authenticate as.

### Required project APIs (prerequisite, not IAM)

Enabled by `google_project_service.apis`: `compute`, `container`, `sqladmin`,
`servicenetworking`, `artifactregistry`, `iam`, `iamcredentials`,
`cloudresourcemanager`, `iap`.

## Prerequisites before ever running this for real

1. **A real GCP project** with billing enabled. Have its project ID ready — it is intentionally
   not hardcoded anywhere in this module; you supply it as `project_id`.
2. **Application Default Credentials** for whoever/whatever runs Terraform:
   ```
   gcloud auth application-default login
   ```
   (or a service account key / Workload Identity Federation setup, for CI-driven applies).
3. **A remote state backend.** `versions.tf` ships with local state (fine for authoring, not
   for a real apply — no locking, nothing durable, nothing shareable). Create a GCS bucket for
   state and uncomment/fill in the `backend "gcs" {}` block in `versions.tf` before the first
   real `terraform init`.
4. **Required variables with no default** — must be supplied via a gitignored `*.tfvars` file,
   `-var` flags, or CI secret variables:
   - `project_id`
   - `db_password` (Cloud SQL app user password — sensitive, never commit it)
   - `jenkins_admin_ips` (defaults to `[]`, i.e. nothing allowed in — populate with real admin CIDRs)
   - `github_webhook_ip_ranges` (defaults to `[]` — fetch current ranges from
     `https://api.github.com/meta`, key `"hooks"`, before applying; GitHub's published IPs
     change over time and are deliberately not hardcoded here)
5. **Init/plan/apply**, once the above are in place:
   ```
   terraform init
   terraform plan -out=tfplan
   # review the plan carefully, then:
   terraform apply tfplan
   ```

## Design notes / known POC gaps (intentional, flagged rather than silently ignored)

- **Jenkins VM network exposure**: unlike the GKE nodes, the Jenkins VM has a public IP
  (`jenkins-vm.tf`'s `access_config {}`) so Jenkins (`:8080`) and SonarQube (`:9000`) are
  reachable directly at `<jenkins_vm_external_ip>:<port>` from a browser — see
  `jenkins/README.md`. This is a deliberate trade-off against the fully-private, IAP-tunnel-only
  posture used everywhere else in this module: SSH remains IAP-only, and both HTTP ports are
  still firewall-restricted (`allow-jenkins-http` / `allow-sonarqube-http` in `networking.tf`) to
  `var.jenkins_admin_ips`, plus GitHub's webhook ranges on `:8080` only. Populate
  `github_webhook_ip_ranges` with GitHub's current published IPs (`https://api.github.com/meta`,
  `"hooks"` key) before applying, or the webhook rule allows nothing in.
- **GKE control-plane public endpoint**: left enabled (`enable_private_endpoint = false`) but
  restricted via `master_authorized_networks` to `var.jenkins_admin_ips`, so admin `kubectl`
  works from allow-listed IPs. The Jenkins VM itself reaches the control plane over the private
  path automatically (it's in the same VPC as the private nodes) — it does not need the public
  endpoint or an admin-IP allowlist entry.
- **GKE + Jenkins VM egress**: both run without public IPs, so Cloud NAT (in `networking.tf`) is
  what gives them internet egress (pulling images, hitting GitHub/apt/gcloud mirrors, etc.).
- **Cloud SQL**: `ipv4_enabled = false` — private IP only, reachable only via the Cloud SQL Auth
  Proxy sidecar in the backend pod (see `helm/backend`), consistent with ARCHITECTURE.md section 7.
- **Workload Identity**: `iam.tf` creates the GCP service account and binds
  `roles/cloudsql.client` plus the `roles/iam.workloadIdentityUser` binding for
  `<project>.svc.id.goog[employee-app-poc/backend]`. The Kubernetes side — creating the KSA
  named `backend` and annotating it with `iam.gke.io/gcp-service-account=<output
  backend_workload_identity_sa_email>` — is the Helm chart's responsibility, not Terraform's.
- **Cloud SQL / K8s Secret credentials**: per ARCHITECTURE.md section 7, the DB
  username/password Kubernetes Secret is bootstrapped manually via `kubectl create secret`, not
  templated into Helm. Terraform creates the actual Cloud SQL user/password
  (`google_sql_user.app_user`, from `var.db_password`) — whoever applies this is responsible for
  then creating the matching K8s Secret out-of-band; that value should never land in git either.
- **Deletion protection**: both the GKE cluster and Cloud SQL instance default deletion
  protection to `false` for easy POC teardown. Flip `db_deletion_protection` and the cluster's
  `deletion_protection` before this is anything but disposable.
- **No separate Jenkins build agent**: the Jenkinsfile's `agent any` with no other node
  registered means pipeline steps run directly on this VM (the controller), not an isolated
  agent — deliberate POC simplification (see ARCHITECTURE.md Decisions Log #8), not something
  this Terraform module provisions for. A dynamic-Kubernetes-agent setup would reuse the
  existing GKE cluster rather than need a second VM here.
- **Node/Jenkins service accounts**: dedicated least-privilege service accounts are created for
  both the GKE node pool and the Jenkins VM rather than reusing the default Compute Engine
  service account, per the shared-contract least-privilege requirement.
- **`terraform fmt`/`validate` were not run** in the authoring environment (no `terraform`
  binary available, and running it would need provider plugin downloads network access wasn't
  assumed to have). Files were hand-formatted to standard `terraform fmt` conventions — run
  `terraform fmt -recursive` and `terraform validate` as a sanity check before the first real
  `plan`.

## Typical variable file (example — do not commit a real one)

```hcl
# infra/terraform.tfvars  (gitignored — see repo .gitignore)
project_id = "my-real-gcp-project-id"
region     = "us-central1"
zone       = "us-central1-a"

db_password = "REPLACE_ME_FROM_A_SECRET_STORE"

jenkins_admin_ips        = ["203.0.113.4/32"]
github_webhook_ip_ranges = ["192.30.252.0/22", "185.199.108.0/22", "140.82.112.0/20"] # example only — fetch current values from https://api.github.com/meta
```
