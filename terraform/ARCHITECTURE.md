# Starflix — Terraform Architecture Design

> Production-ready infrastructure design for the Starflix streaming platform.
> AWS region: `ap-south-1`. Compute: ECS EC2 Launch Type. CI/CD: GitHub + CodeBuild.
>
> This document describes the **full target design** (dev / stage / prod). Much of the
> CDN / DNS / WAF / multi-AZ content is flag-gated and not yet deployed in `dev`.
> For what is **actually running today**, see **§0 Current Deployment Snapshot (dev)**.

---

## 0. Current Deployment Snapshot (dev)

*Reflects the live `dev` environment as of 2026-07-02 (account `882282737240`, `ap-south-1`).*

### What is deployed and working

| Area | Status | Notes |
|---|---|---|
| VPC + 2 public / 2 private subnets | ✅ live | `10.0.0.0/16`, single shared NAT Gateway |
| VPC interface + S3 gateway endpoints | ✅ live | ECR (api/dkr), Secrets Manager, SSM, SSM Messages, CloudWatch Logs, S3 |
| ECS cluster (EC2 launch type) | ✅ live | `t3.small`, desired count 1 |
| Frontend service (React/nginx, port 80) | ✅ live | behind `starflix-dev-alb-frontend` (internet-facing) |
| Backend service (Node/Express, port 4000) | ✅ live | behind `starflix-dev-alb-backend` (internet-facing) |
| ECR repositories (frontend, backend) | ✅ live | |
| Secrets Manager (TMDB key, GitHub token) | ✅ live | values **Terraform-managed** (see §7) |
| CodeBuild + per-service webhooks | ✅ live | path-filtered auto-deploy (see CI/CD note below) |
| CloudWatch log groups, alarms, dashboard | ✅ live | |

### What is designed but NOT deployed in dev (flag-gated off)

| Component | Flag | Reason |
|---|---|---|
| CloudFront CDN | `enable_cloudfront = false` | not needed for dev iteration |
| Route 53 / ACM / custom domain | `enable_dns = false` | traffic uses raw ALB DNS names over **HTTP** |
| HTTPS / 443 listeners | (depends on ACM) | ALBs currently serve **HTTP only** (frontend :80, backend :4000) |
| WAF | `enable_waf = false` | prod-only |
| ALB deletion protection | `enable_deletion_protection = false` | dev convenience |
| Container Insights | `enable_container_insights = false` | cost |

### How frontend talks to backend (important — differs from the CDN design below)

CloudFront is off in dev, and the frontend nginx cannot proxy `/api` to the
internet-facing backend ALB from its private subnet (NAT hairpin to a same-VPC
internet-facing ALB does not route → 504). Instead, the **public backend URL is
baked into the SPA at build time** (`VITE_API_URL`), so the **browser calls the
backend ALB directly**:

```
Browser ──HTTP──► starflix-dev-alb-frontend :80   → static SPA (React/nginx)
Browser ──HTTP──► starflix-dev-alb-backend  :4000 → API (Node/Express)  [CORS-allowed]
```

Both ALBs are public, keeping the backend usable as a standalone/CMS API.
Full root-cause and fix write-up: [`docs/frontend-backend-504-fix.md`](docs/frontend-backend-504-fix.md).

### CI/CD auto-deploy (current)

- GitHub push to `main` → CodeBuild via webhook → build image → push to ECR →
  `ecs update-service --force-new-deployment`.
- Webhooks are **path-scoped** so services deploy independently:
  frontend builds only on `^frontend/` changes, backend only on `^backend/`.
- CodeBuild authenticates to GitHub via a Secrets Manager token
  (`starflix/dev/github-token`), and the frontend build receives `VITE_API_URL`
  as a build-time env var (baked into the SPA bundle).

---

## 1. Architecture Diagram

