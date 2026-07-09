# Starflix on AWS with Terraform — Demo & Narration Script

> **Audience:** technical (engineers / DevOps / reviewers)
> **Duration:** ~25 min (timings per section; trim the *optional* blocks for a 15-min version)
> **Goal:** show how a real full-stack app is provisioned on AWS with modular Terraform,
> deployed via CI/CD, and auto-scales under load.
>
> Legend — **🎤 SAY** = narration, **🖥️ DO** = what to run/show, **💡 NOTE** = presenter aside.

---

## 0. Before you start (pre-flight checklist — do this offstage)

- [ ] Terminal open at `terraform/environments/dev`, font size bumped for readability.
- [ ] AWS creds active for the demo account (`aws sts get-caller-identity` returns OK).
- [ ] Three terminal tabs ready: **(1)** terraform/commands, **(2)** live monitor, **(3)** git push.
- [ ] Browser tabs: the running **frontend URL**, the **AWS Console** (ECS + CloudWatch), the GitHub repo.
- [ ] `terraform output` works (state is reachable).
- [ ] A trivial code change staged but *not* committed (for the CI/CD demo) — e.g. a text tweak in `frontend/`.
- [ ] A load tool available (`hey`, or `docker run williamyeh/hey`).
- [ ] Confirm autoscaling values in `terraform.tfvars` are the ones you want to show.

**💡 NOTE:** Never show real secrets on screen. `terraform.tfvars` holds a GitHub PAT + TMDB key — keep it closed, or scroll past those lines.

---

## 1. Opening hook  ⏱️ 1 min

**🎤 SAY:**
> "This is **Starflix** — a Netflix-style streaming UI backed by a REST API. But the app isn't
> the interesting part today. What's interesting is that **everything it runs on in AWS — the
> network, the servers, the load balancers, the CI/CD pipeline, the alarms — is defined as code
> in Terraform.** I can destroy the entire environment and rebuild it, identically, with a
> couple of commands. Let me show you how it's built."

**🖥️ DO:** Show the running app in the browser — click a title, open the modal, do a search. ~20 seconds. Set the stage that this is live on AWS.

---

## 2. The app in one line  ⏱️ 1 min

**🎤 SAY:**
> "Two services: a **React + Vite** frontend served by nginx, and an **Express** API backend.
> Both are containerized with Docker and run on **AWS ECS using the EC2 launch type** — so our
> containers run on a small fleet of EC2 instances we manage through Terraform. No database — the
> catalog is in-memory, enriched with real artwork from the TMDB API at startup."

**🖥️ DO:** Briefly show the repo root — `backend/`, `frontend/`, `terraform/`.

---

## 3. Why Terraform — not just click it together by hand?  ⏱️ 2 min

**💡 NOTE:** This is the "why should I care" moment — land it before the technical tour. If the room
is skeptical, spend an extra minute here.

**🎤 SAY:**
> "A fair question: I *could* build all of this by clicking through the AWS console. So why
> Terraform? Because clicking gives you a running environment — but nothing else. Terraform gives
> you the environment **plus** everything around it that actually matters in a team:
>
> - **Reproducible** — I can rebuild this entire stack, identically, in another region or account
>   with one command. A hand-built environment lives and dies once; nobody remembers all 200 clicks.
> - **Version-controlled & reviewable** — every infrastructure change is a Git diff that goes through
>   pull-request review, just like app code. You can see *who* changed the load balancer, *when*, and
>   *why*. Console changes leave no trail.
> - **Safe to change** — `terraform plan` shows me exactly what will change *before* it happens. No
>   'click and pray.'
> - **Consistent across environments** — dev, stage, and prod come from the *same* modules, so they
>   don't silently drift apart. The classic 'it worked in dev' bug largely disappears.
> - **Self-documenting** — the code *is* the documentation. There's no stale wiki describing which
>   boxes were ticked; the repo always reflects reality.
> - **Team-safe** — remote state plus locking means two engineers can't clobber each other.
> - **Drift detection** — if someone hand-edits AWS, `plan` flags it and we can reconcile.
> - **Fast teardown & rebuild** — one command to destroy, one to recreate. Try un-clicking 60
>   resources by hand without leaving orphans running up a bill.
> - **Disaster recovery** — this is the big one. If a region goes down, an account is compromised,
>   or someone deletes something critical, I don't scramble to remember how it was built — I run
>   `terraform apply` against a new region or account and the entire stack comes back **exactly** as
>   defined, in minutes. The code is my recovery plan. A hand-built environment has no recovery plan
>   beyond someone's memory and a lot of pressure.
>
> Manual works for a one-off experiment. The moment more than one person, more than one environment,
> or more than one day is involved, clicking stops scaling. Terraform is how you make infrastructure
> **an asset you can reason about**, not a fragile snowflake."

