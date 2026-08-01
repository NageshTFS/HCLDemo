# Employee Management App — Architecture & Deployment Plan (POC Scope)

## 1. Overview
A POC-scope Employee Management application: Java REST API backend, static HTML/JS frontend, Cloud SQL database — containerized and deployed to a single-zone GKE cluster, built and released through a Jenkins CI/CD pipeline triggered from a single-branch GitHub monorepo.

This is intentionally scoped down — simple CRUD only, no observability stack, no HA. Flagged inline wherever something is a POC simplification vs. a permanent decision.

---

## 2. Requirements

### Functional
- Simple CRUD on employee records: id, first name, last name, email, phone, department, designation, salary, date of joining, status
- Plain list view (all employees) — no search, filter, or pagination
- Field validation (required fields, unique email — enforced at both the DB constraint and application layer)
- Basic login gate on the frontend and API — Spring Security HTTP Basic auth, shared/static credentials for POC, gating both `/api/**` and the static frontend (Actuator `/actuator/health` stays unauthenticated for K8s probes and the pipeline smoke test)

### Non-Functional
- **Availability**: single-zone GKE cluster, 1–2 backend replicas — no cross-zone HA for this POC
- **Scalability**: not a concern at this scope; HPA can be added later without redesign
- **Security**: TLS at ingress (temporary self-signed cert on the raw ingress IP until a real domain is available — see Section 9), secrets never in git/images, least-privilege service accounts, basic auth on API + UI
- **Data durability**: handled by Cloud SQL (managed backups)
- **Schema management**: Flyway versioned SQL migrations — not Hibernate `ddl-auto`
- **Repeatability**: everything as code — Terraform for infra (GKE, Cloud SQL, Artifact Registry, Jenkins VM, networking), Jenkinsfile + Helm charts for the app layer
- **Code quality gate**: no image is built/deployed unless JUnit tests pass and SonarQube's Quality Gate passes
- **Observability**: out of scope for this POC — no monitoring/alerting stack planned; GKE's default Cloud Logging still captures pod logs passively, nothing beyond that

---

## 3. Tech Stack

| Layer | Choice |
|---|---|
| Backend | Java 21, Spring Boot 3 (Web, Data JPA, Actuator, Security) |
| Frontend | Static HTML/CSS/JS, served via a lightweight Nginx image |
| Database | Cloud SQL — **PostgreSQL** |
| Schema migrations | Flyway |
| Build | Maven (backend); no build step needed for static frontend |
| Containerization | Docker, multi-stage builds, slim JRE base for backend, `nginx:alpine` for frontend |
| Registry | Google Artifact Registry (Docker image push) |
| CI/CD | Jenkins (single Pipeline job) on a GCE VM |
| Git hosting | **GitHub**, single `main` branch (POC) |
| Orchestration | GKE Standard, single-zone cluster (no regional HA for POC) |
| Infra provisioning | **Terraform** — GKE cluster, Cloud SQL instance, Artifact Registry, Jenkins VM, networking, IAM/Workload Identity bindings |
| Config/secrets | Kubernetes ConfigMap + Secret |
| Ingress/TLS | GCE Ingress; self-signed cert on raw IP for POC (no domain yet), swap for Google-managed cert once a domain is available |
| Code quality | JUnit + JaCoCo (coverage) → SonarQube (**self-hosted**, native systemd service on the Jenkins VM), with a pipeline-enforced Quality Gate |
| Deployment packaging | Helm (chart per component: backend, frontend), charts pushed to Artifact Registry (OCI) |

---

## 4. Repository Structure (Monorepo)

```
employee-app/
├── backend/            # Spring Boot REST API
│   ├── src/
│   │   └── main/resources/db/migration/   # Flyway SQL migrations
│   ├── pom.xml
│   └── Dockerfile
├── frontend/            # Static HTML/CSS/JS
│   ├── src/
│   └── Dockerfile
├── helm/
│   ├── backend/
│   └── frontend/
├── infra/               # Terraform: GKE, Cloud SQL, Artifact Registry, Jenkins VM, networking
├── docker-compose.yml   # local dev: backend + frontend + local Postgres
├── Jenkinsfile
└── README.md
```

Jenkinsfile uses path-based change detection so a frontend-only change doesn't rebuild/redeploy the backend, and vice versa. Terraform under `infra/` is applied separately and far less frequently than the app pipeline — not triggered per-commit.

