#!/usr/bin/env bash
#
# Verify medical-application deployments and expected network connectivity.
#
# Usage:
#   ./scripts/verify-medical-application-network.sh
#   ./scripts/verify-medical-application-network.sh --wait 180
#   ./scripts/verify-medical-application-network.sh --skip-connectivity
#
# Exit codes:
#   0 — all required checks passed
#   1 — one or more required checks failed

set -euo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly PROBE_POD_PREFIX="medical-netcheck"
readonly CURL_IMAGE="${CURL_IMAGE:-curlimages/curl:8.8.0}"
readonly PROBE_NAMESPACE="${NAMESPACE:-frontend}"

WAIT_TIMEOUT=0
SKIP_CONNECTIVITY=false

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

REQUIRED_PASS=0
REQUIRED_FAIL=0
WARN_COUNT=0

readonly MEDICAL_NAMESPACES=(frontend backend payments medical operations)

# Deployments that must be Available (namespace/deployment)
readonly -a REQUIRED_DEPLOYMENTS=(
    "frontend/asset-cache"
    "frontend/tls-proxy"
    "frontend/wordpress"
    "frontend/monitor"
    "backend/api-server"
    "backend/backend-atlas"
    "backend/varnish"
    "backend/postgres"
    "payments/gateway"
    "payments/visa-processor"
    "payments/mastercard-processor"
    "medical/patient-db"
    "medical/reporting"
    "operations/jump-host"
    "operations/puppet-master"
)

# Services that must have ready endpoints (namespace/service)
readonly -a REQUIRED_SERVICES=(
    "frontend/asset-cache-service"
    "frontend/tls-proxy-service"
    "frontend/wordpress-service"
    "backend/api-server-service"
    "backend/backend-atlas-service"
    "backend/postgres-service"
    "backend/varnish-service"
    "payments/gateway-service"
    "payments/visa-processor-service"
    "payments/mastercard-processor-service"
    "medical/patient-db-service"
    "medical/reporting-service"
    "operations/jump-host-service"
    "operations/pupper-master-service"
)

# Expected flows from netflow -connect in everything.yml
# Format: "target_host:port|description|required(yes|no)"
readonly -a EXPECTED_FLOWS=(
    "asset-cache-service.frontend.svc.cluster.local:8080|frontend: tls-proxy → asset-cache|yes"
    "wordpress-service.frontend.svc.cluster.local:80|frontend: tls-proxy → wordpress|yes"
    "api-server-service.backend.svc.cluster.local:9001|backend: varnish → api-server|yes"
    "backend-atlas-service.backend.svc.cluster.local:8080|backend: api-server → backend-atlas|yes"
    "postgres-service.backend.svc.cluster.local:5432|backend: api-server → postgres|yes"
    "gateway-service.payments.svc.cluster.local:7777|backend → payments: api-server → gateway|yes"
    "visa-processor-service.payments.svc.cluster.local:8080|payments: gateway → visa-processor|yes"
    "mastercard-processor-service.payments.svc.cluster.local:8080|payments: gateway → mastercard-processor|yes"
    "visa-processor-service.payments.svc.cluster.local:8080|operations → payments: jump-host → visa|yes"
    "pupper-master-service.operations.svc.cluster.local:8140|operations: jump-host → puppet-master|yes"
    "patient-db-service.medical.svc.cluster.local:8080|medical: reporting → patient-db (deny-all NP may block)|no"
    "reporting-service.medical.svc.cluster.local:8080|medical: patient-db → reporting (deny-all NP may block)|no"
    "patient-db-service.medical.svc.cluster.local:8080|operations → medical: jump-host → patient-db (deny-all NP may block)|no"
)

print_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
print_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; WARN_COUNT=$((WARN_COUNT + 1)); }
print_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
print_step()  { echo -e "${BLUE}[STEP]${NC} $*"; }

usage() {
    cat <<EOF
${SCRIPT_NAME} — verify medical-application network health after deploy

Options:
  -w, --wait SECONDS       Wait for deployments to become Available (default: 0)
  --skip-connectivity      Only check namespaces, deployments, endpoints, netflow pods
  -n, --namespace NAME     Namespace for the probe pod (default: ${PROBE_NAMESPACE})
  -h, --help               Show this help

Checks:
  1. Medical-application namespaces and deployments are Available
  2. Services have ready endpoints
  3. Netflow (-connect) workloads are running
  4. TCP reachability for paths defined in everything.yml manifests

Optional flows (medical namespace / deny-all NetworkPolicy) are reported as warnings only.
EOF
}