**🖥️ DO (optional, punchy):** show `git log --oneline` on the terraform folder — "every one of these
is a reviewed infra change," then `terraform plan` later delivers on the "safe to change" promise.

| Manual (console clicks) | Terraform (IaC) |
|---|---|
| One-off; not repeatable | Reproducible with one command |
| No history of who/what/why | Full Git history + PR review |
| Change = click & hope | `plan` previews every change first |
| Environments drift apart | Same modules → consistent envs |
| Knowledge lives in people's heads | Code is the documentation |
| Hard to tear down cleanly | `destroy` removes everything |
| No recovery plan if it's lost | Rebuild anywhere in minutes = built-in DR |

---

## 4. Terraform structure tour  ⏱️ 3 min

**🖥️ DO:**
```bash
cd terraform
ls
tree modules -L 1   # or: ls modules
```

**🎤 SAY:**
> "The Terraform is organized in three layers:
> 1. **`bootstrap/`** — a tiny, run-once stack that creates the **remote state backend**: an S3
>    bucket for the state file and a DynamoDB table for state locking.
> 2. **`environments/dev/`** — the actual environment. This is the root module we `apply`. It wires
>    together modules and holds the environment's variables.
> 3. **`modules/`** — 14 reusable building blocks, one responsibility each: `vpc`, `security-groups`,
>    `alb`, `ecs-cluster`, `ecs-service`, `ecr`, `iam`, `secrets`, `vpc-endpoints`, `s3`, `dns`,
>    `cloudfront`, `cloudwatch`, `codebuild`.
>
> The environment is just **composition** — each module is called once and passed its inputs.
> The same modules can build `stage` and `prod` by adding new environment folders."

**🖥️ DO:** Open `environments/dev/main.tf` and scroll through the module blocks so they see the composition.

---

## 5. Remote state & why it matters  ⏱️ 2 min  *(optional)*

**🖥️ DO:** Open `environments/dev/backend.tf`.

**🎤 SAY:**
> "State lives in **S3**, and a **DynamoDB** lock table prevents two people from applying at the
> same time and corrupting it. This is what makes the setup team-safe and reproducible — the state
> isn't on my laptop. Notice the backend block hardcodes the bucket and region — that's a Terraform
> limitation: backend config can't use variables, so it's the one place we accept a hardcoded value."

---

## 6. Variables & feature flags  ⏱️ 2 min

**🖥️ DO:** Open `environments/dev/terraform.tfvars` (scroll past the secrets) and `readme.md`.

**🎤 SAY:**
> "The whole environment is driven by this one variables file. There's a `readme.md` next to it
> documenting every value. The pattern I want to highlight is **feature flags** — booleans like
> `enable_dns`, `enable_cloudfront`, `enable_waf`, `single_nat_gateway`. Flip one, and an entire
> module switches on or off via Terraform's `count`. That's how one codebase serves a cheap dev
> environment and a hardened prod: dev runs a single NAT gateway with no CloudFront or WAF; prod
> flips those on. Same modules, different flags."

**💡 NOTE:** If asked about secrets — point out they're gitignored and stored in AWS Secrets Manager, injected into tasks at runtime.

---

## 7. Walk the architecture  ⏱️ 5 min

**🖥️ DO:** Keep `main.tf` open; walk top-to-bottom. Optionally show `ARCHITECTURE.md`.

