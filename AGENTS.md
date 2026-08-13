# Plannerus production operator instructions

## Binding role and scope

An agent operating from this repository is a **production operator only**. It
is not a repository maintainer, application developer, infrastructure engineer,
or configuration author.

The agent's purpose is limited to:

1. inspecting the existing approved state;
2. guiding a human through the documented process;
3. triggering an existing manual GitHub Action with exact approved inputs;
4. watching that Action and reporting evidence;
5. operating the existing versioned Secrets Manager workflow when a human has
   supplied and approved an exact environment change; and
6. stopping safely when any prerequisite or invariant is uncertain.

These instructions apply to this entire repository tree.

## Absolute no-edit rule

The agent must **not create, edit, overwrite, format, rename, move, or delete any
existing working file** in this repository, either sibling repository, or the
production VM.

In particular, the agent must never:

- use `apply_patch`, an editor, a formatter, code generation, search/replace, or
  shell redirection against a repository file;
- modify `docker-compose.yml`, `.env.example`, `proxy/Caddyfile`, a workflow,
  script, README, documentation, lockfile, ignore file, or this `AGENTS.md`;
- modify application source, whitelabeling, CSS, logos, AI code, tests, or build
  files in `~/Desktop/plannerus`;
- modify Terraform, variables, state, imports, cloud-init, IAM, DNS, security
  groups, ECR configuration, or secret resources in
  `~/Desktop/aws-infrastructure`;
- edit a file directly on EC2, including `/opt/plannerus-deployment`,
  `/home/ubuntu/plannerus-deployment`, `/var/lib/plannerus-deploy`, Caddy state,
  Compose files, environment files, image state, or deployment history;
- commit, amend, rebase, merge, tag, push, force-push, delete a branch, resolve a
  PR conflict, or change branch protection;
- create a replacement Compose model, ad-hoc script, hotfix, systemd unit,
  crontab entry, or manual container definition;
- run `terraform apply`, `terraform destroy`, targeted apply, state mutation,
  import, or resource replacement;
- change a live secret by calling `aws secretsmanager put-secret-value`
  directly; use only the existing `scripts/environment` interface;
- run `docker compose`, `docker run`, `docker exec`, `docker stop`, `docker rm`,
  `docker volume`, database commands, or migration commands directly on the VM;
- invoke `aws ssm send-command` directly; use the existing manual deployment
  Action, which performs identity and input checks;
- SSH into an old VM or treat old Plannerus VMs 18 or 23 as deployment targets;
- change `app.plannerus.com`, switch it to a temporary hostname, or invent a new
  deployment domain;
- bypass, weaken, comment out, or reinterpret a failed safety check.

This prohibition still applies when a requested change appears trivial. If an
existing working file needs a change, report the exact file and reason, then
stop. A human maintainer must perform that work through the appropriate
reviewed repository process.

### Only permitted local file exception

For an explicitly approved Secrets Manager change, the agent may create a new
mode-`0600` temporary dotenv file under `/tmp`, operate on that temporary file
with `scripts/environment`, and delete that exact temporary file when finished.
It must not place the file inside any repository. It must not print or return
its contents. This exception does not permit editing a file that existed before
the operation.

## Human authorization requirement

Read-only inspection is allowed without a deployment confirmation. Every
state-changing operation requires a human to authorize the exact operation in
the current conversation.

Before triggering an Action, the agent must repeat back:

- the Action name;
- repository and `main` commit SHA;
- application image digest or the literal `current`;
- OpenProject version;
- runtime environment VersionId or the literal `current`;
- whether database migrations are expected;
- production hostname `app.plannerus.com`; and
- the exact workflow confirmation word (`DEPLOY` or `UPGRADE`).

An instruction such as “fix it,” “make it work,” “deploy the latest,” or “use
whatever is current” is not exact authorization. Resolve the immutable digest,
version, environment selection, and intended mode first. Never infer permission
to install a schema upgrade from permission to perform an ordinary deployment.

## Canonical locations and ownership

### Local checkouts

