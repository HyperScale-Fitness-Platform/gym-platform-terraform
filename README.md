# Gym Platform Terraform

This repository contains Terraform configuration for provisioning AWS infrastructure for the gym platform. The infrastructure is deployed in two layers using Jenkins pipelines: Layer 1 (EKS & infrastructure), followed by Layer 2 (Helm services and applications).

## Overview

The current configuration deploys an AWS development stack with:

- Amazon VPC and subnet topology
- Amazon EKS cluster for Kubernetes workloads
- Amazon ECR repositories for application container images
- Amazon RDS database for the auth service
- IAM Roles for Service Accounts (IRSA)
- Helm-managed Kubernetes addons deployed via Terraform
- Jenkins and Argo CD for CI/CD and GitOps

## Repo Structure

- `infrastructure/` - Core AWS infrastructure (Layer 1)
  - `main.tf` - AWS provider plus module instantiations for VPC, EKS, ECR, RDS, IRSA roles, and Helm addons
  - `variables.tf` - input variable definitions
  - `terraform.tfvars` - infrastructure-specific variable values
  - `outputs.tf` - exported outputs such as cluster name, repo URLs, and DB endpoint
  - `providers.tf` - provider configuration
  - `addons.tf` - Kubernetes addon configuration

- `services/` - Helm services and applications (Layer 2)
  - `main.tf` - Helm provider configuration and service deployments
  - `providers.tf` - provider configuration
  - `variables.tf` - input variable definitions
  - `terraform.tfstate` - Layer 2 state

- `modules/` - reusable Terraform modules
  - `vpc/` - VPC, subnets, and network resources
  - `eks/` - EKS cluster and node group resources
  - `ecr/` - ECR repository management
  - `irsa-roles/` - IAM roles and policies for EKS service accounts
  - `helm-addons/` - Helm provider configuration and addon deployment

- `k8s/` - Kubernetes manifests
  - `cluster-secret-store.yaml` - ExternalSecrets integration with AWS Secrets Manager
  - `jenkins-secret.yaml` - Jenkins credential configuration

- `scripts/` - Utility scripts
  - `create-s3-for-statefile.sh` - Create S3 backend and DynamoDB for Terraform state
  - `delete-ecr-images.sh` - Clean ECR repositories before destruction
  - `delete-s3.sh` - Remove S3 backend and DynamoDB
  - `pre-destroy.sh` - Pre-destruction cleanup steps

## Prerequisites

- Terraform installed (v1.0+)
- AWS CLI installed and configured
- AWS credentials with permissions to create VPC, EKS, RDS, ECR, IAM, and related resources
- Docker installed (for running Jenkins locally)
- kubectl installed (for Kubernetes operations)
- Helm installed (for Kubernetes package management)
- Jenkins installed (local or remote)

## Quick Start: Deploy with Jenkins (Recommended)

### Option 1: Run Jenkins on Localhost

#### Prerequisites for Local Jenkins

- Docker and Docker Compose installed
- Port 8080 available (Jenkins web interface)
- AWS credentials available to the Jenkins container

#### Step 1: Start Jenkins Locally

```bash
# Create a directory for Jenkins home
mkdir -p ~/jenkins_home
chmod 777 ~/jenkins_home

# Run Jenkins in Docker
docker run -d \
  --name gym-jenkins \
  -p 8080:8080 \
  -p 50000:50000 \
  -v ~/jenkins_home:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e DOCKER_HOST=unix:///var/run/docker.sock \
  jenkins/jenkins:latest
```

#### Step 2: Access Jenkins and Initial Setup

1. Open Jenkins in your browser: `http://localhost:8080`
2. Retrieve the initial admin password:
   ```bash
   docker exec gym-jenkins cat /var/jenkins_home/secrets/initialAdminPassword
   ```
3. Follow the setup wizard to install recommended plugins
4. Create your first admin user

#### Step 3: Configure Jenkins with AWS Credentials

1. In Jenkins, go to **Manage Jenkins** → **Credentials** → **System** → **Global credentials**
2. Click **Add Credentials** and create two secret text credentials:
   - `aws-access-key-id` - Your AWS access key
   - `aws-secret-access-key` - Your AWS secret key
   - `jenkins-admin-pass` - Password for Jenkins admin user

#### Step 4: Create a Pipeline Job

1. In Jenkins, click **New Item**
2. Enter job name (e.g., "gym-infra-deploy")
3. Select **Pipeline** and click **OK**
4. Under **Pipeline**, select **Pipeline script from SCM**
5. Choose **Git** and enter your repository URL
6. Set the **Script Path** to `Jenkinsfile.apply`
7. Save and build