**🎤 SAY (narrate the request path):**
> "Let's follow a user request through the infrastructure the modules build:
> 1. **VPC** — our own network: 2 public subnets (for load balancers + NAT) and 2 private subnets
>    (for the servers), across 2 availability zones.
> 2. **Security groups** — the firewall rules. The ALB is open to the internet; the ECS hosts only
>    accept traffic *from* the ALB.
> 3. **ALB** — two Application Load Balancers, one for the frontend, one for the backend API. They
>    live in the public subnets and forward to the containers.
> 4. **ECS cluster** — an Auto Scaling Group of `t3.small` EC2 hosts, tied to ECS by a **capacity
>    provider**. This is where containers actually run.
> 5. **ECS services** — one per app. Each keeps N copies (tasks) of a container running and
>    registers them with its load balancer.
> 6. **ECR** — private Docker registries the images are pushed to.
> 7. **Secrets Manager** — the TMDB key and GitHub token, injected securely.
> 8. **CloudWatch** — logs, a dashboard, and alarms on CPU, memory, 5xx errors, and latency.
> 9. **CodeBuild** — our CI/CD, which I'll demo shortly.
>
> There are also **VPC endpoints** so the private hosts can reach ECR, Logs, and Secrets without
> routing everything through the NAT gateway."

**💡 NOTE:** Don't read every module — narrate the *path*. Keep it to a couple minutes.

---

## 8. Live: plan & outputs  ⏱️ 3 min

**🖥️ DO:**
```bash
cd environments/dev
terraform plan          # show "No changes" — infra matches code
terraform output        # show real resource IDs / ALB DNS names
```

**🎤 SAY:**
> "`terraform plan` compares my code to what's actually in AWS. Right now it says **no changes** —
> the live environment exactly matches the code. That's the whole promise of IaC: the repo *is* the
> source of truth. And `terraform output` gives me the real resource identifiers — here are the
> live ALB DNS names the app is served from."

**💡 NOTE:** If `plan` shows drift, that's a great teaching moment — explain drift and that `apply` would reconcile it. (Best to pre-check offstage so you know what to expect.)

---

## 9. Live: verify the deployed infra  ⏱️ 2 min  *(optional)*

**🖥️ DO:**
```bash
../../scripts/health-check.sh dev
```

**🎤 SAY:**
> "This is a read-only health-check script that reads the Terraform outputs and then queries AWS
> to confirm each piece actually exists and is healthy — VPC, subnets, ALBs, target health, ECS
> services running vs desired, alarms, and it even does a live HTTP probe of both load balancers.
> Green across the board means the infrastructure Terraform declared is real and serving traffic."

---

## 10. Demo: CI/CD — push to deploy  ⏱️ 3 min

**🖥️ DO:** Open `modules/codebuild/main.tf` briefly (show the webhook filters), then in the git tab:
```bash
# make the pre-staged change visible
git diff
git add -A && git commit -m "demo: tweak frontend copy"
git push origin main
```
Then switch to the AWS Console → CodeBuild → watch the build start.

**🎤 SAY:**
> "CI/CD is also Terraform-managed. CodeBuild registered a **webhook on the GitHub repo**. Watch:
> when I push to `main` with a change under `frontend/`, GitHub fires the webhook, CodeBuild wakes
> up, builds the Docker image, pushes it to ECR tagged with the commit SHA, and then triggers a
> **rolling deploy** on ECS. The filters are path-scoped — a frontend change only rebuilds the
> frontend, a backend change only the backend. No manual deploy steps."

**💡 NOTE:** Builds take a few minutes — either pre-warm one, or keep talking and cut back to it. Have the CodeBuild logs tab ready.

---

## 11. Demo: auto-scaling under load  ⏱️ 3 min

**🖥️ DO (tab 1 — generate load):**
```bash
hey -z 4m -c 300 "http://<backend_alb_dns>:4000/api/content/search?q=iron"
# or: docker run --rm williamyeh/hey -z 4m -c 300 "http://<backend_alb_dns>:4000/..."
```
**🖥️ DO (tab 2 — watch it react):**
```bash
./scripts/loadtest.sh dev        # baseline + live task/host monitor + scaling activities
```

