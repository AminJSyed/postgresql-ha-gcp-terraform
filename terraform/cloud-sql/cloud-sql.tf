resource "google_sql_database_instance" "postgresql" {
  name             = var.instance_name
  project          = var.project_id
  region           = var.region
  database_version = var.database_version

  # Protects the instance from deletion through Terraform.
  deletion_protection = true

  settings {
    tier              = var.database_tier
    edition           = "ENTERPRISE"
    availability_type = "REGIONAL"

    # Protects against deletion through the API, console, gcloud, and Terraform.
    deletion_protection_enabled = true

    disk_type             = "PD_SSD"
    disk_size             = 20
    disk_autoresize       = true
    disk_autoresize_limit = 100

    backup_configuration {
      enabled                        = true
      start_time                     = "02:00"
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7

      backup_retention_settings {
        retained_backups = 14
        retention_unit   = "COUNT"
      }
    }

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = google_compute_network.postgresql.self_link
      allocated_ip_range                            = google_compute_global_address.private_service_range.name
      enable_private_path_for_google_cloud_services = true
      ssl_mode                                      = "ENCRYPTED_ONLY"
    }

    maintenance_window {
      day          = 7
      hour         = 3
      update_track = "stable"
    }

    insights_config {
      query_insights_enabled  = true
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = true
    }

    user_labels = {
      application  = "postgresql"
      environment  = "production"
      managed_by   = "terraform"
      availability = "regional"
    }
  }

  depends_on = [
    google_project_service.required["sqladmin.googleapis.com"],
    google_service_networking_connection.private_services
  ]
}

resource "google_sql_database" "application" {
  name     = var.database_name
  project  = var.project_id
  instance = google_sql_database_instance.postgresql.name
}
