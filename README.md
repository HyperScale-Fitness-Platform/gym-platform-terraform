# Gym Platform Terraform

This repository contains Terraform configuration for provisioning AWS infrastructure for the gym platform. The project is organized around a development environment under `environments/dev/` and reusable infrastructure modules in `modules/`.

## Overview

The current configuration deploys an AWS development stack with:

- Amazon VPC and subnet topology
- Amazon EKS cluster for Kubernetes workloads
- Amazon ECR repositories for application container images
- Amazon RDS database for the auth service
- IAM Roles for Service Accounts (IRSA)
- Helm-managed Kubernetes addons deployed via Terraform

The `environments/dev/main.tf` file wires together AWS provider settings and reusable modules.

## Repo Structure

- `environments/dev/` - development environment configuration
  - `backend.tf` - backend state configuration
  - `main.tf` - AWS provider plus module instantiations for VPC, EKS, ECR, RDS, IRSA roles, and Helm addons
  - `variables.tf` - input variable definitions for the dev environment
  - `terraform.tfvars` - environment-specific variable values
  - `outputs.tf` - exported outputs such as cluster name, repo URLs, and DB endpoint
- `modules/` - reusable Terraform modules
  - `vpc/` - VPC, subnets, and network resources
  - `eks/` - EKS cluster and node group resources
  - `ecr/` - ECR repository management
  - `rds/` - managed database deployment
  - `irsa-roles/` - IAM roles and policies for EKS service accounts
  - `helm-addons/` - Helm provider configuration and addon deployment

## Prerequisites

- Terraform installed
- AWS CLI installed and configured
- AWS profile named `gym` configured with access to the target AWS account
- IAM permissions to create VPC, EKS, RDS, ECR, IAM, and related AWS resources

## Setup

1. Clone the repository:

   git clone <repository-url>
   cd gym-platform-terraform

2. Change into the environment directory:

   cd environments/dev

3. Initialize Terraform:

   terraform init

4. Review the planned changes:

   terraform plan

5. Apply the infrastructure:

   terraform apply

## Common Commands

- `terraform init` - initialize the working directory
- `terraform fmt` - format Terraform configuration files
- `terraform validate` - validate configuration syntax
- `terraform plan` - preview proposed changes
- `terraform apply` - apply the planned infrastructure changes
- `terraform destroy` - remove infrastructure created by Terraform

## Notes

- The development environment uses the AWS profile `gym`.
- Helm resources are deployed by the Helm provider against the EKS cluster created by the `eks` module.
- Environment-specific infrastructure lives under `environments/dev/`, while reusable modules live in `modules/`.
- The `main.tf` file in the dev environment ties together VPC, EKS, ECR, RDS, IRSA roles, and Helm addons.

## Goals

This repository should enable an operator to:

- Deploy and manage the gym platform development AWS infrastructure
- Reuse shared Terraform modules across environments
- Keep environment-specific configuration isolated under `environments/dev/`

To extend this project, add new environment folders or reuse the existing modules with additional variables and backend configuration.
