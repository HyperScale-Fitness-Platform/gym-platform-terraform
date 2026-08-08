# AWS Load Balancer Controller
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"

  set = [
    {
      name  = "clusterName"
      value = var.cluster_name
    },
    {
      name  = "vpcId"
      value = var.vpc_id
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = var.alb_controller_role_arn
    },
    {
      name  = "serviceAccount.create"
      value = "true"
    }
  ]
}

# External Secrets Operator
resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true

  set = [
    {
      name  = "installCRDs"
      value = "true"
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = var.external_secrets_role_arn
    },
    {
      name  = "serviceAccount.name"
      value = "external-secrets"
    }
  ]
}


# Jenkins
resource "kubernetes_namespace" "jenkins" {
  metadata {
    name = "jenkins"
  }
}

# Install Jenkins via Helm
resource "helm_release" "jenkins" {
  name       = "jenkins"
  repository = "https://charts.jenkins.io"
  chart      = "jenkins"
  version    = "5.1.2" 
  namespace  = kubernetes_namespace.jenkins.metadata[0].name

  # Pass custom values to override default chart behavior
  values = [
    <<-EOT
    controller:
      componentName: "jenkins-controller"
      # Allocate adequate resources for EKS worker nodes
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
    EOT
  ]
}