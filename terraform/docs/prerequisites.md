# Prerequisites — Before `terraform apply`

**Date:** 2026-07-03
**Environment:** `dev` (`ap-south-1`)
**Status:** Reference

---

## Overview

This checklist covers everything required before the first `terraform apply` of
the `dev` environment. It is ordered by sequence — do them top to bottom.

> The current `environments/dev/terraform.tfvars` has **`enable_dns = true`** and
> **`enable_cloudfront = true`**, which makes domain delegation a hard
> prerequisite (see §5 and [`dns-and-tls.md`](dns-and-tls.md)).

---

## 1. Local tooling (on the machine running apply)

| Tool | Requirement | Why |
|------|-------------|-----|
| **Terraform** | `~> 1.15.0` | Pinned via `required_version` in `providers.tf`. Bootstrap needs `>= 1.10.0`. |
| **AWS CLI v2** | installed, on `PATH`, authenticated | **Not optional** — `null_resource.seed_images` runs a `bash` script that calls `aws codebuild start-build` / `batch-get-builds` during apply. Missing CLI fails the first apply. |
| **bash** | available at `/bin/bash` | The seed provisioner's `interpreter`. |
| **git** | any recent version | Repository access. |
| **Docker** | **not required locally** | Images are built inside AWS CodeBuild, not on your machine. |

---

## 2. AWS account & credentials

- Authenticated AWS credentials for the target account in **`ap-south-1`**, with
  broad permissions for the first run (creates VPC, IAM, ECS, ALB, ACM, Route 53,
  CloudFront, S3, Secrets Manager, CodeBuild — effectively admin initially).
- The **same credentials must be usable by the AWS CLI** — the seed step inherits
  your shell profile / environment.
- **CloudFront's certificate is auto-created in `us-east-1`** via the aliased
  provider, so credentials must allow ACM in `us-east-1` as well (no manual step).

---

## 3. Bootstrap the remote state backend — do this first, separately

The `dev` environment uses an S3 backend (`backend.tf`) that must exist before
`terraform init`:

1. Edit `environments/dev/backend.tf` — replace the hardcoded account ID
   `882282737240` in the bucket name with **your** 12-digit account ID.
2. Create the state bucket + lock table:
   ```bash
   cd terraform/bootstrap
   terraform init && terraform apply
   ```
3. Initialise the environment:
   ```bash
   cd ../environments/dev
   terraform init
   ```

---

## 4. Configuration & secrets

- `terraform.tfvars` already exists. **Required variables with no default:**
  `environment` and `github_repo_url` (both set in the current file).
- **`github_token`** — GitHub PAT with scopes **`repo` + `admin:repo_hook`**
  (CodeBuild source auth *and* webhook registration). Prefer an env var over
  committing it:
  ```bash
  export TF_VAR_github_token=ghp_xxx
  ```
- **`tmdb_api_key`** — optional; empty = backend runs with placeholder images.
- The GitHub repo must contain a valid **`buildspec.yml`** on `github_branch`
  (`main`) — CodeBuild runs it during the seed step.

---

## 5. Domain delegation — required because `enable_dns = true`

`aws_acm_certificate_validation` waits (up to its `60m` timeout) for the
validation CNAMEs to resolve **publicly**, which requires `starflix.com`'s name
servers to be delegated to the new hosted zone at your **registrar**. Because the
zone (and its NS) don't exist until apply creates them, use a **two-step apply**:

```bash
# 1. Create only the hosted zone
terraform apply -target=module.dns[0].aws_route53_zone.this

# 2. Read the nameservers and delegate them at the registrar
terraform output route53_name_servers
#    → set these NS records at your registrar, then verify:
dig NS starflix.com +short

# 3. After delegation propagates, run the full apply
terraform apply
```

Full registrar walkthrough (per-provider steps, verification, alternatives):
[`dns-and-tls.md`](dns-and-tls.md).

If you do **not** control the domain, set `enable_dns = false` (and
`enable_cloudfront = false`) to deploy the plain-HTTP dev topology with no domain
dependency.

---

## 6. Account quotas (new accounts)

- **Elastic IPs** for the NAT Gateway (1 with `single_nat_gateway = true`) — new
  accounts default to 5, usually sufficient.
- **EC2 vCPU limits** must allow the ECS `t3.small` host(s).

---

## Happy-path summary

```bash
# one-time backend (after editing backend.tf account id)
cd terraform/bootstrap && terraform init && terraform apply

# environment
cd ../environments/dev && terraform init
export TF_VAR_github_token=ghp_xxx

# delegate DNS, then full apply
terraform apply -target=module.dns[0].aws_route53_zone.this
terraform output route53_name_servers      # set NS at registrar, wait for propagation
terraform apply
```
