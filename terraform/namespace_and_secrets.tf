# ── Namespace, Secrets & ConfigMaps ──────────────────────────────────────────
#
# This file sets up the foundational Kubernetes resources:
#
#   1. Namespace     → isolates all movierama resources in their own namespace
#   2. Secret        → stores passwords securely (never hardcoded in pod specs)
#   3. ConfigMap     → pg_hba.conf: controls who can connect to PostgreSQL
#   4. ConfigMap     → primary.sh:  init script that runs on the primary at first start
#
# ─────────────────────────────────────────────────────────────────────────────

# ── 1. Namespace ──────────────────────────────────────────────────────────────
resource "kubernetes_namespace" "movierama" {
  metadata {
    name = "movierama"
  }
}

# ── 2. Secret ─────────────────────────────────────────────────────────────────
# Stores the admin and replication passwords.
# Pods reference this secret instead of having passwords written directly in their spec.
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

# ── 3. ConfigMap: pg_hba.conf ─────────────────────────────────────────────────
# pg_hba.conf is PostgreSQL's authentication file.
# It controls who can connect, from where, and how they must authenticate.
# PostgreSQL reads this file on every new incoming connection.
#
# Rules (read top to bottom, first match wins):
#   - Local connections    → trust (no password needed, internal only)
#   - Replication user     → must use scram-sha-256 password (for replica streaming)
#   - All other users      → must use scram-sha-256 password
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

# ── 4. ConfigMap: primary.sh ──────────────────────────────────────────────────
# Init script that runs once on the primary pod's first start.
# It configures WAL replication and creates the replication user.
# See scripts/primary.sh for details.
resource "kubernetes_config_map" "postgres_init_script" {
  metadata {
    name      = "postgres-init-script"
    namespace = kubernetes_namespace.movierama.metadata[0].name
  }

  data = {
    "primary.sh" = file("${path.module}/scripts/primary.sh")
  }
}
