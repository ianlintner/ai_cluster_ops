#!/bin/bash
# validate.sh - Pre-deployment validation for Kubernetes manifests
#
# Usage:
#   ./scripts/validate.sh <manifest-path>
#   ./scripts/validate.sh k8s/
#   ./scripts/validate.sh deployment.yaml

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

MANIFEST_PATH="${1:-.}"
ERRORS=0
WARNINGS=0

log_pass() {
    echo -e "${GREEN}✓${NC} $1"
}

log_fail() {
    echo -e "${RED}✗${NC} $1"
    ((ERRORS++))
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARNINGS++))
}

echo "Validating manifests in: ${MANIFEST_PATH}"
echo "================================================"

# Check if path exists
if [[ ! -e "$MANIFEST_PATH" ]]; then
    log_fail "Path does not exist: $MANIFEST_PATH"
    exit 1
fi

# Find all YAML files
YAML_FILES=$(find "$MANIFEST_PATH" -name "*.yaml" -o -name "*.yml" 2>/dev/null || echo "")

if [[ -z "$YAML_FILES" ]]; then
    log_fail "No YAML files found in $MANIFEST_PATH"
    exit 1
fi

echo ""
echo "Checking YAML syntax..."
echo "------------------------"

for file in $YAML_FILES; do
    if kubectl apply --dry-run=client -f "$file" >/dev/null 2>&1; then
        log_pass "Valid YAML: $file"
    else
        log_fail "Invalid YAML: $file"
        kubectl apply --dry-run=client -f "$file" 2>&1 | head -5
    fi
done

echo ""
echo "Checking deployment configurations..."
echo "--------------------------------------"

for file in $YAML_FILES; do
    # Check for Istio sidecar annotation
    if grep -q "kind: Deployment" "$file"; then
        DEPLOYMENT_NAME=$(grep "name:" "$file" | head -1 | awk '{print $2}')
        
        if grep -q 'sidecar.istio.io/inject.*"true"' "$file"; then
            log_pass "Istio sidecar enabled: $DEPLOYMENT_NAME"
        else
            log_warn "Missing Istio sidecar annotation: $DEPLOYMENT_NAME"
        fi
        
        # Check for resource limits
        if grep -q "limits:" "$file"; then
            log_pass "Resource limits set: $DEPLOYMENT_NAME"
        else
            log_fail "Missing resource limits: $DEPLOYMENT_NAME"
        fi
        
        # Check for health probes
        if grep -q "livenessProbe:" "$file"; then
            log_pass "Liveness probe configured: $DEPLOYMENT_NAME"
        else
            log_warn "Missing liveness probe: $DEPLOYMENT_NAME"
        fi
        
        if grep -q "readinessProbe:" "$file"; then
            log_pass "Readiness probe configured: $DEPLOYMENT_NAME"
        else
            log_warn "Missing readiness probe: $DEPLOYMENT_NAME"
        fi
        
        # Check for security context
        if grep -q "runAsNonRoot: true" "$file"; then
            log_pass "Non-root user configured: $DEPLOYMENT_NAME"
        else
            log_fail "Missing runAsNonRoot: true: $DEPLOYMENT_NAME"
        fi
        
        # Check container registry
        if grep -q "gabby.azurecr.io" "$file"; then
            log_pass "Using correct registry: $DEPLOYMENT_NAME"
        else
            log_warn "Not using gabby.azurecr.io: $DEPLOYMENT_NAME"
        fi
    fi
done

echo ""
echo "Checking VirtualService configurations..."
echo "------------------------------------------"

for file in $YAML_FILES; do
    if grep -q "kind: VirtualService" "$file"; then
        VS_NAME=$(grep "name:" "$file" | head -1 | awk '{print $2}')
        
        # Check for shared gateway
        if grep -q "aks-istio-ingress/cat-herding-gateway" "$file"; then
            log_pass "Using shared gateway: $VS_NAME"
        else
            log_warn "Not using shared gateway (aks-istio-ingress/cat-herding-gateway): $VS_NAME"
        fi
        
        # Check hostname
        if grep -q "cat-herding.net" "$file"; then
            log_pass "Valid hostname: $VS_NAME"
        else
            log_warn "Non-standard hostname (not *.cat-herding.net): $VS_NAME"
        fi
    fi
done

echo ""
echo "Checking for common mistakes..."
echo "--------------------------------"

for file in $YAML_FILES; do
    # Check for new Gateway (usually wrong)
    if grep -q "kind: Gateway" "$file"; then
        if ! grep -q "cat-herding-gateway" "$file"; then
            log_warn "Creating new Gateway in $file - consider using shared gateway"
        fi
    fi
    
    # Check for Certificate (usually not needed)
    if grep -q "kind: Certificate" "$file"; then
        if grep -q "cat-herding.net" "$file"; then
            log_warn "Creating Certificate for *.cat-herding.net in $file - wildcard already exists"
        fi
    fi
    
    # Check for hardcoded secrets
    if grep -qE "(password|secret|api.?key|token).*:.*['\"]?[a-zA-Z0-9]+" "$file"; then
        log_fail "Possible hardcoded secret in $file"
    fi
done

echo ""
echo "================================================"
echo "Validation Summary"
echo "================================================"
echo -e "Errors:   ${RED}${ERRORS}${NC}"
echo -e "Warnings: ${YELLOW}${WARNINGS}${NC}"

if [[ $ERRORS -gt 0 ]]; then
    echo ""
    echo -e "${RED}Validation failed with $ERRORS error(s)${NC}"
    exit 1
elif [[ $WARNINGS -gt 0 ]]; then
    echo ""
    echo -e "${YELLOW}Validation passed with $WARNINGS warning(s)${NC}"
    exit 0
else
    echo ""
    echo -e "${GREEN}All checks passed!${NC}"
    exit 0
fi