resolve_kubectl() {
    if [[ -n "${KUBECTL:-}" ]]; then
        echo "${KUBECTL}"
        return
    fi
    if command -v oc >/dev/null 2>&1; then
        echo "oc"
    elif command -v kubectl >/dev/null 2>&1; then
        echo "kubectl"
    else
        print_error "Neither oc nor kubectl found in PATH"
        exit 1
    fi
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -w|--wait) WAIT_TIMEOUT="$2"; shift 2 ;;
            --skip-connectivity) SKIP_CONNECTIVITY=true; shift ;;
            -n|--namespace) PROBE_NAMESPACE="$2"; shift 2 ;;
            -h|--help) usage; exit 0 ;;
            *) print_error "Unknown option: $1"; usage >&2; exit 1 ;;
        esac
    done
}

record_required() {
    local ok="$1"
    local msg="$2"
    if [[ "${ok}" == "ok" ]]; then
        print_info "  PASS  ${msg}"
        REQUIRED_PASS=$((REQUIRED_PASS + 1))
    else
        print_error "  FAIL  ${msg}"
        REQUIRED_FAIL=$((REQUIRED_FAIL + 1))
    fi
}

record_optional() {
    local ok="$1"
    local msg="$2"
    if [[ "${ok}" == "ok" ]]; then
        print_info "  PASS  ${msg}"
    else
        print_warn "  WARN  ${msg}"
    fi
}

check_cluster() {
    local kube="$1"
    print_step "Cluster access"
    if "${kube}" cluster-info >/dev/null 2>&1; then
        print_info "Cluster reachable"
    else
        print_error "Cannot reach cluster"
        exit 1
    fi
}

check_namespaces() {
    local kube="$1"
    print_step "Namespaces"
    local ns missing=0
    for ns in "${MEDICAL_NAMESPACES[@]}"; do
        if "${kube}" get namespace "${ns}" >/dev/null 2>&1; then
            print_info "  namespace/${ns} exists"
        else
            print_error "  namespace/${ns} missing"
            missing=$((missing + 1))
        fi
    done
    if [[ "${missing}" -gt 0 ]]; then
        print_error "Apply k8s-deployment-manifests/-namespaces/ and medical-application/ first"
        exit 1
    fi
}

wait_for_deployments() {
    local kube="$1"
    [[ "${WAIT_TIMEOUT}" -gt 0 ]] || return 0
    print_step "Waiting up to ${WAIT_TIMEOUT}s for deployments..."
    local ns deploy
    for entry in "${REQUIRED_DEPLOYMENTS[@]}"; do
        ns="${entry%%/*}"
        deploy="${entry##*/}"
        if ! "${kube}" wait --for=condition=Available "deployment/${deploy}" \
            -n "${ns}" --timeout="${WAIT_TIMEOUT}s" >/dev/null 2>&1; then
            print_warn "  deployment/${ns}/${deploy} not Available within ${WAIT_TIMEOUT}s"
        fi
    done
}

check_deployments() {
    local kube="$1"
    print_step "Deployments (required)"
    local ns deploy ready
    for entry in "${REQUIRED_DEPLOYMENTS[@]}"; do
        ns="${entry%%/*}"
        deploy="${entry##*/}"
        ready=$("${kube}" get deployment "${deploy}" -n "${ns}" \
            -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "")
        if [[ "${ready}" == "True" ]]; then
            record_required "ok" "${ns}/${deploy} Available"
        else
            record_required "fail" "${ns}/${deploy} not Available"
            "${kube}" get pods -n "${ns}" -l "app=${deploy}" 2>/dev/null | head -5 >&2 || true
        fi
    done
}

check_service_endpoints() {
    local kube="$1"
    print_step "Service endpoints"
    local ns svc endpoints
    for entry in "${REQUIRED_SERVICES[@]}"; do
        ns="${entry%%/*}"
        svc="${entry##*/}"
        endpoints=$("${kube}" get endpoints "${svc}" -n "${ns}" \
            -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || echo "")
        if [[ -n "${endpoints}" ]]; then
            record_required "ok" "${ns}/${svc} has ready endpoints"
        else
            record_required "fail" "${ns}/${svc} has no ready endpoints"
        fi
    done
}

