# Teardown Runbook — `terraform destroy`

**Applies to:** any Starflix environment (`dev` / `stage` / `prod`).
**TL;DR:** don't run a bare `terraform destroy` on this stack — scale the ECS
Auto Scaling Group to zero first, or use `scripts/destroy.sh`, which does it for you.

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

Verify the stuck state:

```bash
aws ecs describe-services --cluster starflix-dev-cluster \
  --services starflix-dev-svc-frontend starflix-dev-svc-backend \
  --region ap-south-1 \
  --query 'services[].{name:serviceName,status:status,running:runningCount}'
# -> status: DRAINING, running: 0   (stuck)

aws ecs list-container-instances --cluster starflix-dev-cluster --region ap-south-1
# -> 3 instances still registered   (the blocker)
```

---

## The fix — scale the ASG to zero before destroying

Removing the container instances lets the `DRAINING` services finalize, which
unblocks the rest of the destroy.

### Option A — use the wrapper script (recommended)

```bash
cd terraform
scripts/destroy.sh dev            # env defaults to dev
scripts/destroy.sh dev ap-south-1 # optional explicit region
```

The script:
1. Finds the ASG + cluster from Terraform outputs (falls back to `starflix-<env>-asg`).
2. Scales the ASG to `min=0, desired=0`.
3. Waits for all ECS container instances to deregister.
4. Runs `terraform destroy -auto-approve`.
5. Verifies the state is empty.

### Option B — manual, two commands

```bash
cd terraform/environments/dev

# 1. Scale compute to zero and let instances drain
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name starflix-dev-asg \
  --min-size 0 --desired-capacity 0 --region ap-south-1

# wait until this returns nothing:
watch -n 10 "aws ecs list-container-instances --cluster starflix-dev-cluster \
  --region ap-south-1 --query containerInstanceArns --output text"

# 2. Destroy
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
it running** and, in another shell, scale the ASG to zero. Terraform's next poll
will see the services finish and continue automatically — no need to abort.

```bash
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name starflix-dev-asg \
  --min-size 0 --desired-capacity 0 --region ap-south-1
```

> Do **not** just terminate the EC2 instances directly while the ASG is still
> active — with `min_size >= 1` the ASG will immediately launch replacements.
> Scale the ASG down instead.

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

## Post-teardown verification

```bash
cd terraform/environments/dev
terraform state list | wc -l    # expect 0

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
