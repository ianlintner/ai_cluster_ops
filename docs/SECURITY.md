# Security best practices

Security guidelines for applications deployed to the `bigboy` AKS cluster.

## Container security

### Required security context

All deployments MUST include these security settings:

```yaml
spec:
  # Pod-level security
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
        readOnlyRootFilesystem: true  # Recommended
```

### Dockerfile best practices

```dockerfile
# Use specific version, not latest
FROM node:20-alpine

# Create non-root user
RUN addgroup -g 1001 -S appgroup && \
    adduser -u 1001 -S appuser -G appgroup

WORKDIR /app
COPY --chown=appuser:appgroup . .

# Install dependencies as root, then switch
RUN npm ci --only=production

# Switch to non-root user
USER 1001

# Use non-privileged port
EXPOSE 8080

CMD ["node", "server.js"]
```

### Image scanning

Images pushed to `gabby.azurecr.io` should be scanned for vulnerabilities:

```bash
# Enable scanning in ACR (if not already enabled)
az acr config content-trust update --registry gabby --status enabled

# Check scan results
az acr repository show-manifests --name gabby --repository myapp --detail
```

## Secrets management

> ⚠️ **CRITICAL**: **Never** store secrets in Kubernetes manifests, Git repositories, or environment variables in Dockerfiles. Always use Azure Key Vault.

### Do not

- ❌ Hardcode secrets in code or manifests
- ❌ Commit secrets to Git (even encrypted)
- ❌ Use environment variables in Dockerfile
- ❌ Store secrets in ConfigMaps
- ❌ Log secrets or sensitive data
- ❌ Pass secrets as command-line arguments
- ❌ Include secrets in container images

### Do

- ✅ **Use Azure Key Vault** for all secrets
- ✅ Use managed identities for authentication
- ✅ Rotate secrets regularly
- ✅ Use separate Key Vaults per environment
- ✅ Audit secret access
- ✅ Use least-privilege access policies

---

## Azure Key Vault integration

The cluster has **Azure Key Vault Secrets Provider** enabled with automatic secret rotation every 2 minutes.

### Step 1: Create an Azure Key Vault (if needed)

```bash
# Create Key Vault
az keyvault create \
  --name myapp-kv \
  --resource-group nekoc \
  --location centralus \
  --enable-rbac-authorization

# Add a secret
az keyvault secret set \
  --vault-name myapp-kv \
  --name database-password \
  --value "your-secret-password"

az keyvault secret set \
  --vault-name myapp-kv \
  --name api-key \
  --value "your-api-key"
```

### Step 2: Grant access to AKS managed identity

```bash
# Get the AKS Key Vault identity
KV_IDENTITY=$(az aks show -g nekoc -n bigboy --query addonProfiles.azureKeyvaultSecretsProvider.identity.clientId -o tsv)

# Get Key Vault resource ID
KV_RESOURCE_ID=$(az keyvault show --name myapp-kv --query id -o tsv)

# Assign Key Vault Secrets User role
az role assignment create \
  --role "Key Vault Secrets User" \
  --assignee $KV_IDENTITY \
  --scope $KV_RESOURCE_ID
```

### Step 3: Create `SecretProviderClass`

Create a `SecretProviderClass` to define which secrets to sync:

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: myapp-secrets
  namespace: default
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "true"
    userAssignedIdentityID: "f2a13db4-007a-46c8-b155-28de1e7d24f6"  # AKS KV identity
    keyvaultName: "myapp-kv"
    tenantId: "your-tenant-id"  # Azure AD tenant ID
    objects: |
      array:
        - |
          objectName: database-password
          objectType: secret
        - |
          objectName: api-key
          objectType: secret
  # Optional: Sync to Kubernetes Secret for env var use
  secretObjects:
    - secretName: myapp-secrets-k8s
      type: Opaque
      data:
        - objectName: database-password
          key: DATABASE_PASSWORD
        - objectName: api-key
          key: API_KEY
```

### Step 4: Mount secrets in deployment

**Option A: Mount as files (recommended)**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  template:
    spec:
      containers:
        - name: app
          image: gabby.azurecr.io/myapp:latest
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
              secretProviderClass: myapp-secrets
```

Secrets will be available as files:
- `/mnt/secrets/database-password`
- `/mnt/secrets/api-key`

**Option B: Sync to environment variables**

If your app requires environment variables (use the `secretObjects` section above):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  template:
    spec:
      containers:
        - name: app
          image: gabby.azurecr.io/myapp:latest
          env:
            - name: DATABASE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: myapp-secrets-k8s  # From secretObjects sync
                  key: DATABASE_PASSWORD
            - name: API_KEY
              valueFrom:
                secretKeyRef:
                  name: myapp-secrets-k8s
                  key: API_KEY
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
              secretProviderClass: myapp-secrets
