# Teardown Runbook — `terraform destroy`

**Applies to:** any Starflix environment (`dev` / `stage` / `prod`).
**TL;DR:** don't run a bare `terraform destroy` on this stack. Use
`scripts/destroy.sh`, which does it in the right order: scale ECS **services** to
0, **suspend** the ASG's launch process, scale the ASG to 0, then destroy. On a
low-memory box also see the OOM section below (`-parallelism` / CLI fallback).

---

## The problem — ECS-on-EC2 destroy deadlock

A plain `terraform destroy` on this stack **hangs** partway through, even though the
plan looks clean. Observed behaviour: ~76 resources delete, then it stalls for many
minutes on:

```
module.ecs_service_frontend.aws_ecs_service.this: Still destroying... [06m00s elapsed]
module.ecs_service_backend.aws_ecs_service.this:  Still destroying... [05m00s elapsed]
module.vpc.aws_internet_gateway.this:             Still destroying... [04m00s elapsed]
```

### Why it happens

1. Terraform destroys the ECS **service** before the **ASG/cluster** (correct
   dependency order — the service depends on the cluster).
2. Deleting the service drains its tasks to **0 running** almost immediately.
3. But the service then gets **stuck in `DRAINING`** and never transitions to
   `INACTIVE` **while its EC2 container instances are still registered**.
4. Terraform won't touch the ASG until the services finish deleting — but the
   services won't finish until the instances are gone. **Circular wait.**

> This is **not** caused by scale-in protection (that is already
> `managed_termination_protection = DISABLED` / `protect_from_scale_in = false`).
> It is the service-drain vs. instance-registration ordering.

### The gotcha — managed scaling respawns the instances

Just scaling the ASG to zero is **not enough**. The ECS capacity provider uses
**managed (target-tracking) scaling**, which installs an
`ECSManagedAutoScalingPolicy` on the ASG. If the ECS **services still want tasks**
(`desiredCount >= 1`) when you scale the ASG down, those tasks go `PENDING`, the
`AlarmHigh` alarm fires, and the policy **drives the ASG's desired capacity right
back up** — instances terminate and respawn forever:

```
user request → desired 3→0, instances terminated
TargetTracking AlarmHigh → ECSManagedAutoScalingPolicy → desired 0→2
TargetTracking AlarmHigh → desired 2→3     (respawned)
```

So a correct teardown must **(a) remove the task demand first** (scale services to
0) **and (b) prevent the ASG from launching** (suspend its `Launch` process), then
scale it to zero.

Verify the stuck / respawn state:

```bash
aws ecs describe-services --cluster starflix-dev-cluster \
  --services starflix-dev-svc-frontend starflix-dev-svc-backend \
  --region ap-south-1 \
  --query 'services[].{name:serviceName,status:status,running:runningCount}'
# -> status: DRAINING, running: 0   (stuck)

aws autoscaling describe-scaling-activities --auto-scaling-group-name starflix-dev-asg \
  --region ap-south-1 --max-items 4 --query 'Activities[].Cause'
# -> shows ECSManagedAutoScalingPolicy raising desired capacity (respawn)
```

---

## The fix — the correct teardown order

The wrapper script encodes the full, correct sequence:

1. **Scale every ECS service to `desired-count 0`** and wait for tasks to stop
   (removes the task demand that drives managed scaling).
2. **Suspend the ASG processes** `Launch`, `AlarmNotification`, `ReplaceUnhealthy`
   (so the managed-scaling policy physically cannot relaunch instances;
   `Terminate` stays enabled so the next step can remove them).
3. **Scale the ASG to `min=0, desired=0`** and wait for container instances to
   deregister.
4. **`terraform destroy`**.
5. Verify the state is empty.

### Option A — use the wrapper script (recommended)

```bash
cd terraform
scripts/destroy.sh dev            # env defaults to dev
scripts/destroy.sh dev ap-south-1 # optional explicit region
```

### Option B — manual

