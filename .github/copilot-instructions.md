---
applyTo: '**'
---

# Bigboy AKS Cluster - Copilot Onboarding Instructions

You are helping deploy applications to the **bigboy** AKS cluster. Use these instructions to generate correct Kubernetes manifests, Helm charts, and CI/CD pipelines.

## Cluster Context

- **Cluster**: bigboy (AKS, Kubernetes 1.32.9)
- **Location**: Azure centralus
- **Resource Group**: nekoc
- **Container Registry**: gabby.azurecr.io
- **Primary Domain**: cat-herding.net (wildcard SSL enabled)
- **Secondary Domain**: hugecat.net

## Critical Configuration Requirements

### 1. Istio Sidecar Injection

ALL deployments MUST include Istio sidecar injection:

```yaml
metadata:
  annotations:
    sidecar.istio.io/inject: "true"
    sidecar.istio.io/proxyCPU: "50m"
    sidecar.istio.io/proxyCPULimit: "200m"
    sidecar.istio.io/proxyMemory: "64Mi"
    sidecar.istio.io/proxyMemoryLimit: "256Mi"
```

### 2. Use Shared Gateway

For apps on `*.cat-herding.net`, use the existing shared gateway:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: <app-name>
  namespace: default
  labels:
    app: <app-name>
    app.kubernetes.io/component: web-application
    app.kubernetes.io/name: <app-name>
spec:
  gateways:
    - aks-istio-ingress/cat-herding-gateway  # ALWAYS use this gateway
  hosts:
    - <app-name>.cat-herding.net
  http:
    - match:
        - uri:
            prefix: /
      route:
        - destination:
            host: <app-name>.default.svc.cluster.local
            port:
              number: 80
```

### 3. Container Image Registry

Always use `gabby.azurecr.io` for images:

```yaml
image: gabby.azurecr.io/<app-name>:<tag>
imagePullPolicy: Always
```

### 4. Security Context (Required)

```yaml
securityContext:
  runAsNonRoot: true
  seccompProfile:
    type: RuntimeDefault
containers:
  - name: app
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop:
          - ALL
      runAsNonRoot: true
      runAsUser: 1001
```

### 5. Health Probes (Required)

```yaml
livenessProbe:
  httpGet:
    path: /health  # or /api/health, /healthz
    port: http
  initialDelaySeconds: 30
  periodSeconds: 15
readinessProbe:
  httpGet:
    path: /health
    port: http
  initialDelaySeconds: 5
  periodSeconds: 10
startupProbe:
  httpGet:
    path: /health
    port: http
  failureThreshold: 30
  periodSeconds: 5
```

### 6. Resource Limits (Required)

```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 250m
    memory: 512Mi
```

### 7. Spot Instance Tolerance

Add for scheduling on spot nodes:

```yaml
tolerations:
  - key: kubernetes.azure.com/scalesetpriority
    operator: Equal
    value: spot
    effect: NoSchedule
```

## Deployment Templates by App Type

### Simple Web App (No Auth)

1. Deployment + Service
2. VirtualService using shared gateway
3. No certificate needed (wildcard covers it)

### Web App with GitHub OAuth

1. Deployment with oauth2-proxy sidecar container
2. Service pointing to port 4180 (proxy port)
3. VirtualService routing to 4180
4. Mount oauth2-proxy-sidecar-config ConfigMap
5. Reference oauth2-proxy-secret for credentials

OAuth2-proxy sidecar pattern:
```yaml
containers:
  - name: oauth2-proxy
    image: quay.io/oauth2-proxy/oauth2-proxy:v7.6.0
    args:
      - --config=/etc/oauth2-proxy/oauth2_proxy.cfg
      - --whitelist-domain=.cat-herding.net
    env:
      - name: OAUTH2_PROXY_REDIRECT_URL
        value: https://auth.cat-herding.net/oauth2/callback
      - name: OAUTH2_PROXY_CLIENT_ID
        valueFrom:
          secretKeyRef:
            name: oauth2-proxy-secret
            key: client-id
      - name: OAUTH2_PROXY_CLIENT_SECRET
        valueFrom:
          secretKeyRef:
            name: oauth2-proxy-secret
            key: client-secret
      - name: OAUTH2_PROXY_COOKIE_SECRET
        valueFrom:
          secretKeyRef:
            name: oauth2-proxy-secret
            key: cookie-secret
      - name: OAUTH2_PROXY_UPSTREAMS
        value: http://127.0.0.1:8080  # Your app's port
    ports:
      - containerPort: 4180
        name: proxy
    volumeMounts:
      - name: oauth2-proxy-config
        mountPath: /etc/oauth2-proxy
        readOnly: true
  - name: app
    image: gabby.azurecr.io/<app>:latest
    ports:
      - containerPort: 8080
        name: http
volumes:
  - name: oauth2-proxy-config
    configMap:
      name: oauth2-proxy-sidecar-config
