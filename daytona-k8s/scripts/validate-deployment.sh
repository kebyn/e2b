#!/bin/bash
# validate-deployment.sh - Post-deployment validation checks
# Run after deploy.sh to verify everything is working
set -euo pipefail

NAMESPACE="daytona"
DOMAIN="${1:-sandbox.company.com}"
ERRORS=0
WARNINGS=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; ((ERRORS++)); }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; ((WARNINGS++)); }
check() { echo -e "  Checking: $*"; }

echo "========================================="
echo "  Daytona Deployment Validation"
echo "  Domain: ${DOMAIN}"
echo "========================================="
echo ""

# 1. Namespace
check "Namespace exists"
kubectl get namespace ${NAMESPACE} &>/dev/null && pass "Namespace ${NAMESPACE} exists" || fail "Namespace not found"

# 2. Secrets
check "Required secrets"
for secret in daytona-core daytona-db daytona-redis daytona-s3 daytona-registry; do
  kubectl -n ${NAMESPACE} get secret ${secret} &>/dev/null && pass "Secret ${secret} exists" || fail "Missing secret: ${secret}"
done

# 3. PostgreSQL
check "PostgreSQL cluster"
kubectl -n ${NAMESPACE} get cluster daytona-postgres &>/dev/null && {
  phase=$(kubectl -n ${NAMESPACE} get cluster daytona-postgres -o jsonpath='{.status.phase}' 2>/dev/null)
  [[ "${phase}" == "Cluster in healthy state" ]] && pass "PostgreSQL healthy (${phase})" || warn "PostgreSQL phase: ${phase}"
} || warn "PostgreSQL cluster not found (CloudNativePG may not be installed)"

# 4. Pods running
check "Pod status"
for dep in daytona-api daytona-proxy daytona-ssh-gateway; do
  ready=$(kubectl -n ${NAMESPACE} get deployment ${dep} -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
  desired=$(kubectl -n ${NAMESPACE} get deployment ${dep} -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
  [[ "${ready}" == "${desired}" && "${ready}" != "0" ]] && pass "${dep}: ${ready}/${desired} ready" || fail "${dep}: ${ready}/${desired} ready"
done

# Runner pods
runner_count=$(kubectl -n ${NAMESPACE} get pods -l app.kubernetes.io/name=daytona-runner --field-selector=status.phase=Running -o name 2>/dev/null | wc -l)
[[ ${runner_count} -gt 0 ]] && pass "Runners: ${runner_count} running" || fail "No running runner pods"

# MinIO
check "MinIO"
kubectl -n ${NAMESPACE} get statefulset daytona-minio &>/dev/null && {
  ready=$(kubectl -n ${NAMESPACE} get statefulset daytona-minio -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
  [[ "${ready}" -gt 0 ]] && pass "MinIO ready" || warn "MinIO not ready"
} || warn "MinIO not deployed"

# Redis
check "Redis"
redis_pod=$(kubectl -n ${NAMESPACE} get pods -l app.kubernetes.io/name=redis -o name 2>/dev/null | head -1)
[[ -n "${redis_pod}" ]] && pass "Redis pod found" || warn "Redis pods not found"

# Registry
check "Registry"
kubectl -n ${NAMESPACE} get deployment daytona-registry &>/dev/null && {
  ready=$(kubectl -n ${NAMESPACE} get deployment daytona-registry -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
  [[ "${ready}" -gt 0 ]] && pass "Registry ready" || warn "Registry not ready"
} || warn "Registry not deployed"

# 5. Services
check "Services"
for svc in daytona-api daytona-proxy daytona-ssh-gateway daytona-runner; do
  endpoints=$(kubectl -n ${NAMESPACE} get endpoints ${svc} -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w)
  [[ ${endpoints} -gt 0 ]] && pass "Service ${svc}: ${endpoints} endpoints" || warn "Service ${svc}: no endpoints"
done

# 6. Ingress
check "Ingress"
for ing in daytona-api daytona-proxy; do
  kubectl -n ${NAMESPACE} get ingress ${ing} &>/dev/null && pass "Ingress ${ing} configured" || warn "Ingress ${ing} not found"
done

# 7. Health endpoint
check "API health endpoint"
api_svc=$(kubectl -n ${NAMESPACE} get svc daytona-api -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
if [[ -n "${api_svc}" ]]; then
  health=$(kubectl -n ${NAMESPACE} run health-check --rm -i --restart=Never --image=curlimages/curl:latest -- \
    curl -s -o /dev/null -w '%{http_code}' "http://${api_svc}:3000/api/health" 2>/dev/null || echo "000")
  [[ "${health}" == "200" ]] && pass "API health: HTTP ${health}" || warn "API health: HTTP ${health}"
else
  warn "Cannot find API service IP"
fi

# 8. Resource quotas
check "Resource usage"
echo "  CPU/Memory requests:"
kubectl -n ${NAMESPACE} describe resourcequota daytona-quota 2>/dev/null | grep -E "requests\.(cpu|memory)" || warn "ResourceQuota not found"

echo ""
echo "========================================="
echo "  Validation Summary"
echo "========================================="
echo -e "  Errors:   ${ERRORS}"
echo -e "  Warnings: ${WARNINGS}"
echo ""
if [[ ${ERRORS} -eq 0 ]]; then
  if [[ ${WARNINGS} -eq 0 ]]; then
    echo -e "${GREEN}  All checks passed!${NC}"
  else
    echo -e "${YELLOW}  Deployment functional with ${WARNINGS} warnings${NC}"
  fi
  echo ""
  echo "  Test sandbox creation:"
  echo "    pip install daytona"
  echo "    python3 -c \""
  echo "    from daytona import Daytona, DaytonaConfig"
  echo "    config = DaytonaConfig("
  echo "      api_url='https://api.${DOMAIN}/api',"
  echo "      api_key='YOUR_ADMIN_API_KEY'"
  echo "    )"
  echo "    client = Daytona(config)"
  echo "    sandbox = client.create()"
  echo "    print(sandbox.process.code_run('print(\\\"Hello from Daytona!\\\")').result)"
  echo "    sandbox.delete()"
  echo "    \""
else
  echo -e "${RED}  Deployment has ${ERRORS} errors - please fix before use${NC}"
  exit 1
fi
