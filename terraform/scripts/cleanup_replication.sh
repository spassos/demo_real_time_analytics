#!/bin/bash

# Script to clean up PostgreSQL logical replication artifacts (slot, publication)
# before running 'terraform destroy'.
# Requires: terraform, gcloud (for auth), cloud-sql-proxy, psql, installed and configured.

set -e 

set -o pipefail

echo "--- Starting PostgreSQL Replication Cleanup ---"

echo "Fetching configuration from Terraform state..."
INSTANCE_CONNECTION_NAME=$(terraform output -raw postgres_instance_connection_name)
DB_NAME="datastream_source"
ADMIN_USER="postgres"
DATASTREAM_USER="datastream_user"
STREAM_ID="pg_to_bq_stream"

if [ -z "$INSTANCE_CONNECTION_NAME" ] || [ -z "$DB_NAME" ] || [ -z "$ADMIN_USER" ] || [ -z "$STREAM_ID" ]; then
  echo "ERROR: Could not retrieve required values from terraform output."
  echo "Please ensure outputs (postgres_instance_connection_name, database_name_for_cleanup, admin_db_user_for_cleanup, datastream_stream_id_for_cleanup) are defined in outputs.tf and state is up-to-date."
  exit 1
fi

REPLICATION_SLOT_NAME="ds_replication_slot_for_${STREAM_ID}"
PUBLICATION_NAME="ds_publication_for_${STREAM_ID}"

PROXY_PORT=5433

# Example: PGPASSWORD="your_secure_password" ./scripts/cleanup_replication.sh
if [ -z "$PGPASSWORD" ]; then
    echo "ERROR: PGPASSWORD environment variable is not set."
    echo "Please set the password for the admin user ('$ADMIN_USER') before running."
    echo "Example: PGPASSWORD=\"your_password\" $0"
    exit 1
fi
export PGPASSWORD

echo "Starting cloud-sql-proxy for instance '$INSTANCE_CONNECTION_NAME' on port $PROXY_PORT..."
cloud-sql-proxy "$INSTANCE_CONNECTION_NAME" --port=$PROXY_PORT &
PROXY_PID=$!
echo "Proxy started with PID $PROXY_PID. Waiting for connection..."


sleep 5
n=0
until [ $n -ge 6 ] 
do

  psql -h 127.0.0.1 -p $PROXY_PORT -U "$ADMIN_USER" -d "$DB_NAME" -c "SELECT 1" --no-password > /dev/null 2>&1 && break
  n=$((n+1))
  echo "Waiting for proxy connection (attempt $n)..."
  sleep 5
done

if [ $n -ge 6 ]; then
  echo "ERROR: Could not connect to database via cloud-sql-proxy after several attempts."
  echo "Stopping proxy (PID $PROXY_PID)..."
  kill $PROXY_PID
  wait $PROXY_PID 2>/dev/null || true
  exit 1
fi
echo "Proxy connected successfully."

echo "Executing cleanup commands on database '$DB_NAME' as user '$ADMIN_USER'..."

SQL_COMMANDS_ADM="
  -- Attempt to drop the replication slot.
  -- This might fail if the slot is actively in use or doesn't exist,
  -- but pg_drop_replication_slot should handle non-existence gracefully.
  -- If it fails due to activity, manual intervention might be needed via Cloud Console/gcloud.
  ALTER USER $ADMIN_USER WITH REPLICATION;
  
  SELECT pg_catalog.pg_drop_replication_slot(slot_name)
  FROM pg_catalog.pg_replication_slots
  WHERE slot_name = '$REPLICATION_SLOT_NAME';
  SELECT 'Dropped replication slot $REPLICATION_SLOT_NAME (if it existed).' AS cleanup_status;

"

SQL_COMMANDS_USR="
  -- Drop the publication
  DROP PUBLICATION IF EXISTS \"$PUBLICATION_NAME\";
  SELECT 'Dropped publication $PUBLICATION_NAME (if it existed).' AS cleanup_status;
"

psql -h 127.0.0.1 -p $PROXY_PORT -U "$ADMIN_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 --no-password <<EOF
$SQL_COMMANDS_ADM
EOF

psql -h 127.0.0.1 -p $PROXY_PORT -U "$DATASTREAM_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 --no-password <<EOF
$SQL_COMMANDS_USR
EOF

if [ $? -ne 0 ]; then
    echo "ERROR: psql command failed during cleanup execution."
else
    echo "SQL cleanup commands executed successfully."
fi

echo "Stopping cloud-sql-proxy (PID $PROXY_PID)..."
kill $PROXY_PID
wait $PROXY_PID 2>/dev/null || true
echo "Proxy stopped."

echo "--- PostgreSQL Replication Cleanup Finished ---"
exit 0