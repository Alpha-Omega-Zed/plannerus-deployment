# Plannerus production operations

Use this repository to deploy [app.plannerus.com](https://app.plannerus.com),
change its environment, or install a new OpenProject version.

Nothing deploys on push or merge. Those events run **Check deployment files
(never deploys)** only. Production changes happen only when a developer selects
**Run workflow** on one of the manual actions below.

## Deploy code changes

First build the image in
[Alpha-Omega-Zed/plannerus](https://github.com/Alpha-Omega-Zed/plannerus) as
described in that repository's README. Copy the resulting ECR digest ending in
`@sha256:...`.

Then open
[**Actions → Deploy Plannerus (manual)**](https://github.com/Alpha-Omega-Zed/plannerus-deployment/actions/workflows/deploy.yml),
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
stops and tells you to use **Install version upgrade in production (manual)**.

## Change the environment

Environment values are in AWS Secrets Manager, not Git and not the VM.

For environment editing only, you need the company AWS CLI profile. Manual
Build, Deploy, and production version-install actions do not require local AWS
credentials. Verify your AWS login before editing:

```bash
aws sts get-caller-identity
# Account must be 583909165557.
```

If the command fails or shows another account, stop and ask the team lead to
configure your company AWS CLI profile.

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
[**Actions → Deploy Plannerus (manual)**](https://github.com/Alpha-Omega-Zed/plannerus-deployment/actions/workflows/deploy.yml)
and enter:

- `release_image`: `current`;
- `openproject_version`: the currently deployed version;
- `environment_version_id`: the new VersionId;
- `confirmation`: `DEPLOY`.

Use the OpenProject version shown in the latest successful Deploy workflow
summary if you do not know the currently deployed version.

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

## Install an OpenProject version update in production

Do not use this for an ordinary code change.

This is one three-stage process, not two competing kinds of upgrade:

```text
Create version-update PR (code only) → Build image → Install in production
```

1. In [Alpha-Omega-Zed/plannerus](https://github.com/Alpha-Omega-Zed/plannerus),
   run **Create OpenProject version-update PR (code only)** with the exact
   official tag. This changes source code only.
2. Review every file and complete the whitelabel checklist in the generated PR.
   Wait for **Plannerus CI (checks only; never deploys)**, then merge it.
3. Run **Build immutable Plannerus image (manual)** and copy its digest and
   version.
4. Here, run
   [**Install version upgrade in production
   (manual)**](https://github.com/Alpha-Omega-Zed/plannerus-deployment/actions/workflows/upgrade.yml)
   with that digest, version, `environment_version_id=current`, and confirmation
   `UPGRADE`.
5. Wait for success and test [app.plannerus.com](https://app.plannerus.com).

The production installation creates a matched PostgreSQL and attachment backup
before migrations.
Schema changes require a short maintenance window; normal Deploy releases do
not.

## Roll back a normal release

Run **Deploy Plannerus (manual)** again with the image digest and environment VersionId
from the previous successful Deploy workflow summary. Do not run an older app
image after a schema upgrade; use the recovery procedure in the technical
reference.

## Where things live

- `plannerus`: application code, Build, and version-update PR action.
- `plannerus-deployment`: this guide, production Compose, environment tools,
  Deploy, and production version-install action.
- `aws-infrastructure/plannerus-deployment`: Terraform only.

For architecture, authentication, secret contents, failure behavior, and
recovery details, read [docs/HANDOFF.md](docs/HANDOFF.md).
