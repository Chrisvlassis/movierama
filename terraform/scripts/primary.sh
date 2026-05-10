#!/bin/bash
set -e

# Copy pg_hba.conf from the mounted ConfigMap into PGDATA, where PostgreSQL expects it.
echo "Loading pg_hba.conf..."
cp /mnt/pg_hba.conf "$PGDATA/pg_hba.conf"

# Enable streaming replication so the replica can receive changes:
#   wal_level = replica   → write enough WAL data for streaming
#   max_wal_senders = 3   → max replicas allowed to connect
#   hot_standby = on      → replica can serve read-only queries
echo "Configuring replication settings..."
cat >> "$PGDATA/postgresql.conf" << EOF
wal_level = replica
max_wal_senders = 3
hot_standby = on
EOF

# Create a dedicated replication user (no access to application data).
# IF NOT EXISTS prevents errors when the pod restarts.
echo "Creating replication user..."
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<-SQL
  DO \$\$
  BEGIN
    IF NOT EXISTS (
      SELECT FROM pg_catalog.pg_roles WHERE rolname = '${REPLICATION_USER}'
    ) THEN
      CREATE USER ${REPLICATION_USER} WITH REPLICATION LOGIN PASSWORD '${REPLICATION_PASSWORD}';
    END IF;
  END
  \$\$;
SQL

echo "Primary setup complete!"
