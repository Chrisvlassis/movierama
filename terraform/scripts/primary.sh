#!/bin/bash
set -e

# ── Step 1: Load pg_hba.conf ──────────────────────────────────────────────────
# pg_hba.conf controls who can connect to PostgreSQL and how they authenticate.
# The ConfigMap is mounted as read-only so we copy it into PGDATA where
# PostgreSQL expects to find it. (i was getting an error without this)
echo "Loading pg_hba.conf..."
cp /mnt/pg_hba.conf "$PGDATA/pg_hba.conf"

# ── Step 2: Configure WAL replication ─────────────────────────────────────────
# These settings enable streaming replication so the replica can receive changes.
#
#   wal_level = replica   → writes enough WAL data for streaming replication
#   max_wal_senders = 3   → max number of replicas allowed to connect
#   hot_standby = on      → allows the replica to serve read-only queries
echo "Configuring replication settings..."
cat >> "$PGDATA/postgresql.conf" << EOF
wal_level = replica
max_wal_senders = 3
hot_standby = on
EOF

# ── Step 3: Create replication user ───────────────────────────────────────────
# Creates a dedicated user with ONLY the REPLICATION privilege.
# This user cannot read or write application data.
# The replica uses this user to authenticate and pull WAL changes from primary.
# The IF NOT EXISTS check prevents errors on pod restarts.
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