```
                                    INTERNET
                                        │
                              ┌─────────▼──────────┐
                              │   Route 53 (DNS)    │
                              │  starflix.com        │
                              └─────────┬────────────┘
                                        │
                              ┌─────────▼──────────┐
                              │   CloudFront CDN    │◄──── S3 (Static Assets)
                              │  (TLS termination)  │      posters, backdrops
                              └──────┬──────┬───────┘
                                     │      │
                        ┌────────────┘      └────────────┐
                        │ /api/*                          │ /*
                        │                                 │
              ┌─────────▼──────────┐          ┌──────────▼─────────┐
              │  Application Load   │          │  Application Load   │
              │  Balancer (ALB)     │          │  Balancer (ALB)     │
              │  [backend-alb]      │          │  [frontend-alb]     │
              └─────────┬──────────┘          └──────────┬──────────┘
                        │                                 │
          ══════════════╪═════════════════════════════════╪══════════════
          VPC: 10.0.0.0/16  ap-south-1
          ══════════════╪═════════════════════════════════╪══════════════
                        │                                 │
          ┌─────────────┴─── PUBLIC SUBNETS ─────────────┘
          │             (10.0.1.0/24 · 10.0.2.0/24)
          │  ┌──────────────────────────────────────────┐
          │  │  NAT Gateway (1 per AZ in prod)           │
          │  └──────────────────────────────────────────┘
          │
          └─────────────┬─── PRIVATE SUBNETS ──────────────┐
                        │   (10.0.11.0/24 · 10.0.12.0/24)  │
                        │                                   │
              ┌─────────▼──────────┐           ┌───────────▼────────┐
              │  ECS Cluster        │           │  ECS Cluster        │
              │  [EC2 Launch Type]  │           │  [EC2 Launch Type]  │
              │                     │           │                     │
              │  ┌───────────────┐  │           │  ┌───────────────┐  │
              │  │ Backend Svc   │  │           │  │ Frontend Svc  │  │
              │  │ Node.js/Expr  │  │           │  │ React/Nginx   │  │
              │  │ port: 4000    │  │           │  │ port: 80      │  │
              │  └───────────────┘  │           │  └───────────────┘  │
              └─────────────────────┘           └─────────────────────┘
                        │
          ┌─────────────┴──── AWS SERVICES (via VPC Endpoints) ────────────┐
          │                                                                  │
          │  ┌──────────┐  ┌──────────┐  ┌───────────┐  ┌───────────────┐  │
          │  │   ECR    │  │  SSM     │  │  Secrets  │  │  CloudWatch   │  │
          │  │ (images) │  │(params)  │  │  Manager  │  │  Logs + Alarms│  │
          │  └──────────┘  └──────────┘  └───────────┘  └───────────────┘  │
          └──────────────────────────────────────────────────────────────────┘

          ┌──────────────── CI/CD PLANE ─────────────────────────────────────┐
          │                                                                    │
          │  GitHub ──► CodeBuild ──► ECR ──► ECS Rolling Deploy              │
          │                │                                                   │
          │                └──► S3 (build artifacts + tfstate)                │
          └────────────────────────────────────────────────────────────────────┘
```

---

## 2. Repository Structure

```
terraform/
├── ARCHITECTURE.md               ← this file
│
├── bootstrap/                    ← run once per account; not part of normal apply
│   ├── main.tf                   #   S3 tfstate bucket, DynamoDB lock table, OIDC role
│   ├── variables.tf
│   └── outputs.tf
│
├── modules/                      ← reusable, environment-agnostic building blocks
│   ├── vpc/                      ← (exists) VPC, subnets, IGW, NAT, route tables
│   ├── security-groups/          ← (exists) ALB / ECS / VPC-endpoint SGs
│   ├── ecr/                      ← repositories for frontend + backend images
│   ├── ecs-cluster/              ← EC2 launch template, ASG, ECS cluster
│   ├── ecs-service/              ← task definition, ECS service, IAM roles
│   ├── alb/                      ← ALB, listeners (HTTP→HTTPS redirect), target groups
│   ├── cloudfront/               ← distribution, cache policies, origin configs
│   ├── s3/                       ← assets bucket, versioning, lifecycle, bucket policy
│   ├── dns/                      ← Route 53 hosted zone, A/CNAME records, ACM cert
│   ├── iam/                      ← cross-cutting roles and policies
│   ├── secrets/                  ← Secrets Manager secrets + SSM parameters
│   ├── codebuild/                ← CodeBuild project, IAM role, S3 artifact bucket
│   ├── vpc-endpoints/            ← ECR, SSM, Secrets Manager, CloudWatch interface endpoints
│   └── cloudwatch/               ← log groups, metric alarms, dashboard
│
├── environments/
│   ├── dev/
│   │   ├── backend.tf            #   S3 key: dev/terraform.tfstate
│   │   ├── providers.tf
│   │   ├── locals.tf             #   name_prefix, common_tags, feature flags
│   │   ├── variables.tf
│   │   ├── terraform.tfvars      #   dev-specific values (gitignored)
│   │   ├── terraform.tfvars.example
│   │   ├── main.tf               #   module calls wired together
│   │   └── outputs.tf
│   │
│   ├── stage/
│   │   └── (same structure as dev)
│   │
│   └── prod/
│       └── (same structure as dev)
│
└── scripts/
    ├── plan.sh                   ← wraps terraform plan with var-file injection
    ├── apply.sh                  ← wraps terraform apply with approval gate
    └── validate-all.sh           ← runs fmt + validate across all environments
```

