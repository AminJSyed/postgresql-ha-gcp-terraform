output "cloud_sql_instance_name" {
  description = "Name of the Cloud SQL PostgreSQL instance."
  value       = google_sql_database_instance.postgresql.name
}

output "cloud_sql_connection_name" {
  description = "Connection name used by Cloud SQL connectors and the Auth Proxy."
  value       = google_sql_database_instance.postgresql.connection_name
}

output "cloud_sql_private_ip" {
  description = "Private IP address assigned to the Cloud SQL instance."
  value       = google_sql_database_instance.postgresql.private_ip_address
}

output "database_name" {
  description = "Name of the application database."
  value       = google_sql_database.application.name
}

output "vpc_network_name" {
  description = "Name of the VPC network used by the PostgreSQL platform."
  value       = google_compute_network.postgresql.name
}

output "application_subnet_name" {
  description = "Name of the subnet used by application resources."
  value       = google_compute_subnetwork.application.name
}

output "private_service_range_name" {
  description = "Reserved IP range used for Google-managed services."
  value       = google_compute_global_address.private_service_range.name
}
