module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "gym-vpc-${var.environment}"
  cidr = var.vpc_cidr

  azs             = var.azs
  private_subnets = [for i in range(length(var.azs)) : cidrsubnet(var.vpc_cidr, 8, i)]
  public_subnets  = [for i in range(length(var.azs)) : cidrsubnet(var.vpc_cidr, 8, i + 100)]

  enable_nat_gateway   = true
  single_nat_gateway   = true   # one shared NAT gateway — cheaper for dev
  enable_dns_hostnames = true

  # These tags are REQUIRED — EKS and the AWS Load Balancer Controller
  # look for these exact tags to know which subnets to use for internal
  # load balancers vs internet-facing ones.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  tags = {
    Environment = var.environment
    Project     = "gym-platform"
  }
}