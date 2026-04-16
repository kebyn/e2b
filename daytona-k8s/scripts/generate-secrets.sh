#!/bin/bash
# generate-secrets.sh - Generate all required secrets for Daytona K8s deployment
# Usage: ./generate-secrets.sh [DOMAIN] [OIDC_ISSUER_URL]
#
# Example: ./generate-secrets.sh sandbox.company.com https://keycloak.company.com/realms/daytona

set -euo pipefail

DOMAIN="${1:-sandbox.company.com}"
OIDC_ISSUER="${2:-https://keycloak.company.com/realms/daytona}"
NAMESPACE="daytona"
OUTPUT_DIR="$(dirname "$0")/../01-secrets"

echo "==> Generating secrets for domain: ${DOMAIN}"
echo "==> OIDC Issuer: ${OIDC_ISSUER}"

# Generate random values
ENCRYPTION_KEY=$(openssl rand -base64 32)
ENCRYPTION_SALT=$(openssl rand -base64 16)
ADMIN_API_KEY=$(openssl rand -hex 32)
RUNNER_TOKEN=$(openssl rand -hex 32)
PROXY_API_KEY=$(openssl rand -hex 32)
SSH_GATEWAY_API_KEY=$(openssl rand -hex 32)
SSH_PRIVATE_KEY=$(openssl genrsa 2048 2>/dev/null | base64 -w0)
SSH_HOST_KEY=$(ssh-keygen -t rsa -b 2048 -f /tmp/daytona-host-key -N "" -q && cat /tmp/daytona-host-key | base64 -w0 && rm -f /tmp/daytona-host-key /tmp/daytona-host-key.pub)
DB_PASSWORD=$(openssl rand -hex 16)
REDIS_PASSWORD=$(openssl rand -hex 16)
MINIO_ACCESS_KEY=$(openssl rand -hex 12)
MINIO_SECRET_KEY=$(openssl rand -hex 24)
REGISTRY_PASSWORD=$(openssl rand -hex 16)
HEALTH_CHECK_KEY=$(openssl rand -hex 16)
OTEL_COLLECTOR_KEY=$(openssl rand -hex 16)
REGISTRY_HTPASSWD=$(htpasswd -nBb daytona-robot "${REGISTRY_PASSWORD}" 2>/dev/null || echo "daytona-robot:\$2y\$05\$placeholder")

# Save plain-text backup (protect this file!)
SECRETS_BACKUP="${OUTPUT_DIR}/.secrets-backup.env"
cat > "${SECRETS_BACKUP}" <<EOF
# Daytona Secrets Backup - GENERATED $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# PROTECT THIS FILE - DO NOT COMMIT TO GIT
DOMAIN=${DOMAIN}
OIDC_ISSUER=${OIDC_ISSUER}
ENCRYPTION_KEY=${ENCRYPTION_KEY}
ENCRYPTION_SALT=${ENCRYPTION_SALT}
ADMIN_API_KEY=${ADMIN_API_KEY}
RUNNER_TOKEN=${RUNNER_TOKEN}
PROXY_API_KEY=${PROXY_API_KEY}
SSH_GATEWAY_API_KEY=${SSH_GATEWAY_API_KEY}
DB_PASSWORD=${DB_PASSWORD}
REDIS_PASSWORD=${REDIS_PASSWORD}
MINIO_ACCESS_KEY=${MINIO_ACCESS_KEY}
MINIO_SECRET_KEY=${MINIO_SECRET_KEY}
REGISTRY_PASSWORD=${REGISTRY_PASSWORD}
HEALTH_CHECK_KEY=${HEALTH_CHECK_KEY}
OTEL_COLLECTOR_KEY=${OTEL_COLLECTOR_KEY}
EOF
chmod 600 "${SECRETS_BACKUP}"
echo "==> Secrets backup saved to: ${SECRETS_BACKUP}"

# Apply secrets to K8s
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Core secrets
kubectl -n ${NAMESPACE} create secret generic daytona-core \
  --from-literal=encryption-key="${ENCRYPTION_KEY}" \
  --from-literal=encryption-salt="${ENCRYPTION_SALT}" \
  --from-literal=admin-api-key="${ADMIN_API_KEY}" \
  --from-literal=runner-token="${RUNNER_TOKEN}" \
  --from-literal=proxy-api-key="${PROXY_API_KEY}" \
  --from-literal=ssh-gateway-api-key="${SSH_GATEWAY_API_KEY}" \
  --from-literal=health-check-key="${HEALTH_CHECK_KEY}" \
  --from-literal=otel-collector-key="${OTEL_COLLECTOR_KEY}" \
  --from-literal=ssh-private-key="${SSH_PRIVATE_KEY}" \
  --from-literal=ssh-host-key="${SSH_HOST_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -

# Database secrets
kubectl -n ${NAMESPACE} create secret generic daytona-db \
  --from-literal=host="daytona-postgres-rw" \
  --from-literal=port="5432" \
  --from-literal=username="daytona" \
  --from-literal=password="${DB_PASSWORD}" \
  --from-literal=database="daytona" \
  --from-literal=connection-string="postgresql://daytona:${DB_PASSWORD}@daytona-postgres-rw:5432/daytona?sslmode=require" \
  --dry-run=client -o yaml | kubectl apply -f -

# Redis secrets
kubectl -n ${NAMESPACE} create secret generic daytona-redis \
  --from-literal=host="daytona-redis-master" \
  --from-literal=port="6379" \
  --from-literal=password="${REDIS_PASSWORD}" \
  --from-literal=url="redis://:${REDIS_PASSWORD}@daytona-redis-master:6379" \
  --dry-run=client -o yaml | kubectl apply -f -

# S3/MinIO secrets
kubectl -n ${NAMESPACE} create secret generic daytona-s3 \
  --from-literal=endpoint="http://daytona-minio:9000" \
  --from-literal=access-key="${MINIO_ACCESS_KEY}" \
  --from-literal=secret-key="${MINIO_SECRET_KEY}" \
  --from-literal=bucket="daytona" \
  --dry-run=client -o yaml | kubectl apply -f -

# Registry secrets
kubectl -n ${NAMESPACE} create secret generic daytona-registry \
  --from-literal=url="http://daytona-registry:5000" \
  --from-literal=admin="daytona-robot" \
  --from-literal=password="${REGISTRY_PASSWORD}" \
  --from-literal=htpasswd="${REGISTRY_HTPASSWD}" \
  --dry-run=client -o yaml | kubectl apply -f -

# TLS certificate placeholder (replace with real cert)
kubectl -n ${NAMESPACE} create secret tls daytona-tls \
  --cert=/dev/null --key=/dev/null \
  --dry-run=client -o yaml 2>/dev/null || true

echo ""
echo "==> Secrets applied to namespace '${NAMESPACE}'"
echo "==> IMPORTANT: Replace daytona-tls with your real TLS certificate"
echo "==> IMPORTANT: Back up ${SECRETS_BACKUP} to a secure location"
echo ""
echo "Generated secrets:"
echo "  daytona-core       : encryption, tokens, SSH keys"
echo "  daytona-db         : PostgreSQL credentials"
echo "  daytona-redis      : Redis credentials"
echo "  daytona-s3         : MinIO/S3 credentials"
echo "  daytona-registry   : Docker registry credentials"