```bash
cd terraform/environments/dev
CL=starflix-dev-cluster; ASG=starflix-dev-asg; R=ap-south-1

# 1. Remove task demand
for s in $(aws ecs list-services --cluster $CL --region $R --query serviceArns --output text); do
  aws ecs update-service --cluster $CL --service "$s" --desired-count 0 --region $R >/dev/null
done

# 2. Stop the ASG from relaunching, then 3. scale to zero
aws autoscaling suspend-processes --auto-scaling-group-name $ASG \
  --scaling-processes Launch AlarmNotification ReplaceUnhealthy --region $R
aws autoscaling update-auto-scaling-group --auto-scaling-group-name $ASG \
  --min-size 0 --desired-capacity 0 --region $R

# wait until this returns nothing:
watch -n 10 "aws ecs list-container-instances --cluster $CL --region $R \
  --query containerInstanceArns --output text"

# 4. Destroy
terraform destroy -auto-approve
```

### Option C — Terraform-only (no CLI)

Set these in `terraform.tfvars`, `apply`, then `destroy`:

```hcl
ecs_min_size         = 0
ecs_desired_capacity = 0
```

---

## Unblocking a destroy that is ALREADY hung

If you already ran `terraform destroy` and it's stuck on the ECS services, **leave
it running** and, in another shell, run steps 1–3 above (scale services to 0,
suspend ASG processes, scale ASG to 0). Terraform's next poll will see the
services finish and continue automatically — no need to abort.

> Do **not** just terminate the EC2 instances directly while the ASG is still
> active — managed scaling / `min_size` will immediately launch replacements.
> Suspend `Launch` and scale the ASG down instead.

---

## If terraform itself keeps crashing (low memory / OOM)

Symptom — the destroy dies mid-run, **not** on a specific resource, with:

```
Error: Plugin did not respond
The plugin ... failed to respond to ... ApplyResourceChange
Error: execution halted
```

or `Request cancelled ... UpgradeResourceState request was cancelled` during the
refresh phase. This is the **AWS provider process being OOM-killed**, not a logic
error. Check:

```bash
free -h    # if 'available' is a few hundred MB and Swap is ~full, that's the cause
```

The AWS provider (v6.x) is memory-hungry and default parallelism runs 10 resource
operations concurrently. On a constrained box it gets killed after 10–20 resources,
makes partial progress, and looks like an endless loop.

Mitigations, in order:

1. **Free RAM** (close other heavy processes) — the reliable fix.
2. **Lower parallelism** so fewer provider ops run at once:
   ```bash
   terraform destroy -auto-approve -parallelism=2   # or -parallelism=1
   ```
3. **Last resort — delete via AWS CLI** (uses a fraction of the memory), then
   reconcile state. See the next section.

> Partial OOM destroys can leave state **inconsistent** — resources get deleted
> out of module order. A known consequence: the IAM `secretsmanager:GetSecretValue`
> policy gets deleted before the CodeBuild **webhooks**, after which
> `DeleteWebhook` fails with *"service role does not have access to retrieve
> secret"*. Fix: `terraform state rm module.codebuild.aws_codebuild_webhook.frontend
> module.codebuild.aws_codebuild_webhook.backend` (deleting the CodeBuild *project*
> removes the webhook server-side anyway), then continue.

---

## Manual CLI teardown (last resort, when terraform can't run)

If the box is too memory-starved for terraform to run at all, delete the remaining
resources directly, in dependency order, then clear state. Discover IDs by the
`Project=starflix` tag / deterministic names, then:

```bash
R=ap-south-1
# 1. ALB first (releases ENIs over ~1-2 min)
aws elbv2 delete-load-balancer --region $R --load-balancer-arn <alb-arn>
# 2. CodeBuild projects, 3. ECR repos (force), 4. ECS cluster, 5. secrets
aws codebuild delete-project --region $R --name starflix-dev-frontend-build
aws codebuild delete-project --region $R --name starflix-dev-backend-build
aws ecr delete-repository --region $R --repository-name starflix-dev/frontend --force
aws ecr delete-repository --region $R --repository-name starflix-dev/backend  --force
aws ecs delete-cluster    --region $R --cluster starflix-dev-cluster
aws secretsmanager delete-secret --region $R --secret-id starflix/dev/github-token  --force-delete-without-recovery
aws secretsmanager delete-secret --region $R --secret-id starflix/dev/tmdb-api-key --force-delete-without-recovery
# 6. empty + delete S3 artifacts bucket (handle versions/delete-markers if versioned)
aws s3 rb s3://<artifacts-bucket> --force
# 7. IAM codebuild role: detach attached + delete inline, then delete-role
# 8. wait for ENIs to clear, then IGW (detach+delete), subnets, ALB SG, VPC
until [ "$(aws ec2 describe-network-interfaces --region $R \
  --filters Name=vpc-id,Values=<vpc-id> --query 'length(NetworkInterfaces)' --output text)" = 0 ]; do sleep 15; done
