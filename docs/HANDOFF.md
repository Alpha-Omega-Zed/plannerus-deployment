# Plannerus operations handoff

This document separates one-time platform setup from normal developer work.
Developers do not put AWS access keys in GitHub and do not log in to the VM for
ordinary application releases.

## Current readiness

The one-time platform setup is complete. The Build and Deploy actions have been
run successfully against production. `app.plannerus.com` is served by the
single `plannerus-production` VM, using two application/AI container slots and
one persistent PostgreSQL database and attachment directory.

All six team members use the same actions. There is no reviewer gate and no
developer needs a local AWS key for Build, Deploy, or Upgrade. Only `main` is
accepted so an arbitrary feature branch cannot be deployed accidentally.

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

The credentials expire automatically. A normal developer needs repository
access, not an AWS user or local AWS keys.

## One-time platform-owner setup

An AWS/GitHub administrator performs this once:

1. Create GitHub environments before creating the AWS roles:
   - in `Alpha-Omega-Zed/plannerus`: `plannerus-image-release`;
   - in `Alpha-Omega-Zed/plannerus-deployment`: `plannerus-production`.
   Allow only `main`. The team is flat and no additional reviewer gate is used.
2. In `aws-infrastructure/plannerus-deployment`, review and apply Terraform.
   Capture these outputs:
   - `github_image_publish_role_arn`;
   - `github_production_deploy_role_arn`;
   - `runtime_env_secret_arn` and `ai_env_secret_arn`;
   - `instance_id` and `openproject_ecr_repository_url`.
3. Configure the variables listed in the deployment README using the exact
   Terraform outputs. Do not create AWS access-key GitHub secrets.
4. Populate `plannerus/production/runtime-env` and
   `plannerus/production/ai-env` with validated dotenv payloads. Terraform
   creates only the empty secret containers and never stores secret values in
   Terraform state.
5. Install and verify AWS CLI v2 on the application VM. The VM uses its EC2
   instance role to fetch the selected secret version.
6. Run repository validation, then a `release_image=current` deployment before
   permitting normal releases.

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

It contains `AI_ENV_VERSION_ID`, which binds a deployment to one exact version
of the separate AI environment secret. It does not contain the provider keys.

During a deployment, GitHub never reads this secret. The protected workflow
sends an SSM command to the exact VM. On the VM, `scripts/environment pull`
uses the EC2 instance role to call `secretsmanager:GetSecretValue` for the exact
VersionId supplied to the workflow, validates the dotenv structure, and writes
it mode `0600` under `/var/lib/plannerus-deploy/runtime.env`.

Changing this secret is an operator task. The operator needs company AWS access
that permits only reading/versioning this one secret, then follows the
pull/validate/push commands in the README. Application developers do not need
that permission for ordinary code releases.

## AI service secret

The AI backend reads
`/home/ubuntu/plannerus-deployment/backend/.env.production`. This file includes
database, mail, reCAPTCHA, OpenRouter, OpenAI, and Google provider settings. It
is mode `0600` and is not committed to Git.

The source of truth is `plannerus/production/ai-env`. Each runtime secret version
selects an exact AI secret VersionId. Before starting candidate containers, the
VM fetches that version and materializes this file as mode `0600`. Direct VM
edits are therefore temporary; use `scripts/environment push-ai`, update
`AI_ENV_VERSION_ID`, version runtime, and deploy current.

## Operator roles

All team members can change the application and run Build, Deploy, or Upgrade
through GitHub. No local AWS credentials are required for those actions. A team
member needs company AWS access only when versioning runtime/AI configuration or
changing Terraform; ordinary releases never run Terraform.

## Routine paths

- Code-only release: build an immutable digest in `plannerus`, then run Deploy
  with the environment input left as `current`.
- Environment-only release: version the runtime secret, then run Deploy with
  `release_image=current`.
- OpenProject upgrade: prepare/review the source-upgrade PR, build its digest,
  then run Upgrade. Schema migrations require the documented short write
  outage; they are not zero-downtime database changes.