check_netflow_pods() {
    local kube="$1"
    print_step "Netflow workloads (automatic -connect traffic)"
    local ns netflow_count=0
    for ns in "${MEDICAL_NAMESPACES[@]}"; do
        while read -r _; do
            netflow_count=$((netflow_count + 1))
        done < <("${kube}" get pods -n "${ns}" --field-selector=status.phase=Running \
            -o jsonpath='{range .items[*]}{range .spec.containers[?(@.image)]}{.image}{"\n"}{end}{end}' 2>/dev/null \
            | grep 'rhacs-demo/netflow' || true)
    done

    if [[ "${netflow_count}" -ge 5 ]]; then
        record_required "ok" "${netflow_count} running netflow container(s) found"
    elif [[ "${netflow_count}" -gt 0 ]]; then
        record_required "fail" "only ${netflow_count} netflow container(s) running (expected several)"
    else
        record_required "fail" "no rhacs-demo/netflow containers running (check image pull / rhacs-demo-pull-pull-secret)"
    fi

    local entry deploy pod spec
    for entry in "backend/api-server" "backend/varnish" "frontend/tls-proxy" "payments/gateway" "medical/patient-db" "operations/jump-host"; do
        ns="${entry%%/*}"
        deploy="${entry##*/}"
        pod=$("${kube}" get pods -n "${ns}" -l "app=${deploy}" \
            -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [[ -z "${pod}" ]]; then
            record_required "fail" "${ns}/${deploy}: no pod found"
            continue
        fi
        spec=$("${kube}" get pod "${pod}" -n "${ns}" \
            -o jsonpath='{range .spec.containers[*]}{.image}{" "}{.args}{" "}{.command}{" "}{end}' 2>/dev/null || echo "")
        if [[ "${spec}" == *"netflow"* && "${spec}" == *"connect"* ]]; then
            record_required "ok" "${ns}/${deploy}: netflow -connect configured"
        else
            record_required "fail" "${ns}/${deploy}: missing netflow -connect configuration"
        fi
    done
}

probe_pod_name() {
    echo "${PROBE_POD_PREFIX}-$$"
}

create_probe_pod() {
    local kube="$1"
    local pod="$2"
    "${kube}" run "${pod}" \
        -n "${PROBE_NAMESPACE}" \
        --restart=Never \
        --image="${CURL_IMAGE}" \
        --command -- sleep 600 \
        >/dev/null
    "${kube}" wait --for=condition=Ready "pod/${pod}" \
        -n "${PROBE_NAMESPACE}" --timeout=120s >/dev/null
}

delete_probe_pod() {
    local kube="$1"
    local pod="$2"
    "${kube}" delete pod "${pod}" -n "${PROBE_NAMESPACE}" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}

probe_tcp() {
    local kube="$1"
    local pod="$2"
    local host_port="$3"
    local host="${host_port%:*}"
    local port="${host_port##*:}"
    if "${kube}" exec -n "${PROBE_NAMESPACE}" "${pod}" -- \
        curl -s -m 5 "telnet://${host}:${port}" >/dev/null 2>&1; then
        echo "ok"
    else
        echo "fail"
    fi
}

check_connectivity() {
    local kube="$1"
    print_step "TCP connectivity (paths from everything.yml)"
    local pod
    pod=$(probe_pod_name)
    trap 'delete_probe_pod "'"${kube}"'" "'"${pod}"'"' RETURN
    create_probe_pod "${kube}" "${pod}"
    print_info "Probing from ${PROBE_NAMESPACE}/${pod}"

    local entry target desc required result
    for entry in "${EXPECTED_FLOWS[@]}"; do
        target="${entry%%|*}"
        rest="${entry#*|}"
        desc="${rest%|*}"
        required="${rest##*|}"
        result=$(probe_tcp "${kube}" "${pod}" "${target}")
        if [[ "${required}" == "yes" ]]; then
            record_required "${result}" "${desc} (${target})"
        else
            record_optional "${result}" "${desc} (${target})"
        fi
    done
    delete_probe_pod "${kube}" "${pod}"
    trap - RETURN
}

print_summary() {
    echo
    print_step "Summary"
    print_info "Required checks passed: ${REQUIRED_PASS}"
    if [[ "${REQUIRED_FAIL}" -gt 0 ]]; then
        print_error "Required checks failed: ${REQUIRED_FAIL}"
    fi
    if [[ "${WARN_COUNT}" -gt 0 ]]; then
        print_info "Optional / medical-namespace warnings: ${WARN_COUNT}"
    fi
    echo
    if [[ "${REQUIRED_FAIL}" -eq 0 ]]; then
        print_info "Medical-application network verification PASSED"
        print_info "Netflow pods generate east-west traffic continuously; optional: run scripts/generate-medical-application-traffic.sh for extra HTTP probes"
        return 0
    fi
    print_error "Medical-application network verification FAILED"
    print_info "Hints: oc describe pod -n <ns> <pod> | oc get events -n <ns> --sort-by=.lastTimestamp"
    return 1
}

main() {
    parse_args "$@"
    local kube
    kube=$(resolve_kubectl)

    print_info "=========================================="
    print_info "Medical application network verification"
    print_info "=========================================="

    check_cluster "${kube}"
    check_namespaces "${kube}"
    wait_for_deployments "${kube}"
    check_deployments "${kube}"
    check_service_endpoints "${kube}"
    check_netflow_pods "${kube}"

    if [[ "${SKIP_CONNECTIVITY}" == false ]]; then
        check_connectivity "${kube}"
    else
        print_info "Skipping connectivity probes (--skip-connectivity)"
    fi

    print_summary
}

main "$@"
