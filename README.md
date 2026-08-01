# Employee Management App (POC)

A proof-of-concept Employee Management CRUD application: a Java Spring Boot REST API backend, a static HTML/JS frontend, and a PostgreSQL database on Cloud SQL — containerized with Docker, deployed to a single-zone GKE cluster via Helm, and built/released through a Jenkins CI/CD pipeline. Infrastructure (GKE, Cloud SQL, Artifact Registry, Jenkins VM, networking) is provisioned with Terraform.

See [ARCHITECTURE.md](./ARCHITECTURE.md) for the full design — this README covers structure, local dev, and one-time manual setup only.

## Repository Structure

```
employee-app/
├── backend/            # Spring Boot REST API (CRUD on /api/employees/**), Flyway migrations
├── frontend/            # Static HTML/CSS/JS UI with login form, calls the backend REST API
├── helm/
│   ├── backend/         # Helm chart for the backend Deployment/Service
│   └── frontend/        # Helm chart for the frontend Deployment/Service
├── infra/               # Terraform: GKE, Cloud SQL, Artifact Registry, Jenkins VM, networking
├── jenkins/             # Manual setup guide for Jenkins + self-hosted SonarQube (native services on the Jenkins VM, installed by infra/jenkins-startup.sh)
├── docker-compose.yml   # Local dev stack: backend + frontend + local Postgres
├── Jenkinsfile          # CI/CD pipeline: build, test, scan, push, deploy to GKE
└── README.md
```

Jenkins uses path-based change detection, so a frontend-only change doesn't rebuild/redeploy the backend, and vice versa. `infra/` is applied separately and far less frequently than the app pipeline — it is not triggered per-commit.

## Run Locally

```
docker-compose up
```

This starts three containers:

| Service | URL / Port |
|---|---|
| Frontend | http://localhost (port 80) |
| Backend API | http://localhost:8080 |
| Postgres | localhost:5432 |

Locally, nginx (frontend container) reverse-proxies `/api/*` to the backend so behavior matches the production Ingress routing. Flyway migrations run automatically on backend startup against the local Postgres instance.

> **Note:** Credentials used by `docker-compose.yml` (DB and basic-auth) are dev-only defaults for local convenience — never reuse them outside local dev. Production credentials are never in git (see below).

## Manual One-Time Setup Steps

These steps are **intentionally not automated** by the Jenkins pipeline or Helm charts, because secrets and base infrastructure can't live in git.

### 1. Bootstrap the Kubernetes Secret

Before the first Helm deploy, create the `employee-app-secrets` Secret in the `employee-app-poc` namespace with the DB and basic-auth credentials:

```
kubectl create secret generic employee-app-secrets \
  --namespace employee-app-poc \
  --from-literal=db-username=<db-username> \
  --from-literal=db-password=<db-password> \
  --from-literal=auth-username=<auth-username> \
  --from-literal=auth-password=<auth-password>
```

Helm charts reference this Secret by name but never create or template its contents.

### 2. Provision infrastructure with Terraform

Before the pipeline can build or deploy anything, run Terraform from `infra/` to provision the GKE cluster, Cloud SQL instance, Artifact Registry, Jenkins VM, networking, and IAM/Workload Identity bindings:

```
cd infra
terraform init
terraform apply
```

This must complete (and the `employee-app-poc` namespace plus the Secret above must exist) before the Jenkins pipeline's `helm upgrade --install` deploy stage will succeed.

### 3. Configure Jenkins + SonarQube on the Jenkins VM

`infra/jenkins-startup.sh` installs and starts Jenkins (:8080) and SonarQube (:9000) as
native systemd services on the VM automatically — no docker-compose step needed. What's
still manual is one-time configuration: finishing the Jenkins setup wizard, registering the
SonarQube server, generating tokens/credentials, the SonarQube→Jenkins webhook, and the
Jenkins Pipeline job. See **[jenkins/README.md](./jenkins/README.md)** for the full
walkthrough — do this before the first pipeline run, since the pipeline's SonarQube Analysis
and Quality Gate stages (5–6) have nothing to talk to otherwise.

The Jenkins VM has a public IP (`terraform output jenkins_vm_external_ip`), locked down by
firewall to `var.jenkins_admin_ips` (+ GitHub's webhook ranges on :8080 only) — see
`infra/networking.tf`.

## Full Design Reference

For requirements, tech stack rationale, CI/CD pipeline stages, Kubernetes object design, Cloud SQL connectivity, and security considerations, see [ARCHITECTURE.md](./ARCHITECTURE.md) — the source of truth for this project's design.
