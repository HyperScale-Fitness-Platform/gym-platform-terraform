module "irsa_roles" {
  source                    = "../modules/irsa-roles"
  cluster_name              = module.eks.cluster_name
  oidc_provider_arn         = module.eks.oidc_provider_arn
  oidc_provider_url         = module.eks.oidc_provider_url
  product_images_bucket_arn = module.product_images_bucket.bucket_arn
  depends_on                = [module.eks, module.product_images_bucket]
}

module "helm_addons" {
  source                    = "../modules/helm-addons"
  cluster_name              = module.eks.cluster_name
  vpc_id                    = module.vpc.vpc_id
  alb_controller_role_arn   = module.irsa_roles.alb_controller_role_arn
  external_secrets_role_arn = module.irsa_roles.external_secrets_role_arn
  depends_on                = [module.eks, module.irsa_roles]
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = module.irsa_roles.ebs_csi_role_arn

  depends_on = [module.irsa_roles, module.eks]
}

resource "kubernetes_storage_class" "ebs_gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner = "ebs.csi.aws.com"
  volume_binding_mode = "WaitForFirstConsumer"
  reclaim_policy      = "Delete"

  parameters = {
    type = "gp3"
  }

  depends_on = [aws_eks_addon.ebs_csi]
}