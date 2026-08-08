module "irsa_roles" {
  source             = "../modules/irsa-roles"
  cluster_name       = module.eks.cluster_name
  oidc_provider_arn  = module.eks.oidc_provider_arn
  oidc_provider_url  = module.eks.oidc_provider_url
  depends_on = [module.eks]
}

module "helm_addons" {
  source                     = "../modules/helm-addons"
  cluster_name               = module.eks.cluster_name
  vpc_id                     = module.vpc.vpc_id
  alb_controller_role_arn    = module.irsa_roles.alb_controller_role_arn
  external_secrets_role_arn  = module.irsa_roles.external_secrets_role_arn
  depends_on = [module.eks, module.irsa_roles]
}