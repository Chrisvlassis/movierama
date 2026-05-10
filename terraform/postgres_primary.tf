# PostgreSQL primary: accepts both reads and writes from the application.
# Defined as a StatefulSet (stable pod name + persistent disk) plus a headless
# Service so the replica can reach it at: postgres-primary.movierama.svc.cluster.local

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

          env {
            name  = "POSTGRES_DB"
            value = var.postgres_db
          }

          # Admin user: used by the application to read and write data.
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

          # Replication user: used only by the replica to stream WAL changes.
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

          # pg_hba.conf is mounted read-only; primary.sh copies it into PGDATA.
          volume_mount {
            name       = "postgres-config"
            mount_path = "/mnt/pg_hba.conf"
            sub_path   = "pg_hba.conf"
          }

          # Persistent storage so data survives pod restarts.
          volume_mount {
            name       = "postgres-data"
            mount_path = "/var/lib/postgresql/data"
          }

          # Init script: runs once on first start.
          volume_mount {
            name       = "init-script"
            mount_path = "/docker-entrypoint-initdb.d/primary.sh"
            sub_path   = "primary.sh"
          }
        }

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

    # 1Gi disk for the primary's data, kept across pod restarts.
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

# Headless service: gives the primary a stable DNS name used by the replica.
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