### Principles

- **One state file per environment.** Each `environments/<env>/` is an independent Terraform root with its own backend key.
- **Modules own no state.** All resources live in the calling environment root; modules are pure functions.
- **`bootstrap/` is out-of-band.** It creates the S3 bucket and DynamoDB table that other environments need. Applied once per account, manually.
- **No `terraform.tfvars` committed.** Only `terraform.tfvars.example` is committed. Real values come from CI secrets or a local gitignored file.

---

## 3. Module Dependency Graph

```
environments/dev (root)
│
├── module.vpc                          ← no module deps; AWS provider only
│       outputs: vpc_id, public_subnet_ids, private_subnet_ids, azs
│
├── module.security_groups              ← depends on: module.vpc
│       inputs:  vpc_id, frontend_port, backend_port
│       outputs: alb_sg_id, ecs_sg_id, endpoint_sg_id
│
├── module.vpc_endpoints                ← depends on: module.vpc, module.security_groups
│       inputs:  vpc_id, private_subnet_ids, endpoint_sg_id
│       outputs: endpoint_ids (map)
│
├── module.ecr                          ← no vpc deps; global-ish
│       outputs: frontend_repo_url, backend_repo_url
│
├── module.iam                          ← depends on: module.secrets (github_token_secret_arn)
│       inputs:  github_token_secret_arn   # scopes CodeBuild secretsmanager:GetSecretValue
│       outputs: ecs_task_exec_role_arn, ecs_task_role_arn,
│                codebuild_role_arn, ecs_instance_role_arn
│
├── module.secrets                      ← no module deps
│       inputs:  tmdb_api_key, github_token  # sensitive; optional (see §7)
│       outputs: tmdb_api_key_arn, github_token_arn,
│                frontend_url_ssm_arn, backend_url_ssm_arn
│
├── module.s3                           ← no vpc deps
│       outputs: assets_bucket_name, artifacts_bucket_name
│
├── module.dns                          ← no vpc deps (global)
│       outputs: zone_id, acm_cert_arn, cloudfront_cert_arn (ap-south-1)
│
├── module.alb                          ← depends on: module.vpc, module.security_groups, module.dns
│       inputs:  vpc_id, public_subnet_ids, alb_sg_id, acm_cert_arn
│       outputs: frontend_tg_arn, backend_tg_arn, alb_dns_name
│
├── module.ecs_cluster                  ← depends on: module.vpc, module.iam
│       inputs:  private_subnet_ids, ecs_instance_role_arn
│       outputs: cluster_id, cluster_name, asg_name
│
├── module.ecs_service_frontend         ← depends on: module.ecs_cluster, module.alb,
│       inputs:  cluster_id, task_exec_role_arn, task_role_arn,           module.ecr, module.security_groups,
│                frontend_repo_url, frontend_tg_arn, ecs_sg_id            module.cloudwatch
│       outputs: service_name
│
├── module.ecs_service_backend          ← depends on: (same as frontend, backend variant)
│       inputs:  cluster_id, task_exec_role_arn, task_role_arn,
│                backend_repo_url, backend_tg_arn, ecs_sg_id,
│                tmdb_secret_arn
│       outputs: service_name
│
├── module.cloudfront                   ← depends on: module.alb, module.s3, module.dns
│       inputs:  alb_dns_name, assets_bucket_name, acm_cert_arn (ap-south-1)
│       outputs: distribution_id, distribution_domain
│
├── module.codebuild                    ← depends on: module.ecr, module.iam, module.s3,
│       inputs:  frontend_repo_url, backend_repo_url, codebuild_role_arn,     module.secrets, module.alb
│                artifacts_bucket_name, github_token_secret_arn,
│                frontend_api_url (= backend ALB URL, baked as VITE_API_URL)
│       depends_on = [module.secrets]   # webhooks need the populated GitHub token secret
│       outputs: project_names
│
└── module.cloudwatch                   ← depends on: module.ecs_cluster
        inputs:  cluster_name, service_names, alb_arn_suffix
        outputs: dashboard_url, alarm_arns
```