**🎤 SAY:**
> "Two scaling layers are defined in Terraform. First, **service auto-scaling**: when average CPU
> crosses our target, ECS adds another task — another copy of the container. Second, the **capacity
> provider** scales the **EC2 hosts** underneath when the tasks no longer fit. I'll drive load at
> the API and we'll watch the task count climb, and CloudWatch's target-tracking alarm flip from OK
> to ALARM as it scales out."

**💡 NOTE:** Target-tracking has a built-in ~3-minute delay and CloudWatch metrics lag 1–2 min —
say this up front so the wait doesn't look like a failure. If time is tight, **pre-scale it** before
the session and just narrate the already-elevated task count + the scaling-activities history.

---

## 12. Cost awareness  ⏱️ 1 min  *(optional)*

**🖥️ DO:** Open `terraform/docs/COST-ESTIMATE.md`.

**🎤 SAY:**
> "Because it's all declared, we can reason about cost precisely. This doc breaks down the monthly
> spend per resource for dev and projected prod, compares instance sizes, and even models Savings
> Plans. The takeaway: the biggest costs are the 'plumbing' — NAT, VPC endpoints, load balancers —
> not the compute. Knowing that lets us optimize the right things."

---

## 13. Teardown & closing  ⏱️ 1 min

**🎤 SAY:**
> "And because everything is code, cleanup is one command — `terraform destroy`, with a helper
> script that handles ordering. To recap: **one Git repo defines the whole stack** — network,
> compute, load balancing, secrets, CI/CD, monitoring, and auto-scaling. It's reproducible,
> reviewable, team-safe through remote state and locking, and environment-agnostic through feature
> flags. Any change goes through code review and `terraform plan` before it ever touches AWS.
> That's infrastructure as code, end to end. Questions?"

---

## Anticipated Q&A (prep)

Grouped by topic. Each has a **short spoken answer** you can give verbatim, plus a **💡 deeper**
note if they push. Skim these before presenting so nothing catches you flat-footed.

### Terraform / IaC fundamentals

- **"Why Terraform and not CloudFormation / CDK?"**
  Cloud-agnostic, huge provider ecosystem, and a mature module system. The declarative HCL + `plan`
  workflow makes changes reviewable before they touch AWS. CDK/CloudFormation would work too — this
  team standardized on Terraform.

- **"What does `terraform plan` actually do?"**
  It refreshes the real state of AWS, diffs it against the code, and prints exactly what would be
  created / changed / destroyed — without changing anything. It's the safety gate before `apply`.

- **"What if the code and AWS drift apart (someone changed something in the console)?"**
  `plan` detects the drift and shows it as a diff; `apply` reconciles AWS back to the code. That's
  why we treat the console as read-only in normal operation — the repo is the source of truth.

- **"How do you review infra changes?"**
  Same as app code — pull request + `terraform plan` output attached. Nothing is applied straight to
  the environment without review.

### State & backend

- **"Where is the state stored and how is it protected?"**
  In **S3** (versioned) with a **DynamoDB lock table**, both created by the run-once `bootstrap`
  stack. No local state, so the team shares one source of truth.
  💡 deeper: the lock prevents two simultaneous `apply`s from corrupting state; versioning lets us
  roll back a bad state file.

- **"Why is the account ID / region hardcoded in `backend.tf`?"**
  Terraform backend blocks **can't use variables** — it's a language limitation. It's the one place
  we accept a hardcoded value, and it's flagged with a comment.

- **"What if the state file is lost or corrupted?"**
  S3 versioning lets us restore a prior version; worst case, `terraform import` re-attaches existing
  resources to fresh state.

### Modules & environments

- **"Why split into 14 modules?"**
  Single responsibility + reuse. Each module (vpc, alb, ecs-service, …) is tested once and reused
  across environments. The environment folder is just composition — it wires modules together.

- **"How do you add a `stage` or `prod` environment?"**
  New folder under `environments/` that calls the same modules with different variable values and
  feature flags. No module changes needed.