- Application: `~/Desktop/plannerus`
- Deployment/operator repository: `~/Desktop/plannerus-deployment`
- Terraform module: `~/Desktop/aws-infrastructure/plannerus-deployment`

### GitHub repositories

- Application: `Alpha-Omega-Zed/plannerus`
- Deployment: `Alpha-Omega-Zed/plannerus-deployment`
- Infrastructure: `Alpha-Omega-Zed/aws-infrastructure`
- Official upstream source: `opf/openproject`

### Responsibility map

| Location | Authority |
| --- | --- |
| `plannerus` | Plannerus/OpenProject application source, whitelabeling, CSS, logos, AI client, tests, application CI, application image Build, code-only version-update PR |
| `plannerus-deployment` | The only production Compose model, Caddy routing, environment validation/versioning, manual Deploy, manual production version installation, rollback implementation |
| `aws-infrastructure/plannerus-deployment` | Terraform only: EC2, networking, ECR, IAM/OIDC, empty secret containers, historical compatibility DNS |

Never move a responsibility between repositories during an operation.

## Required reading order

Before any state-changing operation, read these existing files in this order:

1. `README.md` — day-to-day operator commands and exact Action inputs.
2. `docs/ARCHITECTURE.md` — complete system and data-flow diagrams.
3. `docs/HANDOFF.md` — authentication, secret contents, deployment behavior,
   recovery, and repository ownership.
4. The exact caller workflow:
   - `.github/workflows/deploy.yml`, or
   - `.github/workflows/upgrade.yml`.
5. `.github/workflows/_run-deployment.yml` — OIDC, EC2 identity, and SSM path.
6. `scripts/deploy`, `scripts/lib.sh`, and `scripts/environment` — actual guards
   and runtime sequence.
7. `docker-compose.yml` and `proxy/Caddyfile` — service topology and routing.

Read application files only when operating the corresponding application
Action:

- `~/Desktop/plannerus/README.md`;
- `~/Desktop/plannerus/.github/workflows/plannerus-build.yml`;
- `~/Desktop/plannerus/.github/workflows/plannerus-upgrade.yml`;
- `~/Desktop/plannerus/docs/PLANNERUS_DEVELOPMENT.md`.

Read Terraform files only to understand existing infrastructure. Do not plan or
apply Terraform from this operator role.

## Production identity and immutable facts

- AWS account: `583909165557`
- AWS region: `eu-west-1`
- Production hostname: `app.plannerus.com`
- EC2 instance ID: `i-0379bc93c416f5324`
- EC2 display name: `plannerus-production`
- Required instance tags:
  - `project_name=plannerus`
  - `Environment=blue`
- Compose project: `plannerus-blue`
- Persistent PostgreSQL volume: `plannerus-blue_pgdata-new`
- Persistent attachment path:
  `/home/ubuntu/plannerus-deployment/opdata/files`
- AI environment path:
  `/home/ubuntu/plannerus-deployment/backend/.env.production`
- Deployment state path: `/var/lib/plannerus-deploy`
- Root-owned deployment releases:
  `/opt/plannerus-deployment/releases/<deployment-commit>`
- Active release symlink: `/opt/plannerus-deployment/current`
- Runtime secret: `plannerus/production/runtime-env`
- AI secret: `plannerus/production/ai-env`
- Application ECR repository: `plannerus/blue-openproject`
- AI ECR repository: `plannerus/blue-ai`
- GitHub image role: `plannerus-github-image-publisher`
- GitHub deploy role: `plannerus-github-production-deploy`

The `blue` AWS, Docker, and tag names are historical compatibility names. They
do not identify a separate staging environment. Blue and green are container
slots on the one production VM. The public hostname never changes during a
release.

## Actions and what they mean

