module "vpc" {
  source      = "../../modules/vpc"
  azs         = var.azs
  environment = "dev"
}

module "eks" {
  source            = "../../modules/eks"
  cluster_name      = "gym-cluster"
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

module "secrets" {
  source       = "../../modules/secrets"
}

module "auth_rds" {
  source                   = "../../modules/rds"
  service_name             = "auth"
  db_name                  = "gym_auth"
  vpc_id                   = module.vpc.vpc_id
  private_subnets          = module.vpc.private_subnets
  node_security_group_id   = module.eks.node_security_group_id
  password                 = module.secrets.auth_db_password
}