# Bigboy Cluster Quick Reference

## 🔑 Essential Commands

### Cluster Access

```bash
# Login to Azure
az login

# Get cluster credentials
az aks get-credentials --resource-group nekoc --name bigboy

# Verify connection
kubectl get nodes
```

### Container Registry

```bash
# Login to ACR
az acr login --name gabby

# Build and push
docker build -t gabby.azurecr.io/myapp:latest .
docker push gabby.azurecr.io/myapp:latest

# List images
az acr repository list --name gabby
```

## 🚀 Quick Deploy

### Helm (Recommended)

```bash
# Simple app
helm upgrade --install myapp ./helm/app-template \
  --set app.name=myapp \
  --set app.image=gabby.azurecr.io/myapp:latest \
  --set app.hostname=myapp.cat-herding.net

# With OAuth
helm upgrade --install myapp ./helm/app-template \
  --set app.name=myapp \
  --set app.image=gabby.azurecr.io/myapp:latest \
  --set app.hostname=myapp.cat-herding.net \
  --set oauth2Proxy.enabled=true

# Uninstall
helm uninstall myapp
```

### kubectl

```bash
# Apply manifests
kubectl apply -f k8s/

# Update image
kubectl set image deployment/myapp myapp=gabby.azurecr.io/myapp:v2

# Check rollout
kubectl rollout status deployment/myapp

# Rollback
kubectl rollout undo deployment/myapp
```

## 🔍 Debugging

### Pods

```bash
# List pods
kubectl get pods -l app=myapp

# Describe pod
kubectl describe pod -l app=myapp

# View logs
kubectl logs -l app=myapp -f

# View Istio sidecar logs
kubectl logs -l app=myapp -c istio-proxy

# Exec into pod
kubectl exec -it deployment/myapp -- /bin/sh
```

### Networking

```bash
# Check service
kubectl get svc myapp
kubectl get endpoints myapp

# Check VirtualService
kubectl get virtualservice myapp -o yaml

# Check Gateway (shared)
kubectl get gateway cat-herding-gateway -n aks-istio-ingress

# Test connectivity
kubectl run curl --rm -it --image=curlimages/curl -- curl http://myapp/health
```

### Certificates

```bash
# List certificates
kubectl get certificates -A

# Check certificate status
kubectl describe certificate cat-herding-wildcard -n aks-istio-ingress

# Check secret
kubectl get secret cat-herding-wildcard-tls -n aks-istio-ingress
```

## 📊 Monitoring

### Resource Usage

```bash
# Pod resources
kubectl top pods -l app=myapp

# Node resources  
kubectl top nodes
```

### Events

```bash
# Recent events
kubectl get events --sort-by='.lastTimestamp' | tail -20

# Events for specific app
kubectl get events --field-selector involvedObject.name=myapp-xxx
```

## 🔐 Secrets

```bash
# Create secret
kubectl create secret generic myapp-secrets \
  --from-literal=API_KEY=secret123

# View secret (base64 encoded)
kubectl get secret myapp-secrets -o yaml

# Decode secret
kubectl get secret myapp-secrets -o jsonpath='{.data.API_KEY}' | base64 -d

# Edit secret
kubectl edit secret myapp-secrets
```

## 🌐 DNS

```bash
# List DNS records
az network dns record-set a list -g nekoc -z cat-herding.net --output table

# Add A record
az network dns record-set a add-record \
  -g nekoc -z cat-herding.net -n myapp -a 52.182.228.75

# Test DNS
nslookup myapp.cat-herding.net
```

## 🏷️ Common Values

| Resource | Value |
|----------|-------|
| Container Registry | gabby.azurecr.io |
| External IP | 52.182.228.75 |
| Internal IP | 10.224.0.5 |
| Wildcard Domain | *.cat-herding.net |
| Shared Gateway | aks-istio-ingress/cat-herding-gateway |
| OTEL Endpoint | otel-collector.default.svc.cluster.local:4317 |
| Namespace | default |

## ⚠️ Common Mistakes

| Mistake | Solution |
|---------|----------|
| Creating new Gateway | Use `aks-istio-ingress/cat-herding-gateway` |
| Creating certificates for *.cat-herding.net | Wildcard already exists |
| Missing Istio annotation | Add `sidecar.istio.io/inject: "true"` |
| Running as root | Set `runAsUser: 1001` |
| No health probe | Add `/health` endpoint |
| Missing resource limits | Set requests and limits |

## 📋 Manifest Templates

### Minimal Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 1
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      annotations:
        sidecar.istio.io/inject: "true"
      labels:
        app: myapp
    spec:
      containers:
        - name: myapp
          image: gabby.azurecr.io/myapp:latest
          ports:
            - containerPort: 8080
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 250m
              memory: 512Mi
```

### Minimal Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp
spec:
  ports:
    - port: 80
      targetPort: 8080
  selector:
    app: myapp
```

### Minimal VirtualService

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: myapp
spec:
  gateways:
    - aks-istio-ingress/cat-herding-gateway
  hosts:
    - myapp.cat-herding.net
  http:
    - route:
        - destination:
            host: myapp
            port:
              number: 80
```

## 🎯 Copilot Prompt Examples

### Deploy New App

```
Deploy my Python Flask app to the bigboy cluster:
- Image: gabby.azurecr.io/myflaskapp:latest
- Port: 5000
- Health endpoint: /healthz
- Hostname: myflaskapp.cat-herding.net
- Need environment variables: DATABASE_URL, REDIS_URL
```

### Add Authentication

```
Add GitHub OAuth authentication to my existing deployment 'myapp'
using the oauth2-proxy sidecar pattern
```

### Create CI/CD Pipeline

```
Create a GitHub Actions workflow that:
1. Builds my Docker image on push to main
2. Pushes to gabby.azurecr.io
3. Deploys to bigboy cluster using Helm
```
