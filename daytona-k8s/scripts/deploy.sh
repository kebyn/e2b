#!/bin/bash
# deploy.sh - Daytona Kubernetes Deployment Script
# Usage: ./deploy.sh [ACTION] [OPTIONS]
#
# Actions:
#   deploy-all      Deploy everything from scratch
#   deploy-infra    Deploy infrastructure only (PG, Redis, MinIO, Registry)
#   deploy-app      Deploy application only (API, Proxy, SSH, Runner)
#   deploy-monitor  Deploy monitoring (OTel, Jaeger)
#   status          Check deployment status
#   logs            Tail logs for a component
#   migrate         Run database migrations
#   upgrade         Rolling upgrade of application components
#   destroy         Tear down everything (DANGEROUS)
#
# Options:
#   --domain        Base domain (default: sandbox.company.com)
#   --replicas      Number of runner replicas (default: 2)
#   --storage-class Kubernetes StorageClass name
#   --dry-run       Show what would be deployed
#
# Examples:
#   ./deploy.sh deploy-all --domain my.company.com --storage-class gp3
#   ./deploy.sh status
#   ./deploy.sh logs api
#   ./deploy.sh upgrade --image-tag 0.158.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "${SCRIPT_DIR}")"
NAMESPACE="daytona"

# Defaults
DOMAIN="sandbox.company.com"
RUNNER_REPLICAS=2
STORAGE_CLASS=""
IMAGE_TAG="0.157.0"
DRY_RUN=""
ACTION="${1:-help}"
shift || true

# Parse options
while [[ $# -gt 0 ]]; do
  case $1 in
    --domain) DOMAIN="$2"; shift 2 ;;
    --replicas) RUNNER_REPLICAS="$2"; shift 2 ;;
    --storage-class) STORAGE_CLASS="$2"; shift 2 ;;
    --image-tag) IMAGE_TAG="$2"; shift 2 ;;
    --dry-run) DRY_RUN="--dry-run=client"; shift ;;
    *) shift ;;
  esac
done

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*" >&2; }
info() { echo -e "${BLUE}[i]${NC} $*"; }

check_prerequisites() {
  log "Checking prerequisites..."
  local missing=()
  for cmd in kubectl helm openssl htpasswd; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    err "Missing required tools: ${missing[*]}"
    exit 1
  fi
  kubectl cluster-info &>/dev/null || { err "Cannot connect to Kubernetes cluster"; exit 1; }
  log "Prerequisites OK"
}

set_storage_class() {
  if [[ -n "${STORAGE_CLASS}" ]]; then
    info "Using StorageClass: ${STORAGE_CLASS}"
    # Patch storage class in manifests
    find "${BASE_DIR}" -name '*.yaml' -exec sed -i "s/storageClassName: \"\"/storageClassName: \"${STORAGE_CLASS}\"/g" {} \;
  fi
}

deploy_namespace() {
  log "Deploying namespace and RBAC..."
  kubectl apply ${DRY_RUN} -f "${BASE_DIR}/00-namespace/"
}

deploy_secrets() {
  log "Generating and deploying secrets..."
  if [[ -f "${BASE_DIR}/01-secrets/.secrets-backup.env" ]]; then
    warn "Secrets backup already exists. Re-generating will overwrite."
    read -p "Continue? (y/N) " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && return
  fi
  bash "${BASE_DIR}/scripts/generate-secrets.sh" "${DOMAIN}"
}

deploy_infrastructure() {
  log "Deploying infrastructure..."

  log "Deploying PostgreSQL (CloudNativePG)..."
  kubectl apply ${DRY_RUN} -f "${BASE_DIR}/02-infrastructure/postgres/postgres-cluster.yaml"
  log "Waiting for PostgreSQL to be ready..."
  kubectl -n ${NAMESPACE} wait --for=condition=Ready cluster/daytona-postgres --timeout=300s || warn "PG not ready yet, continuing"

  log "Deploying Redis..."
  if command -v helm &>/dev/null; then
    helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
    helm repo update bitnami
    helm upgrade --install daytona-redis bitnami/redis \
      -n ${NAMESPACE} \
      -f "${BASE_DIR}/02-infrastructure/redis/redis-values.yaml" \
      --set auth.password="$(kubectl -n ${NAMESPACE} get secret daytona-redis -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || openssl rand -hex 16)" \
      --wait --timeout 300s
  else
    warn "Helm not found, skipping Redis Helm deployment. Deploy manually."
  fi

  log "Deploying MinIO..."
  kubectl apply ${DRY_RUN} -f "${BASE_DIR}/02-infrastructure/minio/minio-statefulset.yaml"
  kubectl -n ${NAMESPACE} rollout status statefulset/daytona-minio --timeout=180s || warn "MinIO not ready yet"

  log "Deploying Docker Registry..."
  kubectl apply ${DRY_RUN} -f "${BASE_DIR}/02-infrastructure/registry/registry-deployment.yaml"

  log "Deploying Keycloak..."
  if command -v helm &>/dev/null; then
    helm upgrade --install daytona-keycloak bitnami/keycloak \
      -n ${NAMESPACE} \
      -f "${BASE_DIR}/02-infrastructure/keycloak/keycloak-values.yaml" \
      --wait --timeout 300s
  else
    warn "Helm not found, skipping Keycloak Helm deployment. Deploy manually."
  fi

  log "Waiting for infrastructure pods..."
  kubectl -n ${NAMESPACE} wait --for=condition=Ready pod --all --timeout=300s 2>/dev/null || true
}

