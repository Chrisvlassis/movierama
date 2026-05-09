#!/bin/bash
set -e

# --------------- Step 1: Load pg_hba.conf ----------------------------- #
# pg_hba.conf controls who can connect and how they authenticate.
# The ConfigMap is read-only so we copy it into PGDATA where PostgreSQL expects it.
cp /mnt/pg_hba.conf "$PGDATA/pg_hba.conf"

# --------------- Step 2: Configure WAL replication --------------------- #
# wal_level=replica   - enables WAL logs needed for streaming replication
# max_wal_senders=3   - max number of replicas that can connect
# hot_standby=on      - allows replica to accept read-only queries
echo "Configuring replication settings..."
cat >> "$PGDATA/postgresql.conf" << EOF
wal_level = replica
max_wal_senders = 3
hot_standby = on
EOF

# --------------- Step 3: Create replication user --------------------- #
# This user has ONLY the REPLICATION privilege — it cannot read or write data.
# The replica uses this user to authenticate and stream WAL changes from primary.echo "Creating replication user..."
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