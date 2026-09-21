#!/usr/bin/env bash
# Reuse images/layers already on a registry (default Quay) instead of rebuilding
# or re-pushing from scratch.
#
# Usage:
#   quay-reuse.sh skip-build <image> [dockerfile]   # exit 0 = skip build
#   quay-reuse.sh skip-push  <image>                # exit 0 = skip push
#
# Environment:
#   FORCE_BUILD=1   always rebuild (still pulls first so layer cache is warm)
#   FORCE_PUSH=1    always push
#   PLATFORM        default linux/amd64
#   CONTAINER_CMD   podman or docker (auto-detected)
set -euo pipefail

ACTION="${1:-}"
IMAGE="${2:-}"
DOCKERFILE="${3:-}"
PLATFORM="${PLATFORM:-linux/amd64}"

if [[ -z "${ACTION}" || -z "${IMAGE}" ]]; then
  echo "Usage: $0 skip-build <image> [dockerfile]" >&2
  echo "       $0 skip-push  <image>" >&2
  exit 2
fi

if [[ -z "${CONTAINER_CMD:-}" ]]; then
  if command -v podman >/dev/null 2>&1; then
    CONTAINER_CMD=podman
  elif command -v docker >/dev/null 2>&1; then
    CONTAINER_CMD=docker
  else
    echo "ERROR: neither podman nor docker found" >&2
    exit 2
  fi
fi

have_local() {
  if [[ "${CONTAINER_CMD}" == "podman" ]]; then
    "${CONTAINER_CMD}" image exists "${IMAGE}" >/dev/null 2>&1
  else
    docker image inspect "${IMAGE}" >/dev/null 2>&1
  fi
}

pull_remote() {
  echo "  Checking registry for ${IMAGE}"
  if "${CONTAINER_CMD}" pull --platform "${PLATFORM}" "${IMAGE}"; then
    echo "  Reusing layers from registry: ${IMAGE}"
    return 0
  fi
  echo "  Not in registry (or pull failed): ${IMAGE}"
  return 1
}

dockerfile_newer_than_image() {
  [[ -n "${DOCKERFILE}" && -f "${DOCKERFILE}" ]] || return 1
  local image_created image_time dockerfile_time
  image_created="$("${CONTAINER_CMD}" image inspect "${IMAGE}" --format '{{.Created}}' 2>/dev/null || echo "")"
  [[ -n "${image_created}" ]] || return 1
  image_time="$(python3 -c "from datetime import datetime; print(int(datetime.fromisoformat('${image_created}'.replace('Z', '+00:00')).timestamp()))" 2>/dev/null || echo "0")"
  dockerfile_time="$(stat -c %Y "${DOCKERFILE}" 2>/dev/null || stat -f %m "${DOCKERFILE}" 2>/dev/null || echo "0")"
  [[ "${image_time}" != "0" ]] || return 1
  [[ "${dockerfile_time}" -gt "${image_time}" ]] 2>/dev/null
}

expected_arch() {
  local p="${PLATFORM##*/}"
  printf '%s' "${p:-amd64}"
}

image_arch() {
  "${CONTAINER_CMD}" image inspect "${IMAGE}" --format '{{.Architecture}}' 2>/dev/null || true
}

wrong_arch() {
  local got want
  got="$(image_arch)"
  want="$(expected_arch)"
  [[ -n "${got}" && "${got}" != "${want}" ]]
}

parse_ref() {
  local ref="${IMAGE#docker://}"
  REGISTRY="${ref%%/*}"
  local rest="${ref#*/}"
  if [[ "${rest}" == *":"* ]]; then
    TAG="${rest##*:}"
    REPO_PATH="${rest%:*}"
  else
    TAG="latest"
    REPO_PATH="${rest}"
  fi
}

auth_file() {
  local f
  for f in \
    "${XDG_RUNTIME_DIR:-}/containers/auth.json" \
    "${HOME}/.config/containers/auth.json" \
    "${HOME}/.docker/config.json"; do
    [[ -n "${f}" && -f "${f}" ]] && { echo "${f}"; return 0; }
  done
  return 1
}

registry_basic_auth() {
  local file json
  file="$(auth_file)" || return 1
  json="$(python3 - "${file}" "${REGISTRY}" <<'PY'
import json, sys
path, registry = sys.argv[1], sys.argv[2]
try:
    data = json.load(open(path))
except Exception:
    sys.exit(1)
auths = data.get("auths") or {}
for host in (registry, f"https://{registry}", f"https://{registry}/v1/"):
    entry = auths.get(host) or auths.get(host.rstrip("/"))
    if entry and entry.get("auth"):
        print(entry["auth"])
        sys.exit(0)
sys.exit(1)
PY
)" || return 1
  [[ -n "${json}" ]] && printf '%s' "${json}"
}