---

## 5. Application Architecture

- **Backend**: REST API exposing `/api/employees/**` (plain CRUD: GET all, GET by id, POST, PUT, DELETE), protected by HTTP Basic auth, Spring Data JPA over Cloud SQL Postgres, Actuator health endpoint (`/actuator/health`, unauthenticated) wired to K8s probes and the pipeline smoke test.
- **Frontend**: Static HTML/JS calling the backend's REST API, with a simple login form that captures credentials and attaches them as an `Authorization: Basic` header on API calls. Served same-origin via Ingress path routing (`/` → frontend, `/api/*` → backend) — no CORS configuration needed.
- **Database schema (conceptual)**: single `employees` table — id, first_name, last_name, email (unique), phone, department, designation, salary, hire_date, status, created_at, updated_at. Managed via Flyway migration scripts (`V1__init.sql`, etc.), version-controlled in `backend/src/main/resources/db/migration/`.

---

## 6. Docker Strategy
- **Backend image**: multi-stage — Maven build stage → copy jar into a slim JRE runtime image.
- **Frontend image**: static files copied into `nginx:alpine`, minimal config. For local Docker Compose dev, nginx also reverse-proxies `/api/*` to the backend service so local behavior matches the prod Ingress routing.
- Both images tagged with the Git commit SHA, pushed to Google Artifact Registry.

---