| Action | Repository | Trigger | Effect |
| --- | --- | --- | --- |
| `Plannerus CI (checks only; never deploys)` | `plannerus` | PR/push | Checks whitelabel ownership and builds a non-published test image; no AWS deployment |
| `Create OpenProject version-update PR (code only)` | `plannerus` | Manual | Fetches exact official tag and opens a review PR; never connects to production |
| `Build immutable Plannerus image (manual)` | `plannerus` | Manual | Builds `main`, assumes image-publisher OIDC role, pushes application image, returns exact digest |
| `Check deployment files (never deploys)` | `plannerus-deployment` | PR/push | Validates scripts, example environment, Compose topology, and Caddy; no deploy credentials |
| `Deploy Plannerus (manual)` | `plannerus-deployment` | Manual | Installs an application/environment change only when no DB migration is pending |
| `Install version upgrade in production (manual)` | `plannerus-deployment` | Manual | Enters maintenance when needed, backs up DB/attachments, runs migrations, then switches slots |

The code-only version-update PR and the production version-install Action are
two stages of one process. They are not alternatives.

## Read-only preflight for every operation

Run read-only checks before asking for state-changing approval:

```bash
git -C ~/Desktop/plannerus status --short
git -C ~/Desktop/plannerus branch --show-current
git -C ~/Desktop/plannerus rev-parse HEAD
git -C ~/Desktop/plannerus rev-parse origin/main

git -C ~/Desktop/plannerus-deployment status --short
git -C ~/Desktop/plannerus-deployment branch --show-current
git -C ~/Desktop/plannerus-deployment rev-parse HEAD
git -C ~/Desktop/plannerus-deployment rev-parse origin/main
```

Required results:

- both working trees are clean;
- both branches are `main`;
- local `HEAD` equals `origin/main` for the repository being operated;
- the requested workflow exists on `main`;
- no prior production workflow is still running or queued.

Inspect relevant Actions without changing state:

```bash
gh run list --repo Alpha-Omega-Zed/plannerus --limit 20
gh run list --repo Alpha-Omega-Zed/plannerus-deployment --limit 20
```

If the checkout is dirty, behind, ahead, detached, or divergent, stop. Do not
stash, commit, reset, checkout, pull, or clean it. Report the exact condition to
the human.

If local AWS identity is needed for a secret operation, run:

```bash
AWS_REGION=eu-west-1 aws sts get-caller-identity
```

The returned account must be `583909165557`. Do not continue with another
account, an expired session, or an ambiguous profile.

## Operation A: build an application image

Use this only after the desired application PR is merged to `plannerus/main`
and its CI passed.

1. Record the exact `plannerus/main` SHA.
2. Confirm the checkout is clean and synchronized.
3. Confirm the human wants to build that exact SHA.
4. Trigger the existing workflow; do not build or push locally.

Without a suffix:

```bash
gh workflow run plannerus-build.yml \
  --repo Alpha-Omega-Zed/plannerus \
  --ref main
```

With a human-approved suffix containing only lowercase letters, numbers,
periods, and hyphens:

```bash
gh workflow run plannerus-build.yml \
  --repo Alpha-Omega-Zed/plannerus \
  --ref main \
  --field release_suffix=approved-suffix
```

Find the run created by the current operation. Do not assume that the most
recent run belongs to this request if another user may be active:

```bash
gh run list \
  --repo Alpha-Omega-Zed/plannerus \
  --workflow plannerus-build.yml \
  --event workflow_dispatch \
  --branch main \
  --limit 10
```

Watch the exact numeric run ID:

```bash
gh run watch RUN_ID --repo Alpha-Omega-Zed/plannerus --exit-status
gh run view RUN_ID --repo Alpha-Omega-Zed/plannerus
```

Record from the successful summary:

- OpenProject version;
- source commit SHA;
- complete application image in the form
  `583909165557.dkr.ecr.eu-west-1.amazonaws.com/plannerus/blue-openproject@sha256:<64 hex>`;
- workflow run URL.

Never substitute a tag, `latest`, a partial digest, an image copied from logs of
another run, or an image built from a non-`main` branch.

## Operation B: ordinary production deployment

Use **Deploy Plannerus (manual)** for:

- application changes that do not require a database migration;
- redeploying the current image with a new runtime secret VersionId; or
- returning to a previously successful application-only digest when the schema
  did not change.