- **"What are the feature flags?"**
  Booleans like `enable_dns`, `enable_cloudfront`, `enable_waf`, `single_nat_gateway`. They toggle
  whole modules on/off via Terraform `count`, so one codebase serves cheap dev and hardened prod.

### Networking

- **"Why public and private subnets?"**
  Load balancers and the NAT gateway live in **public** subnets; the EC2 hosts running containers
  live in **private** subnets with no direct inbound internet. Traffic only reaches them through the
  ALB. Defense in depth.

- **"What's the NAT gateway for, and why one vs two?"**
  It lets the private hosts make **outbound** calls (image pulls, TMDB API). `single_nat_gateway`
  controls cost vs HA: dev uses one shared NAT (cheaper); prod uses one per AZ so an AZ outage
  doesn't kill all outbound traffic.

- **"What are the VPC endpoints for?"**
  Private, in-AWS routes to ECR, CloudWatch Logs, Secrets Manager, and SSM — so that traffic doesn't
  have to hairpin out through the NAT gateway.
  💡 deeper (if a cost-savvy person asks): in dev they're actually the *largest* line item and
  partly redundant with the NAT — noted in the cost doc as an optimization target.

- **"How are the security groups set up?"**
  Least privilege: the ALB security group is open to the internet on 80/443; the ECS hosts only
  accept traffic **from the ALB's security group**, not from the world.

### Compute / ECS

- **"Why EC2 launch type and not Fargate?"**
  Cost control and full host visibility for this project — we pay for the instances, not per task,
  and can pack many small tasks onto a host. The modules could be adapted to Fargate if we wanted to
  drop host management.

- **"What's a task vs a service vs the cluster?"**
  A **task** is a running container (or group). A **service** keeps a desired number of task copies
  alive and registered with the load balancer. The **cluster** is the pool of EC2 hosts the tasks
  run on.

- **"What's the capacity provider?"**
  The glue between ECS and the EC2 Auto Scaling Group. When tasks can't fit on current hosts, it
  tells the ASG to launch more instances (and scale in when idle).

### Auto-scaling

- **"How does auto-scaling work here?"**
  Two layers. **Service (task) scaling** adds container copies when average CPU/memory crosses a
  target (target-tracking). **Host scaling** — the capacity provider — adds EC2 instances when the
  tasks no longer fit. Tasks scale on utilization; hosts scale on placement pressure.

