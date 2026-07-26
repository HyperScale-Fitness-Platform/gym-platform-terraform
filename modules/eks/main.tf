module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.36"

  vpc_id     = var.vpc_id
  subnet_ids = concat(var.private_subnets, var.public_subnets)

  cluster_endpoint_public_access = true
  enable_cluster_creator_admin_permissions = true

  # IAM Roles for Service Accounts. It sets up an OpenID Connect (OIDC) identity provider.
  # Without this, your Kubernetes applications would need permanent, hardcoded AWS keys to talk to other AWS resources (like S3 or RDS). 
  # With IRSA, you can attach a fine-grained AWS IAM role directly to a specific Kubernetes application container dynamically.
  enable_irsa = true

  eks_managed_node_groups = {
    gym_nodes = {
      instance_types = [var.node_instance_type]
      min_size       = 2
      max_size       = 4
      desired_size   = 2

      subnet_ids = var.private_subnets
    }
  }

  cluster_addons = {
    vpc-cni    = {}
    coredns    = {}
    kube-proxy = {}
    #aws-ebs-csi-driver = {attach_node_iam_policy = true}
  }
}