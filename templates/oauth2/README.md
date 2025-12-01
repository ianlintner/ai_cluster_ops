# OAuth2 Proxy Templates

This directory contains templates for adding GitHub OAuth authentication to your applications.

## Architecture

OAuth2 Proxy runs as a sidecar container in your pod, intercepting all requests and redirecting unauthenticated users to GitHub for login.

```
Internet → Istio Gateway → OAuth2 Proxy (4180) → Your App (8080)
```

## Prerequisites

The cluster already has:
- Shared OAuth2 Proxy ConfigMap: `oauth2-proxy-sidecar-config`
- OAuth2 Proxy Secret: `oauth2-proxy-secret`

These are configured for SSO across all `*.cat-herding.net` domains.

## Files

1. **deployment-with-oauth2-sidecar.yaml** - Complete deployment template with OAuth2 proxy sidecar
2. **service-oauth2.yaml** - Service that routes to OAuth2 proxy port (4180)
3. **virtualservice-oauth2.yaml** - VirtualService for authenticated apps

## Usage

### Option 1: Use Helm Chart (Recommended)

```yaml
# values.yaml
oauth2Proxy:
  enabled: true
  
app:
  containerPort: 8080  # Your app's port
```

```bash
helm upgrade --install myapp ./helm/app-template -f values.yaml
```

### Option 2: Manual Manifests

1. Copy the templates from this directory
2. Replace placeholders:
   - `<APP_NAME>`: Your application name
   - `<IMAGE>`: Your container image
   - `<APP_PORT>`: Your application's internal port

## How It Works

1. User visits `https://myapp.cat-herding.net`
2. OAuth2 Proxy checks for valid session cookie
3. If no cookie: Redirect to `https://auth.cat-herding.net/oauth2/start`
4. User authenticates with GitHub
5. GitHub redirects to `https://auth.cat-herding.net/oauth2/callback`
6. OAuth2 Proxy sets session cookie and redirects to original URL
7. All subsequent requests pass through with user info headers

## Headers Available to Your App

OAuth2 Proxy adds these headers to authenticated requests:

| Header | Description |
|--------|-------------|
| `X-Auth-Request-User` | GitHub username |
| `X-Auth-Request-Email` | User's email |
| `X-Auth-Request-Access-Token` | GitHub access token |
| `Authorization` | Bearer token |

## Customization

If you need custom OAuth2 Proxy configuration (different scopes, group validation, etc.), you can create your own ConfigMap instead of using the shared one.
