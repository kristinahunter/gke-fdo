provider "google" {
  project = var.project_id
  region  = var.region
}
provider "google-beta" {
  project = var.project_id
  region  = var.region
}
# Enable required Google APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "serviceusage.googleapis.com",
    "compute.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "dns.googleapis.com",
    "iamcredentials.googleapis.com",
    "iam.googleapis.com",
    "cloudapis.googleapis.com",
    "servicemanagement.googleapis.com",
    "storage-api.googleapis.com",
    "storage.googleapis.com",
    "servicenetworking.googleapis.com",
    "sqladmin.googleapis.com",
    "redis.googleapis.com",
    "container.googleapis.com"
  ])
  
  project = var.project_id
  service = each.key

  # Disable service disruption during disable
  disable_on_destroy = false
}
# VPC Network
resource "google_compute_network" "vpc" {
  name                    = "${var.project_id}-vpc"
  auto_create_subnetworks = false
  
  depends_on = [google_project_service.required_apis]
}
# Subnet for GKE
resource "google_compute_subnetwork" "subnet" {
  name          = "${var.project_id}-subnet"
  region        = var.region
  network       = google_compute_network.vpc.name
  ip_cidr_range = "10.10.0.0/24"

  private_ip_google_access = true

  lifecycle {
    ignore_changes = [
      secondary_ip_range,
    ]
  }
}
# Cloud Router for NAT Gateway
resource "google_compute_router" "router" {
  name    = "gke-nat-router"
  region  = var.region
  network = google_compute_network.vpc.name
}
# NAT Gateway
resource "google_compute_router_nat" "nat" {
  name                               = "gke-nat-gateway"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Service account for TFE GCS bucket access
resource "google_service_account" "tfe_bucket_user" {
  account_id   = "tfe-bucket-user"
  display_name = "tfe-bucket-user"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Grant storage admin permissions to the service account
resource "google_project_iam_member" "tfe_bucket_user_storage_admin" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.tfe_bucket_user.email}"
}
# Grant composer environment and storage object admin permissions
resource "google_project_iam_member" "tfe_bucket_user_composer_admin" {
  project = var.project_id
  role    = "roles/composer.environmentAndStorageObjectAdmin"
  member  = "serviceAccount:${google_service_account.tfe_bucket_user.email}"
}
# Create GCS bucket for object storage
resource "google_storage_bucket" "tfe_bucket" {
  name                        = "tfebucket-${var.project_id}"
  location                    = "US" # Multi-region bucket
  project                     = var.project_id
  force_destroy               = true
  uniform_bucket_level_access = true
}


# Create service account key
resource "google_service_account_key" "tfe_bucket_user_key" {
  service_account_id = google_service_account.tfe_bucket_user.name
}

# Output the service account credentials
output "tfe_bucket_credentials_json" {
  description = "Service account credentials for TFE bucket access"
  value       = base64decode(google_service_account_key.tfe_bucket_user_key.private_key)
  sensitive   = true
}
# Private Service Access for managed services
resource "google_compute_global_address" "private_ip_address" {
  name          = "private-service-access"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.self_link
  address       = "10.77.0.0"
  
  depends_on = [google_project_service.required_apis]
}
resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.vpc.self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
  
  # Add explicit dependency on services
  depends_on = [google_project_service.required_apis]
  
  # Add lifecycle to ensure proper destroy order
  lifecycle {
    create_before_destroy = true
  }
}


# PostgreSQL (Cloud SQL)
resource "google_sql_database_instance" "postgres" {
  name             = "tfe-postgresql"
  database_version = "POSTGRES_16"
  region           = var.region
  depends_on       = [google_service_networking_connection.private_vpc_connection]
  
  # Disable deletion protection
  deletion_protection = false

  settings {
    tier    = "db-custom-2-8192"
    edition = "ENTERPRISE"

    ip_configuration {
      ipv4_enabled    = true
      private_network = google_compute_network.vpc.id
    }
  }

  # Add lifecycle policy to ensure this resource is destroyed before the service networking connection
  lifecycle {
    create_before_destroy = true
  }
}

