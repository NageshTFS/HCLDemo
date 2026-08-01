#!/usr/bin/env bash
# Bootstrap for the Jenkins VM: installs Jenkins and SonarQube as NATIVE systemd services
# (not Docker containers) — see jenkins/README.md for the manual setup that follows this.
# Also installs Docker Engine, gcloud, kubectl, Helm, git, which the pipeline itself needs
# for `docker build`/`push`, `gcloud`/`kubectl` deploys, `helm upgrade`, and the Gitleaks/
# Trivy scan stages (those still run via `docker run ...`, so Docker Engine stays).
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# Bump this when you provision — check https://www.sonarsource.com/products/sonarqube/downloads/
# for the current Community Edition version; this pins a known-good one rather than tracking
# "latest" so a VM rebuild doesn't silently pick up a different major version.
SONARQUBE_VERSION="10.6.0.92116"

apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  gnupg \
  git \
  unzip \
  apt-transport-https \
  lsb-release \
  libharfbuzz0b \
  fontconfig \
  fonts-dejavu-core
  # ^ openjdk's font manager dlopens libharfbuzz even under -headless, and separately needs a
  # real fontconfig + at least one font to initialize — without both, Jenkins' Jetty/Winstone
  # startup throws UnsatisfiedLinkError / "Fontconfig head is null" and crash-loops.

# --- Java (Jenkins LTS + SonarQube Community both require Java 17+; use 21 to match the app) ---
apt-get install -y --no-install-recommends openjdk-21-jre-headless

# --- Docker Engine + CLI (still needed for the pipeline's own docker build/push/scan steps) ---
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --yes --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y --no-install-recommends docker-ce docker-ce-cli containerd.io docker-compose-plugin

# --- Google Cloud SDK (gcloud) ---
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
  > /etc/apt/sources.list.d/google-cloud-sdk.list
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --yes --dearmor -o /usr/share/keyrings/cloud.google.gpg
apt-get update
apt-get install -y --no-install-recommends google-cloud-cli google-cloud-cli-gke-gcloud-auth-plugin

# --- kubectl ---
apt-get install -y --no-install-recommends kubectl

# --- Helm ---
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# --- Maven (Jenkinsfile runs `mvn` directly against backend/) ---
# archive.apache.org, not dlcdn.apache.org — dlcdn only mirrors the current release and 404s
# on older pinned versions once a new one ships.
MAVEN_VERSION="3.9.9"
curl -fsSL "https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz" \
  -o /tmp/maven.tar.gz
tar -xzf /tmp/maven.tar.gz -C /opt
ln -sf "/opt/apache-maven-${MAVEN_VERSION}/bin/mvn" /usr/local/bin/mvn
rm /tmp/maven.tar.gz

# --- Trivy (stage 8: image scan) ---
curl -fsSL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
  | sh -s -- -b /usr/local/bin

############################
# Jenkins (native, official apt repo — installs and starts the "jenkins" systemd service,
# listening on :8080 as the "jenkins" OS user)
############################
# Jenkins rotates this key every ~3 years and retires the old filename (jenkins.io-2023.key
# expired 2026-03-26) — if this apt-get update ever fails with NO_PUBKEY, check
# https://pkg.jenkins.io/debian-stable/ for the current jenkins.io-YYYY.key.
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key \
  | gpg --yes --dearmor -o /usr/share/keyrings/jenkins-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.gpg] https://pkg.jenkins.io/debian-stable binary/" \
  > /etc/apt/sources.list.d/jenkins.list
apt-get update
apt-get install -y --no-install-recommends jenkins

# Let the "jenkins" user run `docker build`/`push` without sudo.
groupadd -f docker
usermod -aG docker jenkins
systemctl restart jenkins || true

############################
# PostgreSQL (native, local — SonarQube's own backing DB; separate from the app's Cloud SQL
# instance, which is provisioned in cloudsql.tf and unrelated to this)
############################
apt-get install -y --no-install-recommends postgresql
systemctl enable --now postgresql
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname = 'sonarqube'" | grep -q 1 \
  || sudo -u postgres psql -c "CREATE ROLE sonarqube LOGIN PASSWORD 'sonarqube_local_password';"
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname = 'sonarqube'" | grep -q 1 \
  || sudo -u postgres psql -c "CREATE DATABASE sonarqube OWNER sonarqube;"
# --- VM-INTERNAL ONLY --- this DB is bound to localhost only (default `listen_addresses`),
# so this password is not reachable off the VM. Still worth rotating beyond a POC.

############################
# SonarQube (native, dedicated OS user — SonarQube refuses to start as root)
############################
id -u sonarqube &>/dev/null || useradd --system --home-dir /opt/sonarqube --shell /bin/false sonarqube

if [ ! -d "/opt/sonarqube-${SONARQUBE_VERSION}" ]; then
  curl -fsSL "https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-${SONARQUBE_VERSION}.zip" \
    -o /tmp/sonarqube.zip
  unzip -q /tmp/sonarqube.zip -d /opt
  rm /tmp/sonarqube.zip
  ln -sfn "/opt/sonarqube-${SONARQUBE_VERSION}" /opt/sonarqube
  chown -R sonarqube:sonarqube "/opt/sonarqube-${SONARQUBE_VERSION}" /opt/sonarqube
fi

cat > /opt/sonarqube/conf/sonar.properties <<'EOF'
sonar.jdbc.username=sonarqube
sonar.jdbc.password=sonarqube_local_password
sonar.jdbc.url=jdbc:postgresql://localhost:5432/sonarqube
sonar.web.host=0.0.0.0
sonar.web.port=9000
# SonarQube 10.6 still calls the now-deprecated System.setSecurityManager(); JDK 21 throws
# UnsupportedOperationException on that call unless explicitly allowed (JEP 411).
sonar.web.javaAdditionalOpts=-Djava.security.manager=allow
sonar.ce.javaAdditionalOpts=-Djava.security.manager=allow
EOF
chown sonarqube:sonarqube /opt/sonarqube/conf/sonar.properties
chmod 640 /opt/sonarqube/conf/sonar.properties

# SonarQube's embedded Elasticsearch refuses to start below this - set it persistently so it
# survives a VM reboot, not just the current session.
echo "vm.max_map_count=262144" > /etc/sysctl.d/99-sonarqube.conf
sysctl -w vm.max_map_count=262144

# Official native-install ulimits (see SonarQube docs: "Operating system requirements").
cat > /etc/security/limits.d/99-sonarqube.conf <<'EOF'
sonarqube   -   nofile   65536
sonarqube   -   nproc    4096
EOF

cat > /etc/systemd/system/sonarqube.service <<'EOF'
[Unit]
Description=SonarQube
After=network.target postgresql.service

[Service]
Type=forking
User=sonarqube
Group=sonarqube
ExecStart=/opt/sonarqube/bin/linux-x86-64/sonar.sh start
ExecStop=/opt/sonarqube/bin/linux-x86-64/sonar.sh stop
Restart=on-failure
LimitNOFILE=65536
LimitNPROC=4096

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now sonarqube

echo "Jenkins VM bootstrap complete: jenkins (:8080), sonarqube (:9000, native), docker, gcloud, kubectl, helm, mvn, git installed." \
  > /var/log/employee-app-poc-startup.log
