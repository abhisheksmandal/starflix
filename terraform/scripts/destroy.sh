#!/usr/bin/env bash
#
# destroy.sh — safe teardown for a Starflix environment.
#
# Works around the ECS-on-EC2 destroy deadlock: `terraform destroy` deletes the
# ECS service before the ASG, but the service stays stuck in DRAINING until its
# container instances deregister — which never happens while the ASG is up. This
# script scales the ASG to zero and waits for the instances to drain FIRST, then
# runs terraform destroy so it completes in a single pass.
#
# Usage:
#   scripts/destroy.sh [environment] [aws_region]
#   scripts/destroy.sh dev
#   scripts/destroy.sh dev ap-south-1
#
# Environment defaults to "dev". Region is auto-detected from the environment's
# terraform.tfvars (var "aws_region"), overridable via arg 2 or $AWS_REGION.
#
set -euo pipefail

ENV="${1:-dev}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="${SCRIPT_DIR}/../environments/${ENV}"

if [[ ! -d "${ENV_DIR}" ]]; then
  echo "ERROR: environment directory not found: ${ENV_DIR}" >&2
  exit 1
fi
cd "${ENV_DIR}"

# --- Resolve region --------------------------------------------------------
REGION="${2:-${AWS_REGION:-}}"
if [[ -z "${REGION}" && -f terraform.tfvars ]]; then
  REGION="$(grep -E '^\s*aws_region' terraform.tfvars | head -1 | sed -E 's/.*=\s*"([^"]+)".*/\1/')"
fi
REGION="${REGION:-ap-south-1}"

echo "==> Environment : ${ENV}"
echo "==> Directory   : ${ENV_DIR}"
echo "==> Region      : ${REGION}"

# --- Discover the ASG (from state; fall back to naming convention) ---------
ASG_NAME="$(terraform output -raw ecs_autoscaling_group_name 2>/dev/null || true)"
CLUSTER_NAME="$(terraform output -raw ecs_cluster_name 2>/dev/null || true)"
[[ -z "${ASG_NAME}" ]] && ASG_NAME="starflix-${ENV}-asg"
[[ -z "${CLUSTER_NAME}" ]] && CLUSTER_NAME="starflix-${ENV}-cluster"

# --- Step 1: scale ECS services to 0 FIRST --------------------------------
# The capacity provider uses managed (target-tracking) scaling. If we scale the
# ASG down while the services still want tasks, those tasks go PENDING and
# managed scaling drives the ASG right back up — instances respawn forever.
# Removing the task demand first lets the ASG scale to (and stay at) zero.
if aws ecs describe-clusters --clusters "${CLUSTER_NAME}" --region "${REGION}" \
      --query 'clusters[0].clusterName' --output text 2>/dev/null | grep -q "${CLUSTER_NAME}"; then

  SERVICES="$(aws ecs list-services --cluster "${CLUSTER_NAME}" --region "${REGION}" \
                --query 'serviceArns' --output text 2>/dev/null || true)"
  if [[ -n "${SERVICES}" && "${SERVICES}" != "None" ]]; then
    for SVC in ${SERVICES}; do
      echo "==> Scaling ECS service to 0: ${SVC##*/}"
      aws ecs update-service --cluster "${CLUSTER_NAME}" --service "${SVC}" \
        --desired-count 0 --region "${REGION}" >/dev/null
    done

    echo "==> Waiting for all tasks in '${CLUSTER_NAME}' to stop..."
    for i in $(seq 1 60); do   # up to ~10 min
      TASKS="$(aws ecs list-tasks --cluster "${CLUSTER_NAME}" --region "${REGION}" \
                --query 'length(taskArns)' --output text 2>/dev/null || echo 0)"
      [[ "${TASKS}" == "0" || "${TASKS}" == "None" ]] && { echo "    running tasks: 0"; break; }
      echo "    tasks still running: ${TASKS} (waited $((i*10))s)"
      sleep 10
    done
  fi
fi

# --- Step 2: scale the ASG to zero so instances terminate & deregister ------
if aws autoscaling describe-auto-scaling-groups \
      --auto-scaling-group-names "${ASG_NAME}" --region "${REGION}" \
      --query 'AutoScalingGroups[0].AutoScalingGroupName' --output text 2>/dev/null \
      | grep -q "${ASG_NAME}"; then

  # Suspend Launch/AlarmNotification/ReplaceUnhealthy FIRST. The ECS capacity
  # provider's managed (target-tracking) scaling policy will otherwise raise the
  # ASG's desired capacity back up and relaunch instances even with services at
  # 0 — instances respawn forever. Suspending Launch makes it physically unable
  # to create instances; suspending AlarmNotification stops the policy acting.
  # Terminate is left ENABLED so the scale-to-0 below actually removes instances.
  echo "==> Suspending ASG scaling processes (Launch, AlarmNotification, ReplaceUnhealthy)..."
  aws autoscaling suspend-processes \
    --auto-scaling-group-name "${ASG_NAME}" \
    --scaling-processes Launch AlarmNotification ReplaceUnhealthy \
    --region "${REGION}"

  echo "==> Scaling ASG '${ASG_NAME}' to 0 (min=0, desired=0)..."
  aws autoscaling update-auto-scaling-group \
    --auto-scaling-group-name "${ASG_NAME}" \
    --min-size 0 --desired-capacity 0 --region "${REGION}"

  echo "==> Waiting for ECS container instances to deregister from '${CLUSTER_NAME}'..."
  for i in $(seq 1 60); do   # up to ~10 min
    COUNT="$(aws ecs list-container-instances \
              --cluster "${CLUSTER_NAME}" --region "${REGION}" \
              --query 'length(containerInstanceArns)' --output text 2>/dev/null || echo 0)"
    [[ "${COUNT}" == "0" || "${COUNT}" == "None" ]] && { echo "    container instances: 0"; break; }
    echo "    container instances still registered: ${COUNT} (waited $((i*10))s)"
    sleep 10
  done
else
  echo "==> ASG '${ASG_NAME}' not found (already gone?). Skipping scale-down."
fi

# --- Step 3: terraform destroy --------------------------------------------
echo "==> Running terraform destroy..."
terraform destroy -auto-approve

echo "==> Done. Verifying state is empty:"
REMAINING="$(terraform state list 2>/dev/null | wc -l | tr -d ' ')"
echo "    resources left in state: ${REMAINING}"
if [[ "${REMAINING}" != "0" ]]; then
  echo "    NOTE: some resources remain. Re-run this script — a transient AWS" >&2
  echo "    ENI DependencyViolation sometimes needs a second destroy pass." >&2
  exit 1
fi
echo "==> Teardown complete."
