# Application decommission checklist

**Application Name**: _________________  
**Decommission Date**: _________________  
**Performed By**: _________________  

---

## Pre-Decommission

- [ ] **Document all dependencies**
  - [ ] Check VirtualServices: `kubectl get virtualservices -A -o yaml | grep [APP_NAME]`
  - [ ] Check AuthorizationPolicies: `kubectl get authorizationpolicies -A -o yaml | grep [APP_NAME]`
  - [ ] Check service-to-service calls in code/docs
  - [ ] Identify downstream consumers

- [ ] **Notify stakeholders**
  - [ ] End users
  - [ ] Dependent service owners
  - [ ] Operations team
  - [ ] Security team (for secret cleanup)

- [ ] **Set decommission timeline**
  - [ ] Communication sent: ___________
  - [ ] Shutdown date: ___________
  - [ ] Final deletion date: ___________

- [ ] **Plan data handling**
  - [ ] Data backup required? Yes / No
  - [ ] Backup location: _________________
  - [ ] Data retention period: _________________
  - [ ] Compliance requirements reviewed

- [ ] **Identify migration path** (if applicable)
  - [ ] Replacement service: _________________
  - [ ] Migration guide created
  - [ ] Users migrated/notified

---

## Phase 1: Traffic Removal

- [ ] **Scale down or redirect traffic**
  ```bash
  # Option A: Scale to zero
  kubectl scale deployment/[APP_NAME] --replicas=0
  
  # Option B: Edit VirtualService for redirect
  kubectl edit virtualservice [APP_NAME]
  ```

- [ ] **Verify no active traffic**
  ```bash
  kubectl logs -l app=[APP_NAME] --tail=100
  # Check Azure Monitor for request metrics
  ```

- [ ] **Monitor for 24-48 hours**
  - [ ] No error reports from downstream services
  - [ ] No customer complaints
  - [ ] Metrics show zero traffic

---

## Phase 2: Kubernetes Resource Cleanup

- [ ] **List all resources**
  ```bash
  kubectl get all,virtualservices,secretproviderclass,hpa,pdb -l app=[APP_NAME]
  kubectl get configmap,secret -l app=[APP_NAME]
  ```

- [ ] **Delete resources in order**
  ```bash
  # 1. Remove traffic routing
  kubectl delete virtualservice [APP_NAME]
  
  # 2. Delete service
  kubectl delete service [APP_NAME]
  
  # 3. Delete deployment
  kubectl delete deployment [APP_NAME]
  
  # 4. Delete secrets provider
  kubectl delete secretproviderclass [APP_NAME]-secrets
  
  # 5. Delete supporting resources
  kubectl delete serviceaccount [APP_NAME]
  kubectl delete configmap [APP_NAME]-config
  kubectl delete hpa [APP_NAME]
  kubectl delete pdb [APP_NAME]
  ```

- [ ] **Verify complete removal**
  ```bash
  kubectl get all -l app=[APP_NAME]
  # Should return: No resources found
  ```

- [ ] **Delete namespace** (if app-specific namespace)
  ```bash
  kubectl delete namespace [APP_NAME]-namespace
  ```

---

## Phase 3: Azure Resources Cleanup

### Azure Key Vault

- [ ] **List Key Vaults**
  ```bash
  az keyvault list -g nekoc --query "[?contains(name, '[APP_NAME]')]" -o table
  ```

- [ ] **Backup secrets** (if needed)
  ```bash
  # List all secrets
  az keyvault secret list --vault-name [APP_NAME]-kv -o table
  
  # Backup critical secrets
  az keyvault secret show --vault-name [APP_NAME]-kv --name [SECRET_NAME] --query value -o tsv > backup-[SECRET_NAME].txt
  ```

- [ ] **Soft delete Key Vault**
  ```bash
  az keyvault delete --name [APP_NAME]-kv --resource-group nekoc
  ```

- [ ] **Wait 7-90 days, then purge** (optional)
  ```bash
  # After verification period
  az keyvault purge --name [APP_NAME]-kv
  ```

### Azure Monitor & Alerts

- [ ] **List alerts**
  ```bash
  az monitor metrics alert list -g nekoc --query "[?contains(name, '[APP_NAME]')]" -o table
  ```

- [ ] **Delete alerts**
  ```bash
  az monitor metrics alert delete --name [APP_NAME]-[ALERT_NAME] -g nekoc
  ```

### DNS Records

- [ ] **Check for custom DNS records**
  ```bash
  az network dns record-set list -g nekoc -z cat-herding.net --query "[?contains(name, '[APP_NAME]')]" -o table
  ```

- [ ] **Delete A records** (only if custom record was created)
  ```bash
  # Most apps use wildcard - no action needed
  # If custom A record exists:
  az network dns record-set a delete -g nekoc -z cat-herding.net -n [APP_NAME] --yes
  ```

### Container Registry

- [ ] **List container images**
  ```bash
  az acr repository show-tags --name gabby --repository [APP_NAME] -o table
  ```

- [ ] **Decide retention policy**
  - [ ] Keep images for rollback period: _____ days
  - [ ] Delete all images immediately
  - [ ] Archive images to blob storage

- [ ] **Delete images** (if decided)
  ```bash
  # Delete entire repository
  az acr repository delete --name gabby --repository [APP_NAME] --yes
  
  # Or delete specific tags
  az acr repository delete --name gabby --image [APP_NAME]:[TAG] --yes
  ```

