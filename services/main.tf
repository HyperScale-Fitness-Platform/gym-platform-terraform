resource "helm_release" "jenkins" {
  name             = "jenkins"
  repository       = "https://charts.jenkins.io"
  chart            = "jenkins"
  version          = "5.1.2"
  namespace        = "jenkins"
  create_namespace = true

  cleanup_on_fail  = true
  atomic           = true
  timeout          = 600

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
        existingSecret: "jenkins-admin-credentials"
        passwordKey: "jenkins-admin-password"

    persistence:
      enabled: true
      storageClass: "gp3"
      size: "8Gi"
    EOT
  ]
}