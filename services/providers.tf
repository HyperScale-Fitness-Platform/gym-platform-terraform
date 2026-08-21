terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
  

  backend "s3" {
    bucket         = "gym-platform-tfstate-bucket"  # Same bucket name
    key            = "services/terraform.tfstate"
    region         = "us-east-1"
    use_lockfile = true
    encrypt        = true
  }
}

# Reads Layer 1 state directly from S3
data "terraform_remote_state" "infra" {
  backend = "s3"
  config = {
    bucket = var.state_bucket_name
    key    = "infrastructure/terraform.tfstate"
    region = var.aws_region
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

# Configures Kubernetes provider dynamically using Layer 1 remote state outputs
provider "kubernetes" {
  host                   = data.terraform_remote_state.infra.outputs.cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.infra.outputs.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.infra.outputs.cluster_name, "--region", var.aws_region]
  }
}

# Configures Helm provider dynamically using Layer 1 remote state outputs
provider "helm" {
  kubernetes = {
    host                   = data.terraform_remote_state.infra.outputs.cluster_endpoint
    cluster_ca_certificate = base64decode(data.terraform_remote_state.infra.outputs.cluster_certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.infra.outputs.cluster_name, "--region", var.aws_region]
    }
  }
}