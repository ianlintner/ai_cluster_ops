# Bigboy AKS Cluster Overview

## Cluster Information

| Property | Value |
|----------|-------|
| **Name** | bigboy |
| **Location** | centralus |
| **Resource Group** | nekoc |
| **Kubernetes Version** | 1.32.9 |
| **FQDN** | bigboy-nekoc-79307c-wwev96e7.hcp.centralus.azmk8s.io |
| **Subscription ID** | 79307c77-54c3-4738-be2a-dc96da7464d9 |

## Namespaces

| Namespace | Purpose |
|-----------|---------|
| `default` | Main application namespace |
| `aks-istio-ingress` | Istio ingress gateways |
| `aks-istio-system` | Istio control plane |
| `aks-istio-egress` | Istio egress gateways |
| `cert-manager` | TLS certificate management |
| `security-agency` | Example isolated app namespace |

## Container Registry

| Property | Value |
|----------|-------|
| **Registry** | gabby.azurecr.io |
| **Resource Group** | nekoc |
| **SKU** | Basic |
| **Admin Enabled** | Yes |

### Pushing Images

```bash
# Login to ACR
az acr login --name gabby

# Tag and push
docker tag myapp:latest gabby.azurecr.io/myapp:latest
docker push gabby.azurecr.io/myapp:latest
```

## Istio Service Mesh

### Configuration

- **Mode**: Azure Managed Istio (ASM)
- **Revision**: asm-1-27
- **External Ingress**: Enabled (LoadBalancer)
- **Internal Ingress**: Enabled (Internal LoadBalancer)

### Ingress Gateway IPs

| Gateway | Type | IP | Ports |
|---------|------|----|----|
| External | LoadBalancer | 52.182.228.75 | 80, 443, 15021 |
| Internal | Internal LB | 10.224.0.5 | 80, 443, 15021 |

### Enabling Istio Sidecar

Add this annotation to your pod spec:

```yaml
metadata:
  annotations:
    sidecar.istio.io/inject: "true"
```

### Sidecar Resource Configuration (Recommended)

```yaml
annotations:
  sidecar.istio.io/proxyCPU: "50m"
  sidecar.istio.io/proxyCPULimit: "200m"
  sidecar.istio.io/proxyMemory: "64Mi"
  sidecar.istio.io/proxyMemoryLimit: "256Mi"
```

## DNS Configuration

### DNS Zones

| Zone | Type | Resource Group |
|------|------|----------------|
| cat-herding.net | Public | nekoc |
| hugecat.net | Public | nekoc |

### Wildcard Records

Both zones have wildcard A records pointing to the external ingress:

```
*.cat-herding.net → 52.182.228.75
*.hugecat.net → 52.182.228.75
```

### Adding a New Subdomain

For most apps, the wildcard DNS handles routing automatically. Just create a VirtualService with the desired hostname. For specific A records:

```bash
az network dns record-set a add-record \
  -g nekoc \
  -z cat-herding.net \
  -n myapp \
  -a 52.182.228.75
```

## TLS Certificates

### Cluster Issuers

| Issuer | Purpose | ACME Server |
|--------|---------|-------------|
| letsencrypt-prod | Production certificates | acme-v02.api.letsencrypt.org |
| letsencrypt-staging | Testing (no rate limits) | acme-staging-v02.api.letsencrypt.org |

### DNS01 Challenge Configuration

Certificates use Azure DNS for DNS01 challenges:
- **Hosted Zone**: hugecat.net
- **Managed Identity Client ID**: e502213f-1f15-4f03-9fb4-b546f51aafe9
- **Resource Group**: nekoc

### Wildcard Certificate

A wildcard certificate exists for `*.cat-herding.net`:

```yaml
# Located in aks-istio-ingress namespace
Name: cat-herding-wildcard
Secret: cat-herding-wildcard-tls
DNS Names:
  - "*.cat-herding.net"
  - "cat-herding.net"
```

### Shared Gateway

Apps can use the shared gateway which already has the wildcard certificate:

```yaml
spec:
  gateways:
    - aks-istio-ingress/cat-herding-gateway
  hosts:
    - myapp.cat-herding.net
```

