#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
STATE_DIR="${DEPLOY_STATE_DIR:-/var/lib/plannerus-deploy}"
RUNTIME_ENV="$STATE_DIR/runtime.env"
IMAGE_ENV="$STATE_DIR/images.env"

log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }
require() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }

compose() {
  docker compose --project-directory "$ROOT" -f "$ROOT/docker-compose.yml" \
    --env-file "$RUNTIME_ENV" --env-file "$IMAGE_ENV" "$@"
}

require_digest() {
  [[ "$1" =~ ^[0-9]{12}\.dkr\.ecr\.[a-z0-9-]+\.amazonaws\.com/[a-z0-9/_-]+@sha256:[0-9a-f]{64}$ ]] \
    || die "image must be an exact ECR sha256 digest"
}

read_state_value() {
  local key="$1"
  sed -n "s/^${key}=//p" "$IMAGE_ENV" | tail -n1
}

write_image_state() {
  local blue="$1" green="$2" candidate="$3" blue_ai="$4" green_ai="$5" temporary
  temporary="$IMAGE_ENV.incomplete.$$"
  umask 077
  printf 'PLANNERUS_BLUE_IMAGE=%s\nPLANNERUS_GREEN_IMAGE=%s\nCANDIDATE_IMAGE=%s\nPLANNERUS_BLUE_AI_IMAGE=%s\nPLANNERUS_GREEN_AI_IMAGE=%s\n' \
    "$blue" "$green" "$candidate" "$blue_ai" "$green_ai" >"$temporary"
  mv "$temporary" "$IMAGE_ENV"
}

slot_web() { printf 'web-%s\n' "$1"; }
slot_worker() { printf 'worker-%s\n' "$1"; }
slot_ai() { printf 'ai-%s\n' "$1"; }

wait_healthy() {
  local service="$1" id health
  for _ in $(seq 1 30); do
    id="$(compose --profile blue --profile green ps -q "$service")"
    if [[ -n "$id" ]]; then
      health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$id")"
      [[ "$health" == healthy ]] && return 0
      [[ "$health" != unhealthy && "$health" != exited && "$health" != dead ]] || return 1
    fi
    sleep 5
  done
  return 1
}

write_upstream() {
  local service="$1" temporary="$STATE_DIR/proxy/upstream.caddy.incomplete.$$"
  umask 077
  if [[ "$service" == maintenance ]]; then
    printf 'respond "Plannerus is being upgraded. Please retry shortly." 503\n' >"$temporary"
  else
    printf 'reverse_proxy http://%s:8080 {\n  header_up Host app.plannerus.com\n  header_up X-Forwarded-Host app.plannerus.com\n  header_up X-Forwarded-Proto https\n}\n' \
      "$service" >"$temporary"
  fi
  mv "$temporary" "$STATE_DIR/proxy/upstream.caddy"
}

reload_proxy() {
  compose up -d --no-deps proxy
  compose exec -T proxy caddy reload --config /etc/caddy/Caddyfile
}

capture_counts() {
  compose exec -T db psql -X --set ON_ERROR_STOP=1 -U openproject -d openproject -At -F '|' \
    -c 'select (select count(*) from users),(select count(*) from projects),(select count(*) from work_packages),(select count(*) from attachments),(select count(*) from journals),(select count(*) from time_entries);'
}

running_openproject_version() {
  local container="$1"
  docker exec "$container" ruby -Ilib -ropen_project/version \
    -e 'print OpenProject::VERSION.to_semver'
}

validate_version_transition() {
  local current="$1" target="$2" mode="$3"
  local current_major current_minor current_patch target_major target_minor target_patch
  IFS=. read -r current_major current_minor current_patch <<<"$current"
  IFS=. read -r target_major target_minor target_patch <<<"$target"
  [[ "$current_major$current_minor$current_patch$target_major$target_minor$target_patch" =~ ^[0-9]+$ ]] \
    || die 'could not parse the current or target OpenProject version'
  (( target_major >= current_major )) || die 'OpenProject downgrades are forbidden'
  (( target_major <= current_major + 1 )) || die 'OpenProject major versions must be upgraded sequentially'
  if [[ "$mode" == deploy ]]; then
    [[ "$target" == "$current" ]] \
      || die 'a normal deployment must retain the current OpenProject version; use Install version upgrade in production'
  fi
}

plannerus_smoke() {
  local body
  body="$(curl -fsSL --resolve app.plannerus.com:443:127.0.0.1 https://app.plannerus.com/)" \
    || die 'Plannerus HTTPS smoke check failed'
  grep -Fq '<title>Sign in | Plannerus</title>' <<<"$body" \
    || die 'Plannerus login title/whitelabel smoke check failed'
}

backup_data() {
  local release_id="$1" output="$STATE_DIR/backups/$release_id" opdata
  [[ ! -e "$output" ]] || die "backup already exists: $output"
  install -d -m 700 "$output"
  compose exec -T db pg_dump -U openproject -d openproject -Fc --no-owner --no-privileges >"$output/database.dump"
  compose exec -T db pg_restore --list <"$output/database.dump" >/dev/null
  opdata="$(sed -n 's/^OPDATA=//p' "$RUNTIME_ENV" | tail -n1)"
  [[ "$opdata" == /* && -d "$opdata" ]] || die 'OPDATA is not an existing absolute directory'
  tar -C "$opdata" -czf "$output/attachments.tar.gz" .
  tar -tzf "$output/attachments.tar.gz" >/dev/null
  sha256sum "$output/database.dump" "$output/attachments.tar.gz" >"$output/SHA256SUMS"
  printf '%s\n' "$output"
}

current_legacy_image() {
  local id
  id="$(docker ps -q --filter label=com.docker.compose.project=plannerus-blue --filter label=com.docker.compose.service=web | head -n1)"
  [[ -n "$id" ]] || return 1
  docker inspect --format '{{.Config.Image}}' "$id"
}

current_legacy_ai_image() {
  local id
  id="$(docker ps -q --filter label=com.docker.compose.project=plannerus-blue \
    --filter label=com.docker.compose.service=aitextfeature-backend | head -n1)"
  [[ -n "$id" ]] || return 1
  docker inspect --format '{{.Config.Image}}' "$id"
}

assert_target() {
  local token identity account instance environment project
  token="$(curl -fsS --connect-timeout 2 -X PUT -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' http://169.254.169.254/latest/api/token)" \
    || die 'IMDSv2 is unavailable'
  identity="$(curl -fsS -H "X-aws-ec2-metadata-token: $token" http://169.254.169.254/latest/dynamic/instance-identity/document)"
  account="$(jq -r .accountId <<<"$identity")"
  instance="$(jq -r .instanceId <<<"$identity")"
  environment="$(curl -fsS -H "X-aws-ec2-metadata-token: $token" http://169.254.169.254/latest/meta-data/tags/instance/Environment)"
  project="$(curl -fsS -H "X-aws-ec2-metadata-token: $token" http://169.254.169.254/latest/meta-data/tags/instance/project_name)"
  INSTANCE_PUBLIC_IP="$(curl -fsS -H "X-aws-ec2-metadata-token: $token" http://169.254.169.254/latest/meta-data/public-ipv4)"
  [[ "$account" == 583909165557 && "$instance" == i-0379bc93c416f5324 && "$environment" == blue && "$project" == plannerus ]] \
    || die 'this is not the approved Plannerus application VM'
  [[ "$INSTANCE_PUBLIC_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || die 'the application VM has no public IPv4 address'
  export INSTANCE_PUBLIC_IP
}
