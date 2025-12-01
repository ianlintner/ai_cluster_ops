#!/bin/bash
# deploy.sh - Quick deployment helper for bigboy cluster
# 
# Usage:
#   ./scripts/deploy.sh <app-name> <image-tag> [hostname]
#
# Examples:
#   ./scripts/deploy.sh myapp latest
#   ./scripts/deploy.sh myapp v1.2.3 custom.cat-herding.net

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
REGISTRY="gabby.azurecr.io"
NAMESPACE="${NAMESPACE:-default}"
HELM_CHART_PATH="$(dirname "$0")/../helm/app-template"

# Arguments
APP_NAME="${1:-}"
IMAGE_TAG="${2:-latest}"
HOSTNAME="${3:-${APP_NAME}.cat-herding.net}"

usage() {
    echo "Usage: $0 <app-name> [image-tag] [hostname]"
    echo ""
    echo "Arguments:"
    echo "  app-name    Name of the application (required)"
    echo "  image-tag   Docker image tag (default: latest)"
    echo "  hostname    Custom hostname (default: <app-name>.cat-herding.net)"
    echo ""
    echo "Examples:"
    echo "  $0 myapp"
    echo "  $0 myapp v1.2.3"
    echo "  $0 myapp latest custom.cat-herding.net"
    exit 1
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Validation
if [[ -z "$APP_NAME" ]]; then
    log_error "App name is required"
    usage
fi

# Check prerequisites
command -v kubectl >/dev/null 2>&1 || { log_error "kubectl is required but not installed"; exit 1; }
command -v helm >/dev/null 2>&1 || { log_error "helm is required but not installed"; exit 1; }

# Verify cluster connection
log_info "Verifying cluster connection..."
if ! kubectl cluster-info >/dev/null 2>&1; then
    log_error "Cannot connect to cluster. Run: az aks get-credentials --resource-group nekoc --name bigboy"
    exit 1
fi

CURRENT_CONTEXT=$(kubectl config current-context)
if [[ "$CURRENT_CONTEXT" != "bigboy" ]]; then
    log_warn "Current context is '$CURRENT_CONTEXT', not 'bigboy'"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check if image exists in ACR
log_info "Checking image ${REGISTRY}/${APP_NAME}:${IMAGE_TAG}..."
if ! az acr repository show --name gabby --image "${APP_NAME}:${IMAGE_TAG}" >/dev/null 2>&1; then
    log_warn "Image ${APP_NAME}:${IMAGE_TAG} not found in ACR. Proceeding anyway..."
fi

# Deploy with Helm
log_info "Deploying ${APP_NAME} to namespace ${NAMESPACE}..."

helm upgrade --install "${APP_NAME}" "${HELM_CHART_PATH}" \
    --namespace "${NAMESPACE}" \
    --create-namespace \
    --set app.name="${APP_NAME}" \
    --set app.image="${REGISTRY}/${APP_NAME}" \
    --set app.tag="${IMAGE_TAG}" \
    --set app.hostname="${HOSTNAME}" \
    --wait \
    --timeout 5m

# Verify deployment
log_info "Verifying deployment..."
kubectl rollout status "deployment/${APP_NAME}" -n "${NAMESPACE}" --timeout=3m

# Get pod status
log_info "Pod status:"
kubectl get pods -n "${NAMESPACE}" -l "app=${APP_NAME}"

# Print success message
echo ""
log_info "✅ Deployment successful!"
echo ""
echo "🌐 Your app is available at: https://${HOSTNAME}"
echo ""
echo "Useful commands:"
echo "  kubectl logs -l app=${APP_NAME} -f"
echo "  kubectl describe deployment ${APP_NAME}"
echo "  curl -I https://${HOSTNAME}"
