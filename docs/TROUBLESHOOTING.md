# Troubleshooting Guide

Common issues and their solutions when deploying to the bigboy cluster.

## Pod Issues

### Pod stuck in Pending

**Symptoms**: Pod stays in `Pending` state

**Causes & Solutions**:

1. **Insufficient resources**
   ```bash
   kubectl describe pod <pod-name> | grep -A 5 "Events"
   ```
   Look for "Insufficient cpu" or "Insufficient memory"
   
   Solution: Reduce resource requests or wait for nodes to scale up

2. **Node selector/affinity issues**
   ```bash
   kubectl get pods -o wide  # Check which nodes are available
   kubectl describe nodes    # Check node labels and taints
   ```

3. **PVC binding issues**
   ```bash
   kubectl get pvc
   kubectl describe pvc <pvc-name>
   ```

### Pod stuck in CrashLoopBackOff

**Symptoms**: Pod repeatedly crashes and restarts

**Debug steps**:

```bash
# Check logs from current container
kubectl logs <pod-name> -c <container-name>

# Check logs from previous crashed container
kubectl logs <pod-name> -c <container-name> --previous

# Check events
kubectl describe pod <pod-name>
```

**Common causes**:

1. **App crashes on startup** - Check your app logs
2. **Health probe failing** - Adjust `initialDelaySeconds`
3. **Missing secrets/configmaps** - Verify they exist
4. **Permission denied** - Check `securityContext` settings

### Pod stuck in ImagePullBackOff

**Symptoms**: Can't pull container image

```bash
kubectl describe pod <pod-name> | grep -A 10 "Events"
```

**Solutions**:

1. **Image doesn't exist**
   ```bash
   # Verify image exists
   az acr repository show-tags --name gabby --repository <app-name>
   ```

2. **Authentication issue**
   ```bash
   # Check ACR credentials
   az acr login --name gabby
   
   # Verify AKS has ACR pull permissions
   az aks update -n bigboy -g nekoc --attach-acr gabby
   ```

## Networking Issues

### 503 Service Unavailable

**Debug steps**:

```bash
# 1. Check if pods are running
kubectl get pods -l app=<app-name>

# 2. Check if service has endpoints
kubectl get endpoints <app-name>

# 3. Check VirtualService
kubectl get virtualservice <app-name> -o yaml

# 4. Check if pods are ready
kubectl describe pod -l app=<app-name> | grep -A 5 "Conditions"

# 5. Check Istio proxy logs
kubectl logs -l app=<app-name> -c istio-proxy --tail=100
```

**Common causes**:

1. **No healthy endpoints** - Pods not ready or health check failing
2. **Wrong port configuration** - Service port vs container port mismatch
3. **VirtualService routing error** - Wrong host or port in destination

### 404 Not Found

```bash
# Check VirtualService hosts
kubectl get virtualservice -A -o jsonpath='{range .items[*]}{.metadata.name}: {.spec.hosts[*]}{"\n"}{end}'

# Check Gateway hosts
kubectl get gateway -n aks-istio-ingress cat-herding-gateway -o jsonpath='{.spec.servers[*].hosts}'
```

**Solutions**:
1. Verify VirtualService host matches your URL
2. Ensure VirtualService references correct gateway
3. Check DNS is pointing to correct IP

### Connection Refused

```bash
# Test from within cluster
kubectl run curl --rm -it --image=curlimages/curl -- curl -v http://<app-name>/

# Check if app is listening on correct port
kubectl exec -it <pod-name> -- netstat -tlnp
```

## TLS/Certificate Issues

### Certificate Not Ready

```bash
# Check certificate status
kubectl get certificate -A

# Get detailed certificate status
kubectl describe certificate <cert-name> -n aks-istio-ingress

# Check certificate request
kubectl get certificaterequest -A

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager
```

**Common causes**:

1. **DNS challenge failing** - Check Azure DNS permissions
2. **Rate limited** - Use `letsencrypt-staging` for testing
3. **Wrong issuer** - Verify `issuerRef` in Certificate

### SSL Error in Browser

```bash
# Check which secret the Gateway is using
kubectl get gateway cat-herding-gateway -n aks-istio-ingress -o jsonpath='{.spec.servers[*].tls.credentialName}'

# Verify secret exists
kubectl get secret <secret-name> -n aks-istio-ingress

# Check certificate dates
kubectl get secret <secret-name> -n aks-istio-ingress -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -dates
```

## Istio Issues

### Sidecar Not Injecting

```bash
# Check if injection is enabled
kubectl get namespace default -o jsonpath='{.metadata.labels}'

# Verify annotation on pod
kubectl get pod <pod-name> -o jsonpath='{.metadata.annotations}'
```

**Solution**: Add annotation to pod template:
```yaml
annotations:
  sidecar.istio.io/inject: "true"
```

### mTLS Issues

```bash
# Check peer authentication
kubectl get peerauthentication -A

# Check destination rules
kubectl get destinationrule -A
```

## OAuth2 Proxy Issues

### Redirect Loop

**Symptoms**: Browser keeps redirecting

**Debug**:
```bash
# Check OAuth2 proxy logs
kubectl logs -l app=<app-name> -c oauth2-proxy

# Verify cookie domain
# Cookie domain must be .cat-herding.net for SSO to work
```

**Common causes**:
1. Cookie domain mismatch
2. Redirect URL misconfiguration
3. Upstream not responding

### 500 Error After Login

```bash
# Check OAuth2 proxy can reach upstream
kubectl exec -it <pod-name> -c oauth2-proxy -- wget -O- http://127.0.0.1:<app-port>/health
```

## Resource Issues

### Out of Memory (OOMKilled)

```bash
# Check if pod was OOM killed
kubectl describe pod <pod-name> | grep -i oom

# Check current memory usage
kubectl top pod <pod-name>
```

**Solution**: Increase memory limits in deployment

### CPU Throttling

```bash
# Check current CPU usage
kubectl top pod <pod-name>

# Check if requests are too low
kubectl describe pod <pod-name> | grep -A 5 "Limits"
```

## Useful Debug Commands

```bash
# Interactive shell in cluster
kubectl run debug --rm -it --image=busybox -- /bin/sh

# Network debugging
kubectl run netshoot --rm -it --image=nicolaka/netshoot -- /bin/bash

# DNS debugging
kubectl run dnsutils --rm -it --image=registry.k8s.io/e2e-test-images/jessie-dnsutils:1.3 -- nslookup <service-name>

# View all events
kubectl get events --sort-by='.lastTimestamp' -A

# Check resource quotas
kubectl describe quota -A

# Check limit ranges
kubectl describe limitrange -A
```

## Getting Help

1. Check this troubleshooting guide
2. Review [CLUSTER_OVERVIEW.md](./CLUSTER_OVERVIEW.md) for cluster details
3. Check logs: `kubectl logs -l app=<app-name> --all-containers`
4. Describe resources: `kubectl describe <resource-type> <name>`
5. Check events: `kubectl get events --sort-by='.lastTimestamp'`
