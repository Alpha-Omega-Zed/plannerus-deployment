#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

# --- Configuration ---
EFS_MOUNT_PATH="/mnt/efs_share"
DUMP_FILENAME="openproject_dump.sql" # Change if your dump has a different name or is a custom format (e.g., .dump)
DB_DUMP_ON_EFS="$EFS_MOUNT_PATH/$DUMP_FILENAME"

NEW_DB_CONTAINER_NAME="openproject-docker-compose-db-1" # As specified by you
NEW_DB_NAME="openproject"
NEW_DB_USER="openproject"
NEW_DB_PASS="openproject" # The password for the NEW_DB_USER

POSTGRES_ADMIN_USER="postgres" # Default superuser in PostgreSQL to create users/databases

# --- Script Start ---
echo "=== OpenProject Database Migration Script ==="

# 1. Check if dump file exists on EFS
if [ ! -f "$DB_DUMP_ON_EFS" ]; then
    echo "ERROR: Database dump file not found at $DB_DUMP_ON_EFS"
    echo "Please ensure the dump file from your old VM is present on the EFS share."
    exit 1
fi
echo "Found database dump file: $DB_DUMP_ON_EFS"

# 2. Navigate to docker-compose directory (optional, assumes script is run from there or path is adjusted)
# cd ~/openproject-docker-compose || { echo "ERROR: Could not navigate to openproject-docker-compose directory."; exit 1; }
echo "Assuming current directory is your openproject-docker-compose setup."

# 3. Stop relevant application services (db service can remain running or be started next)
echo "Stopping application services (web, worker, cron, seeder, proxy, autoheal)..."
sudo docker compose stop web worker cron seeder proxy autoheal || echo "Some services might not have been running, continuing..."
sudo docker compose rm -f web worker cron seeder proxy autoheal || echo "Some services might not have existed, continuing..."


# 4. Ensure DB service is up and running
echo "Ensuring database service ($NEW_DB_CONTAINER_NAME) is running..."
sudo docker compose up -d db

echo "Waiting for database service to initialize (20 seconds)..."
sleep 20 # Give PostgreSQL time to start, especially if it's initializing
# Check if DB is ready
MAX_RETRIES=5
RETRY_COUNT=0
DB_READY=false
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if sudo docker exec $NEW_DB_CONTAINER_NAME pg_isready -U $POSTGRES_ADMIN_USER -d postgres -h localhost -q; then
        echo "Database service is ready."
        DB_READY=true
        break
    else
        echo "Database not yet ready, waiting 10 more seconds..."
        sleep 10
        RETRY_COUNT=$((RETRY_COUNT+1))
    fi
done

if [ "$DB_READY" = false ]; then
    echo "ERROR: Database service did not become ready. Please check its logs: sudo docker compose logs $NEW_DB_CONTAINER_NAME"
    exit 1
fi

# 5. Prepare the database: Drop existing, create new user and database
echo "Preparing database: dropping existing database and user (if they exist)..."
sudo docker exec -it $NEW_DB_CONTAINER_NAME psql -U $POSTGRES_ADMIN_USER -c "DROP DATABASE IF EXISTS $NEW_DB_NAME;"
sudo docker exec -it $NEW_DB_CONTAINER_NAME psql -U $POSTGRES_ADMIN_USER -c "DROP USER IF EXISTS $NEW_DB_USER;"

echo "Creating new user '$NEW_DB_USER' with password '$NEW_DB_PASS'..."
sudo docker exec -it $NEW_DB_CONTAINER_NAME psql -U $POSTGRES_ADMIN_USER -c "CREATE USER $NEW_DB_USER WITH PASSWORD '$NEW_DB_PASS';"

echo "Creating new database '$NEW_DB_NAME' owned by '$NEW_DB_USER'..."
sudo docker exec -it $NEW_DB_CONTAINER_NAME psql -U $POSTGRES_ADMIN_USER -c "CREATE DATABASE $NEW_DB_NAME OWNER $NEW_DB_USER;"
echo "Database preparation complete."

# 6. Copy the dump file from EFS into the new database container
CONTAINER_DUMP_PATH="/tmp/$DUMP_FILENAME"
echo "Copying '$DB_DUMP_ON_EFS' into container '$NEW_DB_CONTAINER_NAME' at '$CONTAINER_DUMP_PATH'..."
sudo docker cp "$DB_DUMP_ON_EFS" "$NEW_DB_CONTAINER_NAME:$CONTAINER_DUMP_PATH"
echo "Dump file copied into container."

# 7. Restore the database
echo "Restoring database from '$CONTAINER_DUMP_PATH' as user '$NEW_DB_USER'..."
# This command is for a PLAIN SQL DUMP (.sql file)
# If your DUMP_FILENAME is a custom format (e.g., .dump from pg_dump -Fc),
# you need to use pg_restore instead. See commented example below.
sudo docker exec -i $NEW_DB_CONTAINER_NAME psql -U $NEW_DB_USER -d $NEW_DB_NAME < "$DB_DUMP_ON_EFS" # Alternative for direct pipe, might need careful quoting
# More robust for plain SQL with file copied into container:
# sudo docker exec -it $NEW_DB_CONTAINER_NAME psql -U $NEW_DB_USER -d $NEW_DB_NAME -f $CONTAINER_DUMP_PATH

# If using pg_dump -Fc (custom format, e.g. DUMP_FILENAME="openproject_dump.dump"):
# echo "Restoring custom-format database dump..."
# sudo docker exec -t $NEW_DB_CONTAINER_NAME pg_restore -U $NEW_DB_USER -d $NEW_DB_NAME -v $CONTAINER_DUMP_PATH
# Note: pg_restore does not typically need --clean or --if-exists if the database was just freshly created and is empty.

echo "Database restore command executed. Check output above for errors."

# 8. Clean up dump file from inside the container
echo "Removing dump file from container..."
sudo docker exec -it $NEW_DB_CONTAINER_NAME rm "$CONTAINER_DUMP_PATH"
echo "Dump file removed from container."

echo ""
echo "=== Database Restore Phase Complete ==="
echo "Next steps:"
echo "1. Ensure your .env file has the correct DATABASE_URL:"
echo "   DATABASE_URL=postgres://$NEW_DB_USER:$NEW_DB_PASS@db/$NEW_DB_NAME?pool=20&encoding=unicode&reconnect=true"
echo "2. Run the seeder service to perform database migrations:"
echo "   sudo docker compose run --rm seeder"
echo "   (Monitor its output carefully and be very patient, this can take a long time)"
echo "3. If seeder completes successfully, start all application services:"
echo "   sudo docker compose up -d"
echo "4. Check logs and test your OpenProject application."

exit 0