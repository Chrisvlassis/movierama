# i want 2 users. one for the main and one for the replica. In a sense we dont want the same 'person' have access to both databases

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