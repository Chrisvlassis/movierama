# namespace for the database in k8s
resource "kubernetes_namespace" "movierama" {
  metadata {
    name = "movierama"
  }
}

# store passwords securely in k8s. We use this secret to pass the passwords to the pods
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

# only need pg_hba.conf to allow replica to connect for replication
resource "kubernetes_config_map" "postgres_config" {
  metadata {
    name      = "postgres-config"
    namespace = kubernetes_namespace.movierama.metadata[0].name
  }

  data = {
    # Lines must start at column 0: <<-EOF only strips to the closing delimiter's indent;
    # extra indent on body lines leaves leading spaces and breaks pg_hba parsing.
    "pg_hba.conf" = <<-EOF
local   all             all                     trust
host    all             all       127.0.0.1/32  trust
host    all             all       ::1/128       trust
# Replication from cluster pods (pg_basebackup / streaming, non-SSL on pod network)
host    replication     replicator  0.0.0.0/0   scram-sha-256
host    all             all         0.0.0.0/0   scram-sha-256
  EOF
  }
}

# init script - creates replication user on primary. (this is kind of extra)
# Configure replication settings
resource "kubernetes_config_map" "postgres_init_script" {
  metadata {
    name      = "postgres-init-script"
    namespace = kubernetes_namespace.movierama.metadata[0].name
  }

  data = {
    "primary.sh" = file("${path.module}/scripts/primary.sh")
  }
}

###-------------------------------------------###
###-------------- Primary Pod ----------------###
###-------------------------------------------###
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

          # admin user #
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

          # replication user # This user will be created from the primary.sh. Later i will use this user to connect to the primary database
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

          # pg_hba must not be mounted inside PGDATA: the entrypoint chowns PGDATA and
          # ConfigMap mounts are read-only. Copy into PGDATA from primary.sh instead.
          volume_mount {
            name       = "postgres-config"
            mount_path = "/mnt/pg_hba.conf"
            sub_path   = "pg_hba.conf"
          }

          # mount persistent storage
          volume_mount {
            name       = "postgres-data"
            mount_path = "/var/lib/postgresql/data"
          }

          # mount init script - creates replication user on first start
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
    # Request of Disk. (In case of restarts of pods the data will persist)
    volume_claim_template {
      metadata {
        name = "postgres-data"
      }

      spec {
        access_modes = ["ReadWriteOnce"] # only one node can read and write to the disk (lets avoid conflicts)
        resources {
          requests = {
            storage = "1Gi"
          }
        }
      }
    }
  }
}

# stable network address for the primary
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



###-------------------------------------------###
###-------------- Replica Pod ----------------###
###-------------------------------------------###
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
        # init container runs after the postgres primary container starts
        # it copies all data from primary using pg_basebackup
        # Here i use the replication user to connect to the primary database
        init_container {
          name  = "init-replica"
          image = "postgres:${var.postgres_version}"

        command = [
        "bash", "-c",
        <<-EOF
            set -euo pipefail
            until pg_isready -h postgres-primary.movierama.svc.cluster.local -p 5432; do
            echo "Waiting for primary to be ready..."
            sleep 2
            done
            echo "Primary is ready, starting base backup..."
            rm -rf /var/lib/postgresql/data/*
            PGPASSWORD="$REPLICATION_PASSWORD" pg_basebackup \
            -h postgres-primary.movierama.svc.cluster.local \
            -U "$REPLICATION_USER" \
            -D /var/lib/postgresql/data \
            -Fp -Xs -R -P
            echo "Base backup complete"
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
          # admin user #
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

# stable network address for the replica
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
