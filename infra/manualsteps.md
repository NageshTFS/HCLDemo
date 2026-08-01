# What Terraform automates vs. what still needs a human

`terraform apply` (from this `infra/` module) provisions the cloud infrastructure and the
right *identities* for it — but nothing running *inside* any of it (Kubernetes objects,
Jenkins app config, Helm releases) is Terraform's job. This is the full split.

## Sequencing: `terraform apply` always comes first

This isn't just a suggested order — every manual step below has a hard dependency on
something `terraform apply` creates, so none of them are possible beforehand:

- The **`backend` KSA and Secret** need the **GKE cluster** to exist
- **`gcp-sa-key`** needs the **`jenkins` service account** to exist (you're generating a key
  *for* it — nothing to generate before Terraform creates the SA)
- **Jenkins/SonarQube configuration** needs the **VM to be up and reachable**, which means
  both the VM itself and `jenkins-startup.sh` (installing the actual Jenkins/SonarQube
  software) must have already run as part of the VM booting — that happens automatically
  during `terraform apply`, not as a separate manual step
- The **GitHub webhook** needs the VM's **external IP**, which only exists once Terraform
  creates it (`terraform output jenkins_vm_external_ip`)

So the flow is always: **`terraform apply` completes → then work through the manual steps**,
in the order given below. Nothing here can be front-loaded or done in parallel with the
`apply`.

## Created automatically by `terraform apply`

- All 3 service accounts (`backend-wi`, `jenkins`, `gke-node`) and every IAM role binding —
  see the IAM / Permissions Map in [README.md](./README.md)
- The Workload Identity binding itself (`roles/iam.workloadIdentityUser`) — the **GCP-side
  half** of that trust chain (see below for the other half)
- Required project API enablement
- Firewall rules and `master_authorized_networks` entries — but only take effect once you've
  populated `jenkins_admin_ips` / `github_webhook_ip_ranges` (see below)
- `iap_tunnel_admins` role grants — same caveat, only for whatever principals you list
- VPC, subnet, Cloud NAT, Cloud SQL instance + private IP + the `employeedb` app DB user
  (from `var.db_password`), GKE cluster + node pool, Artifact Registry repos, the Jenkins VM
  itself (with Jenkins + SonarQube installed as native services by `jenkins-startup.sh`)

## Requires manual action — nothing automates these

| Step | Why it can't be Terraform |
|---|---|
| **Populate `project_id`, `db_password`, `jenkins_admin_ips`, `iap_tunnel_admins`, `github_webhook_ip_ranges`** in a real `.tfvars` before applying | These are *inputs* — left at their empty defaults, the corresponding access just isn't granted (fails safe, doesn't error) |
| **Kubernetes ServiceAccount `backend`** + its `iam.gke.io/gcp-service-account=...` annotation — the **K8s-side half** of Workload Identity | Created by the Helm chart (`helm/backend`), not Terraform — Terraform doesn't touch the cluster's Kubernetes API, only provisions the cluster itself |
| **K8s Secret `employee-app-secrets`** (DB username/password, basic-auth creds) | Deliberately never templated into Helm/git; bootstrapped via `kubectl create secret` — and its `db-password` value must match what Terraform set as `var.db_password`, a manual sync you're responsible for |
| **`gcp-sa-key`** — a downloadable JSON key for the `jenkins` SA | Terraform creates the SA, not a long-lived key for it (deliberate — key management shouldn't live in state); run `gcloud iam service-accounts keys create` yourself |
| **Jenkins itself**: setup wizard, plugins, credentials (`gcp-sa-key`, `sonar-token`, `slack-webhook-url`), SonarQube server registration, SonarQube webhook, the Pipeline job | Jenkins app-level config lives in its own internal state (`/var/lib/jenkins`), not something `jenkins-startup.sh` can populate — that script only gets the *software* running. Full walkthrough: [../jenkins/README.md](../jenkins/README.md) |
| **GitHub repo webhook** (Settings → Webhooks) | Lives on GitHub's side, outside GCP entirely |
| **Remote state backend** (GCS bucket for `terraform.tfstate`) | Ships with local state by default; must be created and wired into `versions.tf` before a real team-shared apply |
| **First `helm upgrade --install`** | The Jenkins pipeline does this once fully configured — but until then, it's a manual `helm` command |

## Suggested order

1. `terraform apply` (this module) — everything below depends on this having finished
2. Bootstrap the `employee-app-secrets` K8s Secret — do this *before* the first deploy, since
   the backend pod won't start cleanly without it
3. First `helm upgrade --install` (manually, or let the pipeline's first run do it) — this is
   what actually creates the `backend` KSA + its Workload Identity annotation, completing the
   trust chain Terraform started in step 1
4. Generate and upload `gcp-sa-key`
5. Stand up Jenkins/SonarQube app-level config — see [../jenkins/README.md](../jenkins/README.md)
6. Wire the GitHub webhook (needs `terraform output jenkins_vm_external_ip` from step 1)
7. Set up the remote state backend before anyone else needs to run Terraform against the
   same infrastructure
