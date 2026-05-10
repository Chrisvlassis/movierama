# Foundational Kubernetes resources:
#   - Namespace  → isolates all movierama resources
#   - Secret     → stores admin and replication passwords
#   - ConfigMap  → pg_hba.conf (PostgreSQL authentication rules)
#   - ConfigMap  → primary.sh (init script that runs on the primary's first start)

resource "kubernetes_namespace" "movierama" {
  metadata {
    name = "movierama"
  }
}

# Pods reference this Secret instead of having passwords hardcoded in their spec.
resource "kubernetes_secret" "postgres" {
  metadata {
    name      = "postgres-secret"
    namespace = kubernetes_namespace.movierama.metadata[0].name
  }

  data = {
    postgres-password    = var.postgres_password
    replication-password = var.replication_password
  }
}

# pg_hba.conf controls who can connect to PostgreSQL and how they authenticate.
# Rules are read top to bottom and the first match wins:
#   - local connections      → trust (no password needed)
#   - replication user       → password (used by the replica)
#   - all other users        → password
resource "kubernetes_config_map" "postgres_config" {
  metadata {
    name      = "postgres-config"
    namespace = kubernetes_namespace.movierama.metadata[0].name
  }

  data = {
    "pg_hba.conf" = <<-EOF
local   all             all                     trust
host    all             all       127.0.0.1/32  trust
host    all             all       ::1/128       trust
host    replication     replicator  0.0.0.0/0   scram-sha-256
host    all             all         0.0.0.0/0   scram-sha-256
EOF
  }
}

# Init script that runs once on the primary's first start.
# Configures WAL replication and creates the replication user (see scripts/primary.sh).
resource "kubernetes_config_map" "postgres_init_script" {
  metadata {
    name      = "postgres-init-script"
    namespace = kubernetes_namespace.movierama.metadata[0].name
  }

  data = {
    "primary.sh" = file("${path.module}/scripts/primary.sh")
  }
}
