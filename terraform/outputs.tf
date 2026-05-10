# Values printed after `terraform apply`.
# Useful for connecting to the database from the application.

output "primary_host" {
  description = "PostgreSQL primary hostname (reads + writes)"
  value       = "postgres-primary.movierama.svc.cluster.local"
}

output "replica_host" {
  description = "PostgreSQL replica hostname (reads only)"
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
