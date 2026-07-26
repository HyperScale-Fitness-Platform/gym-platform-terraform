provider "aws" {
  region = var.region
  profile = "gym"
}

module "vpc" {
  source      = "../../modules/vpc"
  azs         = var.azs
  environment = "dev"
}

module "eks" {
  source            = "../../modules/eks"
  cluster_name      = "gym-cluster-dev"
  vpc_id            = module.vpc.vpc_id
  private_subnets   = module.vpc.private_subnets
  public_subnets    = module.vpc.public_subnets
}

module "ecr" {
  source = "../../modules/ecr"
  repository_names = [
    "gym-auth-service",
  ]
}

module "auth_rds" {
  source                  = "../../modules/rds"
  service_name             = "auth"
  db_name                  = "auth_db"
  vpc_id                   = module.vpc.vpc_id
  private_subnets          = module.vpc.private_subnets
  node_security_group_id   = module.eks.node_security_group_id
}

provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["--profile", "gym", "eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
    }
  }
}

module "irsa_roles" {
  source             = "../../modules/irsa-roles"
  cluster_name       = module.eks.cluster_name
  oidc_provider_arn  = module.eks.oidc_provider_arn
  oidc_provider_url  = module.eks.oidc_provider_url
  depends_on = [module.eks]
}

module "helm_addons" {
  source                     = "../../modules/helm-addons"
  cluster_name               = module.eks.cluster_name
  vpc_id                     = module.vpc.vpc_id
  alb_controller_role_arn    = module.irsa_roles.alb_controller_role_arn
  external_secrets_role_arn  = module.irsa_roles.external_secrets_role_arn
  depends_on = [module.eks, module.irsa_roles]
}