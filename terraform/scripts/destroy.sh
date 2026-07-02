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

# --- Step 1: scale the ASG to zero so instances terminate & deregister ------
if aws autoscaling describe-auto-scaling-groups \
      --auto-scaling-group-names "${ASG_NAME}" --region "${REGION}" \
      --query 'AutoScalingGroups[0].AutoScalingGroupName' --output text 2>/dev/null \
      | grep -q "${ASG_NAME}"; then

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

# --- Step 2: terraform destroy --------------------------------------------
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