deploy_application() {
  log "Deploying application components..."

  kubectl apply ${DRY_RUN} -f "${BASE_DIR}/03-application/api/api-deployment.yaml"
  kubectl apply ${DRY_RUN} -f "${BASE_DIR}/03-application/proxy/proxy-deployment.yaml"
  kubectl apply ${DRY_RUN} -f "${BASE_DIR}/03-application/ssh-gateway/ssh-gateway-deployment.yaml"
  kubectl apply ${DRY_RUN} -f "${BASE_DIR}/03-application/runner/runner-statefulset.yaml"

  # Set DOMAIN env var in all deployments
  for dep in daytona-api daytona-proxy daytona-ssh-gateway; do
    kubectl -n ${NAMESPACE} set env deployment/${dep} DOMAIN=${DOMAIN} 2>/dev/null || true
  done
  for i in $(seq 0 $((RUNNER_REPLICAS - 1))); do
    kubectl -n ${NAMESPACE} set env statefulset/daytona-runner DOMAIN=${DOMAIN} 2>/dev/null || true
  done

  # Scale runner replicas
  kubectl -n ${NAMESPACE} scale statefulset daytona-runner --replicas=${RUNNER_REPLICAS}

  log "Waiting for API to be ready..."
  kubectl -n ${NAMESPACE} rollout status deployment/daytona-api --timeout=600s

  log "Waiting for Proxy to be ready..."
  kubectl -n ${NAMESPACE} rollout status deployment/daytona-proxy --timeout=300s

  log "Waiting for SSH Gateway to be ready..."
  kubectl -n ${NAMESPACE} rollout status deployment/daytona-ssh-gateway --timeout=300s

  log "Waiting for Runners to be ready..."
  kubectl -n ${NAMESPACE} rollout status statefulset/daytona-runner --timeout=600s
}

deploy_monitoring() {
  log "Deploying monitoring stack..."
  kubectl apply ${DRY_RUN} -f "${BASE_DIR}/04-monitoring/otel/otel-collector.yaml"
  kubectl apply ${DRY_RUN} -f "${BASE_DIR}/04-monitoring/jaeger/jaeger-deployment.yaml"
}

deploy_ingress() {
  log "Deploying ingress..."
  # Replace domain placeholder
  sed "s/sandbox.company.com/${DOMAIN}/g" "${BASE_DIR}/05-ingress/ingress.yaml" | kubectl apply ${DRY_RUN} -f -
}

deploy_all() {
  check_prerequisites
  set_storage_class
  deploy_namespace
  deploy_secrets
  deploy_infrastructure
  deploy_monitoring
  deploy_application
  deploy_ingress
  print_summary
}

show_status() {
  echo ""
  echo "========================================="
  echo "  Daytona Deployment Status"
  echo "========================================="
  echo ""

  echo "--- Namespace ---"
  kubectl get namespace ${NAMESPACE} 2>/dev/null || { err "Namespace not found"; return; }

  echo ""
  echo "--- Pods ---"
  kubectl -n ${NAMESPACE} get pods -o wide

  echo ""
  echo "--- Services ---"
  kubectl -n ${NAMESPACE} get svc

  echo ""
  echo "--- Ingress ---"
  kubectl -n ${NAMESPACE} get ingress

  echo ""
  echo "--- PVCs ---"
  kubectl -n ${NAMESPACE} get pvc

  echo ""
  echo "--- HPA ---"
  kubectl -n ${NAMESPACE} get hpa

  echo ""
  echo "--- PostgreSQL ---"
  kubectl -n ${NAMESPACE} get cluster 2>/dev/null || echo "  (CloudNativePG not available)"

  echo ""
  echo "--- Recent Events ---"
  kubectl -n ${NAMESPACE} get events --sort-by='.lastTimestamp' | tail -20
}

tail_logs() {
  local component="${1:-api}"
  case ${component} in
    api)     kubectl -n ${NAMESPACE} logs -f -l app.kubernetes.io/name=daytona-api --tail=100 ;;
    proxy)   kubectl -n ${NAMESPACE} logs -f -l app.kubernetes.io/name=daytona-proxy --tail=100 ;;
    ssh)     kubectl -n ${NAMESPACE} logs -f -l app.kubernetes.io/name=daytona-ssh-gateway --tail=100 ;;
    runner)  kubectl -n ${NAMESPACE} logs -f -l app.kubernetes.io/name=daytona-runner --tail=100 ;;
    all)     kubectl -n ${NAMESPACE} logs -f -l app.kubernetes.io/part-of=daytona --tail=100 --max-log-requests=10 ;;
    *)       err "Unknown component: ${component}. Use: api, proxy, ssh, runner, all" ;;
  esac
}

