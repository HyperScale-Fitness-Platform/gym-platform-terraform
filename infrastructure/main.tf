module "vpc" {
  source      = "../modules/vpc"
  azs         = var.azs
  environment = "dev"
}

module "eks" {
  source          = "../modules/eks"
  cluster_name    = "gym-cluster"
  vpc_id          = module.vpc.vpc_id
  private_subnets = module.vpc.private_subnets
  public_subnets  = module.vpc.public_subnets
}

module "ecr" {
  source = "../modules/ecr"
  repository_names = [
    "gym-api-gateway",
    "gym-auth-service",
    "gym-operations-service"
  ]
}