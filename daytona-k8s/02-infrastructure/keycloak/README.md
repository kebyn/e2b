# Keycloak for Daytona OIDC Authentication
#
# Install via Helm:
#   helm repo add bitnami https://charts.bitnami.com/bitnami
#   helm install daytona-keycloak bitnami/keycloak \
#     -n daytona -f keycloak-values.yaml
#
# After install, import the realm:
#   kubectl -n daytona port-forward svc/daytona-keycloak 8080:8080
#   Open http://localhost:8080, login admin/admin
#   Create realm 'daytona' with the config below
