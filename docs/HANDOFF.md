# Plannerus technical operations reference

The repository README is the day-to-day runbook. This file explains the system
behind it and is intended for troubleshooting and ownership handoff.

## Production layout

- Public host: `app.plannerus.com`.
- EC2 display name: `plannerus-production`.
- Instance: `i-0379bc93c416f5324`, account `583909165557`, region `eu-west-1`.
- Runtime: one VM, two app/AI slots, one Caddy proxy, one PostgreSQL database,
  one attachment directory, and one cache.
- Persistent database volume: `plannerus-blue_pgdata-new`.
- Persistent attachments:
  `/home/ubuntu/plannerus-deployment/opdata/files`.

Some Docker, ECR, Terraform, and tag names retain `blue` for compatibility with
the original deployment. They do not indicate another live environment. Do not
rename the Compose project or database volume: their names connect the app to
the existing data.

The old Plannerus 18 and 23 VMs are not deployment targets.

## AWS authentication

Build, Deploy, and Upgrade use GitHub OIDC. GitHub requests a short-lived token,
AWS validates the repository and environment identity, and STS returns temporary
credentials for that workflow run. No long-lived AWS access key is stored in
GitHub or on a developer laptop.

- `plannerus-github-image-publisher` publishes only the Plannerus app image.
- `plannerus-github-production-deploy` can inspect and send SSM commands only
  to the production Plannerus instance.
- The EC2 instance role pulls the two ECR images and reads the two production
  secrets.

All team members with repository access can run the actions. There is no
reviewer gate. Only `main` is accepted, and deployments are serialized so two
team members cannot deploy simultaneously.

Local company AWS credentials are needed only to change Secrets Manager values
or Terraform. Confirm account `583909165557` before either operation.

## Secrets Manager

Terraform creates the secret containers but never stores their values in state.

### `plannerus/production/runtime-env`

This raw dotenv document includes:

- PostgreSQL password and `DATABASE_URL`;
- Rails `SECRET_KEY_BASE`;
- hostname, HTTPS, SMTP, worker, and thread settings;
- persistent attachment and deployment-state paths;
- the immutable AI image digest;
- `AI_ENV_VERSION_ID`, which selects one exact AI secret version; and
- the Caddy ACME contact.

The VM fetches the selected version, validates it, and writes
`/var/lib/plannerus-deploy/runtime.env` with mode `0600`.

The existing short `SECRET_KEY_BASE` is intentionally preserved because an
unplanned rotation can invalidate sessions or encrypted credentials. Rotate it
only as a separate maintenance task.

### `plannerus/production/ai-env`

This raw dotenv document includes the AI database, mail, reCAPTCHA, Google,
OpenAI, and OpenRouter settings. The VM writes the selected version to
`/home/ubuntu/plannerus-deployment/backend/.env.production` with mode `0600`.

The Google API key originally edited on the VM is already stored here. Future
VM edits are overwritten; version the secret instead.

## Deployment behavior

For a normal Deploy:

1. resolve exact app, AI, and environment versions;
2. reject an image with pending database migrations;
3. start and health-check the inactive app and AI slot;
4. validate Caddy and Plannerus login branding;
5. switch local Caddy to the healthy slot; and
6. drain and stop the former slot, then start the new worker.

The hostname never changes. PostgreSQL, cache, attachments, and Caddy state are
shared rather than duplicated. A pre-cutover failure keeps or restores the old
slot.

For Upgrade, the action first enters maintenance, stops writers, creates a
custom-format PostgreSQL dump and attachment archive with checksums under
`/var/lib/plannerus-deploy/backups`, runs the candidate seeder once, confirms no
migrations remain, compares core record counts, and then performs the same
health-gated slot switch.

OpenProject major upgrades must be sequential. A schema-changing upgrade has a
short write outage because both slots use one local database.

## Recovery

An application-only release can be reversed by running Deploy with the previous
image digest and environment VersionId. The emergency on-VM helper is
`sudo bash scripts/rollback`.

After a schema migration, never start the old image against the migrated
database. Either apply a forward fix or restore the matching pre-upgrade
database dump and attachment archive together. Restoring loses writes made
after that recovery point.

PostgreSQL, attachments, and local migration backups currently live on the
encrypted EC2 root volume. Terraform protects the instance with
`prevent_destroy`, and AWS Backup covers it, but an off-instance verified
database/attachment recovery point is still required before replacing the VM.

## Ownership boundary

- `Alpha-Omega-Zed/plannerus`: application source, CI, whitelabeling, Build, and
  OpenProject source-upgrade preparation.
- `Alpha-Omega-Zed/plannerus-deployment`: the only production Compose model,
  environment validation, Deploy, Upgrade, and rollback logic.
- `Alpha-Omega-Zed/aws-infrastructure/plannerus-deployment`: EC2, security
  group, Route53, ECR, IAM/OIDC, and empty Secrets Manager containers.

Terraform never deploys application containers. The app repository's root
Compose file is never used in production.