#### Step 5: Trigger the Deployment

1. Click **Build** on the job
2. Jenkins will:
   - Deploy Layer 1 (EKS & Infrastructure) from `infrastructure/`
   - Pre-create Kubernetes namespaces and ExternalSecrets
   - Deploy Layer 2 (Helm services) from `services/`
   - Output Argo CD access credentials

#### Step 6: Monitor Deployment Progress

```bash
# Watch pod creation in real-time
kubectl get pods -A -w

# Check EKS cluster status
aws eks describe-cluster --name gym-cluster --region us-east-1

# Access Argo CD
kubectl port-forward -n argocd svc/argocd-server 8081:443
# Then open https://localhost:8081
# Use credentials from Jenkins build output
```

### Option 2: Run Jenkins Remotely or in Kubernetes

If you prefer to use Jenkins installed on a remote server or within Kubernetes:

1. Ensure Jenkins has AWS credentials configured
2. Clone this repository into Jenkins' workspace
3. Create a pipeline job pointing to `Jenkinsfile.apply`
4. Trigger the build through Jenkins UI or API

## Manual Setup (Without Jenkins)

If you prefer to deploy manually without Jenkins:

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd gym-platform-terraform
   ```

2. Create S3 backend for Terraform state:
   ```bash
   chmod +x ./scripts/create-s3-for-statefile.sh
   ./scripts/create-s3-for-statefile.sh
   ```

3. Deploy Layer 1 (Infrastructure):
   ```bash
   cd infrastructure
   terraform init -reconfigure
   terraform plan
   terraform apply
   ```

4. Configure kubectl:
   ```bash
   aws eks update-kubeconfig --region us-east-1 --name gym-cluster
   ```

5. Create Kubernetes namespaces and ExternalSecrets:
   ```bash
   kubectl create namespace jenkins
   kubectl create namespace argocd
   kubectl apply -f ./k8s/
   ```

6. Deploy Layer 2 (Services):
   ```bash
   cd ../services
   terraform init -reconfigure
   terraform plan
   terraform apply
   ```

7. Retrieve Argo CD credentials:
   ```bash
   kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
   ```


## Destroying the Infrastructure

### Using Jenkins (Recommended)

1. In Jenkins, create a new pipeline job with **Script Path** set to `Jenkinsfile.destroy`
2. Click **Build** to trigger the destruction
3. Jenkins will:
   - Delete ECR images
   - Destroy Layer 2 (Helm services)
   - Clean Kubernetes namespaces and finalizers
   - Destroy Layer 1 (EKS & infrastructure)
   - Remove S3 backend and DynamoDB

### Manual Destruction

```bash
# Delete ECR images
chmod +x ./scripts/delete-ecr-images.sh
./scripts/delete-ecr-images.sh

# Destroy services (Layer 2)
cd services
terraform destroy -auto-approve
cd ..

# Clean Kubernetes resources
kubectl delete namespace argocd jenkins external-secrets --ignore-not-found=true

# Destroy infrastructure (Layer 1)
cd infrastructure
terraform destroy -auto-approve
cd ..

# Remove S3 backend
chmod +x ./scripts/delete-s3.sh
./scripts/delete-s3.sh
```

## Deployment Architecture

### Layer 1: Infrastructure (EKS & Core AWS Resources)
- VPC and networking
- EKS cluster and node groups
- ECR repositories
- RDS database
- IAM roles and IRSA configuration
- State backend (S3 + DynamoDB)

### Layer 2: Helm Services & Applications
- Jenkins installation
- Argo CD installation
- External Secrets operator
- Application deployments via Helm

The two-layer approach ensures infrastructure stability and allows independent service scaling.

## Common Commands

- `terraform init` - initialize the working directory
- `terraform fmt` - format Terraform configuration files
- `terraform validate` - validate configuration syntax
- `terraform plan` - preview proposed changes
- `terraform apply` - apply the planned infrastructure changes
- `terraform destroy` - remove infrastructure created by Terraform
- `kubectl get pods -A` - list all pods across namespaces
- `kubectl logs <pod-name> -n <namespace>` - view pod logs
- `kubectl port-forward svc/<service-name> <local-port>:<remote-port> -n <namespace>` - forward service port

## Accessing Deployed Services

### Argo CD
```bash
kubectl port-forward -n argocd svc/argocd-server 8081:443 &
# Open https://localhost:8081
# Username: admin
# Password: (from Jenkins build output or)
kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### Jenkins
If Jenkins is deployed in the cluster:
```bash
kubectl port-forward -n jenkins svc/jenkins 8080:8080 &
# Open http://localhost:8080
```

