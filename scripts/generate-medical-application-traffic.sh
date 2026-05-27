#!/usr/bin/env bash
#
# Generate network traffic across the medical-application demo namespaces.
#
# How this demo app produces traffic:
#   - Most pods run quay.io/rhacs-demo/netflow with /bin/entrypoint -listen/-connect.
#     Those containers open listening ports and periodically dial peer services (TCP).
#     That traffic starts automatically once pods are Ready — no script required.
#   - Struts apps (asset-cache, backend-atlas, visa/mastercard processors) and WordPress
#     are real HTTP servers. This script sends benign GET requests to them.
#   - The medical namespace has a default-deny NetworkPolicy; cross-namespace probes from
#     a curl pod often fail until policies are relaxed (expected for the CIS demo).
#
# Usage:
#   ./scripts/generate-medical-application-traffic.sh
#   ./scripts/generate-medical-application-traffic.sh --duration 600 --interval 3
#   ./scripts/generate-medical-application-traffic.sh --background

set -euo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly TRAFFIC_POD_PREFIX="medical-traffic-gen"
readonly CURL_IMAGE="${CURL_IMAGE:-curlimages/curl:8.8.0}"

DURATION=0
INTERVAL=5
BACKGROUND=false
TRAFFIC_NAMESPACE="${NAMESPACE:-frontend}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
print_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
print_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
print_step()  { echo -e "${BLUE}[STEP]${NC} $*"; }

usage() {
    cat <<EOF
${SCRIPT_NAME} — generate traffic for the medical-application Kubernetes demo

Options:
  -d, --duration SECONDS   Stop after SECONDS (default: 0 = until Ctrl+C)
  -i, --interval SECONDS   Delay between sweeps (default: ${INTERVAL})
  -n, --namespace NAME     Namespace for the curl traffic pod (default: ${TRAFFIC_NAMESPACE})
  -b, --background         Run in background (log: /tmp/${TRAFFIC_POD_PREFIX}.log)
  -h, --help               Show this help

Traffic model:
  1. Netflow pods (-connect in manifests) produce east-west TCP flows continuously.
  2. This script supplements with HTTP GETs to Struts/WordPress services only.
  3. Netflow listeners are checked with TCP connect (not HTTP).
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
            -d|--duration) DURATION="$2"; shift 2 ;;
            -i|--interval) INTERVAL="$2"; shift 2 ;;
            -n|--namespace) TRAFFIC_NAMESPACE="$2"; shift 2 ;;
            -b|--background) BACKGROUND=true; shift ;;
            -h|--help) usage; exit 0 ;;
            *) print_error "Unknown option: $1"; usage >&2; exit 1 ;;
        esac
    done
}

# Real HTTP applications (Struts / WordPress). Format: "url|label"
readonly -a HTTP_APPS=(
    "http://asset-cache-service.frontend.svc.cluster.local:8080/|asset-cache (Struts)"
    "http://backend-atlas-service.backend.svc.cluster.local:8080/|backend-atlas (Struts)"
    "http://visa-processor-service.payments.svc.cluster.local:8080/|visa-processor (Struts)"
    "http://mastercard-processor-service.payments.svc.cluster.local:8080/|mastercard-processor (Struts)"
    "http://wordpress-service.frontend.svc.cluster.local/|wordpress"
    "http://tls-proxy-service.frontend.svc.cluster.local/|tls-proxy (netflow listener on :80)"
)

# Netflow / non-HTTP listeners — TCP connect only. Format: "host:port|label"
readonly -a TCP_LISTENERS=(
    "asset-cache-service.frontend.svc.cluster.local:8080|asset-cache (also HTTP)"
    "varnish-service.backend.svc.cluster.local:8080|varnish (netflow)"
    "api-server-service.backend.svc.cluster.local:9001|api-server (netflow)"
    "gateway-service.payments.svc.cluster.local:7777|gateway (netflow)"
    "postgres-service.backend.svc.cluster.local:5432|postgres (netflow)"
    "patient-db-service.medical.svc.cluster.local:8080|patient-db (netflow; may be blocked by deny-all NP)"
    "reporting-service.medical.svc.cluster.local:8080|reporting (netflow; may be blocked by deny-all NP)"
    "jump-host-service.operations.svc.cluster.local:8001|jump-host (SSH via service port)"
    "pupper-master-service.operations.svc.cluster.local:8140|puppet-master (netflow)"
)

