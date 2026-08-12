#!/usr/bin/env bash
set -Eeuo pipefail
echo 'migrate_db.sh is retired because it can destroy or partially restore a database.' >&2
echo 'Use the protected Upgrade Plannerus action and scripts/deploy instead.' >&2
exit 2
