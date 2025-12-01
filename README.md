# AI Cluster Ops - Bigboy AKS Onboarding

A comprehensive knowledge base and automation toolkit for rapidly onboarding new applications to the **bigboy** AKS cluster hosted in Azure.

## 🎯 Purpose

This repository enables engineers (and AI assistants like GitHub Copilot) to quickly deploy new services to our Kubernetes cluster with minimal manual configuration. Simply provide Copilot with access to this repo and describe your app - it will generate all the necessary Kubernetes manifests, Helm charts, and CI/CD pipelines.

## 📋 Quick Start

### For Engineers with Copilot

1. **In your app repository**, ensure you have CLI access configured:
   ```bash
   az login
   az aks get-credentials --resource-group nekoc --name bigboy
   ```

2. **Reference this repo** in your Copilot prompt:
   ```
   Using the ai_cluster_ops templates and instructions, deploy my [Node.js/Python/Go] 
   app to the bigboy cluster with hostname [myapp].cat-herding.net
   ```

3. Copilot will generate:
   - Dockerfile (if needed)
   - Kubernetes manifests or Helm chart
   - Istio Gateway/VirtualService
   - TLS certificate configuration
   - GitHub Actions workflow

### Manual Onboarding

See [docs/ONBOARDING.md](docs/ONBOARDING.md) for step-by-step instructions.

## 🏗️ Cluster Architecture

| Component | Description |
|-----------|-------------|
| **AKS Cluster** | `bigboy` in `centralus`, Kubernetes 1.32.9 |
| **Resource Group** | `nekoc` |
| **Container Registry** | `gabby.azurecr.io` |
| **Service Mesh** | Azure Managed Istio (ASM 1.27) |
| **TLS Certificates** | cert-manager with Let's Encrypt |
| **Ingress** | Istio Gateway (external: 52.182.228.75) |
| **DNS Zones** | `cat-herding.net`, `hugecat.net` |
| **Observability** | OpenTelemetry Collector + Azure Monitor |

## 📁 Repository Structure

```
ai_cluster_ops/
├── .github/
│   ├── copilot-instructions.md    # AI assistant context
│   └── workflows/                  # Reusable CI/CD templates
├── docs/
│   ├── CLUSTER_OVERVIEW.md        # Detailed cluster architecture
│   ├── ONBOARDING.md              # Step-by-step guide
│   ├── TROUBLESHOOTING.md         # Common issues & solutions
│   └── SECURITY.md                # Security best practices
├── helm/
│   └── app-template/              # Base Helm chart for apps
├── manifests/
│   ├── base/                      # Base Kustomize resources
│   └── examples/                  # Example deployments
├── templates/
│   ├── deployment/                # Deployment templates
│   ├── istio/                     # Gateway/VirtualService templates
│   ├── certificates/              # TLS certificate templates
│   └── oauth2/                    # OAuth2 proxy templates
└── scripts/
    ├── deploy.sh                  # Deployment helper
    └── validate.sh                # Pre-deployment validation
```

## 🔧 Available Templates

| Template | Use Case |
|----------|----------|
| `simple-web` | Static sites, simple APIs (no auth) |
| `authenticated-web` | Apps requiring GitHub OAuth |
| `api-service` | Backend APIs with health checks |
| `full-stack` | Apps with database/Redis dependencies |

## 📡 DNS & Ingress

Apps deployed to this cluster automatically get:
- **Wildcard DNS**: `*.cat-herding.net` → 52.182.228.75
- **Wildcard TLS**: Automatic HTTPS via Let's Encrypt
- **Istio sidecar**: Automatic mTLS between services

Simply create a VirtualService pointing to your subdomain!

## 🔐 Authentication Options

1. **No Auth** - Public endpoints
2. **OAuth2 Proxy Sidecar** - GitHub OAuth protection
3. **Istio AuthorizationPolicy** - Service-to-service auth

## 📊 Observability

All apps automatically get:
- **Distributed Tracing** via Istio + OTLP (port 4317/4318)
- **Metrics** scraped by Azure Monitor
- **Logging** via container stdout/stderr

## 🚀 Deployment Patterns

### Pattern 1: Helm Chart (Recommended)
```bash
helm upgrade --install myapp ./helm/app-template \
  --set app.name=myapp \
  --set app.image=gabby.azurecr.io/myapp:latest \
  --set app.hostname=myapp.cat-herding.net
```

### Pattern 2: kubectl with Templates
```bash
# Generate manifests
./scripts/generate.sh myapp myapp.cat-herding.net

# Apply
kubectl apply -f generated/myapp/
```

### Pattern 3: Kustomize
```bash
kubectl apply -k manifests/overlays/myapp/
```

## 📝 License

Internal use only - Nekoc Labs
