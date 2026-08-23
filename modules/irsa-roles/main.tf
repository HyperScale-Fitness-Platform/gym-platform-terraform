locals {
  oidc_url_cleaned = replace(var.oidc_provider_url, "https://", "")
}

# ============================================================
# AWS Load Balancer Controller — IAM role + policy
# ============================================================

data "http" "alb_controller_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json"
}

# what to do inside?
resource "aws_iam_policy" "alb_controller" {
  name   = "${var.cluster_name}-alb-controller-policy"
  policy = data.http.alb_controller_policy.response_body
}

# This trust policy is the actual IRSA mechanism: it says "only the
# Kubernetes ServiceAccount named aws-load-balancer-controller, in the
# kube-system namespace, in THIS specific cluster's OIDC provider, may
# assume this role" — nothing else can.
# who can have this role?
data "aws_iam_policy_document" "alb_controller_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url_cleaned}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url_cleaned}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "alb_controller" {
  name               = "${var.cluster_name}-alb-controller-role"
  assume_role_policy = data.aws_iam_policy_document.alb_controller_trust.json
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}

# ============================================================
# External Secrets Operator — IAM role + policy
# ============================================================

resource "aws_iam_policy" "external_secrets" {
  name = "${var.cluster_name}-external-secrets-policy"

  # This is deliberately narrow: read-only access to Secrets Manager,
  # nothing else. External Secrets Operator only ever needs to READ
  # secrets and sync them into Kubernetes — it should never be able to
  # create, modify, or delete anything in Secrets Manager.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "*"
      }
    ]
  })
}

data "aws_iam_policy_document" "external_secrets_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url_cleaned}:sub"
      values   = ["system:serviceaccount:external-secrets:external-secrets"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url_cleaned}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "external_secrets" {
  name               = "${var.cluster_name}-external-secrets-role"
  assume_role_policy = data.aws_iam_policy_document.external_secrets_trust.json
}

resource "aws_iam_role_policy_attachment" "external_secrets" {
  role       = aws_iam_role.external_secrets.name
  policy_arn = aws_iam_policy.external_secrets.arn
}


# ============================================================
# EBS CSI Driver — IAM role + policy
# ============================================================
module "ebs_csi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name             = "${var.cluster_name}-ebs-csi-role"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

# ============================================================
# ArgoCD Image Updater — IAM role + policy
# ============================================================
resource "aws_iam_policy" "image_updater" {
  name = "${var.cluster_name}-image-updater-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ecr:GetAuthorizationToken",
        "ecr:ListImages",
        "ecr:DescribeImages",
        "ecr:DescribeRepositories",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchCheckLayerAvailability"
      ]
      Resource = "*"
    }]
  })
}

data "aws_iam_policy_document" "image_updater_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url_cleaned}:sub"
      values   = ["system:serviceaccount:argocd:argocd-image-updater"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url_cleaned}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "image_updater" {
  name               = "${var.cluster_name}-image-updater-role"
  assume_role_policy = data.aws_iam_policy_document.image_updater_trust.json
}

resource "aws_iam_role_policy_attachment" "image_updater" {
  role       = aws_iam_role.image_updater.name
  policy_arn = aws_iam_policy.image_updater.arn
}