run_migration() {
  log "Running database migrations..."
  kubectl -n ${NAMESPACE} exec deploy/daytona-api -- node dist/apps/api/main.js --migration-run
}

do_upgrade() {
  log "Upgrading application to tag: ${IMAGE_TAG}"
  for dep in daytona-api daytona-proxy daytona-ssh-gateway; do
    kubectl -n ${NAMESPACE} set image deployment/${dep} ${dep}=daytonaio/${dep}:${IMAGE_TAG}
  done
  kubectl -n ${NAMESPACE} set image statefulset/daytona-runner daytona-runner=daytonaio/daytona-runner:${IMAGE_TAG}

  kubectl -n ${NAMESPACE} rollout status deployment/daytona-api --timeout=600s
  kubectl -n ${NAMESPACE} rollout status deployment/daytona-proxy --timeout=300s
  kubectl -n ${NAMESPACE} rollout status statefulset/daytona-runner --timeout=600s
  log "Upgrade complete"
}

destroy_all() {
  warn "This will DELETE the entire Daytona deployment including all data!"
  read -p "Type 'yes-delete-everything' to confirm: " -r
  if [[ "$REPLY" == "yes-delete-everything" ]]; then
    log "Destroying Daytona deployment..."
    kubectl delete namespace ${NAMESPACE} --wait=true
    kubectl delete clusterrole daytona-runner 2>/dev/null || true
    kubectl delete clusterrolebinding daytona-runner 2>/dev/null || true
    kubectl delete -f "${BASE_DIR}/05-ingress/ingress.yaml" 2>/dev/null || true
    log "Deployment destroyed"
  else
    err "Aborted"
  fi
}

print_summary() {
  echo ""
  echo "========================================="
  echo "  Daytona Deployment Complete"
  echo "========================================="
  echo ""
  echo "  API Dashboard:  https://api.${DOMAIN}"
  echo "  Sandbox Proxy:  https://{PORT}-{sandboxId}.proxy.${DOMAIN}"
  echo "  SSH Gateway:    ssh -p 2222 {TOKEN}@ssh.${DOMAIN}"
  echo "  Jaeger UI:      https://jaeger.${DOMAIN}"
  echo ""
  echo "  Admin API Key:  (check 01-secrets/.secrets-backup.env)"
  echo ""
  echo "  Quick test:"
  echo "    curl https://api.${DOMAIN}/api/health"
  echo ""
  echo "  Next steps:"
  echo "    1. Configure DNS: *.proxy.${DOMAIN} -> Ingress LB IP"
  echo "    2. Replace TLS cert if using self-signed"
  echo "    3. Configure SMTP relay"
  echo "    4. Import Keycloak realm & create users"
  echo "    5. Verify: $(basename "$0") status"
  echo ""
}

show_help() {
  echo "Usage: $(basename "$0") ACTION [OPTIONS]"
  echo ""
  echo "Actions:"
  echo "  deploy-all      Full deployment (infra + app + monitoring)"
  echo "  deploy-infra    Infrastructure only"
  echo "  deploy-app      Application only"
  echo "  deploy-monitor  Monitoring only"
  echo "  deploy-ingress  Ingress only"
  echo "  status          Show deployment status"
  echo "  logs [comp]     Tail logs (api|proxy|ssh|runner|all)"
  echo "  migrate         Run DB migrations"
  echo "  upgrade         Upgrade app images"
  echo "  destroy         Delete everything"
  echo ""
  echo "Options:"
  echo "  --domain NAME       Base domain (default: sandbox.company.com)"
  echo "  --replicas N        Runner replica count (default: 2)"
  echo "  --storage-class SC  StorageClass name"
  echo "  --image-tag TAG     Image tag for upgrade (default: 0.157.0)"
  echo "  --dry-run           Preview only"
}

# Main
case "${ACTION}" in
  deploy-all)     deploy_all ;;
  deploy-infra)   check_prerequisites; set_storage_class; deploy_namespace; deploy_secrets; deploy_infrastructure ;;
  deploy-app)     check_prerequisites; deploy_application ;;
  deploy-monitor) check_prerequisites; deploy_monitoring ;;
  deploy-ingress) check_prerequisites; deploy_ingress ;;
  status)         show_status ;;
  logs)           tail_logs "${1:-api}" ;;
  migrate)        run_migration ;;
  upgrade)        do_upgrade ;;
  destroy)        destroy_all ;;
  help|--help|-h) show_help ;;
  *)              err "Unknown action: ${ACTION}"; show_help; exit 1 ;;
esac
