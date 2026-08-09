resource "helm_release" "jenkins" {
  name             = "jenkins"
  repository       = "https://charts.jenkins.io"
  chart            = "jenkins"
  namespace        = "jenkins"
  create_namespace = true

  # cleanup_on_fail = true
  # atomic          = true
  timeout         = 600

  values = [
    <<-EOT
    controller:
      componentName: "jenkins-controller"
      resources:
        requests:
          cpu: "500m"
          memory: "1024Mi"
        limits:
          cpu: "2000m"
          memory: "2048Mi"
      serviceType: "ClusterIP"
      admin:
        username: "admin"
        userKey: ""
        existingSecret: "jenkins-admin-credentials"
        passwordKey: "jenkins-admin-password"

    persistence:
      enabled: true
      storageClass: "gp3"
      size: "8Gi"
    EOT
  ]
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  timeout          = 600

  values = [
    <<-EOT
    global:
      domain: "argocd.local"

    server:
      service:
        type: "ClusterIP"
      metrics:
        enabled: true

    controller:
      metrics:
        enabled: true

    repoServer:
      metrics:
        enabled: true
    EOT
  ]
}