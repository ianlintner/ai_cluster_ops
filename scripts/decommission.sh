#!/bin/bash
# Application Decommission Helper Script
# Usage: ./decommission.sh <app-name> [--dry-run]

set -e

APP_NAME=$1
DRY_RUN=${2:-""}
RESOURCE_GROUP="nekoc"
CLUSTER_NAME="bigboy"
REGISTRY="gabby"
DNS_ZONE="cat-herding.net"

if [ -z "$APP_NAME" ]; then
    echo "Usage: ./decommission.sh <app-name> [--dry-run]"
    echo ""
    echo "Example:"
    echo "  ./decommission.sh myapp --dry-run  # Preview changes"
    echo "  ./decommission.sh myapp            # Execute decommission"
    exit 1
fi

if [ "$DRY_RUN" == "--dry-run" ]; then
    echo "🔍 DRY RUN MODE - No changes will be made"
    echo ""
fi

function run_cmd() {
    local cmd=$1
    if [ "$DRY_RUN" == "--dry-run" ]; then
        echo "  [DRY RUN] $cmd"
    else
        echo "  ▶ $cmd"
        eval $cmd
    fi
}

echo "=================================================="
echo "Application Decommission Helper"
echo "=================================================="
echo "App Name: $APP_NAME"
echo "Dry Run: ${DRY_RUN:-false}"
echo ""

# Check if user is ready
if [ "$DRY_RUN" != "--dry-run" ]; then
    echo "⚠️  This will DELETE all resources for $APP_NAME"
    read -p "Are you sure you want to proceed? (type 'yes' to continue): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Aborted."
        exit 0
    fi
fi

echo ""
echo "📋 Phase 1: Discovery"
echo "=================================================="

echo "Checking Kubernetes resources..."
run_cmd "kubectl get all,virtualservices,secretproviderclass,hpa -l app=$APP_NAME -o name || echo 'No resources found'"

echo ""
echo "Checking Key Vaults..."
run_cmd "az keyvault list -g $RESOURCE_GROUP --query \"[?contains(name, '$APP_NAME')].{Name:name, Location:location}\" -o table"

echo ""
echo "Checking DNS records..."
run_cmd "az network dns record-set list -g $RESOURCE_GROUP -z $DNS_ZONE --query \"[?contains(name, '$APP_NAME')].{Name:name, Type:type, TTL:ttl}\" -o table"

echo ""
echo "Checking container images..."
run_cmd "az acr repository show-tags --name $REGISTRY --repository $APP_NAME -o table 2>/dev/null || echo 'No images found'"

echo ""
echo "Checking Azure Monitor alerts..."
run_cmd "az monitor metrics alert list -g $RESOURCE_GROUP --query \"[?contains(name, '$APP_NAME')].{Name:name, Enabled:enabled}\" -o table 2>/dev/null || echo 'No alerts found'"

if [ "$DRY_RUN" == "--dry-run" ]; then
    echo ""
    echo "✅ Dry run complete. Run without --dry-run to execute decommission."
    exit 0
fi

echo ""
read -p "Continue with deletion? (type 'yes'): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "🗑️  Phase 2: Kubernetes Cleanup"
echo "=================================================="

echo "Deleting VirtualService..."
run_cmd "kubectl delete virtualservice $APP_NAME --ignore-not-found=true"

echo "Deleting Service..."
run_cmd "kubectl delete service $APP_NAME --ignore-not-found=true"

echo "Deleting Deployment..."
run_cmd "kubectl delete deployment $APP_NAME --ignore-not-found=true"

echo "Deleting SecretProviderClass..."
run_cmd "kubectl delete secretproviderclass ${APP_NAME}-secrets --ignore-not-found=true"

echo "Deleting ConfigMap..."
run_cmd "kubectl delete configmap ${APP_NAME}-config --ignore-not-found=true"

echo "Deleting ServiceAccount..."
run_cmd "kubectl delete serviceaccount $APP_NAME --ignore-not-found=true"

echo "Deleting HPA..."
run_cmd "kubectl delete hpa $APP_NAME --ignore-not-found=true"

echo ""
echo "Verifying Kubernetes cleanup..."
run_cmd "kubectl get all -l app=$APP_NAME || echo 'All resources deleted'"

echo ""
echo "🔐 Phase 3: Azure Key Vault Cleanup"
echo "=================================================="

# Find Key Vaults matching app name
KV_LIST=$(az keyvault list -g $RESOURCE_GROUP --query "[?contains(name, '$APP_NAME')].name" -o tsv)

