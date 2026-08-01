// Jenkinsfile - Employee Management POC CI/CD pipeline
//
// Runs on the Jenkins GCE VM described in ARCHITECTURE.md section 8 (Docker, gcloud SDK,
// kubectl, Helm, git, plus a self-hosted SonarQube instance all pre-installed on that VM).
// Single-branch (`main`) GitHub monorepo, triggered by a GitHub webhook.
//
// `agent any` with no other node registered means every stage below runs directly on the
// Jenkins CONTROLLER VM - there is no separate build agent/slave for this POC (see
// ARCHITECTURE.md section 8 / Decisions Log #8). Deliberate simplification, not an oversight;
// revisit (likely dynamic Kubernetes agent pods in the existing GKE cluster) before this is
// anything but a POC.
//
// Stage numbering below matches ARCHITECTURE.md section 8 ("CI/CD Pipeline") 1:1, with two
// deliberate implementation notes:
//   - Stage 13 (Notify) is implemented in the pipeline-level `post` block, not as a mid-flow
//     `stage()`, so it reliably fires on success AND failure - a stage that fails part-way
//     through (e.g. Quality Gate) causes Jenkins to skip all remaining declarative stages and
//     jump straight to `post`, so a literal "stage 13" would never run on a failed build.
//   - Stage 14 (Rollback) is exactly the `post { failure { ... } }` hook the task calls for,
//     attached only to the Deploy and Smoke Test stages (11 and 12) - nothing is deployed yet
//     if an earlier stage fails, so there is nothing to roll back.
//
// Placeholder Jenkins credential IDs referenced below (create these in the Jenkins credential
// store before running for real - none of them exist in this repo):
//   - gcp-sa-key  (Secret file)  GCP service account JSON key - Artifact Registry push + GKE deploy
//   - sonar-token (Secret text)  Auth token for the self-hosted SonarQube instance

def rollbackChangedReleases(String reason) {
    echo "ROLLBACK: ${reason}"
    if (env.BACKEND_CHANGED == 'true') {
        echo "Rolling back Helm release 'backend' in namespace ${env.NAMESPACE}"
        sh "helm rollback backend --namespace ${env.NAMESPACE} || true"
    }
    if (env.FRONTEND_CHANGED == 'true') {
        echo "Rolling back Helm release 'frontend' in namespace ${env.NAMESPACE}"
        sh "helm rollback frontend --namespace ${env.NAMESPACE} || true"
    }
}

def notify(String status) {
    def summary = "Employee App POC pipeline *${status}* - build #${env.BUILD_NUMBER}, " +
        "commit ${env.GIT_COMMIT_SHA ?: env.GIT_COMMIT ?: 'unknown'} " +
        "(backend_changed=${env.BACKEND_CHANGED ?: 'n/a'}, frontend_changed=${env.FRONTEND_CHANGED ?: 'n/a'}) " +
        "${env.BUILD_URL ?: ''}"
    echo "NOTIFY: ${summary}"
}

pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20'))
        skipDefaultCheckout(true)
    }

    triggers {
        githubPush()
    }

    parameters {
        // Pipeline-from-SCM jobs have no job-level parameter override that applies to
        // webhook-triggered builds - only this Jenkinsfile default is used for those (a
        // "Build with Parameters" override only affects a single manual run). Now that this
        // project is actually deployed, the placeholder this used to be would silently break
        // every automatic build, so it's the real project ID - same as GAR_LOCATION/
        // GAR_REPOSITORY/GKE_CLUSTER/GKE_ZONE below, which are likewise real values, not
        // placeholders.
        string(name: 'GCP_PROJECT_ID', defaultValue: 'hcldemo-504209', description: 'GCP project hosting Artifact Registry and GKE')
        string(name: 'GAR_LOCATION', defaultValue: 'us-central1', description: 'Artifact Registry region')
        string(name: 'GAR_REPOSITORY', defaultValue: 'employee-app', description: 'Artifact Registry Docker repository name')
        string(name: 'GKE_CLUSTER', defaultValue: 'employee-app-poc-gke', description: 'GKE cluster name (provisioned by Terraform under infra/)')
        string(name: 'GKE_ZONE', defaultValue: 'us-central1-a', description: 'GKE cluster zone (single-zone POC cluster)')
    }

    environment {
        NAMESPACE      = 'employee-app-poc'
        GAR_HOST       = "${params.GAR_LOCATION}-docker.pkg.dev"
        BACKEND_IMAGE  = "${GAR_HOST}/${params.GCP_PROJECT_ID}/${params.GAR_REPOSITORY}/backend"
        FRONTEND_IMAGE = "${GAR_HOST}/${params.GCP_PROJECT_ID}/${params.GAR_REPOSITORY}/frontend"

        // Placeholder credential IDs - see header comment. `credentials()` in this block both
        // exposes and masks the secret value for every stage/post block in this run.
        GCP_SA_KEY  = credentials('gcp-sa-key')
        SONAR_TOKEN = credentials('sonar-token')
    }

    stages {

        stage('1. Checkout') {
            steps {
                checkout scm
                script {
                    env.GIT_COMMIT_SHA = sh(script: 'git rev-parse --short=12 HEAD', returnStdout: true).trim()
                    echo "Building commit ${env.GIT_COMMIT_SHA}"
                }
            }
        }

        stage('2. Secret Scan (Gitleaks)') {
            steps {
                // Public repo (per ARCHITECTURE.md section 10) - this gates every build.
                // Non-zero exit on any finding fails this stage and aborts the pipeline.
                sh '''
                    docker run --rm -v "$WORKSPACE:/repo" zricethezav/gitleaks:latest \
                        detect --source /repo -v --redact \
                        --report-format json --report-path /repo/gitleaks-report.json
                '''
            }
            post {
                always {
                    archiveArtifacts artifacts: 'gitleaks-report.json', allowEmptyArchive: true
                }
            }
        }

        stage('3. Detect Changed Paths') {
            steps {
                script {
                    // Path-diff skip logic was here (diff against GIT_PREVIOUS_SUCCESSFUL_COMMIT
                    // or HEAD~1) but only ever compares against the immediate parent commit, not
                    // cumulatively back to the last build that actually deployed - a push that
                    // doesn't itself touch backend/frontend (e.g. a Jenkinsfile or infra fix)
                    // would skip every build/deploy stage even when a real, undeployed app change
                    // is sitting one or more commits back. Every push now builds and deploys both.
                    env.BACKEND_CHANGED = 'true'
                    env.FRONTEND_CHANGED = 'true'

                    echo "BACKEND_CHANGED=${env.BACKEND_CHANGED}  FRONTEND_CHANGED=${env.FRONTEND_CHANGED}"
                }
            }
        }

        stage('4. Backend Build & Test') {
            when { expression { env.BACKEND_CHANGED == 'true' } }
            steps {
                dir('backend') {
                    // Runs JUnit tests + JaCoCo coverage report (see backend/pom.xml).
                    // Flyway migrations run at app startup, not here - see ARCHITECTURE.md section 8.
                    sh 'mvn --batch-mode clean verify'
                }
            }
            post {
                always {
                    junit testResults: 'backend/target/surefire-reports/*.xml', allowEmptyResults: true
                    archiveArtifacts artifacts: 'backend/target/site/jacoco/**, backend/target/*.jar', allowEmptyArchive: true
                }
            }
        }

        stage('5. SonarQube Analysis') {
            when { expression { env.BACKEND_CHANGED == 'true' } }
            steps {
                dir('backend') {
                    // 'self-hosted-sonarqube' must match a "SonarQube servers" entry under
                    // Manage Jenkins > System (self-hosted instance per ARCHITECTURE.md section 3/8).
                    withSonarQubeEnv('self-hosted-sonarqube') {
                        // Full plugin coordinate, not the "sonar:sonar" prefix shorthand -
                        // org.sonarsource.scanner.maven isn't in Maven's default
                        // plugin-prefix search groups (org.apache.maven.plugins,
                        // org.codehaus.mojo), so the shorthand fails to resolve.
                        sh '''
                            mvn --batch-mode org.sonarsource.scanner.maven:sonar-maven-plugin:sonar \
                                -Dsonar.projectKey=employee-app-backend \
                                -Dsonar.login=$SONAR_TOKEN \
                                -Dsonar.java.coveragePlugin=jacoco \
                                -Dsonar.coverage.jacoco.xmlReportPaths=target/site/jacoco/jacoco.xml
                        '''
                    }
                }
            }
        }

        stage('6. Quality Gate') {
            when { expression { env.BACKEND_CHANGED == 'true' } }
            steps {
                // Requires the SonarQube webhook to be pointed back at this Jenkins instance;
                // aborts the pipeline (no image is built) if the gate fails or times out.
                timeout(time: 10, unit: 'MINUTES') {
                    script {
                        def qg = waitForQualityGate()
                        if (qg.status != 'OK') {
                            error "SonarQube Quality Gate failed: ${qg.status} - aborting pipeline, no image will be built."
                        }
                    }
                }
            }
        }

        stage('7. Docker Build') {
            when { expression { env.BACKEND_CHANGED == 'true' || env.FRONTEND_CHANGED == 'true' } }
            parallel {
                stage('Build backend image') {
                    when { expression { env.BACKEND_CHANGED == 'true' } }
                    steps {
                        sh "docker build -t ${env.BACKEND_IMAGE}:${env.GIT_COMMIT_SHA} ./backend"
                    }
                }
                stage('Build frontend image') {
                    when { expression { env.FRONTEND_CHANGED == 'true' } }
                    steps {
                        sh "docker build -t ${env.FRONTEND_IMAGE}:${env.GIT_COMMIT_SHA} ./frontend"
                    }
                }
            }
        }

        stage('8. Image Scan (Trivy)') {
            when { expression { env.BACKEND_CHANGED == 'true' || env.FRONTEND_CHANGED == 'true' } }
            steps {
                script {
                    if (env.BACKEND_CHANGED == 'true') {
                        sh "trivy image --exit-code 1 --severity HIGH,CRITICAL --ignore-unfixed --no-progress ${env.BACKEND_IMAGE}:${env.GIT_COMMIT_SHA}"
                    }
                    if (env.FRONTEND_CHANGED == 'true') {
                        sh "trivy image --exit-code 1 --severity HIGH,CRITICAL --ignore-unfixed --no-progress ${env.FRONTEND_IMAGE}:${env.GIT_COMMIT_SHA}"
                    }
                }
            }
        }

        stage('9. Push to Artifact Registry') {
            when { expression { env.BACKEND_CHANGED == 'true' || env.FRONTEND_CHANGED == 'true' } }
            steps {
                sh '''
                    gcloud auth activate-service-account --key-file="$GCP_SA_KEY"
                    gcloud auth configure-docker "$GAR_HOST" --quiet
                '''
                script {
                    if (env.BACKEND_CHANGED == 'true') {
                        sh "docker push ${env.BACKEND_IMAGE}:${env.GIT_COMMIT_SHA}"
                    }
                    if (env.FRONTEND_CHANGED == 'true') {
                        sh "docker push ${env.FRONTEND_IMAGE}:${env.GIT_COMMIT_SHA}"
                    }
                }
            }
        }

        stage('10. Helm Lint & Template') {
            when { expression { env.BACKEND_CHANGED == 'true' || env.FRONTEND_CHANGED == 'true' } }
            steps {
                script {
                    if (env.BACKEND_CHANGED == 'true') {
                        sh """
                            helm lint helm/backend
                            helm template backend helm/backend \
                                --namespace ${env.NAMESPACE} \
                                --set image.repository=${env.BACKEND_IMAGE} \
                                --set image.tag=${env.GIT_COMMIT_SHA} > /dev/null
                        """
                    }
                    if (env.FRONTEND_CHANGED == 'true') {
                        sh """
                            helm lint helm/frontend
                            helm template frontend helm/frontend \
                                --namespace ${env.NAMESPACE} \
                                --set image.repository=${env.FRONTEND_IMAGE} \
                                --set image.tag=${env.GIT_COMMIT_SHA} > /dev/null
                        """
                    }
                }
            }
        }

        stage('11. Deploy to GKE') {
            when { expression { env.BACKEND_CHANGED == 'true' || env.FRONTEND_CHANGED == 'true' } }
            steps {
                sh """
                    gcloud container clusters get-credentials ${params.GKE_CLUSTER} \
                        --zone ${params.GKE_ZONE} --project ${params.GCP_PROJECT_ID}
                """
                script {
                    // employee-app-secrets and employee-app-config are bootstrapped manually
                    // in-cluster (see README.md) - the charts only reference them by name,
                    // never template their contents.
                    if (env.BACKEND_CHANGED == 'true') {
                        sh """
                            helm upgrade --install backend helm/backend \
                                --namespace ${env.NAMESPACE} --create-namespace \
                                --set image.repository=${env.BACKEND_IMAGE} \
                                --set image.tag=${env.GIT_COMMIT_SHA} \
                                --wait --timeout 5m
                        """
                    }
                    if (env.FRONTEND_CHANGED == 'true') {
                        sh """
                            helm upgrade --install frontend helm/frontend \
                                --namespace ${env.NAMESPACE} --create-namespace \
                                --set image.repository=${env.FRONTEND_IMAGE} \
                                --set image.tag=${env.GIT_COMMIT_SHA} \
                                --wait --timeout 5m
                        """
                    }
                }
            }
            post {
                // Stage 14: rollback whichever release(s) this build touched if the deploy itself fails.
                failure {
                    script { rollbackChangedReleases('Deploy to GKE stage failed') }
                }
            }
        }

        stage('12. Smoke Test') {
            when { expression { env.BACKEND_CHANGED == 'true' || env.FRONTEND_CHANGED == 'true' } }
            steps {
                sh "kubectl -n ${env.NAMESPACE} rollout status deploy/backend --timeout=120s"
                sh """
                    kubectl -n ${env.NAMESPACE} run smoke-test-${env.BUILD_NUMBER} \
                        --rm -i --restart=Never --image=curlimages/curl:8.10.1 \
                        --command -- curl -sf http://backend.${env.NAMESPACE}.svc.cluster.local:8080/actuator/health
                """
            }
            post {
                // Stage 14: rollback whichever release(s) this build touched if the freshly
                // deployed backend fails its post-deploy health check.
                failure {
                    script { rollbackChangedReleases('Post-deploy smoke test against /actuator/health failed') }
                }
            }
        }
    }

    post {
        // Stage 13 (Notify): implemented here rather than as a mid-flow stage so it always
        // fires, no matter which stage above failed - see header comment.
        success {
            script { notify('SUCCESS') }
        }
        unstable {
            script { notify('UNSTABLE') }
        }
        failure {
            script { notify('FAILURE') }
        }
        aborted {
            script { notify('ABORTED') }
        }
    }
}