**Build order** (Terraform resolves automatically; shown for clarity):

```
vpc → security_groups → vpc_endpoints
vpc → alb
vpc → ecs_cluster
secrets → iam            (github_token_secret_arn scopes CodeBuild's secret access)
iam → ecs_cluster
iam → codebuild
ecr → ecs_service_*
ecr → codebuild
alb → ecs_service_*
alb → codebuild          (backend ALB URL → frontend VITE_API_URL build arg)
alb → cloudfront
s3  → cloudfront
s3  → codebuild
secrets → codebuild      (GitHub token secret for source auth + webhooks)
dns → alb
dns → cloudfront
ecs_cluster → ecs_service_*
ecs_cluster → cloudwatch
secrets → ecs_service_backend
```

---

## 4. Naming Convention

### Pattern

```
{project}-{environment}-{resource-type}[-{qualifier}]
```

| Token | Values | Notes |
|---|---|---|
| `project` | `starflix` | Fixed. Set via `var.project`. |
| `environment` | `dev` / `stage` / `prod` | Set via `var.environment`. |
| `resource-type` | see table below | Short, readable abbreviation. |
| `qualifier` | `frontend` / `backend` / AZ suffix | Optional; used when multiple of the same type exist. |

### Resource Type Abbreviations

| AWS Resource | Abbreviation | Example |
|---|---|---|
| VPC | `vpc` | `starflix-dev-vpc` |
| Subnet (public) | `pub-{az}` | `starflix-dev-pub-1a` |
| Subnet (private) | `priv-{az}` | `starflix-dev-priv-1a` |
| Internet Gateway | `igw` | `starflix-dev-igw` |
| NAT Gateway | `nat[-{az}]` | `starflix-dev-nat-1a` |
| Elastic IP | `nat-eip[-{az}]` | `starflix-dev-nat-eip-1a` |
| Route Table | `rt-{tier}` | `starflix-dev-rt-public` |
| Security Group (ALB) | `alb-sg` | `starflix-dev-alb-sg` |
| Security Group (ECS) | `ecs-sg` | `starflix-dev-ecs-sg` |
| Security Group (endpoints) | `endpoint-sg` | `starflix-dev-endpoint-sg` |
| Application Load Balancer | `alb-{qualifier}` | `starflix-dev-alb-frontend` |
| Target Group | `tg-{qualifier}` | `starflix-dev-tg-backend` |
| ECS Cluster | `cluster` | `starflix-dev-cluster` |
| ECS Service | `svc-{qualifier}` | `starflix-dev-svc-backend` |
| ECS Task Definition | `td-{qualifier}` | `starflix-dev-td-frontend` |
| Auto Scaling Group | `asg` | `starflix-dev-asg` |
| Launch Template | `lt` | `starflix-dev-lt` |
| ECR Repository | `{qualifier}` | `starflix/frontend` (ECR uses `/`) |
| S3 Bucket | `{project}-{purpose}-{account_id}-{region}` | `starflix-assets-123456789-ap-south-1` |
| IAM Role | `{project}-{environment}-{actor}-role` | `starflix-dev-ecs-task-role` |
| IAM Policy | `{project}-{environment}-{policy-name}-policy` | `starflix-dev-s3-read-policy` |
| Secrets Manager | `{project}/{environment}/{name}` | `starflix/dev/tmdb-api-key` |
| SSM Parameter | `/{project}/{environment}/{name}` | `/starflix/dev/frontend-url` |
| CloudWatch Log Group | `/ecs/{project}/{environment}/{qualifier}` | `/ecs/starflix/dev/backend` |
| CloudFront Distribution | (use description field) | `starflix-dev-cdn` |
| ACM Certificate | (use domain tag) | `starflix-dev-cert` |
| CodeBuild Project | `{project}-{environment}-{qualifier}-build` | `starflix-dev-backend-build` |

### Rules

1. All lowercase, hyphens only — no underscores in AWS resource names.
2. Terraform identifiers (locals, variables, resource labels) use `snake_case`.
3. S3 bucket names include `account_id` + `region` suffix — globally unique, no manual bikeshedding.
4. ECR repository names use a slash prefix: `starflix/frontend`, `starflix/backend`.

---

## 5. Tagging Strategy

### Mandatory Tags (enforced via `common_tags` local, merged on every resource)

