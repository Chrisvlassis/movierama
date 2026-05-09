# ── PostgreSQL Replica ────────────────────────────────────────────────────────
#
# The replica is a read-only copy of the primary.
# It continuously receives and applies WAL changes from the primary.
#
# Resources:
#   1. StatefulSet → runs the replica PostgreSQL pod
#   2. Service     → headless service that gives the pod a stable DNS name:
#                    postgres-replica.movierama.svc.cluster.local
#
# Startup sequence:
#   Step 1 → Init container runs BEFORE PostgreSQL starts
#            - Waits until primary is ready
#            - Runs pg_basebackup to copy all data from primary
#   Step 2 → PostgreSQL starts using the copied data
#   Step 3 → Replica connects to primary and streams WAL changes automatically
# ─────────────────────────────────────────────────────────────────────────────

# ── 1. StatefulSet ────────────────────────────────────────────────────────────
resource "kubernetes_stateful_set" "postgres_replica" {
  metadata {
    name      = "postgres-replica"
    namespace = kubernetes_namespace.movierama.metadata[0].name
    labels = {
      app  = "postgres"
      role = "replica"
    }
  }

  spec {
    service_name = "postgres-replica"
    replicas     = 1

    selector {
      match_labels = {
        app  = "postgres"
        role = "replica"
      }
    }

    template {
      metadata {
        labels = {
          app  = "postgres"
          role = "replica"
        }
      }

      spec {

        # ── Init Container ─────────────────────────────────────────────────────
        # Runs once before PostgreSQL starts.
        # Copies all data from the primary using pg_basebackup.
        # pg_basebackup also writes a standby.signal file which tells
        # PostgreSQL to start in replica (read-only) mode.
        init_container {
          name  = "init-replica"
          image = "postgres:${var.postgres_version}"

          command = [
            "bash", "-c",
            <<-EOF
              set -euo pipefail

              # Wait until the primary is accepting connections
              until pg_isready -h postgres-primary.movierama.svc.cluster.local -p 5432; do # Very IMPORTANT to wait for the primary to be ready otherwise it will fail!!
                echo "Waiting for primary to be ready..."
                sleep 2
              done

              echo "Primary is ready. Starting base backup..."

              # Clear the data directory before copying (i had an error about that so i removed it)
              rm -rf /var/lib/postgresql/data/*

              # Copy all data from primary
              # -Fp = plain format
              # -Xs = stream WAL during backup
              # -R  = write recovery config (enables streaming after start)
              # -P  = show progress
              PGPASSWORD="$REPLICATION_PASSWORD" pg_basebackup \
                -h postgres-primary.movierama.svc.cluster.local \
                -U "$REPLICATION_USER" \
                -D /var/lib/postgresql/data \
                -Fp -Xs -R -P

              echo "Base backup complete. PostgreSQL will start in replica mode."
            EOF
          ]

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

          volume_mount {
            name       = "postgres-data"
            mount_path = "/var/lib/postgresql/data"
          }
        }

        # ── Main Container ─────────────────────────────────────────────────────
        # Starts PostgreSQL using the data copied by the init container.
        # Automatically connects to primary and streams WAL changes.
        container {
          name  = "postgres"
          image = "postgres:${var.postgres_version}"

          port {
            container_port = 5432
          }

          env {
            name  = "POSTGRES_DB"
            value = var.postgres_db
          }

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

          volume_mount {
            name       = "postgres-data"
            mount_path = "/var/lib/postgresql/data"
          }
        }
      }
    }

    # ── Persistent Volume Claim ────────────────────────────────────────────────
    # Separate 1Gi disk for the replica's data.
    # This is physically separate from the primary's disk.
    # If the primary fails, the replica still has its own complete copy of the data.
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
# Headless service (cluster_ip = "None") gives the replica pod a stable DNS name:
#   postgres-replica.movierama.svc.cluster.local
# Use this address for read-only queries (e.g. reports, analytics).
resource "kubernetes_service" "postgres_replica" {
  metadata {
    name      = "postgres-replica"
    namespace = kubernetes_namespace.movierama.metadata[0].name
  }

  spec {
    selector = {
      app  = "postgres"
      role = "replica"
    }
    port {
      port        = 5432
      target_port = 5432
    }
    cluster_ip = "None"
  }
}
