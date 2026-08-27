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
    "gym-profile-service",
    "gym-progress-service",
    "gym-catalog-service",
    "gym-order-service",
    "gym-payment-service",
    "gym-operations-service",
    "gym-social-service",
    "gym-ai-service",
    "frontend-service"
  ]
}



module "product_images_bucket" {
  source          = "../modules/s3"
  bucket_name     = "gym-platform-product-images"
  allowed_origins = ["http://localhost:3080"] # add the prod frontend URL once it exists
}



