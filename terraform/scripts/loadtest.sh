#!/usr/bin/env bash
#
# loadtest.sh — drive HTTP load at a Starflix ALB and watch ECS auto-scaling
# react, so you can verify that service (task) and cluster (host) scaling
# actually work.
#
# It resolves the target ALB DNS from `terraform output` (falling back to the
# naming convention + an AWS lookup), prints the environment's auto-scaling
# config for context, records a baseline, then generates load with whichever
# tool is available (hey > k6 > ab > a curl/xargs fallback) while a background
# monitor tails task counts, host counts, and scaling activities.
#
# It mutates NOTHING in Terraform/AWS — it only sends HTTP requests. Any scaling
# is AWS reacting to load; it scales back in on its own (slowly — see note).
#
# Usage:
#   scripts/loadtest.sh [environment] [aws_region]
#   scripts/loadtest.sh dev
#   scripts/loadtest.sh dev ap-south-1
#
# Tunables (environment variables):
#   TARGET=backend|frontend   Which service to hit         (default: backend)
#   DURATION=6m               Load duration (Ns|Nm or secs) (default: 6m)
#   CONCURRENCY=200           Concurrent connections        (default: 200)
#   ENDPOINT=/custom/path     Override the URL path         (default per target)
#
# Backend is the better target for CPU scaling — its /api/content/search does a
# full-text scan. CPU utilisation is measured against each task's *reserved*
# 256 CPU units (0.25 vCPU), so a modest load crosses the 60% target quickly.
#
# Exit code: 0 on completion. WARNs (missing tools/outputs) don't abort.
#
set -uo pipefail

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

pass() { printf '  %s✓%s %s\n' "${GREEN}" "${RESET}" "$1"; }
warn() { printf '  %s!%s %s\n' "${YELLOW}" "${RESET}" "$1"; }
fail() { printf '  %s✗%s %s\n' "${RED}"   "${RESET}" "$1"; }
info() { printf '  %s·%s %s\n' "${BLUE}"  "${RESET}" "$1"; }
section() { printf '\n%s── %s %s%s\n' "${BOLD}" "$1" "$(printf '─%.0s' $(seq 1 $((58 - ${#1}))))" "${RESET}"; }

# --- Config ----------------------------------------------------------------
TARGET="${TARGET:-backend}"
DURATION="${DURATION:-6m}"
CONCURRENCY="${CONCURRENCY:-200}"

# Resolve region (same logic as health-check.sh / destroy.sh).
REGION="${2:-${AWS_REGION:-}}"
if [[ -z "${REGION}" && -f terraform.tfvars ]]; then
  REGION="$(grep -E '^\s*aws_region' terraform.tfvars | head -1 | sed -E 's/.*=\s*"([^"]+)".*/\1/')"
fi
REGION="${REGION:-ap-south-1}"

PREFIX="starflix-${ENV}"
CLUSTER="${PREFIX}-cluster"
FRONTEND_SVC="${PREFIX}-svc-frontend"
BACKEND_SVC="${PREFIX}-svc-backend"

# Ports from tfvars (fall back to defaults).
BE_PORT="4000"; FE_PORT="80"
if [[ -f terraform.tfvars ]]; then
  v="$(grep -E '^\s*backend_port'  terraform.tfvars | head -1 | sed -E 's/.*=\s*([0-9]+).*/\1/')"; [[ -n "$v" ]] && BE_PORT="$v"
  v="$(grep -E '^\s*frontend_port' terraform.tfvars | head -1 | sed -E 's/.*=\s*([0-9]+).*/\1/')"; [[ -n "$v" ]] && FE_PORT="$v"
fi

# Convert a duration like "6m" / "90s" / "360" to whole seconds.
to_seconds() {
  local d="$1"
  case "$d" in
    *m) echo $(( ${d%m} * 60 )) ;;
    *s) echo "${d%s}" ;;
    *)  echo "$d" ;;
  esac
}
DURATION_SECS="$(to_seconds "${DURATION}")"

printf '%s' "${BOLD}"
echo "════════════════════════════════════════════════════════════════"
echo " Starflix load test — verify ECS auto-scaling"
echo "════════════════════════════════════════════════════════════════"
printf '%s' "${RESET}"
echo "  Environment : ${ENV}"
echo "  Region      : ${REGION}"
echo "  Target      : ${TARGET}"
echo "  Duration    : ${DURATION} (${DURATION_SECS}s)"
echo "  Concurrency : ${CONCURRENCY}"