resource "google_sql_database" "database" {
  name     = "tfe"
  instance = google_sql_database_instance.postgres.name
}
resource "google_sql_user" "user" {
  name     = var.postgres_username
  instance = google_sql_database_instance.postgres.name
  password = var.postgres_password
}
# Redis (Memorystore)
resource "google_redis_instance" "redis" {
  name           = "redis-tfe"
  tier           = "BASIC"
  memory_size_gb = 1
  region         = var.region

  authorized_network = google_compute_network.vpc.self_link
  connect_mode       = "PRIVATE_SERVICE_ACCESS"

  depends_on = [google_service_networking_connection.private_vpc_connection]
  
  # Add lifecycle policy to ensure this resource is destroyed before the service networking connection
  lifecycle {
    create_before_destroy = true
  }
}
# Firewall Rules
resource "google_compute_firewall" "tfe_ingress" {
  name    = "tfe-ingress-rules"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["443", "5432", "8201", "6379"]
  }

  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
}
# Create specific egress rules for the database and Redis subnets
resource "google_compute_firewall" "tfe_sql_egress" {
  name    = "allow-sql-egress"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }

  direction          = "EGRESS"
  destination_ranges = ["10.77.80.0/24"] # PostgreSQL subnet
}
resource "google_compute_firewall" "tfe_redis_egress" {
  name    = "allow-redis-egress"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["6379"]
  }

  direction          = "EGRESS"
  destination_ranges = ["10.77.81.0/29"] # Redis subnet
}
# Reserved static IP for LoadBalancer
resource "google_compute_address" "static_ip" {
  name   = "tfe-static-ip"
  region = var.region
}
# GKE Cluster
resource "google_container_cluster" "primary" {
  name     = "${var.project_id}-gke"
  location = var.region

  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.subnet.name

  # We use a separately managed node pool
  remove_default_node_pool = true
  initial_node_count       = 1
  
  # Disable deletion protection
  deletion_protection = false
}
resource "google_container_node_pool" "primary_nodes" {
  name       = google_container_cluster.primary.name
  location   = var.region
  cluster    = google_container_cluster.primary.name
  node_count = 6

  node_config {
    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/devstorage.read_only"
    ]

    machine_type = "e2-standard-2"
    tags         = ["gke-node", "${var.project_id}-gke"]

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }
}
# Reference existing DNS zone instead of creating a new one
data "google_dns_managed_zone" "existing_zone" {
  name = "doormat-accountid" # The name shown in your Cloud Console, doormat-accountid or doormat-useremail
}

# DNS Record for TFE
resource "google_dns_record_set" "tfe_dns" {
  name         = "${var.dns_hostname}.${data.google_dns_managed_zone.existing_zone.dns_name}"
  type         = "A"
  ttl          = 300
  managed_zone = data.google_dns_managed_zone.existing_zone.name
  # Using the static IP reserved for the LoadBalancer
  rrdatas = [google_compute_address.static_ip.address]
}
# Output values to be used by deployment script
output "gke_cluster_name" {
  value = google_container_cluster.primary.name
}
output "gke_cluster_region" {
  value = var.region
}
output "postgres_private_ip" {
  value = google_sql_database_instance.postgres.private_ip_address
}
output "postgres_public_ip" {
  value = google_sql_database_instance.postgres.public_ip_address
}
output "redis_host" {
  value = google_redis_instance.redis.host
}
output "redis_port" {
  value = google_redis_instance.redis.port
}
output "tfe_hostname" {
  value = "${var.dns_hostname}.${trimsuffix(data.google_dns_managed_zone.existing_zone.dns_name, ".")}"
}
output "project_id" {
  value = var.project_id
}
output "static_ip" {
  value = google_compute_address.static_ip.address
}
output "tfe_encryption_password" {
  value     = var.tfe_encryption_password
  sensitive = true
}
output "tfe_license" {
  value     = var.tfe_license
  sensitive = true
}

output "postgres_username" {
  value = var.postgres_username
}
output "postgres_password" {
  value     = var.postgres_password
  sensitive = true
}

output "tfe_bucket_credentials" {
  value     = google_service_account_key.tfe_bucket_user_key.private_key
  sensitive = true
}
