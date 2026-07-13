resource "google_compute_network" "postgresql" {
  name                    = var.network_name
  project                 = var.project_id
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"

  depends_on = [
    google_project_service.required["compute.googleapis.com"]
  ]
}

resource "google_compute_subnetwork" "application" {
  name                     = "${var.network_name}-${var.region}"
  project                  = var.project_id
  region                   = var.region
  network                  = google_compute_network.postgresql.id
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true
}

resource "google_compute_global_address" "private_service_range" {
  name          = "${var.network_name}-private-services"
  project       = var.project_id
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = var.private_service_prefix_length
  network       = google_compute_network.postgresql.id

  depends_on = [
    google_project_service.required["servicenetworking.googleapis.com"]
  ]
}

resource "google_service_networking_connection" "private_services" {
  network = google_compute_network.postgresql.id
  service = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [
    google_compute_global_address.private_service_range.name
  ]
}
