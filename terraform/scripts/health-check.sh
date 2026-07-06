#!/usr/bin/env bash
#
# health-check.sh — verify that the infrastructure Terraform provisioned for a
# Starflix environment actually exists and is healthy in AWS.
#
# It reads resource identifiers from `terraform output` (falling back to the
# naming convention when state is unavailable), then queries AWS for each one
# and reports PASS / WARN / FAIL. Read-only: it never mutates anything.
#
# Checks: prerequisites (aws/terraform/jq), backend state, VPC + subnets + NAT,
# security groups, VPC endpoints, ECR repos (and that images exist), IAM roles,
# S3 buckets, Secrets Manager secrets, ALBs + listeners + target-group health,
# ECS cluster + ASG + container instances, ECS services (running vs desired),
# CloudWatch dashboard + alarms, CodeBuild projects, and finally live HTTP
# probes against the frontend and backend ALBs.
#
# Usage:
#   scripts/health-check.sh [environment] [aws_region]
#   scripts/health-check.sh dev
#   scripts/health-check.sh dev ap-south-1
#
# Environment defaults to "dev". Region is auto-detected from the environment's
# terraform.tfvars (var "aws_region"), overridable via arg 2 or $AWS_REGION.
#
# Exit code: 0 if no FAILs, 1 if one or more checks FAILed. WARNs don't fail.
#
set -uo pipefail   # NOTE: no -e; we want every check to run and tally results.

ENV="${1:-dev}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="${SCRIPT_DIR}/../environments/${ENV}"

if [[ ! -d "${ENV_DIR}" ]]; then
  echo "ERROR: environment directory not found: ${ENV_DIR}" >&2
  exit 1
fi
cd "${ENV_DIR}"

# --- Colours (disabled when not a TTY) -------------------------------------
if [[ -t 1 ]]; then
  RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; RESET=''
fi

PASS_COUNT=0; WARN_COUNT=0; FAIL_COUNT=0

