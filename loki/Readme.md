# Monitoring Stack Setup (Prometheus + Grafana + Loki + Promtail)

This guide explains how to install a complete monitoring and logging stack on Kubernetes using Helm.

## Components

| Component | Purpose |
|----------|---------|
| Prometheus | Collects metrics from Kubernetes workloads |
| Grafana | Visualizes metrics and logs using dashboards |
| Loki | Stores application and Kubernetes logs |
| Promtail | Collects logs from nodes/pods and sends them to Loki |

---

# Prerequisites

- Kubernetes Cluster
- Helm installed
- Monitoring namespace

Create the namespace if it doesn't exist:

```bash
kubectl create namespace monitoring
```

---

# Step 1: Add Helm Repositories

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

helm repo add grafana https://grafana.github.io/helm-charts

helm repo update
```

---

# Step 2: Install Loki

Loki is the log aggregation system that stores logs.

```bash
helm upgrade --install loki grafana/loki-distributed \
-n monitoring
```

Verify installation:

```bash
kubectl get pods -n monitoring
```

---

# Step 3: Create Grafana Configuration

Create a file named **grafana-config.yaml**

```yaml
prometheus:
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false
    serviceMonitorSelector: {}
    serviceMonitorNamespaceSelector: {}

grafana:
  sidecar:
    datasources:
      defaultDatasourceEnabled: true

  additionalDataSources:
    - name: Loki
      type: loki
      url: http://loki-loki-distributed-query-frontend.monitoring:3100
```

This configuration:

- Enables Prometheus ServiceMonitor discovery.
- Configures Grafana automatically.
- Adds Loki as a data source.

---

# Step 4: Install Prometheus & Grafana

```bash
helm upgrade --install grafana \
prometheus-community/kube-prometheus-stack \
-n monitoring \
-f grafana-config.yaml
```

Verify installation:

```bash
kubectl get pods -n monitoring
```

---

# Step 5: Create Promtail Configuration

Create a file named **promtail-config.yaml**

```yaml
config:
  serverPort: 8080

  clients:
    - url: http://loki-loki-distributed-gateway/loki/api/v1/push
```

This configuration tells Promtail where to send logs.

---

# Step 6: Install Promtail

```bash
helm upgrade --install promtail \
grafana/promtail \
-n monitoring \
-f promtail-config.yaml
```

Verify installation:

```bash
kubectl get daemonset -n monitoring
```

---

# Verify Installation

Check all monitoring resources:

```bash
kubectl get pods -n monitoring
```

Expected components:

- Prometheus
- Grafana
- Loki
- Promtail
- Alertmanager

---

# Access Grafana

Port forward Grafana:

```bash
kubectl port-forward svc/grafana 3000:80 -n monitoring
```

Open:

```
http://localhost:3000
```

Get the admin password:

```bash
kubectl get secret grafana-grafana \
-n monitoring \
-o jsonpath="{.data.admin-password}" | base64 -d
```

Username:

```
admin
```

---

# Verify Loki Data Source

In Grafana:

1. Open **Connections → Data Sources**
2. Verify:
   - Prometheus
   - Loki
3. Both should show **Healthy**

---

# View Logs

Navigate to:

```
Explore
```

Select:

```
Loki
```

Run a query:

```text
{namespace="default"}
```

or

```text
{job="kubernetes-pods"}
```

Logs from your Kubernetes workloads should appear.

---

# Architecture

```
Kubernetes Pods
        │
        ▼
    Promtail
        │
        ▼
      Loki
        │
        ▼
    Grafana
        ▲
        │
   Prometheus
        ▲
        │
 Kubernetes Metrics
```

---

# Cleanup

Remove all components:

```bash
helm uninstall promtail -n monitoring

helm uninstall loki -n monitoring

helm uninstall grafana -n monitoring
```

---

# Monitoring Stack Overview

| Component | Function |
|----------|----------|
| Prometheus | Metrics collection |
| Grafana | Dashboards and visualization |
| Loki | Log storage |
| Promtail | Log collection |
| Helm | Kubernetes package manager |