## Enabled Addons

| Addon | Status | Details |
|-------|--------|---------|
| Azure Key Vault Secrets Provider | ✅ Enabled | Secret rotation every 2m |
| Azure Monitor (OMS Agent) | ✅ Enabled | Log Analytics workspace configured |
| Azure Service Mesh (Istio) | ✅ Enabled | ASM 1.27 |

### Key Vault Integration

The cluster has Azure Key Vault Secrets Provider enabled:
- **Client ID**: f2a13db4-007a-46c8-b155-28de1e7d24f6
- **Rotation Interval**: 2 minutes

> ⚠️ **IMPORTANT**: Never store secrets in Kubernetes manifests or Git. Always use Azure Key Vault.

#### Quick Start: Using Key Vault Secrets

1. **Create secrets in Key Vault**:
   ```bash
   az keyvault secret set --vault-name YOUR-KEYVAULT --name my-secret --value "secret-value"
   ```

2. **Create SecretProviderClass**:
   ```yaml
   apiVersion: secrets-store.csi.x-k8s.io/v1
   kind: SecretProviderClass
   metadata:
     name: myapp-secrets
   spec:
     provider: azure
     parameters:
       usePodIdentity: "false"
       useVMManagedIdentity: "true"
       userAssignedIdentityID: "f2a13db4-007a-46c8-b155-28de1e7d24f6"
       keyvaultName: "YOUR-KEYVAULT"
       tenantId: "YOUR-TENANT-ID"
       objects: |
         array:
           - |
             objectName: my-secret
             objectType: secret
   ```

3. **Mount in Deployment**:
   ```yaml
   volumes:
     - name: secrets-store
       csi:
         driver: secrets-store.csi.k8s.io
         readOnly: true
         volumeAttributes:
           secretProviderClass: myapp-secrets
   ```

See [Security Guide](SECURITY.md#azure-key-vault-integration) for complete examples.

## Observability

### OpenTelemetry Collector

The cluster runs a centralized OTLP collector:

| Endpoint | Port | Protocol |
|----------|------|----------|
| otel-collector.default.svc.cluster.local | 4317 | gRPC |
| otel-collector.default.svc.cluster.local | 4318 | HTTP |

### Sending Traces from Your App

```yaml
env:
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://otel-collector.default.svc.cluster.local:4317"
  - name: OTEL_SERVICE_NAME
    value: "myapp"
```

## Node Pools & Tolerations

The cluster uses spot instances. Add tolerations for scheduling:

```yaml
tolerations:
  - key: "kubernetes.azure.com/scalesetpriority"
    operator: "Equal"
    value: "spot"
    effect: "NoSchedule"
```

## Security Best Practices

### Pod Security Context (Recommended)

```yaml
securityContext:
  runAsNonRoot: true
  seccompProfile:
    type: RuntimeDefault
containers:
  - securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop:
          - ALL
      runAsNonRoot: true
      runAsUser: 1001
```

### Network Policies

Istio provides automatic mTLS between services. Additional network policies can be applied using Kubernetes NetworkPolicy resources.

## Existing Services Reference

| Service | Namespace | Hostname | Port |
|---------|-----------|----------|------|
| portfolio | default | cat-herding.net | 80 |
| chat-backend | default | chat.cat-herding.net | 80 |
| python-dsa | default | dsa.cat-herding.net | 80 |
| slop-detector | default | slop.cat-herding.net | 80 |
| security-agency | security-agency | security.cat-herding.net | 80 |
| example-app | default | example-app.cat-herding.net | 4180 (oauth2-proxy) |
| inker | default | inker.cat-herding.net | 80 |

## Quick Commands

```bash
# Get cluster credentials
az aks get-credentials --resource-group nekoc --name bigboy

# View all apps
kubectl get deployments -A | grep -v kube-system

# Check Istio injection status
kubectl get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].name}{"\n"}{end}'

# View gateways
kubectl get gateways -A

# View virtual services
kubectl get virtualservices -A

# Check certificate status
kubectl get certificates -A

# View ingress gateway logs
kubectl logs -n aks-istio-ingress -l app=aks-istio-ingressgateway-external -f
```