| Tag Key | Value | Source |
|---|---|---|
| `Project` | `starflix` | `var.project` |
| `Environment` | `dev` / `stage` / `prod` | `var.environment` |
| `ManagedBy` | `terraform` | hardcoded in `locals.tf` |
| `Owner` | `platform-team` | `var.owner` |
| `CostCenter` | `eng-infra` | `var.cost_center` |
| `GitRepo` | `org/starflix-infra` | hardcoded in `locals.tf` |
| `DataClassification` | `internal` | hardcoded in `locals.tf` |

### Optional Tags (added per resource in the `Name = …` merge block)

| Tag Key | Example Value | Applied To |
|---|---|---|
| `Name` | `starflix-dev-vpc` | all named resources |
| `Tier` | `public` / `private` | subnets |
| `Service` | `frontend` / `backend` | ECS services, task defs |
| `AutoScaling` | `true` | ASG, launch templates |

### Tagging Pattern in Code

```hcl
tags = merge(var.tags, {
  Name    = "${var.name_prefix}-vpc"
  # resource-specific tags only below this line
})
```

`var.tags` is always `local.common_tags` passed from the environment root — modules never construct tags from scratch.

### Cost Allocation

- All cost allocation reports are filtered by `Project` + `Environment`.
- `CostCenter` maps to the FinOps team's chart of accounts.
- Dev resources show `Environment = dev`; isolated billing per environment is achieved with a single tag filter rather than separate AWS accounts.

---

## 6. Feature Flag Strategy

Feature flags live in `locals.tf` of each environment root under the `features` map. They control infrastructure-level behavior (not application feature toggles).

### Current Flags

```hcl
features = {
  single_nat_gateway    = var.single_nat_gateway   # bool
}
```

### Full Flag Catalogue (planned)

| Flag | Type | Dev | Stage | Prod | Effect |
|---|---|---|---|---|---|
| `single_nat_gateway` | bool | `true` | `false` | `false` | 1 NAT Gateway vs 1 per AZ |
| `enable_cloudfront` | bool | `false` | `true` | `true` | deploy CloudFront distribution |
| VPC endpoints | (always on) | `true` | `true` | `true` | ECR/SSM/CW interface + S3 gateway endpoints — deployed in dev today |
| `enable_waf` | bool | `false` | `false` | `true` | attach WAF ACL to CloudFront |
| `enable_deletion_protection` | bool | `false` | `false` | `true` | ALB deletion protection |
| `enable_container_insights` | bool | `false` | `true` | `true` | ECS Container Insights |
| `multi_az_ecs` | bool | `false` | `true` | `true` | ECS tasks spread across AZs |
| `enable_backup` | bool | `false` | `false` | `true` | AWS Backup plans for S3 |

### Usage in Modules

Flags are passed to modules as explicit variables, not the `features` map itself:

```hcl
module "vpc" {
  single_nat_gateway = local.features.single_nat_gateway
}
```

Modules receive typed booleans — they never read `local.features` directly. This keeps modules self-contained and testable.

### Promotion Process

A flag starts as `false` in dev, validated in stage, then enabled in prod via a PR that updates `terraform.tfvars`. No flag is removed without a two-environment soak period.

---

## 7. State Management Strategy

### Backend

| Item | Value |
|---|---|
| Backend type | S3 + native lock file (`use_lockfile = true`) |
| Bucket | `starflix-tfstate-{account_id}-ap-south-1` |
| Bucket versioning | enabled (30-day noncurrent version retention) |
| Bucket encryption | SSE-S3 (default) — upgrade to SSE-KMS for prod |
| Public access | blocked on all four ACL dimensions |
| Replication | cross-region to `ap-southeast-1` for prod only |

### State File Layout

```
s3://starflix-tfstate-{account_id}-ap-south-1/
├── bootstrap/terraform.tfstate
├── dev/terraform.tfstate
├── stage/terraform.tfstate
└── prod/terraform.tfstate
```

### Locking

Terraform 1.10+ native S3 locking via a `.tflock` companion object. No DynamoDB table required. Each environment root has `use_lockfile = true` in its `backend "s3"` block.

### Remote State Sharing

Modules are the primary sharing mechanism — outputs flow through module calls, not `terraform_remote_state`. The `terraform_remote_state` data source is reserved for cross-root references where modules cannot be used (e.g., reading `bootstrap/` outputs).

### State Access IAM Policy (applied to CI role)

```
s3:GetObject, s3:PutObject, s3:DeleteObject  → arn:aws:s3:::starflix-tfstate-*/
s3:ListBucket                                 → arn:aws:s3:::starflix-tfstate-*
s3:GetBucketVersioning                        → arn:aws:s3:::starflix-tfstate-*
```

