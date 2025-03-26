# GKE FDO Deployment Guide

This guide provides step-by-step instructions for deploying a Google Kubernetes Engine (GKE) environment and necessary components for deploying TFE. The deployment process includes setting up the necessary infrastructure and deploying Terraform Enterprise (TFE) on GKE.

## Prerequisites

Before beginning the deployment, ensure you have the following prerequisites in place:

### GCP Account Setup
1. Request a temporary GCP account through Doormat
   - Note: Account setup can take approximately 10 minutes
   - If using user_email, update the doormat-accountid field to doormat-useremail
   - If using account_id (default) no changes needed

### Required Tools
The following tools must be installed and configured on your local machine:

#### Google Cloud SDK
```bash
brew install --cask google-cloud-sdk
```

#### gke-gcloud-auth-plugin
```bash
# Install the GKE auth plugin
gcloud components install gke-gcloud-auth-plugin

# Add to your PATH
echo 'source "$(brew --prefix)/share/google-cloud-sdk/path.zsh.inc"' >> ~/.zshrc
echo 'source "$(brew --prefix)/share/google-cloud-sdk/completion.zsh.inc"' >> ~/.zshrc
```

#### Helm
```bash
brew install helm
```

#### Terraform
```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```

## Configuration

This section covers the necessary configuration steps before deployment:

### 1. Update Variables
Edit `variables.tf` with the following information:
- Project ID: Your GCP project identifier
- Zone: The GCP zone where resources will be deployed
- License: Your Terraform Enterprise license
- Version: Your desired TFE version
- Certificate Configuration:
  - Certificate Email: Email address for Let's Encrypt notifications
  - Certificate Environment:
  - Note: Staging certificates are not trusted by browsers but have no rate limits
- Other variables can remain at default values

### 2. CLI Setup
Run the following commands in sequence to set up your environment:

```bash
# 1. Authenticate with GCP
gcloud auth application-default login

# 2. Install and configure GKE auth plugin
gcloud components install gke-gcloud-auth-plugin

# 3. Add HashiCorp Helm repository
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# 4. Initialize Terraform
terraform init

# 5. Review the deployment plan
terraform plan

# 6. If the plan looks good, apply the configuration
terraform apply
```

## Deployment Steps

This will create the following resources:
- GKE cluster with FDO capabilities
- Node pools configured for TFE workloads
- Required IAM roles and service accounts
- Network configurations and firewall rules
- Storage buckets for TFE data
- Load balancer for TFE access

After infrastructure is created, deploy TFE:
```bash
./deploy-tfe.sh
```

The `deploy-tfe.sh` script performs the following:
1. Retrieves necessary configuration from Terraform outputs
2. Generates TLS certificates using Let's Encrypt ACME provider:
   - Uses configured environment (staging/production) from variables
   - Creates certificates for the specified domain
   - Note: Changing environments requires updating acme_server_url and redeploying
3. Sets up GKE cluster credentials
4. Creates the terraform-enterprise namespace
5. Configures HashiCorp registry access
6. Creates Helm values file with:
   - Database configuration
   - Redis configuration
   - Object storage settings
   - TLS certificates
   - License and encryption settings
7. Installs TFE using Helm with the configured values
8. Outputs on success

### Monitoring TFE Deployment
Monitor the deployment progress using the following commands:

```bash
# Check pod status in the terraform-enterprise namespace
kubectl get pods -n terraform-enterprise

# Get detailed information about all resources
kubectl get all -n terraform-enterprise

# Follow the TFE container logs
kubectl logs -f deployment/terraform-enterprise -n terraform-enterprise
```

The deployment is complete when:
- All pods show status as "Running"
- No pods are in "Error" or "CrashLoopBackOff" state
- Health checks are successful

### Validating TFE Deployment
Once TFE is running, execute the validation script:
```bash
./validate-tfe.sh
```

This script will:
1. Get the Load Balancer IP
2. Attempt to automatically find the DNS zone
3. Generate the initial admin token
4. Provide the complete setup URL

Example output:
```bash
Getting LoadBalancer IP...
LoadBalancer IP: 123.45.67.89

Update your DNS A record with:
  gcloud dns record-sets update tfe.yourdomain.com. --rrdatas=123.45.67.89 --ttl=300 --type=A --zone=your-zone-name

Initial admin token generated: <token>
To complete setup, visit:
https://tfe.yourdomain.com/admin/account/new?token=<token>

Validation complete!
```

Note: If the script cannot automatically determine the DNS zone, it will provide a template command where you'll need to replace `YOUR_ZONE_NAME` with your actual DNS zone name.

## Troubleshooting

If you encounter a "zone not found" error:
- Verify that both the account-ID and zone details are correctly updated in your configuration
- Double-check the zone name matches your GCP project settings

Note: Deletion is currently messy

  ```
  gcloud compute networks list
  gcloud compute subnets list
  gcloud storage buckets list
  ```

### Command CheatSheet
```bash
export PODNAME=
kubectl get pods -n terraform-enterprise
kubectl delete pod $PODNAME -n terraform-enterprise
kubectl logs $PODNAME -n terraform-enterprise
kubectl describe pod $PODNAME -n terraform-enterprise
helm list -n terraform-enterprise
helm uninstall terraform-enterprise -n terraform-enterprise
helm install terraform-enterprise <chart-name> -n terraform-enterprise
helm upgrade terraform-enterprise <chart-name> -n terraform-enterprise --recreate-pods
kubectl delete pod $PODNAME -n terraform-enterprise
helm upgrade terraform-enterprise hashicorp/terraform-enterprise -n terraform-enterprise -f $path
```