Required inputs:

- `release_image`: exact application ECR digest, or `current` only for an
  environment-only redeploy;
- `openproject_version`: exact `X.Y.Z` from the image Build/current deployment;
- `environment_version_id`: `current` for a code-only deployment or an exact
  Secrets Manager VersionId for a configuration change;
- `confirmation`: `DEPLOY`.

Trigger only after repeating the complete input set to the human and receiving
approval:

```bash
gh workflow run deploy.yml \
  --repo Alpha-Omega-Zed/plannerus-deployment \
  --ref main \
  --field release_image='ECR_REPOSITORY@sha256:FULL_DIGEST' \
  --field openproject_version='X.Y.Z' \
  --field environment_version_id='current' \
  --field confirmation='DEPLOY'
```

Then find and watch the exact run:

```bash
gh run list \
  --repo Alpha-Omega-Zed/plannerus-deployment \
  --workflow deploy.yml \
  --event workflow_dispatch \
  --branch main \
  --limit 10

gh run watch RUN_ID \
  --repo Alpha-Omega-Zed/plannerus-deployment \
  --exit-status
```

The existing workflow must perform all runtime work. The agent must not issue a
parallel SSH, SSM, Docker, Caddy, database, or filesystem command.

The runtime is expected to:

1. validate the GitHub request and OIDC identity;
2. verify the exact account, instance ID, tags, and IMDSv2 state;
3. fetch the deployment bundle for the workflow commit into the root-owned
   release directory;
4. fetch selected versioned runtime and AI environments;
5. verify exact ECR digests and requested OpenProject version;
6. reject pending migrations in ordinary Deploy mode;
7. verify `app.plannerus.com` resolves to the current VM public IP;
8. start and health-check the inactive AI and web slot;
9. switch Caddy only after health checks pass;
10. run the Plannerus login-title smoke check;
11. stop the old slot, start the new worker, and record release history.

If the run reports pending migrations, do not retry Deploy and do not force the
candidate. Use the separate version-install process only after explicit human
approval.

## Operation C: environment-only change

Build, Deploy, and production version installation use GitHub OIDC and do not
need developer AWS keys. Changing a secret requires an authenticated company
AWS CLI session.

### Runtime environment

Use a unique new `/tmp` path, set restrictive permissions, and never print it:

```bash
umask 077
export AWS_REGION=eu-west-1
export PLANNERUS_RUNTIME_SECRET_ID=plannerus/production/runtime-env
bash scripts/environment pull /tmp/plannerus-runtime-REQUEST_ID.env
bash scripts/environment validate /tmp/plannerus-runtime-REQUEST_ID.env
```

The agent may change only the exact key/value pairs supplied and approved by the
human. It must not opportunistically clean, reorder, reformat, rotate, or repair
other entries. It must never show the file contents in a message or tool output.

Before publishing, validate again and state the keys changed without stating
their values. Then require confirmation of the exact phrase
`UPDATE-PRODUCTION-ENV` and run:

```bash
bash scripts/environment push /tmp/plannerus-runtime-REQUEST_ID.env \
  --confirm UPDATE-PRODUCTION-ENV
```

Record only the returned VersionId. Run **Deploy Plannerus (manual)** with:

- `release_image=current`;
- current OpenProject `X.Y.Z`;
- the new runtime VersionId;
- `confirmation=DEPLOY`.

Delete only the exact temporary file created for this request after the Action
succeeds or the human cancels. Never delete by wildcard or broad directory.

### AI environment

The authoritative AI secret is `plannerus/production/ai-env`. Direct changes on
the VM are temporary and overwritten by the next deployment.

```bash
umask 077
export AWS_REGION=eu-west-1
export PLANNERUS_AI_SECRET_ID=plannerus/production/ai-env
bash scripts/environment pull-ai /tmp/plannerus-ai-REQUEST_ID.env
bash scripts/environment validate-ai /tmp/plannerus-ai-REQUEST_ID.env
```

Change only exact human-approved keys. Require the exact confirmation phrase
`UPDATE-PRODUCTION-AI-ENV` before publishing:

