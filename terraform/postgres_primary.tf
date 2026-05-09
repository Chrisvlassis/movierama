# ── PostgreSQL Primary ────────────────────────────────────────────────────────
#
# The primary is the main PostgreSQL instance.
# It accepts both reads and writes from the application.
#
# Resources:
#   1. StatefulSet → runs the primary PostgreSQL pod
#   2. Service     → headless service that gives the pod a stable DNS name
#                    so the replica can always find it at:
#                    postgres-primary.movierama.svc.cluster.local
#
# On first start, primary.sh runs and:
#   - Loads pg_hba.conf
#   - Configures WAL replication settings
#   - Creates the replication user
# ─────────────────────────────────────────────────────────────────────────────

# ── 1. StatefulSet ────────────────────────────────────────────────────────────
# StatefulSet is used instead of Deployment because:
#   - Databases need a stable, predictable pod name (postgres-primary-0)
#   - Data must persist across pod restarts (via PVC)
resource "kubernetes_stateful_set" "postgres_primary" {
  metadata {
    name      = "postgres-primary"
    namespace = kubernetes_namespace.movierama.metadata[0].name
    labels = {
      app  = "postgres"
      role = "primary"
    }
  }

  spec {
    service_name = "postgres-primary"
    replicas     = 1

    selector {
      match_labels = {
        app  = "postgres"
        role = "primary"
      }
    }

    template {
      metadata {
        labels = {
          app  = "postgres"
          role = "primary"
        }
      }

      spec {
        container {
          name  = "postgres"
          image = "postgres:${var.postgres_version}"

          # ── Database config ────────────────────────────────────────────────
          env {
            name  = "POSTGRES_DB"
            value = var.postgres_db
          }

          # ── Admin user ─────────────────────────────────────────────────────
          # Used by the application to read and write data
          env {
            name  = "POSTGRES_USER"
            value = var.postgres_user
          }

          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.postgres.metadata[0].name
                key  = "postgres-password"
              }
            }
          }

          # ── Replication user ───────────────────────────────────────────────
          # Used only by the replica to stream WAL changes from this primary.
          # Created by primary.sh on first start.
          env {
            name  = "REPLICATION_USER"
            value = var.replication_user
          }

          env {
            name = "REPLICATION_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.postgres.metadata[0].name
                key  = "replication-password"
              }
            }
          }

          # ── Volume mounts ──────────────────────────────────────────────────

          # pg_hba.conf: mounted at /mnt (read-only).
          # primary.sh copies it into PGDATA on first start.
          volume_mount {
            name       = "postgres-config"
            mount_path = "/mnt/pg_hba.conf"
            sub_path   = "pg_hba.conf"
          }

          # Persistent storage for database data
          volume_mount {
            name       = "postgres-data"
            mount_path = "/var/lib/postgresql/data"
          }

          # Init script: runs once on first start via docker-entrypoint-initdb.d
          volume_mount {
            name       = "init-script"
            mount_path = "/docker-entrypoint-initdb.d/primary.sh"
            sub_path   = "primary.sh"
          }
        }

        # ── Volumes ────────────────────────────────────────────────────────
        volume {
          name = "postgres-config"
          config_map {
            name = kubernetes_config_map.postgres_config.metadata[0].name
          }
        }

        volume {
          name = "init-script"
          config_map {
            name         = kubernetes_config_map.postgres_init_script.metadata[0].name
            default_mode = "0755"
          }
        }
      }
    }

    # ── Persistent Volume Claim ────────────────────────────────────────────────
    # Requests a 1Gi disk for the primary's data.
    # Data survives pod restarts because it lives on this disk, not inside the pod.
    volume_claim_template {
      metadata {
        name = "postgres-data"
      }

      spec {
        access_modes = ["ReadWriteOnce"]
        resources {
          requests = {
            storage = "1Gi"
          }
        }
      }
    }
  }
}

# ── 2. Service ────────────────────────────────────────────────────────────────
# Headless service (cluster_ip = "None") gives the primary pod a stable DNS name:
#   postgres-primary.movierama.svc.cluster.local
# The replica uses this DNS name to connect for pg_basebackup and WAL streaming.
resource "kubernetes_service" "postgres_primary" {
  metadata {
    name      = "postgres-primary"
    namespace = kubernetes_namespace.movierama.metadata[0].name
  }

  spec {
    selector = {
      app  = "postgres"
      role = "primary"
    }
    port {
      port        = 5432
      target_port = 5432
    }
    cluster_ip = "None"
  }
}
