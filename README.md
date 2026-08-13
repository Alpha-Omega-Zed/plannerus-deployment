# Plannerus deployment

This repository is the runtime source of truth for
[app.plannerus.com](https://app.plannerus.com). Application source and image
builds live in `Alpha-Omega-Zed/plannerus`; Terraform, IAM, DNS and the EC2
instance live in `aws-infrastructure`.

## Repository map

| Repository | What developers use it for |
| --- | --- |
| `Alpha-Omega-Zed/plannerus` | Change application code, update whitelabeling, prepare an OpenProject source upgrade, and build an immutable ECR image |
| `Alpha-Omega-Zed/plannerus-deployment` (this repository) | Change runtime settings, deploy an image, run a schema upgrade, or roll back an application-only release |
| `Alpha-Omega-Zed/aws-infrastructure` | Change AWS resources through Terraform; it contains no Compose runtime and performs no application release |

This repository contains the only production `docker-compose.yml`. There is no
control Compose or database-migration shortcut: all normal deployments and
upgrades enter through the protected GitHub actions and `scripts/deploy`.

The stale Plannerus 18/23 VMs are not deployment targets. The guarded scripts
accept only AWS account `583909165557`, instance `i-0379bc93c416f5324`, and the
tags `project_name=plannerus` and `Environment=blue`.

## What developers do

### Redeploy a code change

1. Merge the code pull request into `plannerus/main` after **Plannerus CI**.
2. Run **Build immutable Plannerus image** in the `plannerus` repository.
3. Copy the ECR digest from the workflow summary.
4. Run **Deploy Plannerus** here with:
   - `release_image`: the copied digest;
   - `openproject_version`: the version printed by the build;
   - `environment_version_id`: the current Secrets Manager VersionId;
   - confirmation `DEPLOY`.

The script pulls the image without modifying the database, starts it in the
inactive blue/green web and AI slot, waits for both health checks, verifies the
Plannerus login branding, switches Caddy, and only then stops the former web,
worker, and AI slot. The database volume and attachment directory are never
recreated.

If the candidate contains Rails migrations, **Deploy Plannerus** stops before
changing anything and tells the developer to use **Upgrade Plannerus**.

### Change `.env` and redeploy

Runtime configuration is a versioned raw dotenv secret named
`plannerus/production/runtime-env`. GitHub, Terraform and the repository never
contain its values.

```bash
export AWS_REGION=eu-west-1
export PLANNERUS_RUNTIME_SECRET_ID=plannerus/production/runtime-env

# Fetch without printing values, edit locally, validate, then create a version.
bash scripts/environment pull ./runtime.env
$EDITOR ./runtime.env
bash scripts/environment validate ./runtime.env
bash scripts/environment push ./runtime.env --confirm UPDATE-PRODUCTION-ENV
```

The last command prints only the new VersionId. Run **Deploy Plannerus** with
`release_image=current`, the currently deployed OpenProject version, and that
VersionId. This starts the same image in the inactive slot with the new
environment, health-checks it, and switches traffic. To reverse a bad setting,
select the previous Secrets Manager VersionId and repeat the same action.

Adding a new OpenProject environment key also requires mapping it under
`x-app-environment` in `docker-compose.yml`; this prevents an unreviewed secret
field from silently changing container behavior.

### Upgrade OpenProject

1. In `plannerus`, run **Prepare OpenProject upgrade** with an exact official
   tag. The action resolves and records its full SHA from the official repo.
2. Review and merge the generated PR. Plannerus-owned logo, CSS and AI files
   are restored verbatim; other conflicts stop for review.
3. Run **Build immutable Plannerus image** and copy its digest.
4. Run **Upgrade Plannerus** here with the digest, target version, current
   environment VersionId, and confirmation `UPGRADE`.

The upgrade action:

1. proves it is on the one approved EC2 instance;
2. determines whether the image has pending Rails migrations;
3. sends Caddy to maintenance and stops all OpenProject web/worker writers;
4. creates a PostgreSQL custom-format dump and attachment archive with SHA-256
   checksums under `/var/lib/plannerus-deploy/backups`;
5. runs the new image's seeder exactly once;
6. verifies no migrations remain and that core record counts are unchanged;
7. starts and health-checks the inactive app/AI slot, verifies the Plannerus
   login branding, switches Caddy, then starts its worker.

OpenProject major upgrades must be sequential. On this single VM with a local
PostgreSQL database, application-only releases have a live blue/green cutover,
but schema-changing upgrades require a short write outage. Claiming zero-write
downtime for a local Compose database would be unsafe.

## Rollback

For a deployment with no schema change:

```bash
sudo bash scripts/rollback
```

This health-checks the prior slot and switches Caddy back. After a schema
migration, automatic rollback is deliberately refused. Restore the matched
database dump and attachment archive together, or apply a forward fix. Starting
the old image against the migrated schema can corrupt data.

## One-time GitHub/AWS setup

Create protected GitHub environments `plannerus-image-release`,
`plannerus-upgrade`, and `plannerus-production`, each with required reviewers
and `main` as the only allowed branch.

The application build environment needs these variables:

- `AWS_REGION=eu-west-1`
- `PLANNERUS_ECR_REGISTRY=583909165557.dkr.ecr.eu-west-1.amazonaws.com`
- `PLANNERUS_APP_ECR_REPOSITORY=plannerus/blue-openproject`
- `PLANNERUS_IMAGE_PUBLISH_ROLE_ARN` (OIDC role scoped to that ECR repository)

The deployment environment needs:

- `AWS_REGION=eu-west-1`
- `AWS_ACCOUNT_ID=583909165557`
- `PLANNERUS_INSTANCE_ID=i-0379bc93c416f5324`
- `PLANNERUS_RUNTIME_SECRET_ID=plannerus/production/runtime-env`
- `PLANNERUS_DEPLOY_ROLE_ARN` (OIDC role scoped to SSM commands on that instance)

The EC2 role needs ECR pull, `secretsmanager:GetSecretValue` for the one runtime
secret, and SSM core permissions. The VM needs Docker Compose, `aws`, `curl`,
`jq`, `tar`, `flock`, and `sha256sum`. No GitHub credential is installed on the
VM: the protected workflow downloads the exact public repository commit archive
identified by the workflow SHA.

## Current data ownership warning

PostgreSQL, attachments and local backups are all on the EC2 root volume. The
automation never runs `down -v`, deletes the database volume, deletes
attachments, or applies Terraform. Before replacing/destroying the instance,
take and verify an off-instance recovery point. The Terraform instance should
also be protected from accidental destroy until dedicated data storage is
introduced.
