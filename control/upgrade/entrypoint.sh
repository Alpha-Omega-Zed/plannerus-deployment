#!/bin/bash
echo 'The legacy in-place control upgrade is disabled. Use the protected Upgrade Plannerus action.' >&2
exit 2
set -e
set -o pipefail

/control/upgrade/scripts/00-db-upgrade.sh

echo "Please restart your installation by issuing the following command:"
echo "  docker compose up -d --build --pull always"
