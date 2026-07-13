variable "project_id" {
  description = "Google Cloud project ID used for the Cloud SQL architecture."
  type        = string

  validation {
    condition     = length(trimspace(var.project_id)) > 0
    error_message = "The project_id value must not be empty."
  }
}

variable "region" {
  description = "Google Cloud region used for regional resources."
  type        = string
  default     = "europe-west3"
}

variable "network_name" {
  description = "Name of the VPC network used by Cloud SQL clients."
  type        = string
  default     = "postgresql-ha-vpc"
}

variable "subnet_cidr" {
  description = "CIDR range for application resources connecting to Cloud SQL."
  type        = string
  default     = "10.10.0.0/24"
}

variable "private_service_prefix_length" {
  description = "Prefix length reserved for Google-managed services."
  type        = number
  default     = 16

  validation {
    condition = (
      var.private_service_prefix_length >= 16 &&
      var.private_service_prefix_length <= 24
    )
    error_message = "The private service prefix length must be between 16 and 24."
  }
}

variable "instance_name" {
  description = "Name of the Cloud SQL PostgreSQL primary instance."
  type        = string
  default     = "postgresql-ha-primary"
}

variable "database_version" {
  description = "PostgreSQL major version used by Cloud SQL."
  type        = string
  default     = "POSTGRES_16"
}

variable "database_tier" {
  description = "Cloud SQL machine tier."
  type        = string
  default     = "db-custom-2-7680"
}

variable "database_name" {
  description = "Initial application database."
  type        = string
  default     = "application"
}