## 7. Cloud SQL Integration
- **Connectivity**: Cloud SQL Auth Proxy as a sidecar container in the backend pod — backend connects to `localhost:5432`, proxy handles the encrypted tunnel to Cloud SQL (private IP only — Cloud SQL instance has no public IP)
- **Credentials**: DB username/password stored in a Kubernetes Secret; bootstrapped manually once via `kubectl create secret` (not templated into Helm, since it can't live in git) — documented as a manual one-time step in README
- **Backups**: handled automatically by Cloud SQL — no custom backup job needed
- **Service account**: backend's Kubernetes service account needs Workload Identity binding to a GCP service account with `Cloud SQL Client` role (created via Terraform)

---

## 8. CI/CD Pipeline (Jenkins, GitHub, single branch)

**Trigger**: GitHub webhook → Jenkins Pipeline job (standard, single-branch `main`; GitHub plugin handles the webhook)

**Pipeline stages**:
1. Checkout
2. Secret scan (Gitleaks) — repo is public, so this gates every build
3. Detect changed paths (`backend/`, `frontend/`, or both)
4. Backend: Maven build + JUnit tests + JaCoCo coverage report (Flyway migrations run automatically on app startup via `spring.flyway.enabled=true` — no separate pipeline migration step needed at this single-replica POC scale)
5. SonarQube analysis (coverage + code smells/bugs/duplication) against the self-hosted SonarQube instance
6. **Quality Gate check** — pipeline aborts here if it fails, no image is built
7. Docker build (backend, frontend — only the changed ones)
8. Image scan (Trivy)
9. Push to Google Artifact Registry (tag = commit SHA)
10. Helm lint + `helm template` validation
11. Deploy to GKE (`helm upgrade --install`)
12. Post-deploy smoke test (hit `/actuator/health`)
13. Notify (Slack/email) on success/failure
14. Rollback path: `helm rollback` if the smoke test fails

**Jenkins VM (GCE)**:
- Jenkins and SonarQube run as **native systemd services** on the VM (installed by `infra/jenkins-startup.sh`) — not Docker containers. Docker Engine is still installed, but only for the pipeline's own `docker build`/`push`/Gitleaks/Trivy steps. SonarQube uses a local native Postgres for its own backing DB (separate from the app's Cloud SQL instance).
- **No separate build agent/slave** — the Jenkinsfile uses `agent any` with no other node configured, so every pipeline step (checkout, `mvn`, `docker build`, Trivy, `helm upgrade`) executes directly on the Jenkins controller VM itself. Deliberate POC simplification, not an oversight: no second VM to provision/manage, and `disableConcurrentBuilds()` already serializes builds so there's no resource contention between concurrent runs. Trade-off: no isolation between the controller process and build steps (a compromised/malicious Jenkinsfile has direct access to whatever the controller can reach), and no horizontal build scaling. Revisit before this is anything but a POC — likely direction: dynamic Kubernetes agent pods in the existing GKE cluster via the Jenkins Kubernetes plugin, rather than a second static VM.
- Least-privilege service account (Artifact Registry writer, GKE deployer role, Cloud SQL Client)
- **Has a public IP** (deliberate trade-off for direct browser access to Jenkins `:8080` / SonarQube `:9000` without an IAP tunnel), locked down by firewall to admin IPs (+ GitHub's webhook ranges on `:8080` only, for webhook delivery)
- SSH remains IAP-tunnel-only (no direct SSH exposure)
- Provisioned via Terraform (`infra/`); see `jenkins/README.md` for the manual setup that follows provisioning

---

## 9. Kubernetes Design (GKE Standard, single-zone cluster)

**Node pool**: single autoscaling pool (e.g. `e2-standard-2`, 1–3 nodes)

**Namespace**: `employee-app-poc`

**Objects**:
- `Deployment` + `Service` (backend) — includes Cloud SQL Auth Proxy sidecar container, resource requests/limits, readiness/liveness probes against `/actuator/health`
- `Deployment` + `Service` (frontend) — Nginx, ClusterIP
- `ConfigMap` — non-secret app config (Cloud SQL instance connection name)
- `Secret` — Cloud SQL DB credentials, basic-auth credentials, app secrets (bootstrapped manually, not in Helm values/git)
- `Ingress` — single IP, path-based routing (`/api/*` → backend, `/*` → frontend). **TLS: self-signed cert for now (no domain yet)** — swap to a `ManagedCertificate` + Google-managed cert once a real domain is pointed at the ingress IP. Tracked as a follow-up, not the final state.

---

## 10. Security Considerations
- No secrets in git or baked into images — Kubernetes Secrets, bootstrapped manually
- Public repo → Gitleaks secret scan is mandatory in the pipeline
- Basic auth gating both `/api/**` and the frontend UI (Actuator health stays open for probes/smoke test)
- TLS terminated at Ingress — self-signed for POC, Google-managed cert once a domain exists
- Cloud SQL instance has no public IP; reachable only via the Auth Proxy sidecar
- RBAC scoping in-cluster access; Jenkins' GKE service account limited to the `employee-app-poc` namespace where possible
- Image scanning (Trivy) gating the deploy stage
- Workload Identity binding for backend pod → GCP service account with `Cloud SQL Client` role

---

## 11. Decisions Log (formerly Open Items)
1. **Database**: PostgreSQL
2. **Login/auth gate**: added now — Spring Security HTTP Basic, shared credentials for POC
3. **SonarQube hosting**: self-hosted, native systemd service on the Jenkins VM (not Docker)
4. **Schema migrations**: Flyway
5. **Infra provisioning**: Terraform (GKE, Cloud SQL, Artifact Registry, Jenkins VM, networking)
6. **Domain/TLS**: no domain yet — self-signed cert on the raw ingress IP as a temporary stand-in; revisit before this goes beyond an internal demo
7. **Jenkins VM network exposure**: given a public IP (not IAP-tunnel-only) so Jenkins `:8080` and SonarQube `:9000` are reachable directly at `<VM_IP>:<port>` from a browser; firewall still restricts both to admin IPs, plus GitHub's webhook ranges on `:8080` only
8. **Jenkins build execution**: no separate agent/slave for POC — pipeline steps run directly on the Jenkins controller VM (`agent any`, no other node registered); revisit (likely dynamic Kubernetes agent pods in GKE) before production

---

## 12. Phased Roadmap (POC)
1. Write Terraform for GKE cluster, Cloud SQL (Postgres) instance, Artifact Registry, Jenkins VM, networking, IAM/Workload Identity — apply to provision base infra
2. Scaffold backend (Spring Boot CRUD + Flyway + Spring Security basic auth) + frontend (static HTML/JS + login form), verify locally with Docker Compose (app + local Postgres for dev; Flyway runs on startup)
3. Push monorepo to GitHub
4. Stand up Jenkins VM (via Terraform), wire basic pipeline (checkout → secret scan → build → test → SonarQube → dockerize)
5. Write Helm charts (backend, frontend)
6. Extend pipeline to push images + `helm upgrade --install` to GKE
7. Add Ingress with self-signed TLS; swap to managed cert + domain when available
8. Confirm Cloud SQL restore works
9. Review before deciding on regional HA, scaling, real domain/managed TLS, or observability if this graduates beyond POC