## Troubleshooting

### Terraform State Issues
- If state is corrupted, the S3 backend and DynamoDB table are preserved
- Manually delete `.terraform` directory and run `terraform init -reconfigure`
- Use `terraform state list` to view current state
- Use `terraform state show <resource>` to inspect a resource

### Kubernetes Namespace Stuck in Terminating
```bash
# Check what's preventing deletion
kubectl api-resources --verbs=list --namespaced=true -o wide

# Force remove finalizers if necessary (use with caution)
kubectl get namespace <namespace-name> -o json | \
  jq '.spec.finalizers = []' | \
  kubectl replace --raw /api/v1/namespaces/<namespace-name>/finalize -f -
```

### EKS Cluster Issues
```bash
# Check cluster status
aws eks describe-cluster --name gym-cluster --region us-east-1

# View cluster events
kubectl get events -A --sort-by='.lastTimestamp'

# Check node status
kubectl get nodes -o wide
```

### Argo CD Sync Issues
```bash
# Check application status
kubectl describe app <app-name> -n argocd

# View application logs
kubectl logs -n argocd -l app=argocd-application-controller -f

# Force sync application
kubectl patch app <app-name> -n argocd -p '{"metadata":{"annotations":{"argocd.argoproj.io/sync":"true"}}}' --type merge
```

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│                     AWS Account                         │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │  VPC                                               │ │
│  │  ┌──────────────────────────────────────────────┐  │ │
│  │  │ EKS Cluster                                  │  │ │
│  │  │ ┌────────────────────────────────────────┐   │  │ │
│  │  │ │ Kube System Namespace                  │   │  │ │
│  │  │ │ - CoreDNS, kube-proxy, AWS VPC CNI     │   │  │ │
│  │  │ └────────────────────────────────────────┘   │  │ │
│  │  │ ┌────────────────────────────────────────┐   │  │ │
│  │  │ │ Jenkins Namespace                      │   │  │ │
│  │  │ │ - Jenkins Server                       │   │  │ │
│  │  │ └────────────────────────────────────────┘   │  │ │
│  │  │ ┌────────────────────────────────────────┐   │  │ │
│  │  │ │ Argo CD Namespace                      │   │  │ │
│  │  │ │ - Argo CD Server, Application-Ctrl    │   │  │ │
│  │  │ │ - Repo Server                          │   │  │ │
│  │  │ └────────────────────────────────────────┘   │  │ │
│  │  │ ┌────────────────────────────────────────┐   │  │ │
│  │  │ │ External Secrets Namespace             │   │  │ │
│  │  │ │ - External Secrets Operator            │   │  │ │
│  │  │ │ - SecretStore (AWS Secrets Manager)    │   │  │ │
│  │  │ └────────────────────────────────────────┘   │  │ │
│  │  │ ┌────────────────────────────────────────┐   │  │ │
│  │  │ │ Node Groups                            │   │  │ │
│  │  │ │ - EC2 Instances                        │   │  │ │
│  │  │ └────────────────────────────────────────┘   │  │ │
│  │  └──────────────────────────────────────────────┘  │ │
│  │                                                    │ │
│  └────────────────────────────────────────────────────┘ │
│                                                          │
│  ┌─────────────────┐  ┌──────────────┐  ┌────────────┐  │
│  │  ECR Repos      │  │  RDS DB      │  │ S3 Bucket  │  │
│  │  - Application  │  │  (Postgres)  │  │ (Tfstate)  │  │
│  │  - Services     │  │              │  │            │  │
│  └─────────────────┘  └──────────────┘  └────────────┘  │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

## Notes

- Infrastructure is deployed via Jenkins pipelines for consistency and auditability
- The two-layer deployment ensures infrastructure stability and scalability
- All secrets are managed via AWS Secrets Manager and synced to Kubernetes via External Secrets
- Helm resources are deployed by the Helm provider against the EKS cluster
- Terraform state is stored remotely in S3 with DynamoDB locking for safety
- Each deployment layer has its own Terraform state file for independence

## Goals

This repository should enable operators to:

- Provision and manage the gym platform development AWS infrastructure automatically
- Deploy infrastructure and services consistently via Jenkins pipelines
- Reuse shared Terraform modules across environments
- Manage secrets securely through AWS Secrets Manager integration
- Track all infrastructure changes through version control and Jenkins audit logs
- Scale services independently via Helm and Argo CD

To extend this project, add new environment folders, reuse existing modules with additional variables, or create new service deployments in the `services/` directory.
