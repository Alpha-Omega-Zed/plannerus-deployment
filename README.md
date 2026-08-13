# Plannerus production operations

Use this repository to deploy [app.plannerus.com](https://app.plannerus.com),
change its environment, or run an OpenProject database upgrade.

## Deploy code changes

First build the image in
[Alpha-Omega-Zed/plannerus](https://github.com/Alpha-Omega-Zed/plannerus) as
described in that repository's README. Copy the resulting ECR digest ending in
`@sha256:...`.

Then open
[**Actions → Deploy Plannerus**](https://github.com/Alpha-Omega-Zed/plannerus-deployment/actions/workflows/deploy.yml),
select `main`, choose **Run workflow**, and enter:

- `release_image`: the copied ECR digest;
- `openproject_version`: the version shown by the Build action;
- `environment_version_id`: leave `current`;
- `confirmation`: `DEPLOY`.

Wait for the action to finish successfully, then check
[app.plannerus.com](https://app.plannerus.com). That is the complete code-release
process.

The action starts the new app and AI containers in the inactive slot, checks
them, switches traffic, and then stops the old slot. It does not recreate the
database or attachment storage. If the image needs a database migration, Deploy
stops and tells you to use Upgrade instead.

## Change the environment

Environment values are in AWS Secrets Manager, not Git and not the VM.

For environment editing only, you need the company AWS CLI profile. Build,
Deploy, and Upgrade actions do not require local AWS credentials. Verify your
AWS login before editing:

```bash
aws sts get-caller-identity
# Account must be 583909165557.
```

From this repository:

```bash
export AWS_REGION=eu-west-1
export PLANNERUS_RUNTIME_SECRET_ID=plannerus/production/runtime-env

bash scripts/environment pull ./runtime.env
$EDITOR ./runtime.env
bash scripts/environment validate ./runtime.env
bash scripts/environment push ./runtime.env --confirm UPDATE-PRODUCTION-ENV
```

The last command prints a new VersionId. Open
[**Actions → Deploy Plannerus**](https://github.com/Alpha-Omega-Zed/plannerus-deployment/actions/workflows/deploy.yml)
and enter:

- `release_image`: `current`;
- `openproject_version`: the currently deployed version;
- `environment_version_id`: the new VersionId;
- `confirmation`: `DEPLOY`.

Delete the local `runtime.env` after the deployment. Never commit it.

### Change an AI key

Google, OpenAI, OpenRouter, AI database, mail, and reCAPTCHA values are stored
separately in `plannerus/production/ai-env`.

```bash
bash scripts/environment pull-ai /tmp/plannerus-ai.env
$EDITOR /tmp/plannerus-ai.env
bash scripts/environment validate-ai /tmp/plannerus-ai.env
bash scripts/environment push-ai /tmp/plannerus-ai.env --confirm UPDATE-PRODUCTION-AI-ENV
```

Copy the returned AI VersionId. Pull `runtime.env`, replace only
`AI_ENV_VERSION_ID`, validate and push `runtime.env`, then run Deploy with
`release_image=current` and the new runtime VersionId.

Delete `runtime.env` and `/tmp/plannerus-ai.env` afterward. A direct edit on the
VM is temporary and is overwritten by the next deployment.

## Upgrade OpenProject

Do not use this for an ordinary code change.

1. In [Alpha-Omega-Zed/plannerus](https://github.com/Alpha-Omega-Zed/plannerus),
   run **Prepare OpenProject upgrade** with the exact official tag.
2. Review the generated PR, wait for **Plannerus CI**, and merge it.
3. Run **Build immutable Plannerus image** and copy its digest and version.
4. Here, run
   [**Upgrade Plannerus**](https://github.com/Alpha-Omega-Zed/plannerus-deployment/actions/workflows/upgrade.yml)
   with that digest, version, `environment_version_id=current`, and confirmation
   `UPGRADE`.
5. Wait for success and test [app.plannerus.com](https://app.plannerus.com).

Upgrade creates a matched PostgreSQL and attachment backup before migrations.
Schema changes require a short maintenance window; normal Deploy releases do
not.

## Roll back a normal release

Run **Deploy Plannerus** again with the previous image digest and previous
environment VersionId. Do not run an older app image after a schema upgrade;
use the recovery procedure in the technical reference.

## Where things live

- `plannerus`: application code, Build, and source-upgrade action.
- `plannerus-deployment`: this guide, production Compose, environment tools,
  Deploy, and database Upgrade action.
- `aws-infrastructure/plannerus-deployment`: Terraform only.

For architecture, authentication, secret contents, failure behavior, and
recovery details, read [docs/HANDOFF.md](docs/HANDOFF.md).
