# Scale-to-Zero & Recovery Runbook — ECS services stuck at 0

**Applies to:** any Starflix environment (`dev` / `stage` / `prod`).
**TL;DR:** Setting `ecs_desired_capacity`/`ecs_min_size`/`ecs_max_size` to `0` and
back does **not** cleanly round-trip. Terraform ignores both the ASG
`desired_capacity` and the ECS service `desired_count` on updates, so scaling the
tfvars values back up brings the **hosts** back but leaves the **services stuck at
`desiredCount = 0`**. Fix it with a one-time `aws ecs update-service ... --desired-count`.

---

## Symptom

After setting the ECS sizing vars to `0`, applying, then setting them back to
non-zero and applying again:

- EC2 hosts come back (ASG shows instances, container instances registered).
- But **no tasks run** — both services sit at `desiredCount = 0`, `runningCount = 0`.

```bash
aws ecs describe-services --cluster starflix-dev-cluster --region ap-south-1 \
  --services starflix-dev-svc-frontend starflix-dev-svc-backend \
  --query "services[].[serviceName,status,desiredCount,runningCount,pendingCount]" \
  --output table
# → both ACTIVE, desired 0, running 0
```

---

## Why it happens

`ecs_desired_capacity` is overloaded — it feeds **two** different things:

1. The **EC2 Auto Scaling Group** (container hosts) —
   `environments/dev/main.tf` → `ecs-cluster` module.
2. The **ECS service `desired_count`** (task count) — `main.tf` for both services.

Both places have a `lifecycle` block that **ignores the value after creation**:

- ASG: `ignore_changes = [desired_capacity]` — `modules/ecs-cluster/main.tf`
- ECS service: `ignore_changes = [desired_count]` — `modules/ecs-service/main.tf`

This is by design: the **capacity provider** (managed scaling) owns the ASG size,
and **Application Auto Scaling** owns the service task count. Terraform only sets
the *initial* values.

### The scale-down (vars → 0)

- `desired_capacity` is ignored, but `min_size`/`max_size` are **not**. Setting
  `max_size = 0` forces the ASG desired capacity to 0 → **all hosts terminate** →
  all tasks stop. The service `desiredCount` gets drained to 0.

### The scale-up (vars → 1/1/2) — why it doesn't fully recover

- ASG: Terraform sets `min_size=1`/`max_size=2` but **ignores `desired_capacity`**.
  AWS enforces `min_size`, so hosts come back (the capacity provider scales out to
  fit pending tasks). ✅ **Hosts self-heal.**
- ECS service: Terraform **ignores `desired_count`**, so the `0 → 1` tfvars change
  has **zero effect** on the services.
- Application Auto Scaling uses **target-tracking on CPU/memory**. A service with
  **0 running tasks emits no metrics**, so its alarms sit in `INSUFFICIENT_DATA`
  and never fire. Target-tracking **does not** proactively raise `desiredCount` up
  to `min_capacity` — it only clamps during an actual metric-driven scaling action.
  → The service is **stranded at 0**. ❌

---

## The fix (recovery)

Give each service one manual nudge to its Auto Scaling **min** (currently
`service_autoscaling_min = 2`). Once tasks run and report metrics, Application Auto
Scaling holds the service in `[min, max]` on its own.

```bash
REGION=ap-south-1
CLUSTER=starflix-dev-cluster

aws ecs update-service --cluster $CLUSTER --service starflix-dev-svc-frontend \
  --desired-count 2 --region $REGION
aws ecs update-service --cluster $CLUSTER --service starflix-dev-svc-backend \
  --desired-count 2 --region $REGION
```

Verify tasks reach a steady state:

```bash
aws ecs describe-services --cluster $CLUSTER --region $REGION \
  --services starflix-dev-svc-frontend starflix-dev-svc-backend \
  --query "services[].[serviceName,desiredCount,runningCount,pendingCount]" \
  --output table
# → desired 2, running 2, pending 0 for both
```

> **Safe against Terraform:** `ignore_changes = [desired_count]` means the next
> `terraform apply` will **not** revert this back to 0.

If the ASG did **not** self-heal (0 instances), also force hosts back — Terraform
ignores `desired_capacity`, so set it directly:

```bash
aws autoscaling set-desired-capacity --region $REGION \
  --auto-scaling-group-name starflix-dev-asg --desired-capacity 2
```

---

## Doing this properly next time

- **Don't scale to zero via the tfvars sizing vars.** The `0 ↔ non-zero`
  round-trip doesn't restore task counts because of the `ignore_changes` design.
- **To pause an environment:**
  - Cleanest: `scripts/destroy.sh` (see [teardown-runbook.md](./teardown-runbook.md)).
  - Or manually set the ASG desired capacity to 0 in the console — Terraform
    ignores it on the next apply.
- **To bring services back:** use the `aws ecs update-service --desired-count`
  command above. That is the reliable path, not a tfvars edit + apply.
- **Capacity sanity check:** `ecs_max_size` (hosts) must be large enough to fit
  `service_autoscaling_min × number-of-services` tasks. With min 2 per service and
  2 services = 4 tasks (frontend 256cpu/512mem + backend 256cpu/768mem each),
  which needs **2× `t3.small`** hosts.

## Naming reference

- Cluster: `starflix-dev-cluster`
- Services: `starflix-dev-svc-frontend`, `starflix-dev-svc-backend` (note `-svc-`)
- ASG: `starflix-dev-asg`
