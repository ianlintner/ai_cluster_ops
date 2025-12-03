# Bigboy AKS Operations Hub

Welcome to the single source of truth for deploying and operating workloads on the **bigboy** Azure Kubernetes Service (AKS) cluster. This site consolidates the playbooks, guardrails, and automation templates that GitHub Copilot and humans rely on to ship trustworthy services to production.

!!! tip "New here?"
    Start with the [Onboarding Guide](ONBOARDING.md) for a soup-to-nuts walkthrough covering prerequisites, required Azure resources, and the exact manifest templates expected on the cluster.

## What lives here

| Area | Why it matters |
|------|----------------|
| [Cluster Overview](CLUSTER_OVERVIEW.md) | Networking, Istio gateways, Key Vault integration, and shared infrastructure configuration. |
| [Security Guide](SECURITY.md) | Mandatory pod security context, secret handling with Azure Key Vault, and CI/CD hardening. |
| [Observability Guide](OBSERVABILITY.md) | OpenTelemetry setup, structured logging patterns, and metrics that keep the platform healthy. |
| [Troubleshooting](TROUBLESHOOTING.md) | Common failure modes plus verified commands for diagnosing deployments. |
| [Cheatsheet](CHEATSHEET.md) | High-signal commands and snippets for quick reference. |
| [Decommissioning Archive](decommissioned/README.md) | Runbook for responsibly retiring services when they are no longer needed. |

## Using this site with GitHub Copilot

1. Give Copilot the context it needs by pointing it to this repository.
2. Mention the relevant docs (for example, "follow the Security Guide from ai_cluster_ops").
3. Keep this site current—when requirements change, update the docs first so every automation run inherits the new truth.

## Local development

```bash
python -m pip install --upgrade pip
pip install -r docs/requirements.txt
mkdocs serve
```

MkDocs will reload automatically as you edit markdown under the `docs/` directory.
