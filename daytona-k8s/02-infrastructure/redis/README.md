# Redis for Daytona
# Deploys Bitnami Redis chart with master-replica topology
#
# Install:
#   helm repo add bitnami https://charts.bitnami.com/bitnami
#   helm repo update
#   helm install daytona-redis bitnami/redis \
#     -n daytona \
#     -f redis-values.yaml \
#     --set auth.password="$(grep REDIS_PASSWORD ../01-secrets/.secrets-backup.env | cut -d= -f2)"
#
# Or apply the raw manifest below:
