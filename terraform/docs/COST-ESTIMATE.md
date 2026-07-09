# Starflix — AWS Monthly Cost Estimate

> **Scope:** Derived from the Terraform in this repo — `environments/dev/` plus every
> module under `modules/`. Covers the **dev** environment as actually configured, plus a
> **projected prod** environment (no prod env exists yet).
>
> **Region:** `ap-south-1` (Mumbai) — from `environments/dev/terraform.tfvars` and
> `providers.tf`. A second, aliased `us-east-1` provider exists **only** to mint the
> CloudFront ACM cert; it creates no billable always-on resource in dev (DNS is disabled).
>
> ⚠️ **All prices are approximate** and reflect on-demand list rates for ap-south-1. They
> **must** be validated against the [AWS Pricing Calculator](https://calculator.aws) or
> [Infracost](https://www.infracost.io) before being quoted. See [Caveats](#7-caveats).

---

## 1. Summary

| Environment | Monthly (approx.) | Annual (approx.) |
|---|---:|---:|
| **Dev** (as configured today) | **≈ $250** | **≈ $3,000** |
| **Prod** (projected, production-grade) | **≈ $600** | **≈ $7,200** |

**Key finding — dev is not Fargate.** The ECS services run on an **EC2 launch type**
cluster (an Auto Scaling Group of `t3.small` hosts with a capacity provider). There is
**no per-task Fargate vCPU/memory charge**; compute cost is the EC2 instances + their EBS.

**The three biggest dev cost drivers are all "plumbing," not compute:**

1. 🥇 **VPC interface endpoints — ≈ $102/mo.** Seven interface endpoints × two AZs = 14
   billed ENIs at ~$0.01/ENI-hr. This is the single largest line item and the one most
   people miss entirely.
2. 🥈 **EC2 ECS hosts — ≈ $49/mo** (3 × `t3.small`).
3. 🥉 **NAT Gateway — ≈ $44/mo** (single NAT, hourly + data processing).
4. **ALBs — ≈ $41/mo** (two application load balancers, frontend + backend).

Together those four are ~95% of the dev bill; everything else (Secrets, CloudWatch,
ECR, S3, CodeBuild) is rounding error at dev scale.

---

## 2. Dev — Resource Inventory & Cost Model

### 2.1 Resource inventory (what Terraform actually creates for dev)

Feature flags in `terraform.tfvars`: `single_nat_gateway = true`, `enable_dns = false`,
`enable_cloudfront = false`, `enable_waf = false`, `enable_container_insights = false`,
`enable_service_autoscaling = true` (min 2 / max 4 per service).

| Module | Resources | Billable? | Always-on / Usage / Scale-to-zero |
|---|---|---|---|
| `vpc` | 1 VPC, 1 IGW, 2 public + 2 private subnets, route tables | No (free) | — |
| `vpc` | **1 NAT Gateway + 1 EIP** (single_nat_gateway=true) | **Yes** | Always-on (hourly) + usage (data) |
| `vpc-endpoints` | **7 interface endpoints** (ecr.api, ecr.dkr, logs, secretsmanager, ssm, ec2messages, ssmmessages) across **2 AZs** | **Yes** | Always-on (per-ENI hourly) + usage (data) |
| `vpc-endpoints` | 1 S3 **gateway** endpoint | No (free) | — |
| `security-groups` | Security groups | No (free) | — |
| `alb` | **2 ALBs** (frontend + backend), 2 target groups, listeners | **Yes** | Always-on (hourly) + usage (LCU) |
| `ecs-cluster` | ECS cluster + capacity provider | No (control plane free) | — |
| `ecs-cluster` | **ASG of `t3.small`** (desired 3, min 1, max 5) | **Yes** | Always-on / **scale-to-zero capable** ¹ |
| `ecs-cluster` | **gp3 EBS root volumes** (30 GiB each, encrypted) | **Yes** | Always-on (per host) |
| `ecs-service` ×2 | Task defs + services (frontend 256/512, backend 256/768), autoscaling | No extra ² | Usage-driven (runs on EC2 hosts) |
| `ecr` | 2 repositories (keep last 20 images) | **Yes** | Usage (storage) |
| `secrets` | **2 Secrets Manager secrets** (tmdb, github) | **Yes** | Always-on ($/secret) |
| `iam` | Roles, policies, instance profile | No (free) | — |
| `s3` | 2 buckets (assets, artifacts), versioned | **Yes** | Usage (storage + requests) |
| `cloudwatch` | 1 dashboard, **8 metric alarms** | **Yes** | Always-on (alarms) + usage (logs) |
| `codebuild` | 2 projects + 2 webhooks + 2 log groups | **Yes** | Usage (build-minutes) |
| `dns` | — | **Not created** (enable_dns=false) | — |
| `cloudfront` | — | **Not created** (enable_cloudfront=false) | — |
| WAF | — | **Not created** (enable_waf=false) | — |

¹ **Scale-to-zero:** per `docs/scale-to-zero-recovery.md`, dev *can* idle at 0 hosts/0
tasks, but the `0 → non-zero` round-trip does **not** cleanly recover (Terraform ignores
`desired_capacity`/`desired_count`), so this is a manual pause, not an automated
off-hours schedule. If actually parked at 0, EC2 + EBS + task charges drop to ~$0, but
**NAT, VPC endpoints, and ALBs keep billing** — i.e. the parked floor is still ~$190/mo.

² ECS **service** tasks incur no separate charge on EC2 launch type — they consume the
EC2 hosts' CPU/memory. The bill is the ASG instances, not the tasks.

### 2.2 Dev cost breakdown

Assumes 730 hrs/month. Usage assumptions are called out and **overridable**.

| # | Resource | Rate (ap-south-1, approx.) | Assumption | Monthly |
|---|---|---|---|---:|
| 1 | **VPC interface endpoints** | ~$0.01 / ENI-hr | 7 endpoints × 2 AZ = 14 ENIs; ~10 GB data | **$102.30** |
| 2 | **EC2 ECS hosts** | `t3.small` ~$0.0224/hr | 3 hosts always-on ³ | **$49.06** |
| 3 | **NAT Gateway** | ~$0.056/hr + $0.056/GB | 1 NAT; ~50 GB processed | **$43.68** |
| 4 | **ALB ×2** | ~$0.0225/hr + LCU | 2 ALBs, low LCU (~1–2) | **$41.00** |
| 5 | **EBS gp3** | ~$0.0912/GB-mo | 30 GiB × 3 hosts = 90 GB | **$8.21** |
| 6 | **CloudWatch** | $0.10/alarm; ~$0.57/GB logs | 8 alarms + ~2 GB logs; dashboard free | **$2.00** |
| 7 | **CodeBuild** | general1.small ~$0.005/min | ~30 builds × 5 min = 150 min | **$1.00** |
| 8 | **Data transfer out** | ~$0.109/GB | ~10 GB egress | **$1.00** |
| 9 | **Secrets Manager** | $0.40/secret + API | 2 secrets | **$0.80** |
| 10 | **ECR storage** | $0.10/GB-mo | ~5 GB images (≤20/repo) | **$0.50** |
| 11 | **S3** | ~$0.025/GB + requests | ~2 GB (placeholder assets in dev) | **$0.10** |
| — | EIP (attached to NAT) | free while attached | 1 | $0.00 |
| | **DEV TOTAL** | | | **≈ $249.65 / mo** |
| | **DEV ANNUAL** | | | **≈ $2,996 / yr** |

³ Configured `desired_capacity = 3`, but the capacity provider (target 80%) and
`ignore_changes = [desired_capacity]` mean the cluster realistically settles at **2–3
hosts** to fit 4 tasks (2 svc × min 2). Range: **~$33 (2 hosts) → ~$82 (5 max)**.

**Hidden-cost callouts (the ones people miss):**

- **VPC interface endpoints bill per-AZ, per-endpoint, per-hour** — 7 × 2 = 14 ENIs is
  **more expensive than the NAT gateway they were meant to reduce traffic through.** In
  dev, running *both* a NAT and a full set of interface endpoints is largely redundant
  (see recommendations).
- **NAT Gateway has two charges:** the hourly (~$41/mo) **and** $0.056/GB processed —
  container image pulls, `apt`/`npm` fetches, and TMDB API calls all flow through it
  (unless served by the endpoints). A busy dev day can add several dollars quietly.
- **Inter-AZ data transfer** ($0.01/GB each way): ALB → cross-AZ target, and ECS tasks
  talking across AZs, are billable in a 2-AZ layout. Small in dev; material in prod.

---

## 3. Prod — Projected Configuration & Cost

No prod environment exists. This projection reuses the same modules with
**production-grade flags** flipped on. Treat instance counts/sizes as a **starting
proposal to right-size against real load.**

### 3.1 Proposed prod deltas vs dev

| Setting | Dev | **Prod (proposed)** | Rationale |
|---|---|---|---|
| `single_nat_gateway` | `true` (1 NAT) | **`false` (2 NAT, per-AZ)** | AZ-level HA for outbound |
| ECS host type / count | `t3.small` × 3 | **`t3.medium` × 4** (ASG 3–8) | Right-sized, headroom |
| Service autoscaling min | 2 | **3+ (no scale-to-zero)** | Always-warm |
| `enable_cloudfront` | `false` | **`true`** | CDN, TLS, offload |
| `enable_waf` | `false` | **`true`** | Edge protection |
| `enable_dns` | `false` | **`true`** | Route53 zone + ACM |
| `enable_container_insights` | `false` | **`true`** | Observability |
| `log_retention_days` | 7 | **30–90** | Audit/retention |
| EBS root | 30 GiB | **50 GiB** | Image/log headroom |

### 3.2 Prod cost breakdown

| Resource | Assumption | Monthly |
|---|---|---:|
| **EC2 ECS hosts** | `t3.medium` × 4 (~$0.0472/hr) baseline | **$137.80** |
| **VPC interface endpoints** | 7 × 2 AZ ENIs (same as dev) | **$102.30** |
| **ALB ×2** | Higher LCU (~5 LCU each) | **$100.00** |
| **NAT Gateway ×2** | 2 NAT hourly + ~300 GB data | **$98.50** |
| **CloudFront** | ~500 GB out + ~5M requests (offsets ALB egress) | **$50.00** |
| **CloudWatch** | Container Insights + 30–90d retention + alarms | **$40.00** |
| **WAF** | Web ACL + ~5 managed rule groups + requests | **$20.00** |
| **EBS gp3** | 50 GiB × 4 hosts = 200 GB | **$18.24** |
| **Inter-AZ / data transfer** | Multi-AZ chatter ~500 GB + direct egress | **$15.00** |
| **CodeBuild** | More frequent / medium compute | **$5.00** |
| **S3** | ~50 GB real artwork + versioning + requests | **$3.00** |
| **ECR** | ~10 GB images | **$1.00** |
| **Route53** | 1 hosted zone + queries | **$1.00** |
| **Secrets Manager** | 2 secrets (more if Strapi secrets enabled) | **$0.80** |
| **ACM certificates** | DNS-validated | **$0.00** |
| **PROD TOTAL** | | **≈ $592 / mo** |
| **PROD ANNUAL** | | **≈ $7,100 / yr** |

> Prod is dominated by **compute + the same 4 "plumbing" lines**, plus CloudFront/WAF at
> the edge. With a Compute Savings Plan on the steady EC2 baseline and NAT/endpoint
> consolidation, prod realistically lands **$450–550/mo** (see recommendations).

---

## 4. Dev vs Prod — Side by Side

| Line item | Dev / mo | Prod / mo |
|---|---:|---:|
| EC2 ECS hosts | $49.06 | $137.80 |
| VPC interface endpoints | $102.30 | $102.30 |
| ALB ×2 | $41.00 | $100.00 |
| NAT Gateway | $43.68 (×1) | $98.50 (×2) |
| CloudFront | — | $50.00 |
| CloudWatch | $2.00 | $40.00 |
| WAF | — | $20.00 |
| EBS gp3 | $8.21 | $18.24 |
| Inter-AZ / data transfer | $1.00 | $15.00 |
| CodeBuild | $1.00 | $5.00 |
| S3 | $0.10 | $3.00 |
| ECR | $0.50 | $1.00 |
| Route53 | — | $1.00 |
| Secrets Manager | $0.80 | $0.80 |
| **Monthly total** | **≈ $250** | **≈ $592** |
| **Annual total** | **≈ $3,000** | **≈ $7,100** |

---

## 5. Recommendations

### 5.1 Cost optimization

| # | Recommendation | Est. saving | Where |
|---|---|---|---|
| 1 | **Consolidate / drop VPC interface endpoints in dev.** 7 endpoints × 2 AZ = ~$102/mo — larger than the NAT. In dev, traffic already egresses via the NAT, so most endpoints are redundant. Either **keep the NAT and remove the interface endpoints**, or drop to a single AZ, or keep only ECR + Logs. | **up to ~$100/mo (dev)** | `modules/vpc-endpoints` |
| 2 | **Fargate Spot / EC2 Spot for non-critical tasks.** Frontend (stateless nginx/SPA) is a good Spot candidate; run baseline on-demand + burst on Spot. | ~30–60% of burst compute | ASG / capacity provider |
| 3 | **Compute Savings Plan** on the steady prod EC2 baseline (1- or 3-yr). | ~20–40% on baseline EC2 | prod ASG |
| 4 | **Single NAT in dev (already done ✅).** Keep `single_nat_gateway = true` for dev. Only use per-AZ NAT where AZ-HA is required. | already applied | `vpc` |
| 5 | **Tighten log retention & Container Insights scope.** 30d (not 90d) for most groups; enable Insights only on prod. Dev already at 7d ✅. | $10–25/mo (prod) | `cloudwatch`, `log_retention_days` |
| 6 | **S3 lifecycle to IA/Glacier** for artifacts + versioned assets. Non-current expiry already configured ✅ — add a transition rule for cold artifacts. | small now, scales | `modules/s3` |
| 7 | **Right-size ECS tasks/hosts from real metrics.** 256 CPU / 512–768 MiB tasks may over/under-fit `t3.small`; validate before committing to prod sizing. | variable | tfvars |
| 8 | **Consider one shared ALB with host/path routing** instead of two, if the frontend/backend split allows it. | ~$20/mo | `modules/alb` |

### 5.2 Reliability trade-offs (cost cuts that reduce resilience — your call)

| Cut | Saves | Risk you take on |
|---|---|---|
| Single NAT (dev) | ~$44/mo per extra NAT | An AZ outage kills **all** outbound for the VPC. Fine for dev; **not** for prod. |
| Drop VPC interface endpoints | ~$100/mo | Traffic to ECR/Logs/Secrets/SSM rides the NAT/internet path — more NAT data cost, and it breaks fully-private (no-NAT) designs. |
| Spot for tasks | 30–60% | Interruptions; needs graceful drain + on-demand base capacity. |
| Lower log retention / no Insights | $10–40/mo | Less forensic depth during incidents. |
| Fewer/smaller hosts | variable | Less burst headroom; risk of pending tasks under load. |
| Single ALB | ~$20/mo | Blast radius: one LB config change affects both services. |

---

## 6. Prod Instance-Type Comparison — `t3.medium` vs `t3.xlarge`

This section varies **only the ECS host instance type** on the projected prod fleet
(**4 hosts**, ASG 3–8, per §3). Every other prod line item — VPC endpoints, NAT ×2,
ALB ×2, CloudFront, WAF, CloudWatch, etc. — is **held constant**, so the difference is
pure compute. Rates are ap-south-1 on-demand, 730 hrs/month.

### 6.1 Compute only (the variable)

| Instance | vCPU / RAM | Rate/hr | Per host/mo | **Fleet of 4/mo** |
|---|---|---|---:|---:|
| **t3.medium** | 2 / 4 GiB | ~$0.0472 | ~$34.46 | **$137.80** |
| **t3.xlarge** | 4 / 16 GiB | ~$0.1888 | ~$137.82 | **$551.30** |

**EC2 compute difference: ~$413/month** (t3.xlarge = 4× the resources ≈ 4× the cost).

### 6.2 All-in prod monthly total

Non-compute prod lines total **≈ $454/mo** (from §3.2: endpoints $102 + NAT ×2 $98.50 +
ALB ×2 $100 + CloudFront $50 + CloudWatch $40 + WAF $20 + EBS $18.24 + transfer $15 +
CodeBuild $5 + S3 $3 + ECR $1 + Route53 $1 + Secrets $0.80). Only the EC2 line changes.

| | **t3.medium × 4** | **t3.xlarge × 4** |
|---|---:|---:|
| EC2 compute | $137.80 | $551.30 |
| All other prod lines (fixed) | ~$454 | ~$454 |
| **Monthly total** | **≈ $592** | **≈ $1,006** |
| **Annual total** | **≈ $7,100** | **≈ $12,070** |

> The `t3.medium × 4` column is the baseline prod projection from §3. Choosing `t3.xlarge`
> roughly **+$414/mo (+$4,970/yr)** for 4× CPU/RAM per host.

### 6.3 With Savings Plans (compute discounted; fixed lines unchanged)

Savings Plans discount **only EC2 compute**. Two plan types:
**Compute SP** (flexible, lower discount) and **EC2 Instance SP** (`t3`/`ap-south-1`
locked, deeper discount).

**Compute cost only:**

| Plan | ~Discount | **t3.medium × 4** | **t3.xlarge × 4** |
|---|---|---:|---:|
| On-demand | — | $137.80 | $551.30 |
| Compute SP — 1yr, no upfront | ~28% | ~$99 | ~$397 |
| EC2 Instance SP — 1yr, no upfront | ~40% | ~$83 | ~$331 |
| Compute SP — 3yr, no upfront | ~50% | ~$69 | ~$276 |
| EC2 Instance SP — 3yr, all upfront | ~60% | ~$55 | ~$221 |

**All-in prod monthly (compute + ~$454 fixed):**

| Plan | **t3.medium × 4** | **t3.xlarge × 4** | Monthly gap |
|---|---:|---:|---:|
| On-demand | ~$592 | ~$1,006 | ~$414 |
| Compute SP — 1yr | ~$553 | ~$851 | ~$298 |
| EC2 Instance SP — 1yr | ~$537 | ~$785 | ~$248 |
| Compute SP — 3yr | ~$523 | ~$730 | ~$207 |
| EC2 Instance SP — 3yr | ~$509 | ~$675 | ~$166 |

**All-in prod annual:**

| Plan | t3.medium × 4 | t3.xlarge × 4 |
|---|---:|---:|
| On-demand | ~$7,100 | ~$12,070 |
| EC2 Instance SP — 1yr | ~$6,440 | ~$9,420 |
| EC2 Instance SP — 3yr | ~$6,110 | ~$8,100 |

### 6.4 Which to choose

- **Start with `t3.medium`.** Tasks are tiny (256 CPU / 512–768 MiB; max 8 total) and pack
  comfortably onto `t3.medium × 3–4` with burst headroom via the ASG (min 3, max 8).
  `t3.xlarge` is **likely oversized** unless heavy TMDB enrichment or high concurrent
  traffic is expected — the CloudWatch CPU/memory alarms will tell you if you need it.
- **Scale out before scaling up.** Adding `t3.medium` hosts (or raising
  `service_autoscaling_max`) is cheaper and more granular than jumping to `t3.xlarge`.
- **Commit only once sized.** Buy an **EC2 Instance SP (1yr, no upfront)** on the steady
  baseline (`service_autoscaling_min` worth of hosts); let auto-scaling spikes run
  on-demand. Over-committing wastes the discount.

---

## 7. Caveats

- **Prices are approximate**, on-demand list rates for **ap-south-1**, and will drift.
  They **must** be validated with the **AWS Pricing Calculator** or **Infracost**
  (`infracost breakdown --path environments/dev`) before being quoted to anyone.
- **Usage-driven lines are assumptions, not measurements** — NAT data GB, ALB LCUs,
  CloudFront egress/requests, CodeBuild minutes, log ingestion, S3 storage, and inter-AZ
  transfer all scale with real traffic. Override the assumptions in §2.2/§3.2 with your
  actual numbers.
- The **§6 instance-type comparison** varies **only** the ECS host size; every other prod
  line (endpoints, NAT, ALB, CloudFront, etc.) is held constant, so the delta is pure
  compute.
- **EC2, not Fargate.** The prompt referenced Fargate vCPU/mem; this stack uses the ECS
  **EC2 launch type**, so the model bills EC2 instances + EBS instead. If you migrate to
  Fargate the cost shape changes materially.
- **Host count is soft.** `desired_capacity` is `ignore_changes`d and driven by the
  capacity provider, so the true host count floats in `[min, max]`; dev is modeled at 3.
- **Taxes, support plans, and free-tier credits are excluded.**
- **⚠️ Security (out of scope for cost, but urgent):** `environments/dev/terraform.tfvars`
  contains **real-looking live secrets** committed to the repo — a GitHub PAT
  (`github_pat_11...`) and a TMDB API key. The file header claims it's gitignored, but it
  is present in the tree. **Rotate both credentials and remove the file from version
  control** regardless of cost concerns.