### Sensitive State Data

The `secrets` module supports **two modes** per secret:

1. **Terraform-managed (current dev)** — pass the value via a `sensitive` variable
   (`tmdb_api_key`, `github_token`, sourced from a gitignored `terraform.tfvars`
   or `TF_VAR_*`). The module creates an `aws_secretsmanager_secret_version`, and
   the value **does land in Terraform state**. This is acceptable here because the
   state bucket is encrypted (SSE-S3) and access-controlled.
2. **Out-of-band** — leave the variable empty; the module creates only the secret
   *container* (no version), and the value is set later via the AWS CLI/console.
   The value then never enters state.

> Trade-off: dev currently uses mode (1) for convenience, so the TMDB key and
> GitHub token are present in the encrypted `dev/terraform.tfstate`. For stronger
> isolation (e.g. prod), prefer mode (2) and inject values out-of-band.

ECS task definitions still reference secrets **by ARN only** via `valueFrom`; the
plaintext is injected into the container by the ECS agent at start, not embedded
in the task definition. Note: because the TMDB key is optional, the backend task
only mounts the `TMDB_API_KEY` secret when a value exists — otherwise it falls
back to placeholder images and the task starts cleanly.

---

## 8. Environment Strategy

### Three Environments

| Dimension | dev | stage | prod |
|---|---|---|---|
| Purpose | rapid iteration | pre-release validation | live traffic |
| AWS Account | shared dev account | dedicated stage account | dedicated prod account |
| Region | `ap-south-1` | `ap-south-1` | `ap-south-1` |
| VPC CIDR | `10.0.0.0/16` | `10.1.0.0/16` | `10.2.0.0/16` |
| AZs | 2 | 2 | 3 |
| NAT Gateways | 1 (single flag) | 2 (1 per AZ) | 3 (1 per AZ) |
| ECS instance type | `t3.small` | `t3.medium` | `t3.large` |
| ECS desired count | 1 | 2 | 3 |
| CloudFront | disabled | enabled | enabled |
| WAF | disabled | disabled | enabled |
| Deletion protection | disabled | disabled | enabled |
| State file key | `dev/terraform.tfstate` | `stage/terraform.tfstate` | `prod/terraform.tfstate` |
| Apply trigger | push to `main` | manual / PR merge | manual + approval gate |
| Auto-destroy | nightly schedule (cost) | never | never |

### Promotion Model

```
developer branch
        │  PR + review
        ▼
    main branch  ──►  CodeBuild (dev apply, automated)
                              │
                              │  release tag (vX.Y.Z)
                              ▼
                        stage apply (manual trigger)
                              │
                              │  stakeholder sign-off
                              ▼
                         prod apply (manual + 2-person approval)
```

### Per-Environment `terraform.tfvars` (committed as `.example`)

```hcl
# environments/prod/terraform.tfvars.example
environment          = "prod"
aws_region           = "ap-south-1"
vpc_cidr             = "10.2.0.0/16"
public_subnet_cidrs  = ["10.2.1.0/24", "10.2.2.0/24", "10.2.3.0/24"]
private_subnet_cidrs = ["10.2.11.0/24", "10.2.12.0/24", "10.2.13.0/24"]
single_nat_gateway   = false
owner                = "platform-team"
cost_center          = "eng-infra"
```

---

## 9. Security Model

### IAM Role Inventory

| Role | Assumed By | Permissions (summary) |
|---|---|---|
| `starflix-{env}-ecs-task-exec-role` | ECS agent | Pull from ECR, write to CloudWatch Logs, read Secrets Manager ARNs |
| `starflix-{env}-ecs-task-role` | Application container | Read S3 assets bucket (GetObject), SSM GetParameter for app config |
| `starflix-{env}-ecs-instance-role` | EC2 ECS host | `AmazonEC2ContainerServiceforEC2Role` managed policy + SSM agent |
| `starflix-{env}-codebuild-role` | CodeBuild | Push to ECR, update ECS service, read/write S3 artifacts bucket, `secretsmanager:GetSecretValue` on the GitHub token secret (source auth + webhooks) |
| `starflix-{env}-terraform-ci-role` | GitHub Actions (OIDC) | Scoped `terraform plan` / `apply` on env-specific resources only |
| `starflix-bootstrap-admin-role` | Human operator (MFA) | Full access to bootstrap resources; not used in CI |