```

### API Service

Same as Simple Web App but:
- May not need browser access
- Consider using internal gateway for service-to-service

## Secrets Management

> ⚠️ **CRITICAL**: NEVER store secrets in Kubernetes manifests, YAML files, or Git repositories. Always use Azure Key Vault.

### Azure Key Vault (Required for Production)

The cluster has Azure Key Vault Secrets Provider enabled with automatic rotation.

**Step 1: Create SecretProviderClass:**

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: <app-name>-secrets
  namespace: default
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "true"
    userAssignedIdentityID: "f2a13db4-007a-46c8-b155-28de1e7d24f6"  # AKS KV identity
    keyvaultName: "<your-keyvault-name>"
    tenantId: "<azure-tenant-id>"
    objects: |
      array:
        - |
          objectName: api-key
          objectType: secret
        - |
          objectName: database-url
          objectType: secret
  # Sync to K8s Secret for env var usage
  secretObjects:
    - secretName: <app-name>-secrets-k8s
      type: Opaque
      data:
        - objectName: api-key
          key: API_KEY
        - objectName: database-url
          key: DATABASE_URL
```

**Step 2: Mount in Deployment:**

```yaml
spec:
  containers:
    - name: app
      envFrom:
        - secretRef:
            name: <app-name>-secrets-k8s  # From secretObjects sync
      volumeMounts:
        - name: secrets-store
          mountPath: "/mnt/secrets"
          readOnly: true
  volumes:
    - name: secrets-store
      csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
          secretProviderClass: <app-name>-secrets
```

### Creating Secrets in Key Vault

```bash
# Create Key Vault (if needed)
az keyvault create --name <app-name>-kv --resource-group nekoc --location centralus

# Add secrets
az keyvault secret set --vault-name <app-name>-kv --name api-key --value "your-secret"
az keyvault secret set --vault-name <app-name>-kv --name database-url --value "postgresql://..."

# Grant AKS access
KV_IDENTITY="f2a13db4-007a-46c8-b155-28de1e7d24f6"
az role assignment create --role "Key Vault Secrets User" --assignee $KV_IDENTITY --scope $(az keyvault show --name <app-name>-kv --query id -o tsv)
```

## OpenTelemetry Integration

Add these env vars for tracing:

```yaml
env:
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://otel-collector.default.svc.cluster.local:4317"
  - name: OTEL_SERVICE_NAME
    value: "<app-name>"
  - name: OTEL_RESOURCE_ATTRIBUTES
    value: "deployment.environment=production"
```

## CI/CD GitHub Actions Template

```yaml
name: Build and Deploy

on:
  push:
    branches: [main]

env:
  REGISTRY: gabby.azurecr.io
  IMAGE_NAME: <app-name>
  CLUSTER_NAME: bigboy
  RESOURCE_GROUP: nekoc

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Login to ACR
        uses: azure/docker-login@v1
        with:
          login-server: ${{ env.REGISTRY }}
          username: ${{ secrets.ACR_USERNAME }}
          password: ${{ secrets.ACR_PASSWORD }}
      
      - name: Build and push
        run: |
          docker build -t $REGISTRY/$IMAGE_NAME:${{ github.sha }} .
          docker push $REGISTRY/$IMAGE_NAME:${{ github.sha }}
      
      - name: Set AKS context
        uses: azure/aks-set-context@v3
        with:
          resource-group: ${{ env.RESOURCE_GROUP }}
          cluster-name: ${{ env.CLUSTER_NAME }}
          admin: 'false'
          use-kubelogin: 'true'
      
      - name: Deploy
        run: |
          kubectl set image deployment/<app-name> <app-name>=$REGISTRY/$IMAGE_NAME:${{ github.sha }}
```

## File Generation Checklist

When asked to deploy an app, generate:

1. [ ] `k8s/deployment.yaml` - Deployment with all required annotations
2. [ ] `k8s/service.yaml` - ClusterIP service
3. [ ] `k8s/virtualservice.yaml` - Istio VirtualService
4. [ ] `k8s/secrets.yaml` - Secrets (if needed, with placeholder values)
5. [ ] `k8s/configmap.yaml` - ConfigMap (if needed)
6. [ ] `.github/workflows/deploy.yaml` - CI/CD pipeline
7. [ ] `Dockerfile` - If not present

## Validation Commands

After generating manifests, suggest running:

```bash
# Validate YAML syntax
kubectl apply --dry-run=client -f k8s/

# Check deployment status
kubectl rollout status deployment/<app-name>

# Verify VirtualService
kubectl get virtualservice <app-name> -o yaml

# Test endpoint
curl -I https://<app-name>.cat-herding.net
```

## Common Mistakes to Avoid

1. ❌ Creating a new Gateway - use `aks-istio-ingress/cat-herding-gateway`
2. ❌ Creating certificates for *.cat-herding.net - wildcard exists
3. ❌ Missing Istio sidecar annotation
4. ❌ Using wrong container registry
5. ❌ Missing health probes
6. ❌ Missing resource limits
7. ❌ Privileged containers (use securityContext)

## Example: Deploy a New App

**User asks**: "Deploy my Node.js app called 'widgets-api' to the cluster"

**Generate**:
1. Deployment with Node.js container, health probes, Istio sidecar
2. Service on port 80 targeting container port 3000
3. VirtualService for widgets-api.cat-herding.net
4. GitHub Actions workflow
5. Dockerfile (if missing)

**Don't generate**:
- Gateway (use shared)
- Certificate (wildcard covers it)
- Ingress (we use Istio VirtualService)