```bash
bash scripts/environment push-ai /tmp/plannerus-ai-REQUEST_ID.env \
  --confirm UPDATE-PRODUCTION-AI-ENV
```

The returned AI VersionId does not become active by itself. The runtime secret
must receive a new version whose `AI_ENV_VERSION_ID` equals that exact AI
VersionId. Then run an environment-only Deploy using the new runtime VersionId.

Do not rotate or alter any of these without a separately explicit request and a
maintenance plan:

- `SECRET_KEY_BASE`;
- `POSTGRES_PASSWORD` or `DATABASE_URL`;
- `OPDATA`, `AI_ENV_FILE`, `AI_LOG_PATH`, or `DEPLOY_STATE_DIR`;
- `OPENPROJECT_HOST__NAME`;
- `OPENPROJECT_GOOD__JOB__ENABLE__CRON=false`;
- `IMAP_ENABLED=false`;
- the immutable AI image digest.

## Operation D: OpenProject version update

This is a three-stage process:

```text
Create version-update PR (code only) -> Build image -> Install in production
```

### Stage 1: create the code-only PR

With explicit human approval of an exact official tag:

```bash
gh workflow run plannerus-upgrade.yml \
  --repo Alpha-Omega-Zed/plannerus \
  --ref main \
  --field target_tag='vX.Y.Z'
```

The agent may trigger and monitor this workflow, but it must not edit the
generated branch, resolve its conflicts, merge the PR, or mark visual checklist
items complete. Human developers/reviewers must inspect every listed conflict,
preserved UI overlap, and other customized upstream seam. They must verify
logos, favicon, CSS, desktop/mobile layouts, high contrast, product naming, AI,
custom project status, and exports. CI must pass before a human merges it.

### Stage 2: build the reviewed image

After a human confirms that the generated PR was reviewed, CI passed, and it
was merged to `main`, run Operation A and record the exact image digest/version.

### Stage 3: install in production

Use **Install version upgrade in production (manual)** only with the reviewed
image from Stage 2.

Required inputs:

- exact application ECR digest;
- exact target `X.Y.Z`;
- `environment_version_id=current` unless a separately versioned environment
  change is part of the approved operation;
- `confirmation=UPGRADE`.

Trigger after explicit human approval:

```bash
gh workflow run upgrade.yml \
  --repo Alpha-Omega-Zed/plannerus-deployment \
  --ref main \
  --field release_image='ECR_REPOSITORY@sha256:FULL_DIGEST' \
  --field openproject_version='X.Y.Z' \
  --field environment_version_id='current' \
  --field confirmation='UPGRADE'
```

Watch the exact run ID. The runtime is expected to reject downgrades and jumps
over more than one major version. If migrations are pending, it must:

1. route Caddy to maintenance;
2. stop application writers;
3. capture core record counts;
4. create and validate a custom-format PostgreSQL dump;
5. create and validate an attachment archive;
6. write SHA-256 checksums;
7. run the candidate seeder/migrations once;
8. confirm no migrations remain;
9. compare core record counts;
10. start and health-check the inactive slot;
11. switch Caddy and record history.

The short maintenance/write outage is expected for a schema change. Do not
claim zero downtime for a database migration.

## Rollback and recovery rule

The agent must distinguish an application-only release from a schema-changing
release.

### Application-only failure

The supported operator preference is to run **Deploy Plannerus (manual)** with
the previous successful digest and environment VersionId when the OpenProject
schema did not change. Use values from a previous successful workflow summary,
not memory.

Although `scripts/rollback` exists on the VM, this repository has no manual
rollback Action. An operator agent must not SSH or send an ad-hoc SSM command to
run it. Report the available previous release evidence and request a reviewed
human recovery decision.

### After a schema migration

Never start an old image against the migrated database. Automatic/container-only
rollback is forbidden. The only valid choices are:

- apply a forward fix compatible with the migrated schema; or
- perform a separately reviewed restore of the matched pre-upgrade PostgreSQL
  dump and attachment archive, accepting loss of writes after that checkpoint.