### Least-Privilege Principles

1. **Task exec role ≠ task role.** The exec role pulls images and writes logs; the task role is what the application code uses. Separate concerns.
2. **No `*` actions.** All IAM policies use explicit action lists. `s3:*` is never used.
3. **No inline policies.** All policies are `aws_iam_policy` resources with `aws_iam_role_policy_attachment`.
4. **No long-lived keys.** CodeBuild and GitHub Actions authenticate via IAM roles (OIDC for GitHub). No `AWS_ACCESS_KEY_ID` secrets stored in CI.

### Secrets Management

| Secret | Store | Rotation |
|---|---|---|
| `TMDB_API_KEY` | Secrets Manager (`starflix/{env}/tmdb-api-key`) | manual; alert at 90 days |
| GitHub token (CodeBuild source auth) | Secrets Manager (`starflix/{env}/github-token`) — JSON `{ServerType, AuthType, Token}`, scopes `repo` + `admin:repo_hook` | manual |
| Future DB password | Secrets Manager | automated via Lambda rotation |
| SSM parameters (non-sensitive config) | SSM Parameter Store | N/A |

ECS task definitions reference secrets by ARN only — the plaintext value is injected at container start by the ECS agent, not stored in the task definition. See §7 for the state-vs-out-of-band trade-off (dev currently stores TMDB/GitHub values in encrypted state for convenience).

### Encryption

| Data | Encryption |
|---|---|
| S3 tfstate bucket | SSE-S3 (dev/stage), SSE-KMS with customer CMK (prod) |
| S3 assets bucket | SSE-S3 |
| Secrets Manager | AWS-managed KMS key (dev/stage), CMK (prod) |
| EBS volumes (ECS hosts) | encrypted at launch template level |
| ALB → ECS traffic | HTTPS within VPC (optional); plain HTTP acceptable within SG boundary |
| Internet → ALB | HTTPS only; HTTP listener redirects 301 to HTTPS |

### Network Security Layers

1. **Security Groups** — stateful; ALB SG allows only 80/443 inbound; ECS SG allows only from ALB SG on container ports.
2. **VPC Endpoints** — ECR, Secrets Manager, SSM, CloudWatch Logs traffic stays on the AWS backbone; never traverses NAT Gateway.
3. **WAF (prod only)** — AWS managed rule groups: `AWSManagedRulesCommonRuleSet`, `AWSManagedRulesKnownBadInputsRuleSet`; rate limit: 2000 req/5 min per IP.
4. **S3 Bucket Policy** — assets bucket allows `s3:GetObject` from CloudFront OAC only; no public `GetObject`.
5. **ACM** — TLS 1.2 minimum policy on ALB; TLS 1.2 minimum on CloudFront.

### Compliance Controls

- `DataClassification = internal` tag on all resources.
- CloudTrail enabled at account level (out-of-scope for this Terraform repo; managed by org-level governance).
- AWS Config rules (recommended, org-level): `restricted-ssh`, `s3-bucket-public-read-prohibited`, `encrypted-volumes`.

---

## 10. Network Design

### CIDR Allocation

| Environment | VPC | Public Subnets | Private Subnets |
|---|---|---|---|
| dev | `10.0.0.0/16` | `10.0.1.0/24`, `10.0.2.0/24` | `10.0.11.0/24`, `10.0.12.0/24` |
| stage | `10.1.0.0/16` | `10.1.1.0/24`, `10.1.2.0/24` | `10.1.11.0/24`, `10.1.12.0/24` |
| prod | `10.2.0.0/16` | `10.2.1.0/24`, `10.2.2.0/24`, `10.2.3.0/24` | `10.2.11.0/24`, `10.2.12.0/24`, `10.2.13.0/24` |

The `10.x` second-octet aligns with environment index. `1x` third-octet = private; `0x` = public. Leaves `10.x.20–254` free for future tiers (data, management).

### Subnet Tiers

```
Public Tier  (internet-routable via IGW)
  └── ALB frontend  (port 80 → 443 redirect, HTTPS to ECS)
  └── ALB backend   (port 4000, public-facing)
  └── NAT Gateway EIPs

Private Tier  (outbound via NAT Gateway)
  └── ECS EC2 hosts (EC2 launch type)
  └── VPC Interface Endpoints
```

No database tier yet (in-memory store). When a persistent DB is added, a third `/24` subnet range is reserved: `10.x.21–22` per AZ.

### Routing