- **"How fast does it react?"**
  Target-tracking needs ~3 consecutive minutes above target, and CloudWatch metrics lag 1–2 minutes,
  so realistically ~3–4 minutes to scale out. Scale-in is deliberately slower (~15 min) to avoid
  flapping. (That's why in a live demo we pre-warm or narrate the delay.)

- **"Does scaling ever fail / loop?"**
  If a task is under-provisioned it can fail its health check under load and get replaced — we saw
  that when CPU was set too low during testing. The fix is right-sizing the CPU/memory reservation.

### CI/CD

- **"How does a code change get deployed?"**
  Push to `main` → GitHub **webhook** → CodeBuild builds the Docker image, pushes it to ECR tagged
  with the commit SHA and `latest`, then triggers an **ECS rolling deploy**. Fully automated.

- **"Frontend and backend build separately?"**
  Yes — the webhooks are **path-filtered**. A change under `frontend/` only rebuilds the frontend; a
  change under `backend/` only the backend. Changes to `terraform/` build neither.

- **"What triggers the very first build when ECR is empty?"**
  A one-time `null_resource.seed_images` on the first `apply` starts both builds and waits for images
  to land, so the ECS tasks don't crash-loop against an empty registry.

- **"How do rollbacks work?"**
  Every image is also tagged with its commit SHA, so we can redeploy a known-good SHA. ECS keeps the
  previous task definition revision as well.

### Security & secrets

- **"How are secrets handled?"**
  Stored in **AWS Secrets Manager**, injected into the backend task at runtime — never baked into
  images. `terraform.tfvars` is gitignored; in CI we prefer `TF_VAR_*` environment variables.

- **"Is anything sensitive in the repo?"**
  No — secrets live in Secrets Manager and a gitignored tfvars file. The GitHub token used by
  CodeBuild is also stored as a secret and referenced by ARN.

- **"Least-privilege IAM?"**
  Separate roles for the ECS task execution, the task itself, the EC2 instances, and CodeBuild —
  each scoped to what it needs (e.g. CodeBuild can update ECS services and read the one secret).

### DNS / TLS / CDN

- **"Is there HTTPS?"**
  Behind the `enable_dns` flag (Route 53 + ACM) and optionally CloudFront. Dev runs HTTP to save
  cost; prod flips these on. The demo environment is HTTP-only by design.

- **"Why is there a `us-east-1` provider when everything runs in `ap-south-1`?"**
  CloudFront **requires** its ACM certificate in `us-east-1` — an AWS rule. That aliased provider
  exists solely to mint that cert; nothing else runs there.

### Cost

- **"What does this cost to run?"**
  Roughly ~$250/mo for dev, ~$600/mo projected for prod — see the cost doc. The surprise is that the
  biggest costs are **plumbing** (NAT, VPC endpoints, load balancers), not compute.

- **"How would you cut cost?"**
  Consolidate/drop redundant VPC endpoints in dev, use Savings Plans on steady prod compute,
  right-size tasks, and possibly share one ALB. All quantified in `COST-ESTIMATE.md`.

### Deployment safety / operations

- **"What happens on a bad deploy?"**
  ECS does a **rolling deployment** gated on health checks — new tasks must pass health checks before
  old ones are drained, and the ALB only routes to healthy targets. A failing image doesn't take the
  service down.

- **"How do you monitor it?"**
  CloudWatch: centralized logs, a dashboard, and alarms on CPU, memory, ALB 5xx, and response time.
  Container Insights can be toggled on for per-task metrics.

- **"How do you tear it all down?"**
  `terraform destroy` (with a helper script that handles ordering, e.g. detaching the internet
  gateway cleanly). Because it's all code, cleanup is a single command.

- **"What's your disaster recovery story?"**
  The Terraform code **is** the recovery plan. If a region fails or the account is compromised, we
  run `terraform apply` against a new region/account and the whole stack rebuilds identically in
  minutes — no runbook of console clicks to follow under pressure.
  💡 deeper: the remote state (S3, versioned) is the one thing to protect and replicate; with the
  state and the code, recovery is deterministic. Data (if we added a database) would need its own
  backup/restore — Terraform recreates infrastructure, not application data.

- **"How long to stand up from scratch?"**
  `bootstrap` once, then a single `apply` for the environment — and the first apply seeds the initial
  images automatically.

### Curveballs

- **"Is this production-ready?"**
  It's production-*shaped*. For real prod you'd flip the HA/security flags (per-AZ NAT, CloudFront,
  WAF, deletion protection, longer secret recovery), right-size compute, and add Savings Plans — the
  cost doc and tfvars already anticipate this.

- **"What would you improve given more time?"**
  Trim redundant VPC endpoints, add a real frontend health endpoint (today it passes via the SPA
  fallback), remove a stale root `buildspec.yml`, and add a `prod` environment folder.

- **"Why no database?"**
  The catalog is intentionally in-memory (41 titles, enriched from TMDB at startup) — this project is
  about the *infrastructure and delivery pipeline*, not data persistence. Adding RDS would be another
  module.

---

## Timing summary

| Section | Min | Cut for 15-min? |
|---|---|---|
| 1. Hook | 1 | keep |
| 2. App | 1 | keep |
| 3. Why Terraform (vs manual) | 2 | keep (the "why care" hook) |
| 4. Structure | 3 | keep |
| 5. Remote state | 2 | **cut** |
| 6. Variables/flags | 2 | keep (shorten) |
| 7. Architecture | 5 | keep (→3) |
| 8. plan/output | 3 | keep |
| 9. health-check | 2 | **cut** |
| 10. CI/CD | 3 | keep |
| 11. Auto-scaling | 3 | keep (pre-scale) |
| 12. Cost | 1 | **cut** |
| 13. Closing | 1 | keep |
