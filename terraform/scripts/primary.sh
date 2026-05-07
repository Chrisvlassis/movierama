#!/bin/bash
set -e
# Writable copy: ConfigMap at /mnt is read-only and must not live under PGDATA (chown fails).
cp /mnt/pg_hba.conf "$PGDATA/pg_hba.conf"

## Configures the replication settings for the primary database
echo "Configuring replication settings..."
cat >> "$PGDATA/postgresql.conf" << EOF
wal_level = replica
max_wal_senders = 3
hot_standby = on
EOF

## Creates the replication user for the primary database
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