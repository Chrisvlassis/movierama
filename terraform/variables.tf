# Database Configuration
# postgres_user  - admin user for the application
# replication_user - used ONLY by the replica to stream changes from the primary

variable "postgres_version" {
  description = "PostgreSQL Docker image version"
  type        = string
  default     = "15"
}

variable "postgres_db" {
  description = "Name of the default database"
  type        = string
  default     = "movierama"
}

variable "postgres_user" {
  description = "PostgreSQL admin username"
  type        = string
  default     = "movierama"
}

variable "postgres_password" {
  description = "PostgreSQL admin password"
  type        = string
  sensitive   = true
  default     = "StrongPassword123!"
}

variable "replication_user" {
  description = "PostgreSQL replication username"
  type        = string
  default     = "replicator"
}

variable "replication_password" {
  description = "PostgreSQL replication password"
  type        = string
  sensitive   = true
  default     = "ReplicaPassword123!"
}