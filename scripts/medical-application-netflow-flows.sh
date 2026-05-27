# Shared netflow -connect flow definitions for medical-application scripts.
# Source this file; do not execute directly.
#
# Each flow: namespace|deployment|container|listen|target1:port,target2:port|required(yes|no)
# Matches k8s-deployment-manifests/medical-application/*/everything.yml

readonly -a MEDICAL_NETFLOW_CONNECT_FLOWS=(
  "frontend|tls-proxy|tls-proxy|80,443|asset-cache-service.frontend.svc.cluster.local:8080,wordpress-service.frontend.svc.cluster.local:80|yes"
  "backend|api-server|api-server|9001|backend-atlas-service.backend.svc.cluster.local:8080,postgres-service.backend.svc.cluster.local:5432,gateway-service.payments.svc.cluster.local:7777|yes"
  "backend|varnish|varnish|8080|api-server-service.backend.svc.cluster.local:9001|yes"
  "payments|gateway|gateway|7777|visa-processor-service.payments.svc.cluster.local:8080,mastercard-processor-service.payments.svc.cluster.local:8080|yes"
  "medical|reporting|reporting|8080|patient-db-service.medical.svc.cluster.local:8080|no"
  "medical|patient-db|patient-db|8080|reporting-service.medical.svc.cluster.local:8080|no"
  "operations|jump-host|jump-host|22|pupper-master-service.operations.svc.cluster.local:8140,visa-processor-service.payments.svc.cluster.local:8080,patient-db-service.medical.svc.cluster.local:8080|yes"
)

readonly MEDICAL_APP_NAMESPACES=(frontend backend payments medical operations)

medical_resolve_kubectl() {
    if [[ -n "${KUBECTL:-}" ]]; then
        echo "${KUBECTL}"
        return
    fi
    if command -v oc >/dev/null 2>&1; then
        echo "oc"
    elif command -v kubectl >/dev/null 2>&1; then
        echo "kubectl"
    else
        echo "kubectl" >&2
        return 1
    fi
}

# Print: pod_name container_name
medical_resolve_pod_container() {
    local kube="$1"
    local ns="$2"
    local deploy="$3"
    local preferred_container="$4"

    local pod
    pod=$("${kube}" get pods -n "${ns}" -l "app=${deploy}" \
        --field-selector=status.phase=Running \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [[ -z "${pod}" ]]; then
        echo ""
        return 1
    fi

    local container="${preferred_container}"
    if ! "${kube}" get pod "${pod}" -n "${ns}" -o jsonpath="{.spec.containers[?(@.name==\"${container}\")].name}" 2>/dev/null | grep -q .; then
        container=$("${kube}" get pod "${pod}" -n "${ns}" -o jsonpath='{range .spec.containers[*]}{.name}{"\t"}{.image}{"\n"}{end}' 2>/dev/null \
            | awk -F'\t' '/rhacs-demo\/(netflow|reporting|jump-host)/ {print $1; exit}')
        if [[ -z "${container}" ]]; then
            container=$("${kube}" get pod "${pod}" -n "${ns}" -o jsonpath='{.spec.containers[0].name}' 2>/dev/null || echo "")
        fi
    fi

    printf '%s %s' "${pod}" "${container}"
}

# TCP dial from inside the source pod (mimics netflow -connect outbound dials).
medical_probe_tcp_from_pod() {
    local kube="$1"
    local ns="$2"
    local pod="$3"
    local container="$4"
    local host_port="$5"

    local host="${host_port%:*}"
    local port="${host_port##*:}"
    local exec_args=(-n "${ns}" "${pod}")
    [[ -n "${container}" ]] && exec_args+=(-c "${container}")

    "${kube}" exec "${exec_args[@]}" -- sh -c "
set -e
host='${host}'
port='${port}'
if command -v curl >/dev/null 2>&1; then
  curl -s -m 5 telnet://\${host}:\${port} >/dev/null 2>&1 && exit 0
fi
if command -v wget >/dev/null 2>&1; then
  wget -q -T 5 -O /dev/null telnet://\${host}:\${port} 2>/dev/null && exit 0
fi
if command -v nc >/dev/null 2>&1; then
  nc -z -w 3 \${host} \${port} 2>/dev/null && exit 0
fi
if command -v bash >/dev/null 2>&1; then
  bash -c \"echo >/dev/tcp/\${host}/\${port}\" 2>/dev/null && exit 0
fi
exit 1
" >/dev/null 2>&1
}

# Run one full sweep of all -connect flows from their source pods.
# Sets MEDICAL_FLOW_OK and MEDICAL_FLOW_FAIL arrays via nameref or globals.
medical_run_connect_flows() {
    local kube="$1"
    local -n ok_count=$2
    local -n fail_count=$3
    local -n warn_count=$4

    ok_count=0
    fail_count=0
    warn_count=0

    local entry ns deploy container listen targets required rest target
    local pod resolved_pod resolved_ctr result label

    for entry in "${MEDICAL_NETFLOW_CONNECT_FLOWS[@]}"; do
        IFS='|' read -r ns deploy container listen targets required <<< "${entry}"
        resolved=$(medical_resolve_pod_container "${kube}" "${ns}" "${deploy}" "${container}" || true)
        resolved_pod="${resolved%% *}"
        resolved_ctr="${resolved#* }"
        [[ "${resolved_pod}" == "${resolved_ctr}" ]] && resolved_ctr="${container}"

        label="${ns}/${deploy}"
        if [[ -n "${listen}" ]]; then
            label="${label} (-listen ${listen})"
        fi

        if [[ -z "${resolved_pod}" ]]; then
            if [[ "${required}" == "yes" ]]; then
                fail_count=$((fail_count + 1))
                echo "FAIL|${label}|no running pod"
            else
                warn_count=$((warn_count + 1))
                echo "WARN|${label}|no running pod"
            fi
            continue
        fi

        IFS=',' read -ra target_list <<< "${targets}"
        for target in "${target_list[@]}"; do
            [[ -z "${target}" ]] && continue
            if medical_probe_tcp_from_pod "${kube}" "${ns}" "${resolved_pod}" "${resolved_ctr}" "${target}"; then
                ok_count=$((ok_count + 1))
                echo "OK|${label}|→ ${target} (from pod/${resolved_ctr})"
            elif [[ "${required}" == "yes" ]]; then
                fail_count=$((fail_count + 1))
                echo "FAIL|${label}|→ ${target} (from pod/${resolved_ctr})"
            else
                warn_count=$((warn_count + 1))
                echo "WARN|${label}|→ ${target} (from pod/${resolved_ctr})"
            fi
        done
    done
}
