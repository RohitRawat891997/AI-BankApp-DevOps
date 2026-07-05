# Grafana — Installed via Helm into the EKS cluster
# Exposed as LoadBalancer (AWS NLB) for easy access

resource "helm_release" "kube_prometheus" {
  name             = "kube-prometheus"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "75.15.1" # Pin the chart version
  namespace        = "monitoring"
  create_namespace = true
  wait             = true

  

  set {
    name  = "grafana.service.type"
    value = "LoadBalancer"
  }

  depends_on = [
    module.eks
  ]
}

data "kubernetes_secret_v1" "grafana" {
  metadata {
    name      = "kube-prometheus-grafana"
    namespace = "monitoring"
  }

  depends_on = [
    helm_release.kube_prometheus
  ]
}

