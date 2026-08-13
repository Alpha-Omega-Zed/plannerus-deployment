# Plannerus operations handoff

This document separates one-time platform setup from normal developer work.
Developers do not put AWS access keys in GitHub and do not log in to the VM for
ordinary application releases.

## Current readiness

The repository workflows and Terraform configuration are committed, but the
one-time platform bootstrap is not complete yet:

- the Terraform resources for the dedicated GitHub OIDC roles and
  `plannerus/production/runtime-env` secret have not been applied;
- the protected GitHub environments and their variables have not been created;
- AWS CLI is not installed on the current application VM;
- AI-provider credentials still live only in
  `/home/ubuntu/plannerus-deployment/backend/.env.production` on the VM.

Do not describe the Deploy or Upgrade buttons as operational until these four
items are completed and a no-change deployment has passed.

## How GitHub authenticates to AWS

GitHub Actions uses OpenID Connect (OIDC), not a stored AWS access key.

1. A protected workflow job requests a short-lived GitHub OIDC token.
2. AWS STS verifies the token against the account's GitHub OIDC provider.
3. The IAM role trust policy accepts only the exact repository and GitHub
   environment named in Terraform.
4. STS returns temporary credentials for that single job.
5. The image-build role can publish only to the Plannerus application ECR
   repository. The deployment role can send an SSM command only to the approved
   Plannerus EC2 instance.

The credentials expire automatically. A normal developer needs GitHub access
and approval for the protected environment, not an AWS user or local AWS keys.

## One-time platform-owner setup

An AWS/GitHub administrator performs this once:

1. In `aws-infrastructure/plannerus-deployment`, review and apply Terraform.
   Capture these outputs:
   - `github_image_publish_role_arn`;
   - `github_production_deploy_role_arn`;
   - `runtime_env_secret_arn`;
   - `instance_id` and `openproject_ecr_repository_url`.
2. Create protected GitHub environments:
   - in `Alpha-Omega-Zed/plannerus`: `plannerus-image-release` and
     `plannerus-upgrade`;
   - in `Alpha-Omega-Zed/plannerus-deployment`: `plannerus-production`.
3. Require reviewers, prevent self-review where available, and allow only
   `main` in each environment.
4. Configure the variables listed in the deployment README using the exact
   Terraform outputs. Do not create AWS access-key GitHub secrets.
5. Populate `plannerus/production/runtime-env` with the validated dotenv
   payload. Terraform creates only the empty secret container and never stores
   secret values in Terraform state.
6. Install and verify AWS CLI v2 on the application VM. The VM uses its EC2
   instance role to fetch the selected secret version.
7. Run repository validation, then a reviewed `release_image=current`
   deployment before permitting normal releases.

## Runtime secret: OpenProject and deployment configuration

`plannerus/production/runtime-env` is a raw dotenv document. The expected key
names are defined in `.env.example`. It contains:

- PostgreSQL password and `DATABASE_URL`;
- Rails `SECRET_KEY_BASE`;
- attachment and deployment-state paths;
- hostname, HTTPS, worker and thread settings;
- SMTP credentials and delivery settings;
- flags that keep cron and IMAP disabled;
- the immutable AI image digest;
- the path to the separate AI environment file and log directory;
- the Caddy ACME contact email.

It does not currently contain the AI provider API keys.

During a deployment, GitHub never reads this secret. The protected workflow
sends an SSM command to the exact VM. On the VM, `scripts/environment pull`
uses the EC2 instance role to call `secretsmanager:GetSecretValue` for the exact
VersionId supplied to the workflow, validates the dotenv structure, and writes
it mode `0600` under `/var/lib/plannerus-deploy/runtime.env`.

Changing this secret is an operator task. The operator needs company AWS access
that permits only reading/versioning this one secret, then follows the
pull/validate/push commands in the README. Application developers do not need
that permission for ordinary code releases.

## AI service secret: current state and required migration

The AI backend currently reads
`/home/ubuntu/plannerus-deployment/backend/.env.production`. This file includes
database, mail, reCAPTCHA, OpenRouter, OpenAI, and Google provider settings. It
is mode `0600` and is not committed to Git.

A normal Deploy or Upgrade action reuses this path and does not overwrite the
file, so an API-key edit made directly on the current VM survives container
recreation and blue/green slot changes. It does not survive VM/root-volume
replacement, loss, or accidental file deletion.

Before declaring the platform fully handed off, create a separate
`plannerus/production/ai-env` Secrets Manager secret, copy the existing file
into it without printing values, grant the VM read-only access, and have the
deployment materialize the selected version as mode `0600`. Keep it separate
from the OpenProject runtime secret so access and rotation remain auditable.

## Operator roles

- **Application developer:** changes `plannerus`, opens a PR, and observes CI.
- **Release operator:** approves/runs Build, Deploy, or Upgrade through GitHub;
  no local AWS credentials are required.
- **Environment administrator:** versions runtime/AI secrets through restricted
  company AWS access; cannot change application code by that permission alone.
- **Infrastructure administrator:** reviews and applies Terraform; ordinary
  releases never run Terraform.

## Routine paths

- Code-only release: build an immutable digest in `plannerus`, then run Deploy.
- Environment-only release: version the runtime secret, then run Deploy with
  `release_image=current`.
- OpenProject upgrade: prepare/review the source-upgrade PR, build its digest,
  then run Upgrade. Schema migrations require the documented short write
  outage; they are not zero-downtime database changes.
