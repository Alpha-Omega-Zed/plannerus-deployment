#!/bin/bash
echo 'The legacy raw-volume backup is disabled. Use scripts/deploy for matched logical DB and attachment backups.' >&2
exit 2
set -e

timestamp=$(date +%s)
mkdir -p /backups
cd /backups
filename="${timestamp}-pgdata.tar.gz"
echo "Backing up PostgreSQL data into backups/${filename}..."
tar czf "${filename}" -C "$PGDATA" .
filename="${timestamp}-opdata.tar.gz"
echo "Backing up OpenProject assets into backups/${filename}..."
tar czf "${filename}" -C "$OPDATA" .
echo "DONE"
