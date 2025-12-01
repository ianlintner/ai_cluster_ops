# Cluster issuer reference
#
# These cluster issuers are already configured in the `bigboy` AKS cluster.
# Do not create new issuers; reference these in your `Certificate` resources.

# ============================================================================
# PRODUCTION ISSUER: letsencrypt-prod
# ============================================================================
# Use this for production certificates.
# Rate limits: 50 certificates per week per domain
# Trusted by all browsers

# ============================================================================
# STAGING ISSUER: letsencrypt-staging
# ============================================================================  
# Use this for testing certificate generation.
# No rate limits - ideal for development
# NOT trusted by browsers (will show certificate warnings)

# ============================================================================
# EXAMPLE USAGE
# ============================================================================

---
# Example: Certificate for hugecat.net subdomain
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: myapp-hugecat-tls
  namespace: aks-istio-ingress
spec:
  secretName: myapp-hugecat-tls
  duration: 2160h
  renewBefore: 360h
  issuerRef:
    kind: ClusterIssuer
    name: letsencrypt-prod
  dnsNames:
    - "myapp.hugecat.net"

---
# Example: Wildcard certificate (if you need one for a new domain)
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: example-wildcard
  namespace: aks-istio-ingress
spec:
  secretName: example-wildcard-tls
  duration: 2160h
  renewBefore: 360h
  issuerRef:
    kind: ClusterIssuer
    name: letsencrypt-prod
  dnsNames:
    - "*.example.hugecat.net"
    - "example.hugecat.net"
