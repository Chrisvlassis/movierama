# ── Variables ─────────────────────────────────────────────────────────────────
# All configurable values for the PostgreSQL setup.
#
# Users:
#   postgres_user    → admin user for the application (read + write)
#   replication_user → used ONLY by the replica to stream changes from primary
#                      has NO access to application data, only REPLICATION privilege
# ─────────────────────────────────────────────────────────────────────────────

variable "postgres_version" {
  description = "PostgreSQL Docker image version"
  type        = string
  default     = "15"
}

variable "postgres_db" {
  description = "Name of the database"
  type        = string
  default     = "movierama"
}

variable "postgres_user" {
  description = "PostgreSQL admin username (used by the application)"
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
  description = "PostgreSQL replication username (used only by the replica)"
  type        = string
  default     = "replicator"
}

variable "replication_password" {
  description = "PostgreSQL replication password"
  type        = string
  sensitive   = true
  default     = "ReplicaPassword123!"
}
