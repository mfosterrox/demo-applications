#!/usr/bin/env bash
#
# Generate network traffic across the medical-application demo namespaces.
# Use this to populate the RHACS Network Graph and netpol baselines during labs.
#
# Usage:
#   ./scripts/generate-medical-application-traffic.sh
#   ./scripts/generate-medical-application-traffic.sh --duration 600 --interval 3
#   ./scripts/generate-medical-application-traffic.sh --background
#
# Environment:
#   KUBECTL   Override kubectl/oc binary (default: oc if available, else kubectl)
#   NAMESPACE Namespace for the short-lived traffic pod (default: frontend)

set -euo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly TRAFFIC_POD_PREFIX="medical-traffic-gen"
readonly CURL_IMAGE="${CURL_IMAGE:-curlimages/curl:8.8.0}"

DURATION=0          # 0 = run until interrupted
INTERVAL=5          # seconds between full sweep of endpoints
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
  -i, --interval SECONDS   Delay between full endpoint sweeps (default: ${INTERVAL})
  -n, --namespace NAME     Namespace for the traffic generator pod (default: ${TRAFFIC_NAMESPACE})
  -b, --background         Run in the background (logs to /tmp/${TRAFFIC_POD_PREFIX}.log)
  -h, --help               Show this help

The medical-application netflow sidecars already open periodic TCP connections.
This script adds HTTP/TCP probes from a curl pod so north-south and cross-namespace
flows show up clearly in RHACS Network Graph during workshops.
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

# HTTP endpoints: "url" or "url|optional_label"
readonly -a HTTP_ENDPOINTS=(
    "http://tls-proxy-service.frontend.svc.cluster.local/"
    "http://asset-cache-service.frontend.svc.cluster.local:8080/"
    "http://wordpress-service.frontend.svc.cluster.local/"
    "http://varnish-service.backend.svc.cluster.local:8080/"
    "http://api-server-service.backend.svc.cluster.local:9001/"
    "http://backend-atlas-service.backend.svc.cluster.local:8080/"
    "http://gateway-service.payments.svc.cluster.local:7777/"
    "http://visa-processor-service.payments.svc.cluster.local:8080/"
    "http://mastercard-processor-service.payments.svc.cluster.local:8080/"
    "http://patient-db-service.medical.svc.cluster.local:8080/"
    "http://reporting-service.medical.svc.cluster.local:8080/"
    "http://jump-host-service.operations.svc.cluster.local:8001/"
    "http://pupper-master-service.operations.svc.cluster.local:8140/"
)

# TCP endpoints: "host:port"
readonly -a TCP_ENDPOINTS=(
    "postgres-service.backend.svc.cluster.local:5432"
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

wait_for_workloads() {
    local kube="$1"
    print_step "Waiting for medical-application deployments to become available..."
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
    print_step "Starting traffic generator pod ${TRAFFIC_NAMESPACE}/${pod}..."
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
    print_info "Traffic pod ready"
}

delete_traffic_pod() {
    local kube="$1"
    local pod="$2"
    "${kube}" delete pod "${pod}" -n "${TRAFFIC_NAMESPACE}" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}

probe_http() {
    local kube="$1"
    local pod="$2"
    local url="$3"
    "${kube}" exec -n "${TRAFFIC_NAMESPACE}" "${pod}" -- \
        curl -sf -m 5 -o /dev/null -w "%{http_code}" "${url}" 2>/dev/null || echo "000"
}

probe_tcp() {
    local kube="$1"
    local pod="$2"
    local host_port="$3"
    local host="${host_port%:*}"
    local port="${host_port##*:}"
    if "${kube}" exec -n "${TRAFFIC_NAMESPACE}" "${pod}" -- \
        curl -sf -m 3 "telnet://${host}:${port}" >/dev/null 2>&1; then
        echo "open"
    else
        echo "closed"
    fi
}

run_traffic_loop() {
    local kube="$1"
    local pod="$2"
    local start end now cycle

    start=$(date +%s)
    cycle=0

    trap 'print_info "Stopping traffic generation..."; delete_traffic_pod "'"${kube}"'" "'"${pod}"'"; exit 0' INT TERM

    print_info "Generating traffic (interval=${INTERVAL}s, duration=${DURATION:-until interrupted})"
    print_info "Press Ctrl+C to stop and remove the traffic pod"

    while true; do
        cycle=$((cycle + 1))
        now=$(date +%s)
        if [[ "${DURATION}" -gt 0 ]] && [[ $((now - start)) -ge "${DURATION}" ]]; then
            print_info "Duration reached (${DURATION}s), stopping"
            break
        fi

        print_info "Sweep #${cycle}"
        for url in "${HTTP_ENDPOINTS[@]}"; do
            code=$(probe_http "${kube}" "${pod}" "${url}")
            if [[ "${code}" == "000" ]]; then
                print_warn "  ${url} — unreachable"
            else
                print_info "  ${url} — HTTP ${code}"
            fi
        done

        for host_port in "${TCP_ENDPOINTS[@]}"; do
            status=$(probe_tcp "${kube}" "${pod}" "${host_port}")
            if [[ "${status}" == "open" ]]; then
                print_info "  tcp://${host_port} — open"
            else
                print_warn "  tcp://${host_port} — closed"
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
        print_info "Running in background; log: ${log}"
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
    wait_for_workloads "${kube}"

    local pod
    pod=$(traffic_pod_name)
    trap 'delete_traffic_pod "'"${kube}"'" "'"${pod}"'"' EXIT
    create_traffic_pod "${kube}" "${pod}"
    run_traffic_loop "${kube}" "${pod}"
}

main "$@"