| Subnet Type | Route | Next Hop |
|---|---|---|
| Public | `0.0.0.0/0` | Internet Gateway |
| Private | `0.0.0.0/0` | NAT Gateway (same AZ in prod; shared in dev) |
| Private | AWS service prefixes | VPC Gateway / Interface Endpoints |

### VPC Endpoints

Deployed in private subnets to eliminate NAT Gateway data-processing charges for AWS API calls:

| Endpoint | Type | Services |
|---|---|---|
| `com.amazonaws.ap-south-1.ecr.dkr` | Interface | ECR image pulls |
| `com.amazonaws.ap-south-1.ecr.api` | Interface | ECR API calls |
| `com.amazonaws.ap-south-1.s3` | Gateway | S3 (no SG required) |
| `com.amazonaws.ap-south-1.secretsmanager` | Interface | Secrets Manager |
| `com.amazonaws.ap-south-1.ssm` | Interface | SSM Parameter Store |
| `com.amazonaws.ap-south-1.logs` | Interface | CloudWatch Logs |

VPC endpoints are guarded by `starflix-{env}-endpoint-sg` (HTTPS/443 from `ecs-sg` only).

### Traffic Flow — Inbound Request

**Target design (CloudFront enabled — stage/prod):**

```
Client
  ├─► CloudFront  (HTTPS, TLS 1.2+, WAF in prod)
  │     ├─► S3 (OAC)             — static assets (posters, JS, CSS)
  │     └─► ALB (frontend)       — React app (nginx, port 80/443)
  │           └─► ECS frontend task (EC2 launch type)
  │
  └─► ALB (backend) [public-facing, port 4000]
        └─► ECS backend task (EC2 launch type)
              └─► Secrets Manager (TMDB key, via VPC endpoint)
              └─► TMDB API (via NAT Gateway → internet)
```

**Current dev flow (no CloudFront; browser-direct API — see §0):**

```
Browser
  ├─HTTP─► ALB (frontend) :80    — static SPA (React/nginx)
  │            └─► ECS frontend task
  │
  └─HTTP─► ALB (backend) :4000   — API, called DIRECTLY by the browser
               │                    (VITE_API_URL baked into the SPA; CORS-allowed)
               └─► ECS backend task
                     └─► Secrets Manager (TMDB key, via VPC endpoint)
                     └─► TMDB API (via NAT Gateway → internet)
```

> Why not nginx-proxied `/api` in dev: the frontend runs in a private subnet and
> cannot reach the internet-facing backend ALB via NAT hairpin (→ 504). The
> browser-direct approach sidesteps this. Details: `docs/frontend-backend-504-fix.md`.

### NAT Gateway HA Model

| Environment | NAT Count | Failure Domain |
|---|---|---|
| dev | 1 (shared) | all private subnets lose outbound if AZ with NAT fails |
| stage | 2 (1 per AZ) | AZ-isolated; one failure leaves one AZ operational |
| prod | 3 (1 per AZ) | AZ-isolated; two failures still leave one AZ operational |

Controlled by `local.features.single_nat_gateway` → `var.single_nat_gateway` in the `vpc` module.

### DNS Strategy

```
Route 53 Hosted Zone: starflix.com
  ├── A (alias)   starflix.com            → CloudFront distribution
  ├── A (alias)   www.starflix.com        → CloudFront distribution
  └── CNAME       api.starflix.com        → backend ALB (public-facing, port 4000)

ACM Certificate (ap-south-1):  *.starflix.com, starflix.com   → ALB
ACM Certificate (ap-south-1):   *.starflix.com, starflix.com   → CloudFront (must be ap-south-1)
```

---

## Implementation Order

Given the dependency graph, implement modules in this sequence:

| Phase | Modules | Gate |
|---|---|---|
| 0 | `bootstrap/` | Manual apply; s3 bucket + lock in place |
| 1 | `vpc`, `security-groups` | Network foundation |
| 2 | `vpc-endpoints`, `iam`, `ecr`, `s3` | Supporting services |
| 3 | `alb`, `dns`, `secrets` | Traffic entry + config |
| 4 | `ecs-cluster`, `ecs-service-frontend`, `ecs-service-backend` | Compute |
| 5 | `cloudfront` | CDN layer |
| 6 | `codebuild`, `cloudwatch` | CI/CD + observability |

---

*Last updated: 2026-07-02. Maintained by the Platform Team.*
*Design doc reflects the target architecture; §0 tracks the live `dev` deployment.*
