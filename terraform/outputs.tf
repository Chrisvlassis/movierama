output "primary_host" {
  description = "PostgreSQL primary hostname"
  value       = "postgres-primary.movierama.svc.cluster.local"
}

output "replica_host" {
  description = "PostgreSQL replica hostname"
  value       = "postgres-replica.movierama.svc.cluster.local"
}

output "database_name" {
  description = "Database name"
  value       = var.postgres_db
}

output "database_user" {
  description = "Database admin user"
  value       = var.postgres_user
}

output "database_port" {
  description = "PostgreSQL port"
  value       = 5432
}