# ===========================================================================
# 0. Prerequisites
# ===========================================================================
section "Prerequisites"
command -v aws >/dev/null 2>&1 && pass "aws CLI found" || { fail "aws CLI not found — required"; exit 1; }
command -v terraform >/dev/null 2>&1 && pass "terraform found" || warn "terraform not found — will fall back to AWS lookup for ALB DNS"

# Pick a load-generation tool, best first.
LOAD_TOOL=""
for t in hey k6 ab; do
  if command -v "$t" >/dev/null 2>&1; then LOAD_TOOL="$t"; break; fi
done
if [[ -n "${LOAD_TOOL}" ]]; then
  pass "load tool: ${LOAD_TOOL}"
else
  warn "no hey/k6/ab found — using a curl+xargs fallback (less precise)"
  LOAD_TOOL="curl-fallback"
fi

# ===========================================================================
# 1. Resolve target URL
# ===========================================================================
section "Target"

tf_out() { terraform output -raw "$1" 2>/dev/null; }

if [[ "${TARGET}" == "frontend" ]]; then
  DNS="$(tf_out frontend_alb_dns_name)"
  PORT="${FE_PORT}"; SERVICE="${FRONTEND_SVC}"
  PATH_DEFAULT="/"
else
  DNS="$(tf_out backend_alb_dns_name)"
  PORT="${BE_PORT}"; SERVICE="${BACKEND_SVC}"
  PATH_DEFAULT="/api/content/search?q=iron"
fi

# Fallback: look the ALB up by name if terraform output was unavailable.
if [[ -z "${DNS}" ]]; then
  warn "no terraform output — querying AWS for the ${TARGET} ALB"
  LB_NAME="${PREFIX}-${TARGET}"   # ALBs are named <prefix>-<service> by the alb module
  DNS="$(aws elbv2 describe-load-balancers --region "${REGION}" \
        --query "LoadBalancers[?contains(LoadBalancerName, '${TARGET}')].DNSName | [0]" \
        --output text 2>/dev/null)"
  [[ "${DNS}" == "None" ]] && DNS=""
fi

if [[ -z "${DNS}" ]]; then
  fail "could not resolve the ${TARGET} ALB DNS — is the stack deployed? (try: terraform output)"
  exit 1
fi

ENDPOINT="${ENDPOINT:-${PATH_DEFAULT}}"
if [[ "${PORT}" == "80" ]]; then
  URL="http://${DNS}${ENDPOINT}"
else
  URL="http://${DNS}:${PORT}${ENDPOINT}"
fi
pass "URL: ${URL}"

# Quick reachability probe before hammering it.
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "${URL}" 2>/dev/null || echo 000)"
if [[ "${code}" =~ ^2 ]]; then pass "reachable (HTTP ${code})"; else warn "probe returned HTTP ${code} — continuing anyway"; fi

# ===========================================================================
# 2. Auto-scaling config (context) + baseline
# ===========================================================================
section "Auto-scaling config (from terraform.tfvars)"
if [[ -f terraform.tfvars ]]; then
  for k in enable_service_autoscaling service_autoscaling_min service_autoscaling_max \
           service_autoscaling_cpu_target service_autoscaling_memory_target \
           ecs_min_size ecs_max_size ecs_instance_type; do
    val="$(grep -E "^\s*${k}\b" terraform.tfvars | head -1 | sed -E 's/.*=\s*//; s/\s*(#.*)?$//')"
    [[ -n "${val}" ]] && info "$(printf '%-34s = %s' "${k}" "${val}")"
  done
else
  warn "terraform.tfvars not found — skipping config readout"
fi

# Helper: current desired/running for both services.
svc_counts() {
  aws ecs describe-services --cluster "${CLUSTER}" \
    --services "${FRONTEND_SVC}" "${BACKEND_SVC}" --region "${REGION}" \
    --query 'services[].{svc:serviceName,desired:desiredCount,running:runningCount}' \
    --output text 2>/dev/null
}
# Helper: registered container instances (EC2 hosts) in the cluster.
host_count() {
  aws ecs describe-clusters --clusters "${CLUSTER}" --region "${REGION}" \
    --query 'clusters[0].registeredContainerInstancesCount' --output text 2>/dev/null
}

section "Baseline (before load)"
echo "${BOLD}  services:${RESET}"; svc_counts | sed 's/^/    /'
info "EC2 hosts registered: $(host_count)"