if [ -z "$KV_LIST" ]; then
    echo "No Key Vaults found for $APP_NAME"
else
    for kv in $KV_LIST; do
        echo "Deleting Key Vault: $kv"
        read -p "Delete $kv? (yes/skip): " confirm_kv
        if [ "$confirm_kv" == "yes" ]; then
            run_cmd "az keyvault delete --name $kv --resource-group $RESOURCE_GROUP"
            echo "  ℹ️  Key Vault soft-deleted. Purge after verification period with:"
            echo "     az keyvault purge --name $kv"
        fi
    done
fi

echo ""
echo "📊 Phase 4: Monitoring Cleanup"
echo "=================================================="

ALERT_LIST=$(az monitor metrics alert list -g $RESOURCE_GROUP --query "[?contains(name, '$APP_NAME')].name" -o tsv 2>/dev/null || echo "")

if [ -z "$ALERT_LIST" ]; then
    echo "No alerts found for $APP_NAME"
else
    for alert in $ALERT_LIST; do
        echo "Deleting alert: $alert"
        run_cmd "az monitor metrics alert delete --name $alert -g $RESOURCE_GROUP"
    done
fi

echo ""
echo "🌐 Phase 5: DNS Cleanup"
echo "=================================================="

# Check for custom A records (most apps use wildcard)
DNS_RECORDS=$(az network dns record-set list -g $RESOURCE_GROUP -z $DNS_ZONE --query "[?name=='$APP_NAME' && type=='Microsoft.Network/dnszones/A'].name" -o tsv)

if [ -z "$DNS_RECORDS" ]; then
    echo "No custom DNS records found (using wildcard)"
else
    echo "Custom A record found for $APP_NAME"
    read -p "Delete DNS A record? (yes/skip): " confirm_dns
    if [ "$confirm_dns" == "yes" ]; then
        run_cmd "az network dns record-set a delete -g $RESOURCE_GROUP -z $DNS_ZONE -n $APP_NAME --yes"
    fi
fi

echo ""
echo "🐳 Phase 6: Container Images"
echo "=================================================="

echo "Container images for $APP_NAME:"
az acr repository show-tags --name $REGISTRY --repository $APP_NAME -o table 2>/dev/null || echo "No images found"

read -p "Delete container repository? (yes/skip): " confirm_images
if [ "$confirm_images" == "yes" ]; then
    run_cmd "az acr repository delete --name $REGISTRY --repository $APP_NAME --yes"
fi

echo ""
echo "📝 Phase 7: Documentation"
echo "=================================================="

echo "Creating decommission record..."

DECOM_FILE="docs/decommissioned/${APP_NAME}.md"
mkdir -p docs/decommissioned

cat > $DECOM_FILE << EOF
# $APP_NAME - Decommissioned

- **Decommission Date**: $(date +%Y-%m-%d)
- **Decommissioned By**: $(whoami)
- **Former URL**: https://${APP_NAME}.cat-herding.net
- **Reason**: [Add reason here]

## Resources Cleaned Up

- [x] Kubernetes resources deleted
- [x] Key Vault deleted (soft-deleted, purge after verification)
- [x] Container images deleted
- [x] DNS records removed (if any)
- [x] Monitoring alerts removed

## Verification Commands

\`\`\`bash
# Verify no pods
kubectl get pods -l app=$APP_NAME

# Verify URL
curl -I https://${APP_NAME}.cat-herding.net

# Check Key Vault
az keyvault list -g $RESOURCE_GROUP --query "[?contains(name, '$APP_NAME')]"
\`\`\`

## Notes

[Add any additional notes about the decommission process]
EOF

echo "Decommission record created at: $DECOM_FILE"
echo ""
echo "To complete documentation:"
echo "  1. Edit $DECOM_FILE and add reason/notes"
echo "  2. Update docs/CLUSTER_OVERVIEW.md to remove app"
echo "  3. Commit changes: git add docs/ && git commit -m 'docs: Decommission $APP_NAME'"

echo ""
echo "✅ Decommission Complete"
echo "=================================================="
echo ""
echo "Next steps:"
echo "  1. Verify URL is inaccessible: curl -I https://${APP_NAME}.cat-herding.net"
echo "  2. Monitor for 24-48 hours for unexpected issues"
echo "  3. After verification, purge Key Vault:"
echo "     az keyvault purge --name ${APP_NAME}-kv"
echo "  4. Update documentation and commit changes"
echo "  5. Archive or delete app repository on GitHub"
echo ""
