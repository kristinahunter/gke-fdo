variable "project_id" {
  description = "GCP Project ID"
  default     = "CHANGEME"
}

variable "environment" {
  description = "Unique identifier for this deployment. Doesn't do anything. . .yet?"
  type        = string
  default     = "test"
}

variable "certificate_environment" {
  description = "Certificate environment to use: 'staging' for testing (no rate limits) or 'production' for real deployments"
  type        = string
  default     = "production"
  validation {
    condition     = contains(["staging", "production"], var.certificate_environment)
    error_message = "certificate_environment must be either 'staging' or 'production'"
  }
}

variable "dns_domain" {
  description = "DNS domain for TFE"
  default     = "CHANGEME"
}

variable "region" {
  description = "GCP Region"
  default     = "us-west2"
}

variable "postgres_username" {
  description = "PostgreSQL Username"
  default     = "tfeadmin"
}

variable "postgres_password" {
  description = "PostgreSQL Password"
  default     = "P@ssw0rd!@#"
  sensitive   = true
}

variable "tfe_encryption_password" {
  description = "Password for TFE data encryption"
  default     = "thisisabadpassword0#"
  sensitive   = true
}

variable "dns_hostname" {
  description = "DNS hostname for TFE"
  default     = "tfe"
}

variable "tfe_license" {
  description = "Base64 encoded TFE license"
  default     = "CHANGEME"
  sensitive   = true
}

variable "certificate_email" {
  description = "Email address to register the Let's Encrypt certificate"
  type        = string
  default     = "CHANGEME"
}

locals {
  # Resource naming
  cluster_name = "tfe-cluster-${var.environment}"
  vpc_name     = "tfe-vpc-${var.environment}"
  subnet_name  = "tfe-subnet-${var.environment}"
  bucket_name  = "tfebucket-${var.environment}"
  tfe_hostname = "${var.dns_hostname}-${var.environment}.${trim(var.dns_domain, ".")}"

  # Certificate server URL based on environment
  acme_server_url = var.certificate_environment == "staging" ? "https://acme-staging-v02.api.letsencrypt.org/directory" : "https://acme-v02.api.letsencrypt.org/directory"
}