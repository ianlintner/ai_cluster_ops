# Application onboarding guide

This guide walks you through deploying a new application to the `bigboy` AKS cluster.

## Prerequisites

### 1. CLI tools

Ensure you have these tools installed:

```bash
# Azure CLI
az --version

# Kubernetes CLI
kubectl version --client

# Helm (optional but recommended)
helm version
```

### 2. Azure login

```bash
# Login to Azure
az login

# Get cluster credentials
az aks get-credentials --resource-group nekoc --name bigboy
```

### 3. ACR access

```bash
# Login to container registry
az acr login --name gabby
```

## Quick start: deploy in 5 minutes

### Option A: Using Helm chart (recommended)

```bash
# Clone ai_cluster_ops
git clone <ai_cluster_ops_repo_url>
cd ai_cluster_ops

# Deploy your app
helm upgrade --install myapp ./helm/app-template \
  --set app.name=myapp \
  --set app.image=gabby.azurecr.io/myapp \
  --set app.tag=latest \
  --set app.hostname=myapp.cat-herding.net \
  --set app.containerPort=8080
```

### Option B: Using kubectl with templates

```bash
# Copy templates
cp templates/deployment/simple-app.yaml k8s/deployment.yaml
cp templates/istio/virtualservice.yaml k8s/virtualservice.yaml

# Edit and replace placeholders
# Then apply
kubectl apply -f k8s/
```

## Deployment types

### 1. Simple web app (no auth)

**Use case**: Public APIs, static sites, internal tools

```bash
helm upgrade --install myapp ./helm/app-template \
  --set app.name=myapp \
  --set app.image=gabby.azurecr.io/myapp:latest \
  --set app.hostname=myapp.cat-herding.net \
  --set app.containerPort=3000
```

### 2. Web app with GitHub OAuth

**Use case**: Internal dashboards, admin panels

```bash
helm upgrade --install myapp ./helm/app-template \
  --set app.name=myapp \
  --set app.image=gabby.azurecr.io/myapp:latest \
  --set app.hostname=myapp.cat-herding.net \
  --set app.containerPort=8080 \
  --set oauth2Proxy.enabled=true
```

### 3. API with database

**Use case**: Backend services with state

```bash
# First, create secrets
kubectl create secret generic myapp-secrets \
  --from-literal=DATABASE_URL='postgresql://...' \
  --from-literal=REDIS_URL='redis://...'

# Then deploy
helm upgrade --install myapp ./helm/app-template \
  --set app.name=myapp \
  --set app.image=gabby.azurecr.io/myapp:latest \
  --set app.hostname=api.cat-herding.net \
  --set secrets[0]=myapp-secrets
```

## Step-by-step guide

### Step 1: Containerize your app

Create a `Dockerfile` in your app repository:

```dockerfile
# Example for Node.js
FROM node:20-alpine

WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .

# Run as non-root (required!)
USER 1001
EXPOSE 3000

CMD ["node", "server.js"]
```

**Important security requirements:**
- Run as non-root user (USER 1001)
- Don't run as PID 1 or use init systems
- Include a health endpoint

### Step 2: Add health check endpoint

Your app MUST expose a health endpoint:

```javascript
// Node.js example
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'healthy' });
});
```

```python
# Flask example
@app.route('/health')
def health():
    return {'status': 'healthy'}, 200
```

### Step 3: Build and push image

```bash
# Build
docker build -t gabby.azurecr.io/myapp:latest .

# Push
docker push gabby.azurecr.io/myapp:latest
```

### Step 4: Create Kubernetes manifests

**Option A: Create `values.yaml` for Helm**

```yaml
# myapp-values.yaml
app:
  name: myapp
  image: gabby.azurecr.io/myapp
  tag: latest
  containerPort: 3000
  hostname: myapp.cat-herding.net
  replicas: 2

resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi

healthCheck:
  path: /health

otel:
  enabled: true
```

**Option B: Create raw manifests**

See `templates/deployment/` for examples.

### Step 5: Deploy

```bash
# Using Helm
helm upgrade --install myapp ./helm/app-template -f myapp-values.yaml

# Or using kubectl
kubectl apply -f k8s/
```

### Step 6: Verify

```bash
# Check deployment status
kubectl rollout status deployment/myapp

# Check pods
kubectl get pods -l app=myapp

# Check VirtualService
kubectl get virtualservice myapp

# Test endpoint
curl -I https://myapp.cat-herding.net
```

## Environment variables and secrets

### ConfigMaps (non-sensitive)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: myapp-config
data:
  LOG_LEVEL: "info"
  FEATURE_FLAG: "true"
```

### Secrets (sensitive)

```bash
# Create from literals
kubectl create secret generic myapp-secrets \
  --from-literal=API_KEY='secret123' \
  --from-literal=DATABASE_URL='postgresql://...'

# Or from file
kubectl create secret generic myapp-secrets \
  --from-file=.env.production
```

Reference in Helm:

```yaml
secrets:
  - myapp-secrets
configMaps:
  - myapp-config
```

## DNS and TLS

### Subdomains of `cat-herding.net`

**No action needed!** The wildcard DNS (`*.cat-herding.net`) and TLS certificate are already configured. Just create your VirtualService and you're done.

### Custom domains

1. Create a Certificate:
```bash
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: myapp-custom-tls
  namespace: aks-istio-ingress
spec:
  secretName: myapp-custom-tls
  issuerRef:
    kind: ClusterIssuer
    name: letsencrypt-prod
  dnsNames:
    - myapp.example.com
EOF
```

2. Create a Gateway pointing to the new certificate
3. Update DNS to point to 52.182.228.75

## Troubleshooting

### Pod not starting

```bash
# Check events
kubectl describe pod -l app=myapp

# Check logs
kubectl logs -l app=myapp -c myapp

# Check Istio sidecar
kubectl logs -l app=myapp -c istio-proxy
```

### 503 Service Unavailable

```bash
# Check service endpoints
kubectl get endpoints myapp

# Check VirtualService
kubectl get virtualservice myapp -o yaml

# Check if pods are ready
kubectl get pods -l app=myapp
```

### Certificate issues

```bash
# Check certificate status
kubectl get certificate -n aks-istio-ingress

# Check certificate details
kubectl describe certificate myapp-tls -n aks-istio-ingress
```

## Cleanup

```bash
# Using Helm
helm uninstall myapp

# Using kubectl
kubectl delete -f k8s/
```

## Next steps

- Set up [CI/CD with GitHub Actions](.github/workflows/deploy-template.yaml)
- Configure [monitoring with OpenTelemetry](docs/OBSERVABILITY.md)
- Add [OAuth2 authentication](templates/oauth2/README.md)
