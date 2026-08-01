# Jenkins + SonarQube — one-time setup

Jenkins and SonarQube run as **native systemd services** directly on the Jenkins GCE VM
(`../infra/jenkins-startup.sh`) — not in Docker. Docker itself is still installed on the VM,
but only for the pipeline's own `docker build`/`push`/Gitleaks/Trivy steps. This doc covers
the manual setup that has to happen after Terraform provisions the VM, since a CI pipeline
can't bootstrap the CI server it runs on.

## Prerequisites

- `../infra/` has been applied (`terraform apply`) with the current `jenkins-vm.tf` /
  `networking.tf` (the Jenkins VM now gets a public IP — see `infra/outputs.tf`'s
  `jenkins_vm_external_ip`, restricted to `var.jenkins_admin_ips` by firewall).
- `terraform output jenkins_vm_external_ip` to get the address used below.

## 1. Confirm the services are up

`jenkins-startup.sh` installs and starts both automatically on first boot. From an admin IP
(SSH via IAP tunnel, or `gcloud compute ssh --tunnel-through-iap`):

```bash
systemctl status jenkins
systemctl status sonarqube
```

SonarQube takes 1-2 minutes to fully start (it's booting an embedded Elasticsearch) — give it
a moment before the UI responds on :9000.

## 2. Open Jenkins and finish the setup wizard

```
http://<jenkins_vm_external_ip>:8080
```

Get the initial admin password:

```bash
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

Install the **suggested plugins**, plus explicitly confirm these are installed (the
Jenkinsfile depends on them):

- **SonarQube Scanner for Jenkins** — provides `withSonarQubeEnv(...)` / `waitForQualityGate()`
- **Pipeline** and **Git** (included in "suggested")
- **GitHub** — provides the `githubPush()` trigger already used in the Jenkinsfile
- **Credentials Binding** — provides `credentials(...)` in the `environment {}` block

Create an initial admin user when prompted.

## 3. Open SonarQube and set the admin password

```
http://<jenkins_vm_external_ip>:9000
```

Log in with `admin` / `admin`, set a new password when prompted.

## 4. Register the SonarQube server in Jenkins

**Manage Jenkins → System → SonarQube servers → Add SonarQube**

| Field | Value |
|---|---|
| Name | `self-hosted-sonarqube` (must match `withSonarQubeEnv('self-hosted-sonarqube')` in the Jenkinsfile exactly) |
| Server URL | `http://localhost:9000` (Jenkins and SonarQube are both native services on the same VM now — no container network involved) |
| Server authentication token | the `sonar-token` credential from step 5 below |

## 5. Generate a SonarQube token and add it as a Jenkins credential

1. In SonarQube: **My Account → Security → Generate Token** — name it e.g. `jenkins`, copy
   the value.
2. In Jenkins: **Manage Jenkins → Credentials → (global) → Add Credentials**
   - Kind: **Secret text**
   - Secret: the token from step 1
   - ID: `sonar-token` (must match `credentials('sonar-token')` in the Jenkinsfile exactly)

## 6. Point a SonarQube webhook back at Jenkins

The Quality Gate stage (`waitForQualityGate()`) blocks waiting for SonarQube to call back —
without this webhook it will time out on every build.

**SonarQube → Administration → Configuration → Webhooks → Create**

| Field | Value |
|---|---|
| Name | `jenkins` |
| URL | `http://localhost:8080/sonarqube-webhook/` |

## 7. Add the remaining Jenkins credentials

The Jenkinsfile's `environment {}` block references three credential IDs; `sonar-token` is
done above, the other two:

- **`gcp-sa-key`** (Kind: **Secret file**) — the JSON key for the Jenkins GCP service
  account Terraform created (`infra/iam.tf`). Generate it once:
  ```bash
  gcloud iam service-accounts keys create jenkins-sa-key.json \
    --iam-account=<jenkins-sa-email-from-terraform-output>
  ```
  Upload `jenkins-sa-key.json` as the credential, then delete the local copy. Rotate
  periodically — a downloaded key has no expiry by default.
- **`slack-webhook-url`** (Kind: **Secret text**) — a real Slack Incoming Webhook URL. Until
  this is set the notify stage fails harmlessly and logs "placeholder webhook not yet
  configured" (see `Jenkinsfile`'s `notify()` function) — the pipeline result is unaffected.

## 8. Create the Pipeline job

**New Item → Pipeline**, name it e.g. `employee-app`, then under **Pipeline**:

- Definition: **Pipeline script from SCM**
- SCM: **Git**, repository URL = this GitHub repo, branch `*/main`
- Script Path: `Jenkinsfile`

Set real defaults for the job **Parameters** (`GCP_PROJECT_ID` especially — the Jenkinsfile
deliberately ships with a placeholder so no real project ID is hardcoded in git).

## 9. Wire up the GitHub webhook

GitHub → repo **Settings → Webhooks → Add webhook**:

| Field | Value |
|---|---|
| Payload URL | `http://<jenkins_vm_external_ip>:8080/github-webhook/` |
| Content type | `application/json` |
| Events | Just the `push` event |

This now works directly — the Jenkins VM has a public IP and the firewall
(`allow_jenkins_admin_and_webhook` in `infra/networking.tf`) already allows
`var.github_webhook_ip_ranges` on port 8080. Set that variable to GitHub's published webhook
IP ranges (`https://api.github.com/meta`, `hooks` key) before applying, if you haven't.

## Reference

- `../infra/jenkins-startup.sh` — installs and configures Jenkins + SonarQube (+ its own
  local Postgres) as native systemd services
- `../infra/jenkins-vm.tf`, `../infra/networking.tf` — public IP + firewall rules for :8080/:9000
- `../infra/outputs.tf` — `jenkins_vm_external_ip`
- `../Jenkinsfile` — the pipeline this setup exists to support
- `../ARCHITECTURE.md` section 8 — pipeline design and the Jenkins VM security posture
