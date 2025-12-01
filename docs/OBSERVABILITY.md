# Observability Guide

How to integrate your application with the cluster's observability stack.

## OpenTelemetry Integration

The cluster runs a centralized OpenTelemetry Collector that can receive traces and metrics from your applications.

### Collector Endpoints

| Protocol | Endpoint | Port |
|----------|----------|------|
| gRPC | otel-collector.default.svc.cluster.local | 4317 |
| HTTP | otel-collector.default.svc.cluster.local | 4318 |

### Quick Setup

Add these environment variables to your deployment:

```yaml
env:
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://otel-collector.default.svc.cluster.local:4317"
  - name: OTEL_SERVICE_NAME
    value: "myapp"
  - name: OTEL_RESOURCE_ATTRIBUTES
    value: "deployment.environment=production,service.namespace=default"
```

Or enable via Helm:

```yaml
otel:
  enabled: true
```

### Language-Specific Setup

#### Node.js

```bash
npm install @opentelemetry/auto-instrumentations-node
```

```javascript
// tracing.js - Import before other modules
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');

const sdk = new NodeSDK({
  traceExporter: new OTLPTraceExporter(),
  instrumentations: [getNodeAutoInstrumentations()],
});

sdk.start();
```

```javascript
// app.js
require('./tracing');
// ... rest of your app
```

#### Python

```bash
pip install opentelemetry-distro opentelemetry-exporter-otlp
opentelemetry-bootstrap -a install
```

```python
# Run with auto-instrumentation
# opentelemetry-instrument python app.py

# Or manual setup:
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

provider = TracerProvider()
processor = BatchSpanProcessor(OTLPSpanExporter())
provider.add_span_processor(processor)
trace.set_tracer_provider(provider)
```

#### Go

```bash
go get go.opentelemetry.io/otel
go get go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc
```

```go
import (
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
    "go.opentelemetry.io/otel/sdk/trace"
)

func initTracer() (*trace.TracerProvider, error) {
    exporter, err := otlptracegrpc.New(context.Background())
    if err != nil {
        return nil, err
    }
    
    tp := trace.NewTracerProvider(
        trace.WithBatcher(exporter),
    )
    otel.SetTracerProvider(tp)
    return tp, nil
}
```

## Istio Metrics

Istio automatically collects metrics for all services. Access via Azure Monitor or Prometheus queries.

### Available Metrics

| Metric | Description |
|--------|-------------|
| `istio_requests_total` | Total requests by response code |
| `istio_request_duration_milliseconds` | Request latency |
| `istio_request_bytes` | Request size |
| `istio_response_bytes` | Response size |

### Viewing in Azure Portal

1. Go to Azure Portal → Monitor → Metrics
2. Select the AKS cluster resource
3. Choose Prometheus metrics namespace
4. Select Istio metrics

## Logging

### Structured Logging

Use JSON-formatted logs for easy parsing:

```javascript
// Node.js with Winston
const logger = winston.createLogger({
  format: winston.format.json(),
  defaultMeta: { service: 'myapp' },
  transports: [new winston.transports.Console()],
});
```

```python
# Python with structlog
import structlog
structlog.configure(
    processors=[structlog.processors.JSONRenderer()],
)
logger = structlog.get_logger()
```

### Log Fields

Include these fields for better correlation:

| Field | Description |
|-------|-------------|
| `service` | Your service name |
| `level` | Log level (info, warn, error) |
| `timestamp` | ISO8601 timestamp |
| `trace_id` | OpenTelemetry trace ID |
| `span_id` | OpenTelemetry span ID |

### Viewing Logs

```bash
# Real-time logs
kubectl logs -l app=myapp -f

# Logs from all containers
kubectl logs -l app=myapp --all-containers

# Logs from specific container
kubectl logs <pod-name> -c myapp

# Previous container logs (after crash)
kubectl logs <pod-name> -c myapp --previous
```

### Azure Log Analytics

Logs are automatically forwarded to Azure Log Analytics. Query with KQL:

```kusto
ContainerLog
| where ContainerName == "myapp"
| where TimeGenerated > ago(1h)
| project TimeGenerated, LogEntry
| order by TimeGenerated desc
```

## Health Endpoints

### Required Endpoints

Your app should expose:

| Endpoint | Purpose | Expected Response |
|----------|---------|-------------------|
| `/health` | Kubernetes probes | 200 OK |
| `/ready` | Readiness check | 200 OK when ready |
| `/live` | Liveness check | 200 OK when alive |

### Example Implementation

```javascript
// Node.js/Express
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    version: process.env.APP_VERSION || 'unknown'
  });
});

app.get('/ready', async (req, res) => {
  // Check dependencies
  const dbHealthy = await checkDatabase();
  const cacheHealthy = await checkCache();
  
  if (dbHealthy && cacheHealthy) {
    res.json({ status: 'ready' });
  } else {
    res.status(503).json({ status: 'not ready' });
  }
});
```

## Alerts (Azure Monitor)

### Setting Up Alerts

1. Go to Azure Portal → Monitor → Alerts
2. Create new alert rule
3. Select AKS cluster as resource
4. Choose metric/log condition
5. Configure action group (email, Slack, etc.)

### Common Alert Conditions

| Condition | Threshold |
|-----------|-----------|
| Pod restart count | > 3 in 5 minutes |
| Container CPU % | > 90% for 5 minutes |
| Container memory % | > 90% for 5 minutes |
| HTTP 5xx rate | > 1% of requests |
| Response latency P99 | > 5 seconds |
