resource "helm_release" "jenkins" {
  name             = "jenkins"
  repository       = "https://charts.jenkins.io"
  chart            = "jenkins"
  namespace        = "jenkins"
  create_namespace = true
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

resource "helm_release" "argocd_image_updater" {
  name             = "argocd-image-updater"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argocd-image-updater"
  namespace        = "argocd"
  create_namespace = false
  timeout          = 300

  values = [
    <<-EOT
    serviceAccount:
      create: true
      name: argocd-image-updater
      annotations:
        eks.amazonaws.com/role-arn: "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${data.terraform_remote_state.infra.outputs.cluster_name}-image-updater-role"

    config:
      registries:
        - name: ECR
          api_url: https://${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com
          prefix: ${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com
          ping: yes
          credentials: ext:/scripts/ecr-login.sh

    authScripts:
      enabled: true
      scripts:
        ecr-login.sh: |
          #!/bin/sh
          export HOME=/tmp
          TOKEN=$(aws ecr get-login-password --region ${var.aws_region})
          echo "AWS:$TOKEN"
    EOT
  ]

  depends_on = [helm_release.argocd]
}

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true

  set = [
    {
      name  = "crds.enabled"
      value = "true"
    }
  ]
}