aws ec2 detach-internet-gateway --region $R --internet-gateway-id <igw> --vpc-id <vpc>
aws ec2 delete-internet-gateway --region $R --internet-gateway-id <igw>
aws ec2 delete-subnet          --region $R --subnet-id <subnet>       # each
aws ec2 delete-security-group  --region $R --group-id <alb-sg>
aws ec2 delete-vpc             --region $R --vpc-id <vpc>
```

Then reconcile terraform state (remove the now-nonexistent managed resources):

```bash
cd terraform/environments/dev
terraform state list | grep -vE '^data\.' | xargs -r terraform state rm
```

---

## Known residual caveat — lingering ENI

Occasionally the **Internet Gateway / VPC / subnet** deletion stalls with a
`DependencyViolation` because an ENI (from ECS tasks or VPC interface endpoints)
takes a moment to detach. This is transient AWS eventual consistency, **not** a
config error. Simply **re-run the destroy** and it clears on the second pass. The
wrapper script exits non-zero and tells you to re-run if any resources remain.

---

## What is NOT destroyed

`terraform destroy` here only tears down the **environment** root
(`environments/<env>`). It does **not** touch:

- The **state backend** (S3 tfstate bucket + lock) — managed by `bootstrap/`.
- Anything created outside Terraform.

Secret **values** are deleted immediately in `dev` (`recovery_window_days = 0`),
but they are stored in the gitignored `terraform.tfvars`, so a later
`terraform apply` repopulates them automatically.

---

## Clean up stale GitHub webhooks (avoid duplicate builds)

When a CodeBuild project is destroyed and later recreated with the **same name**,
its GitHub webhook can survive teardown — an interrupted destroy, or the
`state rm` workaround above (which removes the CodeBuild project server-side but
may leave the GitHub-side hook), both leave an orphan. On the next apply the old
hook's encrypted token still routes to the same-named project, so a single `git
push` triggers **two builds of the same commit**.

After a destroy/re-apply cycle, check the repo has exactly **two** CodeBuild
webhooks (one per project):

```bash
# TOKEN = the GitHub PAT (repo + admin:repo_hook). Repo: abhisheksmandal/starflix
curl -s -H "Authorization: token $TOKEN" \
  https://api.github.com/repos/abhisheksmandal/starflix/hooks \
  | python3 -c "import sys,json;[print(h['id'], h['config'].get('url','')[:60]) for h in json.load(sys.stdin)]"

# The two LIVE hook IDs (do NOT delete these) — match against the current projects:
aws codebuild batch-get-projects \
  --names starflix-dev-frontend-build starflix-dev-backend-build \
  --query "projects[].webhook.url" --output text   # each ends in /hooks/<id>

# Delete any OTHER codebuild.*.amazonaws.com hook (orphan):
curl -s -X DELETE -H "Authorization: token $TOKEN" \
  https://api.github.com/repos/abhisheksmandal/starflix/hooks/<ORPHAN_ID>   # -> HTTP 204
```

Deleting orphan GitHub hooks is safe — they aren't in Terraform state, and the
live webhooks (tracked via the CodeBuild API) are untouched.

---

## Post-teardown verification

```bash
cd terraform/environments/dev
terraform state list | grep -vE '^data\.' | wc -l   # expect 0 (data sources may remain; harmless)

for q in \
  "ec2 describe-instances --filters Name=tag:Project,Values=starflix Name=instance-state-name,Values=running --query Reservations[].Instances[].InstanceId" \
  ; do aws $q --region ap-south-1 --output text; done

aws ecs list-clusters --region ap-south-1 --query "clusterArns[?contains(@,'starflix')]" --output text
aws elbv2 describe-load-balancers --region ap-south-1 --query "LoadBalancers[?contains(LoadBalancerName,'starflix')].LoadBalancerName" --output text
aws ec2 describe-vpcs --region ap-south-1 --filters Name=tag:Project,Values=starflix --query 'Vpcs[].VpcId' --output text
```

All should return empty.

---

*Related: `ARCHITECTURE.md` §0 (deployment snapshot) and the ECS cluster module.*
