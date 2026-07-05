# Starflix Infrastructure — Walkthrough

**Audience**: this doc assumes zero Terraform experience. If you already know Terraform, read `ARCHITECTURE.md` instead — it's the terse reference version of everything explained here.

**What this covers**: what Terraform is and why we use it, what AWS infrastructure this repo builds, how to read the code module by module, the exact commands to run it, a real incident we hit and fixed, and a prioritized list of what's missing or risky today.

---

## 1. Terraform in plain English

Terraform is a tool that turns text files into cloud infrastructure. You describe *what you want to exist* (a server, a network, a load balancer), and Terraform figures out *how to make it exist* on AWS — in what order, using which API calls, and how to change it later without starting over.

A few words you'll see everywhere in this repo, explained once:

| Term | What it means | Where you see it here |
|---|---|---|
| **Provider** | A plugin that knows how to talk to a specific cloud/API. | `provider "aws" { region = ... }` in `providers.tf` |
| **Resource** | One real thing Terraform creates and tracks — a VPC, an EC2 instance, an S3 bucket. | `resource "aws_vpc" "this" { ... }` |
| **Module** | A reusable folder of resources with inputs (variables) and outputs — like a function. | `terraform/modules/vpc/`, `terraform/modules/ecs-service/`, etc. |
| **Root module / environment** | The top-level folder you actually run `terraform` in. It wires modules together. | `terraform/environments/dev/` |
| **Variable** | An input to a module or the root config. | `variable "vpc_cidr" { ... }` |
| **Output** | A value a module hands back to whoever called it (e.g. an ALB's DNS name). | `output "vpc_id" { value = ... }` |
| **State file** | Terraform's private database of "what I created last time and its exact settings." Without it, Terraform can't tell a resource apart from one that doesn't exist yet. | Stored in S3 — see §4 |
| **Plan** | A dry-run: "if you apply this, here's exactly what will change." Nothing touches AWS yet. | `terraform plan` |
| **Apply** | Actually creates/changes/destroys resources to match the code. | `terraform apply` |

**The core loop, every time**: edit `.tf` files → `terraform plan` (review the diff) → `terraform apply` (commit the diff to real AWS resources). Terraform is *declarative* — you never write "create a VPC, then a subnet, then...". You just describe the end state; Terraform diffs it against the state file and figures out the steps and their order.

---

## 2. What are we actually building?

Starflix has two application halves — a React frontend and an Express backend (see the main `CLAUDE.md` for the app itself). This Terraform stack builds everything those two containers need to run on AWS: networking, compute, load balancers, a container registry, CI/CD, secrets, and monitoring.

### The shape of it (today, in `dev`)

```
                         Internet
                             │
             ┌───────────────┴────────────────┐
             │                                 │
    ┌────────▼─────────┐             ┌─────────▼────────┐
    │  Frontend ALB     │             │  Backend ALB      │
    │  (public, :80)    │             │  (public, :4000)  │
    └────────┬──────────┘             └─────────┬────────┘
             │                                   │
      ══════ │ ══════ VPC (10.0.0.0/16) ═════════│ ══════
             │  private subnets                  │
    ┌────────▼──────────┐             ┌──────────▼────────┐
    │ ECS task: frontend │             │ ECS task: backend  │
    │ nginx + React SPA  │             │ Express API         │
    └────────────────────┘             └─────────┬───────────┘
                                                  │
                                        Secrets Manager (TMDB key)
                                        + TMDB API (internet, via NAT)

    Both ECS tasks run on the SAME small pool of EC2 instances
    (an Auto Scaling Group), managed by one ECS cluster.
```

**Important quirk you should know before anything else**: the browser talks to *both* ALBs directly. The React app doesn't call `/api/...` on its own origin and let nginx proxy it — instead, the backend's public URL is baked straight into the JavaScript bundle at build time (as `VITE_API_URL`), so the browser fetches `http://abhishek-backend.1020dev.com:4000/api/...` directly. Section 10 walks through why, via a real bug we just fixed.

### Request flow, plain English

1. You open `http://abhishek-frontend.1020dev.com/` → hits the **frontend ALB** → forwards to an ECS task running **nginx**, which serves the built React app (static HTML/JS/CSS).
2. The React app's JS makes `fetch()` calls straight to `http://abhishek-backend.1020dev.com:4000/api/...` → hits the **backend ALB** → forwards to an ECS task running **Express**, which returns JSON (movies/shows data, held in memory, optionally enriched with real poster art from TMDB on startup).

---

## 3. Repository tour

```
terraform/
├── ARCHITECTURE.md              # terse reference doc (target design + dev snapshot)
├── Walkthrough.md               # ← you are here
├── docs/                        # deep-dives on specific problems already solved
│   ├── teardown-runbook.md      #   how to safely `terraform destroy` this stack
│   ├── frontend-backend-504-fix.md  # why the browser calls the backend directly
│   ├── dns-and-tls.md
│   └── prerequisites.md
├── scripts/
│   └── destroy.sh                # safe teardown wrapper (see §9)
│
├── bootstrap/                    # run ONCE per AWS account, by hand — not part of normal workflow
│   └── main.tf                   #   creates the S3 bucket that holds Terraform's state file
│
├── modules/                      # reusable building blocks — no environment-specific values live here
│   ├── vpc/                Networking: VPC, subnets, NAT gateways, route tables
│   ├── security-groups/    Firewall rules between ALB ↔ ECS ↔ VPC endpoints
│   ├── vpc-endpoints/      Private AWS API access (skip the public internet for ECR/SSM/Secrets/Logs)
│   ├── ecr/                Docker image registries (frontend + backend)
│   ├── iam/                Roles/permissions for ECS tasks, EC2 hosts, CodeBuild
│   ├── secrets/            Secrets Manager (TMDB key, GitHub token) + SSM parameters
│   ├── alb/                Load balancers + listeners + target groups (frontend + backend)
│   ├── ecs-cluster/        The EC2 fleet that runs containers (Auto Scaling Group)
│   ├── ecs-service/        A task definition + service (used twice: once per app)
│   ├── codebuild/          CI: builds Docker images on git push, deploys to ECS
│   ├── cloudwatch/         Dashboards + alarms
│   ├── s3/                 Buckets for build artifacts and (future) media assets
│   ├── dns/                Route 53 + ACM certificates (OFF in dev today)
│   └── cloudfront/         CDN in front of everything (OFF in dev today)
│
└── environments/
    ├── dev/                 ← the only environment actually deployed right now
    │   ├── main.tf          Wires all the modules above together
    │   ├── variables.tf     Every input this environment accepts, with defaults
    │   ├── terraform.tfvars # YOUR actual values (gitignored — never committed)
    │   ├── terraform.tfvars.example  # template to copy
    │   ├── locals.tf        Computed values (naming prefix, tags, feature flags)
    │   ├── backend.tf       Where this environment's state file lives in S3
    │   ├── providers.tf     AWS provider + region config
    │   └── outputs.tf       Values printed after apply (ALB DNS names, etc.)
    ├── stage/                (scaffolded, not deployed)
    └── prod/                 (scaffolded, not deployed)
```

**Why split into modules?** Each module is self-contained and reusable — `modules/ecs-service` doesn't know or care whether it's building "frontend" or "backend"; `environments/dev/main.tf` calls it twice with different inputs. This is why adding `stage` or `prod` later mostly means copying `environments/dev/*.tf` and changing the `.tfvars` file, not rewriting logic.

**Why is `dev` the only thing running?** `stage`/`prod` folders exist as scaffolding for the target design but were never applied — everything described from here on is about the live `dev` environment in AWS account `882282737240`, region `ap-south-1`.

---

## 4. The state backend (why `bootstrap/` exists)

Terraform needs somewhere to store its state file — the record of what it has already built. `terraform/bootstrap/` creates that home:

- An **S3 bucket** (`starflix-tfstate-882282737240-ap-south-1`) — versioned, encrypted, no public access. This is where `dev/terraform.tfstate` (and eventually `stage/`, `prod/`) live.
- A **DynamoDB table** (`starflix-tfstate-locks`) — originally intended for state locking, so two people can't `apply` at the same time and corrupt the state. *(Note: see §12 — this table is actually unused today; `environments/dev/backend.tf` uses Terraform's newer native S3 locking instead. Flagged as cleanup.)*

