# PostgreSQL replica: a read-only copy that streams changes from the primary.
#
# Startup:
#   1. Init container waits for the primary, then runs pg_basebackup to copy its data.
#   2. PostgreSQL starts using that data and automatically streams WAL from the primary.

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

        # Runs once before PostgreSQL starts: copies all data from the primary.
        # pg_basebackup also writes a standby.signal file so PostgreSQL boots in replica mode.
        init_container {
          name  = "init-replica"
          image = "postgres:${var.postgres_version}"

          command = [
            "bash", "-c",
            <<-EOF
              set -euo pipefail

              # Wait until the primary is ready, otherwise pg_basebackup will fail.
              until pg_isready -h postgres-primary.movierama.svc.cluster.local -p 5432; do
                echo "Waiting for primary to be ready..."
                sleep 2
              done

              echo "Primary is ready. Starting base backup..."

              # Clear the data directory before copying.
              rm -rf /var/lib/postgresql/data/*

              # -Fp plain format, -Xs stream WAL during backup,
              # -R  write recovery config (enables streaming), -P show progress.
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

        # Main container: starts on the data copied by the init container
        # and streams further changes from the primary automatically.
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

    # Separate 1Gi disk for the replica, independent from the primary's disk.
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

# Headless service: stable DNS for read-only queries against the replica.
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