# ===========================================================================
# 3. Background monitor
# ===========================================================================
MON_STOP="$(mktemp)"; rm -f "${MON_STOP}"   # sentinel: exists => stop
monitor() {
  local t0 elapsed
  t0="$(date +%s)"
  while [[ ! -f "${MON_STOP}" ]]; do
    elapsed=$(( $(date +%s) - t0 ))
    printf '\n%s[+%3ds]%s ' "${BLUE}" "${elapsed}" "${RESET}"
    printf 'hosts=%s | ' "$(host_count)"
    svc_counts | awk '{printf "%s(d=%s,r=%s) ", $1, $2, $3}'
    # Show the most recent scaling activity, if any.
    local act
    act="$(aws application-autoscaling describe-scaling-activities \
          --service-namespace ecs --region "${REGION}" \
          --query 'ScalingActivities[0].Description' --output text 2>/dev/null)"
    [[ -n "${act}" && "${act}" != "None" ]] && printf '\n        %s↳ %s%s' "${YELLOW}" "${act}" "${RESET}"
    sleep 15
  done
}

section "Generating load  (monitor updates every 15s)"
info "watching: EC2 host count, per-service desired(d)/running(r), scaling activity"
info "expect ~3-4 min before task count climbs 1→2, then a 2nd host appears"

monitor &
MON_PID=$!
# Ensure the monitor is always cleaned up.
cleanup() { : > "${MON_STOP}"; kill "${MON_PID}" 2>/dev/null; wait "${MON_PID}" 2>/dev/null; rm -f "${MON_STOP}" "${K6_TMP:-}"; }
trap cleanup EXIT INT TERM

# ===========================================================================
# 4. Run the load
# ===========================================================================
case "${LOAD_TOOL}" in
  hey)
    hey -z "${DURATION}" -c "${CONCURRENCY}" "${URL}" >/dev/null 2>&1
    ;;
  k6)
    K6_TMP="$(mktemp --suffix=.js)"
    cat > "${K6_TMP}" <<EOF
import http from 'k6/http';
export const options = {
  stages: [
    { duration: '1m', target: $(( CONCURRENCY / 4 )) },
    { duration: '$(( DURATION_SECS > 120 ? DURATION_SECS - 120 : DURATION_SECS ))s', target: ${CONCURRENCY} },
    { duration: '1m', target: 0 },
  ],
};
export default function () { http.get('${URL}'); }
EOF
    k6 run "${K6_TMP}" >/dev/null 2>&1
    ;;
  ab)
    # ab needs a request count; drive by time with a high -n and -t as the cap.
    ab -t "${DURATION_SECS}" -c "${CONCURRENCY}" -n 1000000 "${URL}" >/dev/null 2>&1
    ;;
  curl-fallback)
    end=$(( $(date +%s) + DURATION_SECS ))
    while [[ $(date +%s) -lt ${end} ]]; do
      seq "${CONCURRENCY}" | xargs -P "${CONCURRENCY}" -I{} \
        curl -s -o /dev/null --max-time 10 "${URL}" 2>/dev/null
    done
    ;;
esac

# ===========================================================================
# 5. Stop monitor & report
# ===========================================================================
cleanup
trap - EXIT INT TERM

section "Load finished — final state"
echo "${BOLD}  services:${RESET}"; svc_counts | sed 's/^/    /'
info "EC2 hosts registered: $(host_count)"

section "Recent scaling activities"
aws application-autoscaling describe-scaling-activities \
  --service-namespace ecs --region "${REGION}" \
  --query 'ScalingActivities[0:6].{time:StartTime,desc:Description,status:StatusMessage}' \
  --output table 2>/dev/null || warn "could not read scaling activities"

section "Target-tracking alarms (ALARM = was scaling out)"
aws cloudwatch describe-alarms --region "${REGION}" \
  --query "MetricAlarms[?contains(AlarmName,'${PREFIX}') || contains(AlarmName,'TargetTracking')].{name:AlarmName,state:StateValue}" \
  --output table 2>/dev/null || warn "could not read alarms"

echo
pass "Done."
warn "Scale-IN is deliberately slow (~15 min of low CPU) — if tasks are still at"
warn "2, that's normal. Re-run 'aws ecs describe-services' later to see them drop."
echo
info "Tip: open CloudWatch → Container Insights to see CPU/mem cross the 60/70% lines."
info "To push more scaling steps, raise service_autoscaling_max & ecs_max_size, then apply."