```

> **Note**: The CSI volume must still be mounted for the secret sync to work.

### Secret rotation

Secrets are automatically rotated every 2 minutes. Your app should:

1. **For file-mounted secrets**: Re-read the file when needed (don't cache)
2. **For env var secrets**: Pod restart may be required for updated values

### Complete example: app with Key Vault secrets

```yaml
---
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: myapp-secrets
  namespace: default
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "true"
    userAssignedIdentityID: "f2a13db4-007a-46c8-b155-28de1e7d24f6"
    keyvaultName: "myapp-kv"
    tenantId: "YOUR_TENANT_ID"
    objects: |
      array:
        - |
          objectName: database-url
          objectType: secret
        - |
          objectName: api-key
          objectType: secret
  secretObjects:
    - secretName: myapp-env-secrets
      type: Opaque
      data:
        - objectName: database-url
          key: DATABASE_URL
        - objectName: api-key
          key: API_KEY
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: default
  labels:
    app: myapp
spec:
  replicas: 2
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
      annotations:
        sidecar.istio.io/inject: "true"
    spec:
      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: app
          image: gabby.azurecr.io/myapp:latest
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
            runAsNonRoot: true
            runAsUser: 1001
          ports:
            - containerPort: 8080
          envFrom:
            - secretRef:
                name: myapp-env-secrets
          volumeMounts:
            - name: secrets-store
              mountPath: "/mnt/secrets"
              readOnly: true
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 250m
              memory: 512Mi
      volumes:
        - name: secrets-store
          csi:
            driver: secrets-store.csi.k8s.io
            readOnly: true
            volumeAttributes:
              secretProviderClass: myapp-secrets
      tolerations:
        - key: kubernetes.azure.com/scalesetpriority
          operator: Equal
          value: spot
          effect: NoSchedule
```

### Troubleshooting Key Vault secrets

```bash
# Check SecretProviderClass
kubectl describe secretproviderclass myapp-secrets

# Check if secrets are mounted
kubectl exec -it <pod-name> -- ls /mnt/secrets/

# Check CSI driver logs
kubectl logs -n kube-system -l app=secrets-store-csi-driver

# Verify Key Vault access
az keyvault secret list --vault-name myapp-kv
```

## Network security

### Istio mTLS

Istio automatically enables mutual TLS between services. All service-to-service traffic is encrypted.

### Network policies (optional)

For additional isolation, create NetworkPolicies:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: myapp-network-policy
spec:
  podSelector:
    matchLabels:
      app: myapp
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: aks-istio-ingress
      ports:
        - port: 8080
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              name: default
      ports:
        - port: 5432  # PostgreSQL
```

### Istio Authorization Policies

```yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: myapp-authz
spec:
  selector:
    matchLabels:
      app: myapp
  rules:
    - from:
        - source:
            principals: ["cluster.local/ns/default/sa/frontend"]
      to:
        - operation:
            methods: ["GET", "POST"]
            paths: ["/api/*"]
```

## Authentication & Authorization

### OAuth2 Proxy (GitHub OAuth)

For web applications requiring authentication, use the OAuth2 proxy sidecar pattern. See [OAuth2 Templates](../templates/oauth2/README.md).

### Service Account Tokens

Disable automatic service account token mounting unless needed:

```yaml
spec:
  automountServiceAccountToken: false
```

If your app needs to access Kubernetes API:

```yaml
spec:
  serviceAccountName: myapp-sa
  automountServiceAccountToken: true
```

## Resource Limits

Always set resource limits to prevent DoS:

```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 250m
    memory: 512Mi
```

## Audit & Logging

### What to Log

- Authentication events
- Authorization failures
- Data access patterns
- Error conditions

### What NOT to Log

- Passwords/secrets
- API keys
- Personal identifiable information (PII)
- Credit card numbers

### Log Format

Use structured logging (JSON) for easy parsing:

```json
{
  "timestamp": "2024-01-15T10:30:00Z",
  "level": "info",
  "message": "User authenticated",
  "userId": "user123",
  "action": "login",
  "ip": "10.0.0.1"
}
```

## Security Checklist

Before deploying, verify:

- [ ] Container runs as non-root user
- [ ] No privilege escalation allowed
- [ ] All capabilities dropped
- [ ] Secrets not in environment variables or logs
- [ ] Resource limits set
- [ ] Health probes configured
- [ ] Read-only root filesystem (if possible)
- [ ] No unnecessary ports exposed
- [ ] Image from trusted registry (gabby.azurecr.io)
- [ ] Base image is up-to-date
