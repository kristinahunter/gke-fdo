variable "project_id" {
  description = "GCP Project ID"
  default     = "hc-30f648a533824fa58e5790b670b"
}

variable "dns_domain" {
  description = "DNS domain for TFE"
  default     = "hc-30f648a533824fa58e5790b670b.gcp.sbx.hashicorpdemo.com."
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
  default     = ""
  sensitive   = true
}