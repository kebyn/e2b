# CloudNativePG Operator Installation
#
# Prerequisites:
#   kubectl apply -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.25/releases/cnpg-1.25.0.yaml
#
# Verify:
#   kubectl -n cnpg-system get pods
#
# Then apply this file:
#   kubectl apply -f postgres-cluster.yaml