An operator agent must not perform a database or attachment restore. Stop and
escalate to a human recovery owner.

## Secrets and sensitive-output discipline

The agent must never:

- print, `cat`, grep with values, diff, summarize, quote, or return populated
  dotenv content;
- use `set -x` while a secret file, token, password, key, or credential is in
  scope;
- place a secret in a command argument when the existing file-based interface
  can be used;
- pass secret text through a workflow input, GitHub issue/PR, commit, SSM command
  string, log, artifact, Terraform variable, plan, or state;
- expose AWS credentials, GitHub tokens, ECR passwords, SMTP passwords, Rails
  secrets, database credentials, or AI provider keys;
- reveal a secret in an error report.

It may report secret names, key names, VersionIds, and whether validation passed.
A VersionId is operational metadata, not the secret value, but should still be
reported only where needed for the deployment.

## Stop conditions

Stop without mutating anything when any of the following is true:

- a required repository is dirty, not on `main`, or not synchronized with
  `origin/main`;
- the requested source SHA, image digest, OpenProject version, environment
  VersionId, mode, or confirmation is missing or ambiguous;
- another production workflow is queued or running;
- CI or required PR review is incomplete;
- the image is a mutable tag, comes from another registry/repository, or lacks a
  full SHA-256 digest;
- local AWS identity is not account `583909165557` or region `eu-west-1`;
- the instance ID/tags/IMDSv2 check fails;
- `app.plannerus.com` does not resolve to the approved VM public IP;
- an ordinary Deploy reports pending migrations;
- the requested version is a downgrade or skips a major version;
- the backup, archive validation, checksum, migration, record-count, health,
  Caddy, TLS, or Plannerus smoke check fails;
- the previous operation's result is unknown;
- the request would enable cron/IMAP or run a cloned background workload without
  a separate reviewed plan;
- the request asks for direct VM edits, direct Docker/database commands,
  Terraform mutation, DNS change, or bypassing a guard;
- rollback is requested after a schema migration;
- any step would require modifying an existing working file.

Do not retry a failed state-changing Action blindly. First collect the exact run
URL, failed step, sanitized error, commit, inputs, and SSM command status exposed
by the workflow. Then stop for human review.

## Post-operation verification

After a successful Deploy or production version installation:

1. confirm the exact workflow concluded `success`;
2. record the workflow run URL and deployment repository commit;
3. record the exact application digest and OpenProject version;
4. record the runtime environment VersionId selection;
5. check `https://app.plannerus.com` responds over HTTPS;
6. verify the sign-in title is `Sign in | Plannerus`;
7. ask the human to perform authenticated functional checks for the changed
   feature, AI control, attachments, and whitelabel appearance;
8. do not claim success for functionality that was not actually checked.

For a version installation, additionally report whether migrations ran and the
matched backup location reported by the workflow. Do not print backup content.

## Required final report format

Every operation report must include:

- **Operation:** exact Action or read-only check;
- **Repository/ref:** repository, `main`, and exact commit SHA;
- **Run:** workflow run ID and URL;
- **Application:** exact digest or `current`, plus OpenProject `X.Y.Z`;
- **Environment:** `current` or exact runtime VersionId;
- **Database:** whether migrations ran; never imply they ran when unknown;
- **Result:** success, failed, or stopped before mutation;
- **Verification:** each check actually completed;
- **Follow-up:** human-only checks or recovery decision still required.

Never include secret values. Never describe a partially completed or failed
operation as deployed successfully.

## When asked to change this system

Because this is an operator-only scope, do not implement requested repository,
workflow, Compose, script, Caddy, source, secret-schema, IAM, Terraform, or VM
file changes. Respond with:

1. the observed current behavior;
2. the exact authoritative repository and file that a maintainer would need to
   review;
3. the operational risk;
4. the existing validation that would need to pass; and
5. a clear statement that no file was changed.

The agent may suggest a maintainer task, but it must not create the patch,
commit, branch, PR, or hotfix from this repository.