### IAM & Role Assignments

- [ ] **List role assignments**
  ```bash
  az role assignment list --all --query "[?contains(principalName, '[APP_NAME]')]" -o table
  ```

- [ ] **Remove role assignments**
  ```bash
  az role assignment delete --assignee [PRINCIPAL_ID] --scope [SCOPE]
  ```

---

## Phase 4: CI/CD Cleanup

### GitHub Actions

- [ ] **Disable workflow**
  ```bash
  # In app repository
  mkdir -p .github/workflows/disabled
  mv .github/workflows/deploy.yaml .github/workflows/disabled/
  ```

- [ ] **Remove secrets**
  - [ ] Navigate to repo Settings → Secrets
  - [ ] Delete `ACR_USERNAME`, `ACR_PASSWORD`, `AZURE_CREDENTIALS`

- [ ] **Commit changes**
  ```bash
  git add .github/workflows/
  git commit -m "Decommission: Disable deployment workflows"
  git push origin main
  ```

### GitHub Repository

- [ ] **Archive repository** (recommended)
  - [ ] Go to Settings → Archive this repository
  - [ ] Add topic: `decommissioned`
  - [ ] Update README with decommission notice

- [ ] **Or delete repository** (permanent - not recommended)
  - [ ] Go to Settings → Delete this repository
  - [ ] Type repository name to confirm

### Webhooks & Integrations

- [ ] **Remove webhooks**
  - [ ] Check repo Settings → Webhooks
  - [ ] Delete any app-specific webhooks

---

## Phase 5: Documentation & Knowledge Transfer

### Create Decommission Record

- [ ] **Create decommission doc**
  ```bash
  # In ai_cluster_ops repo
  mkdir -p docs/decommissioned
  cat > docs/decommissioned/[APP_NAME].md << 'EOF'
  # [APP_NAME] - Decommissioned
  
  - **Decommission Date**: YYYY-MM-DD
  - **Reason**: [Service replaced / No longer needed / Merged into X]
  - **Former URL**: https://[APP_NAME].cat-herding.net
  - **Repository**: [Archived at / Deleted]
  - **Data Location**: [Backup path / None]
  - **Migration Path**: [Link to new service / N/A]
  - **Performed By**: [Your name]
  
  ## Resources Cleaned Up
  - [x] Kubernetes resources deleted
  - [x] Key Vault deleted (or retained until: DATE)
  - [x] Container images deleted
  - [x] DNS records removed
  - [x] GitHub Actions disabled
  - [x] Monitoring alerts removed
  
  ## Notes
  [Any special notes or lessons learned]
  EOF
  ```

### Update Cluster Documentation

- [ ] **Remove from CLUSTER_OVERVIEW.md**
  - [ ] Delete from "Existing Services" table
  - [ ] Remove any architecture diagrams

- [ ] **Update ONBOARDING.md**
  - [ ] Remove if used as example
  - [ ] Update any references

- [ ] **Remove from examples**
  ```bash
  # If app was used as example
  rm manifests/examples/[APP_NAME].yaml
  ```

- [ ] **Commit documentation changes**
  ```bash
  git add docs/
  git commit -m "docs: Record decommission of [APP_NAME]"
  git push origin main
  ```

### Notify Stakeholders of Completion

- [ ] **Send completion notice**
  - [ ] Date decommissioned: ___________
  - [ ] Confirmation all resources removed
  - [ ] Data retention information
  - [ ] Contact for questions

---

## Phase 6: Final Verification

- [ ] **Verify URL is inaccessible**
  ```bash
  curl -I https://[APP_NAME].cat-herding.net
  # Should return 404 or connection refused
  ```

- [ ] **Verify no pods running**
  ```bash
  kubectl get pods -l app=[APP_NAME] -A
  # Should return: No resources found
  ```

- [ ] **Verify no DNS resolution** (if custom record)
  ```bash
  nslookup [APP_NAME].cat-herding.net
  # Should return NXDOMAIN or default wildcard
  ```

- [ ] **Check for alerts**
  - [ ] Azure Monitor shows no active alerts
  - [ ] No error notifications from dependent services

- [ ] **Verify Key Vault access removed**
  ```bash
  az keyvault list -g nekoc --query "[?contains(name, '[APP_NAME]')]"
  # Should return empty array
  ```

- [ ] **Confirm cost reduction**
  - [ ] Azure Cost Management shows resource removal
  - [ ] Estimated monthly savings: $___________

---

## Post-Decommission

- [ ] **Archive all documentation**
  - [ ] Decommission record committed
  - [ ] Runbooks archived
  - [ ] Architecture diagrams archived

- [ ] **Schedule follow-up review**
  - [ ] 30-day review: ___________
  - [ ] Verify no unexpected issues
  - [ ] Confirm permanent deletion of soft-deleted resources

- [ ] **Update capacity planning**
  - [ ] Remove from resource forecasts
  - [ ] Update cluster capacity docs

---

## Signatures

**Performed by**: _________________ **Date**: _________  
**Reviewed by**: _________________ **Date**: _________  
**Approved by**: _________________ **Date**: _________  

---

## Notes

_Record any issues, deviations from process, or lessons learned:_

```
[Your notes here]
```