You run `bootstrap/` **once per AWS account**, manually, before anything else:

```bash
cd terraform/bootstrap
terraform init
terraform apply
```

After that you never touch `bootstrap/` again unless you're setting up a brand-new AWS account.

---

## 5. Module-by-module walkthrough

This is the order Terraform actually builds things in (`main.tf` declares them in roughly this sequence, and Terraform's dependency graph enforces the rest automatically — you never have to think about ordering yourself).

### 5.1 `vpc` — the network
Creates a private network (`10.0.0.0/16`) with 2 **public** subnets (where the load balancers live — reachable from the internet) and 2 **private** subnets (where the actual application servers live — not directly reachable). A **NAT Gateway** lets private-subnet resources reach the internet (e.g. to pull Docker images or call the TMDB API) without being reachable *from* the internet themselves.

> Analogy: public subnets are the building's front desk; private subnets are the offices behind it. Visitors go through the front desk; employees can leave the building through a side door (NAT) but strangers can't walk in through it.

Dev uses **one shared NAT Gateway** (`single_nat_gateway = true`) to save money — cheaper, but if that NAT Gateway's availability zone has an outage, all outbound internet access breaks. Stage/prod would use one per AZ.

### 5.2 `security-groups` — the firewall rules
Three groups of rules:
- **ALB security group**: accepts inbound HTTP(S) from the entire internet (`0.0.0.0/0`), only on ports 80, 443, and 4000.
- **ECS security group**: only accepts traffic *from the ALB security group* — never directly from the internet. This is the important one: even though the underlying EC2 host has a private IP, nothing gets to your containers except through the load balancer.
- **VPC endpoint security group**: only accepts HTTPS from the ECS security group.

### 5.3 `vpc-endpoints` — skipping the public internet for AWS API calls
Without this, every time an ECS task needs to pull a Docker image, write a log, or read a secret, that traffic would have to go out through the NAT Gateway to the public AWS API endpoint and back — costing money (NAT charges per GB) and adding a dependency on internet reachability. VPC endpoints create a private, direct pipe from the VPC straight to ECR, Secrets Manager, SSM, and CloudWatch Logs.

### 5.4 `ecr` — Docker image storage
Two private registries — `starflix-dev/frontend` and `starflix-dev/backend`. CodeBuild pushes images here; ECS pulls from here. A lifecycle policy auto-deletes anything past the newest 20 images per repo, so storage cost doesn't grow forever.

### 5.5 `iam` — who's allowed to do what
Four roles, each with a distinct job (this separation matters — see §12 for where it's *not* as tight as it should be):
- **ECS task execution role**: used by the ECS *agent* to pull images and write logs/secrets on the container's behalf.
- **ECS task role**: used by *your application code* inside the container (e.g. to read S3).
- **EC2 instance role**: attached to the EC2 hosts themselves, so they can register with the ECS cluster.
- **CodeBuild role**: lets CI push images to ECR, read the GitHub token, and trigger ECS deployments.

### 5.6 `secrets` — API keys and tokens
Stores the **TMDB API key** (for real movie poster art) and the **GitHub personal access token** (so CodeBuild can pull source code and register webhooks) in AWS Secrets Manager. Values come from your `terraform.tfvars` file (gitignored) — never hardcoded in `.tf` files, never committed to git.

### 5.7 `alb` — the load balancers
Creates **two separate, independent Application Load Balancers** — one for the frontend, one for the backend — each with its own listener and target group. In dev, both listen on plain HTTP (frontend on :80, backend on :4000); if a certificate is provided (via the `dns` module), the frontend gains an HTTPS listener and redirects HTTP → HTTPS.

### 5.8 `ecs-cluster` — the compute fleet
This is **EC2 launch type**, not Fargate — meaning Terraform provisions actual EC2 virtual machines (an Auto Scaling Group, `t3.small` in dev) that register themselves with the ECS cluster, and containers get scheduled onto whichever host has room. A "capacity provider" ties the ASG to ECS so the ASG can grow/shrink automatically based on how full the cluster is.

> Why EC2 instead of Fargate? Fargate is simpler (no servers to manage) but costs more per unit of compute and can't be as finely tuned. This repo intentionally chose EC2 — see `deploy.md` at the repo root for the *older*, Fargate-based deployment guide that predates this Terraform stack and is now out of date (flagged in §12).

### 5.9 `ecs-service` — one task definition + service (used twice)
This module doesn't know about "frontend" or "backend" — `environments/dev/main.tf` calls it twice with different `container_image`, `container_port`, and `environment_variables`. Each call creates:
- A **task definition** — the recipe for one container (image, CPU/memory, env vars, health check).
- A **service** — keeps N copies of that task running, restarts crashed ones, and registers healthy ones with the ALB target group.

### 5.10 `codebuild` — CI/CD
Two CodeBuild projects (frontend, backend), each with a **GitHub webhook** scoped to only fire when files under `frontend/` or `backend/` change on a push to `main`. On trigger: build the Docker image → push to ECR → `aws ecs update-service --force-new-deployment` (tells ECS "go re-pull the image and roll the service"). See §8 for the full day-2 flow.

### 5.11 `cloudwatch` — dashboards and alarms
A dashboard showing CPU/memory/5xx/response-time/healthy-host-count for both services, plus metric alarms on each of those. *(Alarms currently have nowhere to send notifications — see §12.)*

### 5.12 `dns` and `cloudfront` — built, but switched off
Both modules are fully written (Route 53 hosted zone + ACM certs; CloudFront CDN with S3/ALB origins) but gated behind `enable_dns` / `enable_cloudfront` feature flags, both `false` in dev today. This is why dev serves plain HTTP over raw ALB DNS names instead of `https://starflix.com`.

---

## 6. Configuration — variables and `terraform.tfvars`

Every tunable value lives in `environments/dev/variables.tf` (with sane defaults) and gets overridden per-environment in `terraform.tfvars` (gitignored — **never commit real values**; only `terraform.tfvars.example` is checked into git).

A few variables worth understanding by name, because they caused a real production issue (§10):

| Variable | What it does | Gotcha |
|---|---|---|
| `public_frontend_url` | The public URL people use to reach the frontend. Baked into the **backend** as `FRONTEND_URL`, used for CORS. | Must include the `http://`/`https://` scheme — a bare hostname breaks CORS origin matching. |
| `public_backend_url` | The public URL of the backend API. Baked into the **frontend build** as `VITE_API_URL` at Docker build time. | Must include the scheme *and port*. Missing the scheme makes the browser treat it as a relative path instead of an absolute URL — this is exactly what broke on 2026-07-05 (§10). Changing this value requires a **frontend rebuild**, not just `terraform apply` — see §8. |
| `enable_dns` / `enable_cloudfront` | Turn on Route 53 + ACM + CloudFront. | Off in dev; flip these to move toward the "target design" in `ARCHITECTURE.md`. |
| `ecs_desired_capacity` | How many EC2 hosts run in the cluster. | Currently `1` — a single host is a single point of failure (§12). |
| `enable_service_autoscaling` | Whether ECS task count scales with CPU/memory. | `true` in the current `terraform.tfvars`, `false` in the example template — don't assume the example reflects reality. |

---

## 7. Running it for the first time

```bash
# 0. One-time per AWS account (skip if bootstrap/ was already applied)
cd terraform/bootstrap
terraform init && terraform apply

# 1. Configure AWS credentials for your shell
aws configure                       # or export AWS_PROFILE=...
aws sts get-caller-identity         # sanity check — confirms who Terraform will act as

# 2. Set up your environment's variables
cd terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars            # fill in domain, github_repo_url, etc.
                                     # github_token / tmdb_api_key can be passed via
                                     # TF_VAR_github_token / TF_VAR_tmdb_api_key instead
                                     # of sitting in the file, if you prefer.

# 3. Download providers/modules, then preview the plan
terraform init
terraform plan -out=tfplan          # review EVERY line before the next step

# 4. Apply — this is the step that actually creates AWS resources
terraform apply "tfplan"
```

What happens during that first `apply`, concretely: Terraform builds the VPC → security groups → ALBs → ECS cluster (EC2 instances take a few minutes to boot and register) → then a special one-time step (`null_resource.seed_images`) triggers **both** CodeBuild projects and **waits** (via a local script, using your machine's AWS CLI) for them to finish building and pushing the first images to ECR — this can take several minutes and your terminal will look like it's "stuck," but it's actually waiting on CodeBuild logs. Only after images exist does Terraform create the ECS services, so they don't crash-loop on an empty registry.

At the end, `terraform output` prints the frontend/backend ALB DNS names — that's your app's URL until you set up a custom domain.

---

## 8. Day-2 operations — how changes actually ship

There are **two independent update paths** in this repo, and mixing them up is the most common source of confusion:

### Path A — Application code changes (most common)
```
git push origin main  (touching frontend/ or backend/)
        │
        ▼
GitHub webhook fires the matching CodeBuild project
        │
        ▼
CodeBuild: docker build → push to ECR (tags: git-sha AND :latest)
        │
        ▼
CodeBuild: aws ecs update-service --force-new-deployment
        │
        ▼
ECS performs a rolling deploy of the new image
```
This needs **no Terraform involvement at all**. Terraform only had to exist once to create the CodeBuild projects and webhooks.

### Path B — Infrastructure changes (this repo's `.tf` files, or `terraform.tfvars`)
```
edit terraform.tfvars or a .tf file
        │
        ▼
terraform plan -out=tfplan     # ALWAYS read this diff before applying
        │
        ▼
terraform apply "tfplan"
```

**The trap**: some `.tfvars` values (like `public_backend_url`) only take effect through Path A, because they're baked into the CodeBuild project's environment variables and only get *used* the next time an image is built. Running `terraform apply` alone updates the CodeBuild project's configuration, but the container **already running** still has the old build baked in. You must also manually trigger a fresh build:

```bash
aws codebuild start-build --project-name starflix-dev-frontend-build --region ap-south-1
```

This exact gap is what caused the incident in §10.

---

## 9. Tearing it down

**Do not run a bare `terraform destroy`** on this stack — it hangs. ECS-on-EC2 has a chicken-and-egg problem: the ECS *service* won't finish deleting while its EC2 hosts are still registered, but the Auto Scaling Group's managed scaling will keep relaunching those hosts as long as the service still wants tasks running. Full root cause and fix are documented in `docs/teardown-runbook.md`; the short version is to always use the wrapper script, which scales services to 0, suspends the ASG's launch process, scales the ASG to 0, and *then* destroys:

```bash
cd terraform
scripts/destroy.sh dev
```

---

## 10. Case study — the incident we just fixed

This is worth walking through in a presentation because it's a perfect concrete example of "declarative config vs. build-time vs. run-time" — a distinction that trips up almost everyone new to Terraform + Docker + CI/CD together.

**Symptom**: after `terraform apply`, the frontend page showed *"Unable to connect to Starflix API — Unexpected token '<', "<!DOCTYPE "... is not valid JSON."*

**Root cause, step by step**:
1. `terraform.tfvars` had `public_backend_url = "abhishek-backend.1020dev.com:4000"` — no `http://` scheme.
2. `main.tf` passes that value straight through as `VITE_API_URL` to the frontend's CodeBuild project (`frontend_api_url = var.public_backend_url != "" ? var.public_backend_url : ...`) — no scheme gets prepended automatically for a custom value.
3. `frontend/src/api/client.js` does `fetch(`${BASE_URL}${path}`)`. With `BASE_URL` missing a scheme, the *browser* treats the string as a **relative path**, not an absolute URL.
4. So instead of calling the backend, the browser requested a path on the frontend's own nginx server, which doesn't exist — nginx's SPA fallback (`try_files ... /index.html`) served back `index.html` (an HTML document) where JSON was expected.
5. Fixed `terraform.tfvars` to `public_backend_url = "http://abhishek-backend.1020dev.com:4000"`, ran `terraform apply` (updates CodeBuild's env var + the backend's CORS `FRONTEND_URL`) — **but the running frontend container still served the old, broken JS bundle**, because `VITE_API_URL` is baked into the bundle at **Docker build time**, and `terraform apply` doesn't rebuild Docker images.
6. Had to manually run `aws codebuild start-build --project-name starflix-dev-frontend-build`, wait for it to finish, and let ECS roll out the new image before the fix actually took effect in the browser.

**The lesson**: Terraform changes AWS *configuration*. It does not reach inside a running container or rebuild an already-built Docker image. Anything baked in at `docker build` time (like a Vite env var) needs its own rebuild trigger — Terraform updating the *source* of that value isn't enough.

---

## 11. Current state snapshot (dev, as of this writing)

| Area | Status |
|---|---|
| VPC, 2 public + 2 private subnets, 1 shared NAT Gateway | ✅ live |
| ECS cluster, EC2 launch type, `t3.small` | ✅ live |
| Frontend + backend services, each behind their own public ALB | ✅ live |
| HTTPS / custom domain / CloudFront / WAF | ❌ off (`enable_dns`, `enable_cloudfront`, `enable_waf` = false) |
| CI/CD via CodeBuild + GitHub webhooks | ✅ live, path-scoped per service |
| Secrets Manager (TMDB key, GitHub token) | ✅ live, values stored via Terraform (see §12) |
| CloudWatch dashboard + alarms | ✅ live, **no notification target configured** |

---

## 12. Improvements needed

Ranked roughly by impact. These are gaps found by reading the actual code (not hypothetical) — each one is something a reviewer would flag before calling this "production-ready."

### Security
1. **IAM policies are broader than the docs claim.** `ARCHITECTURE.md` states "no `*` actions" and least-privilege throughout, but in practice: the ECS task role's `ssm:GetParameter*` / `secretsmanager:GetSecretValue` statement uses `Resource = "*"`, and CodeBuild's ECR/logs statements do too. Not catastrophic (scoped by *action*, not fully open), but worth tightening to specific ARNs, especially before a `prod` environment exists.
2. **Backend API is plaintext HTTP, open to the whole internet on :4000.** There's no TLS anywhere in dev (expected per `ARCHITECTURE.md`, but worth calling out explicitly) — anything sent to/from the API today is unencrypted in transit and unauthenticated at the edge (no WAF, no rate limiting).
3. **Secrets land in the Terraform state file.** `tmdb_api_key` and `github_token` are passed as Terraform variables, so their plaintext ends up in `dev/terraform.tfstate` (encrypted at rest via SSE-S3, but still readable by anyone with S3 read access to that bucket + key). The `secrets` module already supports an "out-of-band" mode (leave the variable empty, set the value later via CLI) — worth switching to that mode for anything beyond a disposable dev account.
4. **CORS allows exactly one origin string.** `FRONTEND_URL` is a single value; if the API ever needs to serve both an apex and `www.` domain, or multiple environments, this breaks silently.

### Reliability
5. **Single EC2 instance = single point of failure.** `ecs_desired_capacity = 1` means both services likely land on the same host (or a host each, but only one host exists). If that instance dies, both frontend and backend go down simultaneously despite having 2 AZs and 2 subnets provisioned. `service_autoscaling_min` should be ≥ 2 for any environment that needs uptime.
6. **Deploys always target the mutable `:latest` tag.** `buildspec.yml` pushes both a git-sha tag *and* `:latest`, but the ECS task definition (`frontend_image_tag = "latest"`, `backend_image_tag = "latest"`) only ever references `:latest`, and deploys use `--force-new-deployment` rather than registering a new task definition revision. This means: no clean way to roll back to a specific previous build, and no audit trail linking a running task to the git commit that produced it — despite the sha tag already existing in ECR, unused.
7. **CloudWatch alarms have no notification target.** `alarm_actions` defaults to `[]` and nothing in `terraform.tfvars` sets it — alarms will flip to `ALARM` state in the console, but nobody gets paged or emailed. Needs an SNS topic + subscription wired in.
8. **The `null_resource.seed_images` bootstrap step is a fragile one-time hack.** It's a `local-exec` provisioner that shells out to the AWS CLI from whoever's machine runs `terraform apply` — meaning that person needs AWS CLI + bash installed, and if it's ever removed from state without the underlying images existing, there's no automatic re-seed. It also makes a first-time `apply` block for several minutes waiting on an external CI system, which is surprising if you don't know to expect it (now documented in §7, but a Terraform newcomer wouldn't guess it from the code alone).

### Consistency / hygiene
9. **`deploy.md` at the repo root is stale.** It describes a completely different, older deployment approach (manual AWS CLI steps, ECS **Fargate**, a single shared ALB) that no longer matches this Terraform stack (EC2 launch type, two separate ALBs, Terraform-managed everything). Anyone following it today would build the wrong thing. Either delete it or rewrite it to point at this Walkthrough + `ARCHITECTURE.md`.
10. **Provider version mismatch between `bootstrap/` and `environments/dev/`.** Bootstrap pins `hashicorp/aws ~> 5.0`; the dev environment pins `~> 6.0`. Not currently causing problems since they're separate state files and `apply` runs, but it's a landmine for anyone who assumes one version applies repo-wide.
11. **The bootstrap DynamoDB lock table is unused.** `bootstrap/main.tf` creates `starflix-tfstate-locks`, but `environments/dev/backend.tf` uses Terraform's native S3 locking (`use_lockfile = true`) instead of `dynamodb_table = ...`. The table costs effectively nothing (pay-per-request, no traffic) but it's dead code that will confuse the next person who assumes it's load-bearing.
12. **`alb/main.tf`'s backend load balancer comment says "Internal-facing... CloudFront terminates TLS,"** but the resource itself is `internal = false` (public) and CloudFront is off in dev — a leftover comment from an earlier design that no longer matches the code. Small, but the kind of thing that misleads a reader trying to understand the security posture from comments alone.
13. **A stray `tfplan` file was left untracked in `environments/dev/`.** `.gitignore` ignores `*.tfplan` but the convention used here is a bare `tfplan` (no extension), which doesn't match the glob — worth either renaming the convention to `*.tfplan` or adding `tfplan` explicitly to `.gitignore`.

### Cost / scaling (lower priority for dev, relevant before stage/prod)
14. **Single NAT Gateway is a deliberate dev tradeoff** (documented, not a bug) — but it's also a single point of failure for *all* outbound internet access (TMDB calls, image pulls) if that AZ has an issue. Fine for dev; must change before stage/prod (the code already supports this via `single_nat_gateway = false`).
15. **No persistent database.** The backend's data store is entirely in-memory (per `CLAUDE.md`) — this isn't a Terraform gap, but it means every ECS task restart loses any runtime state, and horizontal scaling beyond 1 backend task would serve inconsistent data (each task has its own copy). Worth keeping in mind if `service_autoscaling_max` for the backend is ever raised above 1 in practice.

---

## Quick reference

```bash
# First-time setup (once per account)
cd terraform/bootstrap && terraform init && terraform apply

# Normal workflow
cd terraform/environments/dev
terraform init
terraform plan -out=tfplan
terraform apply "tfplan"

# After changing public_backend_url / public_frontend_url specifically:
aws codebuild start-build --project-name starflix-dev-frontend-build --region ap-south-1

# Safe teardown (never bare `terraform destroy`)
cd terraform && scripts/destroy.sh dev

# Useful checks
terraform output                                   # print ALB DNS names etc.
aws ecs describe-services --cluster starflix-dev-cluster \
  --services starflix-dev-svc-frontend starflix-dev-svc-backend --region ap-south-1
```