# Manifest digest from the registry, not the local store (so a rebuilt local
# image is not compared to itself).
remote_digest() {
  parse_ref
  local digest=""
  if command -v skopeo >/dev/null 2>&1; then
    digest="$(skopeo inspect --override-os linux --override-arch amd64 \
      "docker://${IMAGE}" --format '{{.Digest}}' 2>/dev/null || true)"
    if [[ -n "${digest}" && "${digest}" != "<none>" ]]; then
      printf '%s' "${digest}"
      return 0
    fi
  fi

  if [[ "${REGISTRY}" != "quay.io" ]]; then
    return 1
  fi

  local token="" auth hdr url
  url="https://quay.io/v2/${REPO_PATH}/manifests/${TAG}"
  token_from_auth() {
    local hdrs=()
    [[ -n "${1:-}" ]] && hdrs=(-H "Authorization: Basic ${1}")
    curl -fsS "${hdrs[@]}" \
      "https://quay.io/v2/auth?service=quay.io&scope=repository:${REPO_PATH}:pull" \
      2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('token') or d.get('access_token') or '')" \
      2>/dev/null || true
  }
  auth="$(registry_basic_auth || true)"
  if [[ -n "${auth}" ]]; then
    token="$(token_from_auth "${auth}" || true)"
  fi
  if [[ -z "${token}" ]]; then
    token="$(token_from_auth "" || true)"
  fi

  local curl_auth=()
  [[ -n "${token}" ]] && curl_auth=(-H "Authorization: Bearer ${token}")
  hdr="$(curl -sI "${curl_auth[@]}" \
    -H "Accept: application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.oci.image.index.v1+json" \
    "${url}" 2>/dev/null || true)"
  digest="$(printf '%s\n' "${hdr}" | awk 'BEGIN{IGNORECASE=1} /^docker-content-digest:/ {print $2}' | tr -d '\r' | head -1)"
  if [[ -z "${digest}" ]]; then
    return 1
  fi
  printf '%s' "${digest}"
}

local_digest_list() {
  "${CONTAINER_CMD}" image inspect "${IMAGE}" --format '{{.Digest}}{{range .RepoDigests}} {{.}}{{end}}' 2>/dev/null || true
}

skip_build() {
  if ! have_local; then
    pull_remote || true
  else
    echo "  Local image present: ${IMAGE}"
  fi

  if [[ "${FORCE_BUILD:-0}" == "1" ]]; then
    if have_local; then
      echo "  FORCE_BUILD=1: rebuilding ${IMAGE} (registry layers used as cache if present)"
    else
      echo "  FORCE_BUILD=1: building ${IMAGE} from scratch"
    fi
    return 1
  fi

  if ! have_local; then
    echo "  Will build ${IMAGE}"
    return 1
  fi

  if wrong_arch; then
    echo "  Image architecture is $(image_arch), need $(expected_arch); will rebuild ${IMAGE}"
    return 1
  fi

  if dockerfile_newer_than_image; then
    echo "  Dockerfile newer than image; will rebuild ${IMAGE} using cached layers"
    return 1
  fi

  echo "  Skip build: ${IMAGE} already available locally or on the registry"
  return 0
}

skip_push() {
  if [[ "${FORCE_PUSH:-0}" == "1" ]]; then
    echo "  FORCE_PUSH=1: will push ${IMAGE}"
    return 1
  fi
  if ! have_local; then
    echo "  Local image missing; push will be attempted for ${IMAGE}"
    return 1
  fi
  local remote locals
  remote="$(remote_digest || true)"
  if [[ -z "${remote}" ]]; then
    echo "  Could not read registry digest; will push ${IMAGE}"
    return 1
  fi
  locals="$(local_digest_list)"
  if [[ -z "${locals}" ]]; then
    echo "  Could not read local digest; will push ${IMAGE}"
    return 1
  fi
  if printf '%s\n' "${locals}" | grep -Fq "${remote}"; then
    echo "  Skip push: ${IMAGE} already on registry (${remote})"
    return 0
  fi
  echo "  Local image differs from registry; will push ${IMAGE}"
  return 1
}

case "${ACTION}" in
  skip-build) skip_build ;;
  skip-push) skip_push ;;
  *)
    echo "Unknown action: ${ACTION}" >&2
    exit 2
    ;;
esac