pass() { printf '  %s✓ PASS%s  %s\n' "${GREEN}" "${RESET}" "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
warn() { printf '  %s! WARN%s  %s\n' "${YELLOW}" "${RESET}" "$1"; WARN_COUNT=$((WARN_COUNT+1)); }
fail() { printf '  %s✗ FAIL%s  %s\n' "${RED}"   "${RESET}" "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }
info() { printf '  %s· %s%s\n' "${BLUE}" "$1" "${RESET}"; }
section() { printf '\n%s── %s %s%s\n' "${BOLD}" "$1" "$(printf '─%.0s' $(seq 1 $((60 - ${#1}))))" "${RESET}"; }

# --- Resolve region (same logic as destroy.sh) -----------------------------
REGION="${2:-${AWS_REGION:-}}"
if [[ -z "${REGION}" && -f terraform.tfvars ]]; then
  REGION="$(grep -E '^\s*aws_region' terraform.tfvars | head -1 | sed -E 's/.*=\s*"([^"]+)".*/\1/')"
fi
REGION="${REGION:-ap-south-1}"

PREFIX="starflix-${ENV}"

printf '%s' "${BOLD}"
echo "════════════════════════════════════════════════════════════════"
echo " Starflix infrastructure health check"
echo "════════════════════════════════════════════════════════════════"
printf '%s' "${RESET}"
echo "  Environment : ${ENV}"
echo "  Directory   : ${ENV_DIR}"
echo "  Region      : ${REGION}"
echo "  Name prefix : ${PREFIX}"

# ===========================================================================
# 0. Prerequisites
# ===========================================================================
section "Prerequisites"
for bin in aws terraform; do
  if command -v "${bin}" >/dev/null 2>&1; then pass "${bin} is installed"; else fail "${bin} is not installed"; fi
done
HAVE_JQ=0
if command -v jq >/dev/null 2>&1; then HAVE_JQ=1; pass "jq is installed"; else warn "jq not installed (some checks degrade gracefully)"; fi

if ACCOUNT="$(aws sts get-caller-identity --query Account --output text 2>/dev/null)"; then
  pass "AWS credentials valid (account ${ACCOUNT})"
else
  fail "AWS credentials invalid or expired — cannot reach AWS. Aborting."
  echo
  echo "${BOLD}Result: ${RED}unable to authenticate to AWS.${RESET}"
  exit 1
fi

# ===========================================================================
# Terraform state / outputs
# ===========================================================================
section "Terraform state"
if [[ -d .terraform ]]; then
  pass "terraform initialised (.terraform present)"
else
  warn "no .terraform dir — run 'terraform init' (outputs may be unavailable)"
fi

# Cache all outputs as JSON once (fast; avoids one CLI call per output).
TF_OUT_JSON=""
if [[ "${HAVE_JQ}" == "1" ]]; then
  TF_OUT_JSON="$(terraform output -json 2>/dev/null || echo '{}')"
fi

# out <output_name> [fallback] — resolve a terraform output, else fallback.
out() {
  local name="$1" fallback="${2:-}" val=""
  if [[ -n "${TF_OUT_JSON}" && "${TF_OUT_JSON}" != "{}" ]]; then
    # Flatten list/map outputs to a space-separated string so callers can
    # iterate them with a plain `for`. Scalars pass through unchanged.
    val="$(jq -r --arg k "${name}" '
      .[$k].value
      | if type=="array" then join(" ")
        elif type=="object" then [.[]] | join(" ")
        else (. // empty) end' <<<"${TF_OUT_JSON}" 2>/dev/null)"
  fi
  [[ -z "${val}" ]] && val="$(terraform output -raw "${name}" 2>/dev/null || true)"
  [[ -z "${val}" || "${val}" == "null" ]] && val="${fallback}"
  printf '%s' "${val}"
}

STATE_COUNT="$(terraform state list 2>/dev/null | wc -l | tr -d ' ')"
if [[ "${STATE_COUNT}" -gt 0 ]]; then
  pass "state contains ${STATE_COUNT} resources"
else
  warn "terraform state is empty or unreadable — falling back to name convention"
fi

# ===========================================================================
# 1. VPC + subnets + NAT
# ===========================================================================
section "Networking (VPC)"
VPC_ID="$(out vpc_id)"
if [[ -n "${VPC_ID}" ]]; then
  STATE="$(aws ec2 describe-vpcs --vpc-ids "${VPC_ID}" --region "${REGION}" \
            --query 'Vpcs[0].State' --output text 2>/dev/null || true)"
  [[ "${STATE}" == "available" ]] && pass "VPC ${VPC_ID} available" || fail "VPC ${VPC_ID} not available (state='${STATE:-missing}')"
else
  fail "no vpc_id output — VPC likely not created"
fi

check_subnets() {
  local kind="$1" ids; ids="$(out "$2")"
  [[ -z "${ids}" ]] && { warn "no ${kind}_subnet_ids output"; return; }
  local expected=0 avail=0
  for sid in ${ids}; do
    expected=$((expected+1))
    local s; s="$(aws ec2 describe-subnets --subnet-ids "${sid}" --region "${REGION}" \
                    --query 'Subnets[0].State' --output text 2>/dev/null || true)"
    [[ "${s}" == "available" ]] && avail=$((avail+1))
  done
  [[ "${avail}" == "${expected}" && "${expected}" -gt 0 ]] \
    && pass "${kind} subnets: ${avail}/${expected} available" \
    || fail "${kind} subnets: only ${avail}/${expected} available"
}
check_subnets "public"  public_subnet_ids
check_subnets "private" private_subnet_ids

NAT_IDS="$(out nat_gateway_ids)"
if [[ -n "${NAT_IDS}" ]]; then
  nat_ok=0; nat_total=0
  for n in ${NAT_IDS}; do
    nat_total=$((nat_total+1))
    st="$(aws ec2 describe-nat-gateways --nat-gateway-ids "${n}" --region "${REGION}" \
            --query 'NatGateways[0].State' --output text 2>/dev/null || true)"
    [[ "${st}" == "available" ]] && nat_ok=$((nat_ok+1))
  done
  [[ "${nat_ok}" == "${nat_total}" ]] && pass "NAT gateways: ${nat_ok}/${nat_total} available" \
                                      || fail "NAT gateways: only ${nat_ok}/${nat_total} available"
else
  warn "no nat_gateway_ids output"
fi

# ===========================================================================
# 2. Security groups
# ===========================================================================
section "Security groups"
for pair in "ALB:alb_security_group_id" "ECS:ecs_security_group_id" "VPC-endpoint:vpc_endpoint_security_group_id"; do
  label="${pair%%:*}"; sgid="$(out "${pair#*:}")"
  if [[ -n "${sgid}" ]]; then
    found="$(aws ec2 describe-security-groups --group-ids "${sgid}" --region "${REGION}" \
              --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true)"
    [[ "${found}" == "${sgid}" ]] && pass "${label} SG ${sgid} exists" || fail "${label} SG ${sgid} not found"
  else
    warn "no security group output for ${label}"
  fi
done

# ===========================================================================
# 3. VPC endpoints
# ===========================================================================
section "VPC endpoints"
GW_EP="$(out gateway_endpoint_id)"
if [[ -n "${GW_EP}" ]]; then
  st="$(aws ec2 describe-vpc-endpoints --vpc-endpoint-ids "${GW_EP}" --region "${REGION}" \
          --query 'VpcEndpoints[0].State' --output text 2>/dev/null || true)"
  [[ "${st}" == "available" ]] && pass "S3 gateway endpoint ${GW_EP} available" || fail "S3 gateway endpoint state='${st:-missing}'"
else
  warn "no gateway_endpoint_id output"
fi
IFACE_EPS="$(out interface_endpoint_ids)"
if [[ -n "${IFACE_EPS}" ]]; then
  # Output is a map when captured raw; strip to bare vpce-… ids.
  ep_ok=0; ep_total=0
  for ep in $(grep -oE 'vpce-[0-9a-f]+' <<<"${IFACE_EPS}"); do
    ep_total=$((ep_total+1))
    st="$(aws ec2 describe-vpc-endpoints --vpc-endpoint-ids "${ep}" --region "${REGION}" \
            --query 'VpcEndpoints[0].State' --output text 2>/dev/null || true)"
    [[ "${st}" == "available" ]] && ep_ok=$((ep_ok+1))
  done
  [[ "${ep_total}" -gt 0 && "${ep_ok}" == "${ep_total}" ]] && pass "interface endpoints: ${ep_ok}/${ep_total} available" \
    || { [[ "${ep_total}" -gt 0 ]] && fail "interface endpoints: only ${ep_ok}/${ep_total} available" || warn "no interface endpoint ids parsed"; }
else
  warn "no interface_endpoint_ids output"
fi

# ===========================================================================
# 4. ECR repositories (+ verify images were pushed)
# ===========================================================================
section "ECR repositories"
for pair in "frontend:frontend_ecr_repository_url" "backend:backend_ecr_repository_url"; do
  label="${pair%%:*}"; url="$(out "${pair#*:}")"
  # Repo names are namespaced (e.g. starflix-dev/frontend), so strip only the
  # registry host — NOT everything up to the last slash.
  repo="${PREFIX}/${label}"
  [[ -n "${url}" ]] && repo="${url##*.amazonaws.com/}"
  if aws ecr describe-repositories --repository-names "${repo}" --region "${REGION}" >/dev/null 2>&1; then
    imgs="$(aws ecr list-images --repository-name "${repo}" --region "${REGION}" \
              --query 'length(imageIds)' --output text 2>/dev/null || echo 0)"
    if [[ "${imgs}" -gt 0 ]]; then pass "ECR ${repo} exists (${imgs} images)"; else warn "ECR ${repo} exists but has 0 images (seed build may not have run)"; fi
  else
    fail "ECR repository ${repo} not found"
  fi
done

# ===========================================================================
# 5. IAM roles
# ===========================================================================
section "IAM roles"
for pair in "task-execution:ecs_task_execution_role_arn" "task:ecs_task_role_arn" "instance:ecs_instance_role_arn" "codebuild:codebuild_role_arn"; do
  label="${pair%%:*}"; arn="$(out "${pair#*:}")"
  if [[ -n "${arn}" ]]; then
    rn="${arn##*/}"
    if aws iam get-role --role-name "${rn}" >/dev/null 2>&1; then pass "IAM role ${rn} exists"; else fail "IAM role ${rn} not found"; fi
  else
    warn "no IAM role output for ${label}"
  fi
done

# ===========================================================================
# 6. S3 buckets
# ===========================================================================
section "S3 buckets"
for pair in "assets:assets_bucket_name" "artifacts:artifacts_bucket_name"; do
  label="${pair%%:*}"; b="$(out "${pair#*:}")"
  if [[ -n "${b}" ]]; then
    if aws s3api head-bucket --bucket "${b}" --region "${REGION}" >/dev/null 2>&1; then pass "S3 ${label} bucket ${b} reachable"; else fail "S3 ${label} bucket ${b} missing or inaccessible"; fi
  else
    warn "no ${label} bucket output"
  fi
done

# ===========================================================================
# 7. Secrets Manager
# ===========================================================================
section "Secrets Manager"
for pair in "TMDB:tmdb_api_key_arn" "GitHub:github_token_arn"; do
  label="${pair%%:*}"; arn="$(out "${pair#*:}")"
  if [[ -n "${arn}" ]]; then
    if aws secretsmanager describe-secret --secret-id "${arn}" --region "${REGION}" >/dev/null 2>&1; then pass "${label} secret exists"; else fail "${label} secret not found"; fi
  else
    warn "no ${label} secret output"
  fi
done

# ===========================================================================
# 8. Application Load Balancers + target group health
# ===========================================================================
section "Load balancers & target groups"
check_tg() {
  local label="$1" tg_arn="$2"
  [[ -z "${tg_arn}" ]] && { warn "no ${label} target group ARN output"; return; }
  local health
  health="$(aws elbv2 describe-target-health --target-group-arn "${tg_arn}" --region "${REGION}" \
              --query 'TargetHealthDescriptions[*].TargetHealth.State' --output text 2>/dev/null || true)"
  if [[ -z "${health}" ]]; then
    warn "${label} target group has no registered targets"
    return
  fi
  local total=0 healthy=0
  for s in ${health}; do total=$((total+1)); [[ "${s}" == "healthy" ]] && healthy=$((healthy+1)); done
  [[ "${healthy}" -gt 0 && "${healthy}" == "${total}" ]] && pass "${label} targets: ${healthy}/${total} healthy" \
    || { [[ "${healthy}" -gt 0 ]] && warn "${label} targets: ${healthy}/${total} healthy" || fail "${label} targets: 0/${total} healthy"; }
}

for pair in "frontend:frontend_alb_dns_name:frontend_target_group_arn" "backend:backend_alb_dns_name:backend_target_group_arn"; do
  label="$(cut -d: -f1 <<<"${pair}")"
  dns="$(out "$(cut -d: -f2 <<<"${pair}")")"
  tg="$(out "$(cut -d: -f3 <<<"${pair}")")"
  if [[ -n "${dns}" ]]; then
    st="$(aws elbv2 describe-load-balancers --region "${REGION}" \
            --query "LoadBalancers[?DNSName=='${dns}'].State.Code | [0]" --output text 2>/dev/null || true)"
    [[ "${st}" == "active" ]] && pass "${label} ALB active (${dns})" || fail "${label} ALB not active (state='${st:-missing}')"
  else
    fail "no ${label}_alb_dns_name output"
  fi
  check_tg "${label}" "${tg}"
done

# ===========================================================================
# 9. ECS cluster + capacity (ASG, container instances)
# ===========================================================================
section "ECS cluster & capacity"
CLUSTER="$(out ecs_cluster_name "${PREFIX}-cluster")"
ASG="$(out ecs_autoscaling_group_name "${PREFIX}-asg")"

CL_STATUS="$(aws ecs describe-clusters --clusters "${CLUSTER}" --region "${REGION}" \
              --query 'clusters[0].status' --output text 2>/dev/null || true)"
if [[ "${CL_STATUS}" == "ACTIVE" ]]; then
  CI="$(aws ecs list-container-instances --cluster "${CLUSTER}" --region "${REGION}" \
          --query 'length(containerInstanceArns)' --output text 2>/dev/null || echo 0)"
  pass "ECS cluster ${CLUSTER} ACTIVE (${CI} container instances)"
  [[ "${CI}" -gt 0 ]] || warn "cluster has 0 registered container instances — no capacity to run tasks"
else
  fail "ECS cluster ${CLUSTER} not ACTIVE (status='${CL_STATUS:-missing}')"
fi

ASG_INFO="$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "${ASG}" --region "${REGION}" \
             --query 'AutoScalingGroups[0].[DesiredCapacity,length(Instances[?LifecycleState==`InService`])]' \
             --output text 2>/dev/null || true)"
if [[ -n "${ASG_INFO}" && "${ASG_INFO}" != "None" ]]; then
  desired="$(awk '{print $1}' <<<"${ASG_INFO}")"; inservice="$(awk '{print $2}' <<<"${ASG_INFO}")"
  [[ "${inservice}" -ge "${desired}" && "${desired}" -gt 0 ]] && pass "ASG ${ASG}: ${inservice}/${desired} instances InService" \
    || warn "ASG ${ASG}: ${inservice}/${desired} instances InService"
else
  fail "ASG ${ASG} not found"
fi

# ===========================================================================
# 10. ECS services (running vs desired)
# ===========================================================================
section "ECS services"
check_service() {
  local label="$1" svc="$2"
  local info; info="$(aws ecs describe-services --cluster "${CLUSTER}" --services "${svc}" --region "${REGION}" \
              --query 'services[0].[status,desiredCount,runningCount]' --output text 2>/dev/null || true)"
  if [[ -z "${info}" || "${info}" == "None"* ]]; then fail "${label} service ${svc} not found"; return; fi
  local status desired running
  status="$(awk '{print $1}' <<<"${info}")"; desired="$(awk '{print $2}' <<<"${info}")"; running="$(awk '{print $3}' <<<"${info}")"
  if [[ "${status}" == "ACTIVE" && "${running}" -ge "${desired}" && "${desired}" -gt 0 ]]; then
    pass "${label} service ACTIVE (${running}/${desired} tasks running)"
  elif [[ "${status}" == "ACTIVE" ]]; then
    warn "${label} service ACTIVE but ${running}/${desired} tasks running"
  else
    fail "${label} service status='${status}' (${running}/${desired} tasks)"
  fi
}
check_service "frontend" "$(out frontend_service_name "${PREFIX}-svc-frontend")"
check_service "backend"  "$(out backend_service_name  "${PREFIX}-svc-backend")"

# ===========================================================================
# 11. CloudWatch (dashboard + alarms)
# ===========================================================================
section "CloudWatch"
DASH="$(out cloudwatch_dashboard_name "${PREFIX}-dashboard")"
if aws cloudwatch get-dashboard --dashboard-name "${DASH}" --region "${REGION}" >/dev/null 2>&1; then
  pass "dashboard ${DASH} exists"
else
  warn "dashboard ${DASH} not found"
fi
ALARM_TOTAL="$(aws cloudwatch describe-alarms --alarm-name-prefix "${PREFIX}" --region "${REGION}" \
                --query 'length(MetricAlarms)' --output text 2>/dev/null || echo 0)"
if [[ "${ALARM_TOTAL}" -gt 0 ]]; then
  IN_ALARM="$(aws cloudwatch describe-alarms --alarm-name-prefix "${PREFIX}" --state-value ALARM --region "${REGION}" \
               --query 'length(MetricAlarms)' --output text 2>/dev/null || echo 0)"
  [[ "${IN_ALARM}" == "0" ]] && pass "${ALARM_TOTAL} alarms configured, none in ALARM state" \
                             || warn "${IN_ALARM}/${ALARM_TOTAL} alarms currently in ALARM state"
else
  warn "no CloudWatch alarms found with prefix ${PREFIX}"
fi

# ===========================================================================
# 12. CodeBuild projects
# ===========================================================================
section "CodeBuild"
for pair in "frontend:frontend_codebuild_project" "backend:backend_codebuild_project"; do
  label="${pair%%:*}"; proj="$(out "${pair#*:}" "${PREFIX}-${label}-build")"
  if aws codebuild batch-get-projects --names "${proj}" --region "${REGION}" \
        --query 'projects[0].name' --output text 2>/dev/null | grep -q "${proj}"; then
    pass "CodeBuild project ${proj} exists"
  else
    fail "CodeBuild project ${proj} not found"
  fi
done

# ===========================================================================
# 13. Live HTTP probes (end-to-end reachability)
# ===========================================================================
section "Live HTTP probes"
BE_PORT="4000"
[[ -f terraform.tfvars ]] && BE_PORT="$(grep -E '^\s*backend_port' terraform.tfvars | head -1 | sed -E 's/.*=\s*([0-9]+).*/\1/' || echo 4000)"

probe() {
  local label="$1" url="$2"
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "${url}" 2>/dev/null || echo 000)"
  if [[ "${code}" =~ ^[23] ]]; then pass "${label} responded HTTP ${code} (${url})"
  elif [[ "${code}" == "000" ]]; then fail "${label} unreachable (${url})"
  else warn "${label} responded HTTP ${code} (${url})"; fi
}
if command -v curl >/dev/null 2>&1; then
  FE_DNS="$(out frontend_alb_dns_name)"; BE_DNS="$(out backend_alb_dns_name)"
  [[ -n "${FE_DNS}" ]] && probe "frontend ALB" "http://${FE_DNS}/" || warn "no frontend ALB DNS to probe"
  [[ -n "${BE_DNS}" ]] && probe "backend ALB"  "http://${BE_DNS}:${BE_PORT}/api/content/featured" || warn "no backend ALB DNS to probe"
else
  warn "curl not installed — skipping HTTP probes"
fi

# ===========================================================================
# Summary
# ===========================================================================
printf '\n%s' "${BOLD}"
echo "════════════════════════════════════════════════════════════════"
printf ' Summary:  %s%d passed%s   %s%d warnings%s   %s%d failed%s\n' \
  "${GREEN}" "${PASS_COUNT}" "${RESET}${BOLD}" \
  "${YELLOW}" "${WARN_COUNT}" "${RESET}${BOLD}" \
  "${RED}" "${FAIL_COUNT}" "${RESET}${BOLD}"
echo "════════════════════════════════════════════════════════════════"
printf '%s' "${RESET}"

if [[ "${FAIL_COUNT}" -gt 0 ]]; then
  echo "${RED}Infrastructure has failures — investigate the FAIL lines above.${RESET}"
  exit 1
fi
if [[ "${WARN_COUNT}" -gt 0 ]]; then
  echo "${YELLOW}Infrastructure is up, with warnings worth reviewing.${RESET}"
  exit 0
fi
echo "${GREEN}All checks passed — infrastructure looks healthy.${RESET}"
exit 0