readonly MEDICAL_NAMESPACES=(frontend backend payments medical operations)

check_prerequisites() {
    local kube="$1"
    if ! "${kube}" cluster-info >/dev/null 2>&1; then
        print_error "Cannot reach cluster (${kube} cluster-info failed)"
        exit 1
    fi

    local missing=0
    for ns in "${MEDICAL_NAMESPACES[@]}"; do
        if ! "${kube}" get namespace "${ns}" >/dev/null 2>&1; then
            print_warn "Namespace '${ns}' not found — deploy medical-application manifests first"
            missing=$((missing + 1))
        fi
    done
    if [[ "${missing}" -ge "${#MEDICAL_NAMESPACES[@]}" ]]; then
        print_error "No medical-application namespaces found"
        exit 1
    fi
}

check_netflow_workloads() {
    local kube="$1"
    print_step "Checking netflow workloads (built-in traffic generators)..."
    local count
    count=$("${kube}" get pods -A -o jsonpath='{range .items[*]}{.spec.containers[*].image}{"\n"}{end}' 2>/dev/null \
        | grep -c 'rhacs-demo/netflow' || true)
    if [[ "${count}" -gt 0 ]]; then
        print_info "Found ${count} netflow container(s) — -connect traffic runs inside those pods automatically"
    else
        print_warn "No quay.io/rhacs-demo/netflow containers found; east-west demo traffic may be missing"
    fi

    if ! "${kube}" get deployment monitor -n frontend >/dev/null 2>&1; then
        print_warn "Deployment frontend/monitor not found (optional traffic workload)"
    elif ! "${kube}" wait --for=condition=Available deployment/monitor -n frontend --timeout=60s >/dev/null 2>&1; then
        print_warn "frontend/monitor not Available — check image pull (rhacs-demo-pull-pull-secret)"
    else
        print_info "frontend/monitor is Available"
    fi
}

