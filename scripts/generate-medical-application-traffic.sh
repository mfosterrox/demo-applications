#!/usr/bin/env bash
#
# Generate pod-to-pod network traffic for the medical-application demo by exec'ing
# into each netflow (or entrypoint) container and dialing the same targets as -connect
# in everything.yml — e.g. tls-proxy → asset-cache, api-server → gateway, etc.
#
# Usage:
#   ./scripts/generate-medical-application-traffic.sh
#   ./scripts/generate-medical-application-traffic.sh --duration 600 --interval 10
#   ./scripts/generate-medical-application-traffic.sh --background

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=medical-application-netflow-flows.sh
source "${SCRIPT_DIR}/medical-application-netflow-flows.sh"

readonly SCRIPT_NAME="${0##*/}"
readonly LOG_PREFIX="medical-traffic"

DURATION=0
INTERVAL=10
BACKGROUND=false

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
${SCRIPT_NAME} — mimic medical-application netflow -connect traffic from source pods

Execs into each workload container (tls-proxy, api-server, gateway, etc.) and opens
TCP connections to every target listed in that deployment's -connect args — the same
pod-to-pod paths RHACS Network Graph should display.

Options:
  -d, --duration SECONDS   Stop after SECONDS (default: 0 = until Ctrl+C)
  -i, --interval SECONDS   Seconds between full flow sweeps (default: ${INTERVAL})
  -b, --background         Run in background (log: /tmp/${LOG_PREFIX}.log)
  -h, --help               Show this help

Netflow still runs -connect in the background; this script adds visible, repeatable
dials for demos and lab verification.
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--duration) DURATION="$2"; shift 2 ;;
            -i|--interval) INTERVAL="$2"; shift 2 ;;
            -b|--background) BACKGROUND=true; shift ;;
            -h|--help) usage; exit 0 ;;
            *) print_error "Unknown option: $1"; usage >&2; exit 1 ;;
        esac
    done
}

check_prerequisites() {
    local kube="$1"
    if ! medical_resolve_kubectl >/dev/null; then
        print_error "Neither oc nor kubectl found in PATH"
        exit 1
    fi
    if ! "${kube}" cluster-info >/dev/null 2>&1; then
        print_error "Cannot reach cluster"
        exit 1
    fi
    local ns missing=0
    for ns in "${MEDICAL_APP_NAMESPACES[@]}"; do
        if ! "${kube}" get namespace "${ns}" >/dev/null 2>&1; then
            print_warn "Namespace '${ns}' not found"
            missing=$((missing + 1))
        fi
    done
    if [[ "${missing}" -ge "${#MEDICAL_APP_NAMESPACES[@]}" ]]; then
        print_error "Deploy medical-application manifests first"
        exit 1
    fi
}

run_traffic_loop() {
    local kube="$1"
    local start now cycle ok fail warn line status rest msg detail

    start=$(date +%s)
    cycle=0

    trap 'print_info "Stopped."; exit 0' INT TERM

    print_info "Dialing -connect targets from inside source pods every ${INTERVAL}s"
    print_info "Press Ctrl+C to stop"

    while true; do
        cycle=$((cycle + 1))
        now=$(date +%s)
        if [[ "${DURATION}" -gt 0 ]] && [[ $((now - start)) -ge "${DURATION}" ]]; then
            print_info "Duration reached (${DURATION}s)"
            break
        fi

        print_info "--- Sweep #${cycle} ---"
        while IFS= read -r line; do
            [[ -z "${line}" ]] && continue
            status="${line%%|*}"
            rest="${line#*|}"
            msg="${rest%%|*}"
            detail="${rest#*|}"
            case "${status}" in
                OK)   print_info "  ${msg} ${detail}" ;;
                WARN) print_warn "  ${msg} ${detail}" ;;
                FAIL) print_error "  ${msg} ${detail}" ;;
            esac
        done < <(medical_run_connect_flows "${kube}" ok fail warn)

        print_info "Sweep #${cycle}: ${ok} ok, ${fail} failed, ${warn} warnings"
        sleep "${INTERVAL}"
    done
}

main() {
    parse_args "$@"
    local kube
    kube=$(medical_resolve_kubectl)

    if [[ "${BACKGROUND}" == true ]]; then
        local log="/tmp/${LOG_PREFIX}.log"
        print_info "Background log: ${log}"
        nohup "${BASH_SOURCE[0]}" \
            --duration "${DURATION}" \
            --interval "${INTERVAL}" \
            >>"${log}" 2>&1 &
        print_info "PID $!"
        exit 0
    fi

    print_info "=========================================="
    print_info "Medical application traffic (pod exec)"
    print_info "=========================================="
    check_prerequisites "${kube}"
    run_traffic_loop "${kube}"
}

main "$@"
