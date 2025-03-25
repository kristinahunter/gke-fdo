#!/bin/bash
set -e

# Get Terraform outputs
PROJECT_ID=$(terraform output -raw project_id)
GKE_CLUSTER=$(terraform output -raw gke_cluster_name)
GKE_REGION=$(terraform output -raw gke_cluster_region)
POSTGRES_PRIVATE_IP=$(terraform output -raw postgres_private_ip)
REDIS_HOST=$(terraform output -raw redis_host)
REDIS_PORT=$(terraform output -raw redis_port)
TFE_HOSTNAME=$(terraform output -raw tfe_hostname)
TFE_ENCRYPTION_PASSWORD=$(terraform output -raw tfe_encryption_password)
TFE_LICENSE=$(terraform output -raw tfe_license)
POSTGRES_USERNAME=$(terraform output -raw postgres_username)
POSTGRES_PASSWORD=$(terraform output -raw postgres_password)
TFE_BUCKET_CREDENTIALS=$(terraform output -raw tfe_bucket_credentials_json)
CERTIFICATE_EMAIL=$(terraform output -raw certificate_email)
TFE_VERSION=$(terraform output -raw tfe_version)

# Get the domain parts from TFE_HOSTNAME
DNS_HOSTNAME=$(echo $TFE_HOSTNAME | cut -d. -f1)
DNS_ZONENAME=$(echo $TFE_HOSTNAME | cut -d. -f2-)

echo "Generating TLS certificates using ACME provider..."
mkdir -p cert-manager
cat > cert-manager/main.tf <<EOF
terraform {
  required_providers {
    acme = {
      source  = "vancluever/acme"
      version = "2.11.1"
    }
  }
}

variable "gcp_project" {
  default = "${PROJECT_ID}"
}

variable "dns_hostname" {
  type        = string
  description = "DNS name you use to access the website"
  default     = "${DNS_HOSTNAME}"
}

variable "dns_zonename" {
  type        = string
  description = "DNS zone the record should be created in"
  default     = "${DNS_ZONENAME}"
}

variable "certificate_email" {
  description = "email address to register the certificate"
  default     = "${CERTIFICATE_EMAIL}"
}

provider "acme" {
  # Use staging for testing (no rate limits, faster issuance)
  # server_url = "https://acme-staging-v02.api.letsencrypt.org/directory"
  
  # Use production for real deployments (has rate limits, trusted by browsers)
  # IMPORTANT: Production has strict rate limits. Use staging for testing first!
  server_url = "https://acme-v02.api.letsencrypt.org/directory"
}

# SSL certificates
resource "tls_private_key" "cert_private_key" {
  algorithm = "RSA"
}

resource "acme_registration" "registration" {
  account_key_pem = tls_private_key.cert_private_key.private_key_pem
  email_address   = var.certificate_email
}

resource "acme_certificate" "certificate" {
  account_key_pem = acme_registration.registration.account_key_pem
  common_name     = "\${var.dns_hostname}.\${var.dns_zonename}"
  
  dns_challenge {
    provider = "gcloud"
    
    config = {
      GCE_PROJECT = var.gcp_project
    }
  }
}

output "fullchain" {
  value = base64encode("\${acme_certificate.certificate.certificate_pem}\${acme_certificate.certificate.issuer_pem}")
}

output "key_data" {
  value = base64encode(nonsensitive(acme_certificate.certificate.private_key_pem))
}
EOF

# Generate certificates using Terraform
cd cert-manager
terraform init
terraform apply -auto-approve
CERT_CHAIN=$(terraform output -raw fullchain)
CERT_KEY=$(terraform output -raw key_data)
cd ..

# Get GKE credentials
echo "Connecting to GKE cluster..."
gcloud container clusters get-credentials $GKE_CLUSTER --region $GKE_REGION --project $PROJECT_ID

# Create TFE namespace
echo "Creating terraform-enterprise namespace..."
kubectl create namespace terraform-enterprise --dry-run=client -o yaml | kubectl apply -f -

# Create Docker registry secret for HashiCorp registry
kubectl create secret docker-registry terraform-enterprise \
  --docker-server=images.releases.hashicorp.com \
  --docker-username=terraform \
  --docker-password="CHANGEME" \
  -n terraform-enterprise

# Create overrides.yml for TFE Helm installation
echo "Creating Helm values file..."
cat > overrides.yml <<EOF
env:
  secrets:
    TFE_DATABASE_PASSWORD: "$POSTGRES_PASSWORD"
    TFE_ENCRYPTION_PASSWORD: "$TFE_ENCRYPTION_PASSWORD"
    TFE_LICENSE: "$TFE_LICENSE"
  variables:
    TFE_DATABASE_HOST: "$POSTGRES_PRIVATE_IP"
    TFE_DATABASE_NAME: "tfe"
    TFE_DATABASE_PARAMETERS: "sslmode=require"
    TFE_DATABASE_USER: "$POSTGRES_USERNAME"
    TFE_HOSTNAME: "$TFE_HOSTNAME"
    TFE_IACT_SUBNETS: "0.0.0.0/0"
    TFE_OBJECT_STORAGE_TYPE: "google"
    TFE_OBJECT_STORAGE_GOOGLE_BUCKET: "tfebucket-${PROJECT_ID}"
    TFE_OBJECT_STORAGE_GOOGLE_PROJECT: "$PROJECT_ID"
    TFE_OBJECT_STORAGE_GOOGLE_CREDENTIALS: '$TFE_BUCKET_CREDENTIALS'
    TFE_OPERATIONAL_MODE: "active-active"
    TFE_REDIS_HOST: "${REDIS_HOST}:${REDIS_PORT}"
    TFE_RUN_PIPELINE_KUBERNETES_WORKER_TIMEOUT: "300"
image:
  name: hashicorp/terraform-enterprise
  repository: images.releases.hashicorp.com
  tag: "$TFE_VERSION"
  pullSecrets:
    - name: terraform-enterprise
tls:
  caCertData: "$CERT_CHAIN"
  certData: "$CERT_CHAIN"
  keyData: "$CERT_KEY"
EOF

# Add HashiCorp Helm repository
echo "Adding HashiCorp Helm repository..."
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# Install TFE via Helm
echo "Installing Terraform Enterprise..."
helm install terraform-enterprise hashicorp/terraform-enterprise \
  -n terraform-enterprise \
  --values overrides.yml

exit 0