wait_for_workloads() {
    local kube="$1"
    print_step "Waiting for medical-application deployments..."
    local ns deploy
    for ns in "${MEDICAL_NAMESPACES[@]}"; do
        if ! "${kube}" get namespace "${ns}" >/dev/null 2>&1; then
            continue
        fi
        while read -r deploy; do
            [[ -z "${deploy}" ]] && continue
            if ! "${kube}" wait --for=condition=Available "deployment/${deploy}" \
                -n "${ns}" --timeout=120s >/dev/null 2>&1; then
                print_warn "Deployment ${ns}/${deploy} not ready within 120s (continuing)"
            fi
        done < <("${kube}" get deployment -n "${ns}" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
    done
}

traffic_pod_name() {
    echo "${TRAFFIC_POD_PREFIX}-$$"
}

create_traffic_pod() {
    local kube="$1"
    local pod="$2"
    print_step "Starting curl pod ${TRAFFIC_NAMESPACE}/${pod} for HTTP supplement..."
    "${kube}" run "${pod}" \
        -n "${TRAFFIC_NAMESPACE}" \
        --restart=Never \
        --image="${CURL_IMAGE}" \
        --command -- sleep 86400 \
        >/dev/null

    if ! "${kube}" wait --for=condition=Ready "pod/${pod}" \
        -n "${TRAFFIC_NAMESPACE}" --timeout=120s >/dev/null; then
        print_error "Traffic pod ${pod} did not become Ready"
        "${kube}" describe pod "${pod}" -n "${TRAFFIC_NAMESPACE}" >&2 || true
        exit 1
    fi
}

delete_traffic_pod() {
    local kube="$1"
    local pod="$2"
    "${kube}" delete pod "${pod}" -n "${TRAFFIC_NAMESPACE}" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}

probe_http_app() {
    local kube="$1"
    local pod="$2"
    local url="$3"
    # Do not use -f: Struts/WordPress may return 4xx/5xx but still prove HTTP reachability.
    "${kube}" exec -n "${TRAFFIC_NAMESPACE}" "${pod}" -- \
        curl -s -m 8 -o /dev/null -w "%{http_code}" "${url}" 2>/dev/null || echo "000"
}

probe_tcp() {
    local kube="$1"
    local pod="$2"
    local host_port="$3"
    local host="${host_port%:*}"
    local port="${host_port##*:}"
    if "${kube}" exec -n "${TRAFFIC_NAMESPACE}" "${pod}" -- \
        curl -s -m 5 "telnet://${host}:${port}" >/dev/null 2>&1; then
        echo "open"
    else
        echo "closed"
    fi
}

run_traffic_loop() {
    local kube="$1"
    local pod="$2"
    local start now cycle url label host_port

    start=$(date +%s)
    cycle=0

    trap 'print_info "Stopping..."; delete_traffic_pod "'"${kube}"'" "'"${pod}"'"; exit 0' INT TERM

    print_info "Sweeping HTTP apps + TCP listeners every ${INTERVAL}s (Ctrl+C to stop)"
    print_info "Primary mesh traffic: netflow -connect (already running in application pods)"

    while true; do
        cycle=$((cycle + 1))
        now=$(date +%s)
        if [[ "${DURATION}" -gt 0 ]] && [[ $((now - start)) -ge "${DURATION}" ]]; then
            print_info "Duration reached (${DURATION}s)"
            break
        fi

        print_info "--- Sweep #${cycle}: HTTP applications ---"
        for entry in "${HTTP_APPS[@]}"; do
            url="${entry%%|*}"
            label="${entry##*|}"
            code=$(probe_http_app "${kube}" "${pod}" "${url}")
            if [[ "${code}" == "000" ]]; then
                print_warn "  ${label} — unreachable (${url})"
            else
                print_info "  ${label} — HTTP ${code}"
            fi
        done

        print_info "--- Sweep #${cycle}: TCP listeners (netflow / SSH) ---"
        for entry in "${TCP_LISTENERS[@]}"; do
            host_port="${entry%%|*}"
            label="${entry##*|}"
            status=$(probe_tcp "${kube}" "${pod}" "${host_port}")
            if [[ "${status}" == "open" ]]; then
                print_info "  ${label} — tcp://${host_port} open"
            else
                print_warn "  ${label} — tcp://${host_port} closed (NP, pod not ready, or non-routable)"
            fi
        done

        sleep "${INTERVAL}"
    done

    delete_traffic_pod "${kube}" "${pod}"
}

main() {
    parse_args "$@"
    local kube
    kube=$(resolve_kubectl)

    if [[ "${BACKGROUND}" == true ]]; then
        local log="/tmp/${TRAFFIC_POD_PREFIX}.log"
        print_info "Background log: ${log}"
        nohup "${BASH_SOURCE[0]}" \
            --duration "${DURATION}" \
            --interval "${INTERVAL}" \
            --namespace "${TRAFFIC_NAMESPACE}" \
            >>"${log}" 2>&1 &
        print_info "PID $!"
        exit 0
    fi

    print_info "=========================================="
    print_info "Medical application traffic generator"
    print_info "=========================================="
    check_prerequisites "${kube}"
    check_netflow_workloads "${kube}"
    wait_for_workloads "${kube}"

    local pod
    pod=$(traffic_pod_name)
    trap 'delete_traffic_pod "'"${kube}"'" "'"${pod}"'"' EXIT
    create_traffic_pod "${kube}" "${pod}"
    run_traffic_loop "${kube}" "${pod}"
}

main "$@"
