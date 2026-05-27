#!/usr/bin/env bash
# Pull upstream Emojivoto images, retag, and push to your Quay org (avoids Docker Hub rate limits on-cluster).
#
# On the bastion (recommended):
#   podman login docker.io          # avoids toomanyrequests when pulling buoyantio/*
#   podman login quay.io
#   ./scripts/mirror-emojivoto-to-quay.sh
#
# Usage:
#   TEAM_NAME=mfoster VERSION=0.1.0 ./scripts/mirror-emojivoto-to-quay.sh
#   SOURCE_PREFIX=docker.io/buoyantio SOURCE_TAG=v11 ./scripts/mirror-emojivoto-to-quay.sh
#   PUSH=0 ./scripts/mirror-emojivoto-to-quay.sh    # pull and tag only

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

TEAM_NAME="${TEAM_NAME:-mfoster}"
VERSION="${VERSION:-0.1.0}"
SOURCE_TAG="${SOURCE_TAG:-v11}"
# docker.l5d.io proxies Docker Hub; docker.io/buoyantio is the same images (login to docker.io helps both).
SOURCE_PREFIX="${SOURCE_PREFIX:-docker.io/buoyantio}"
TARGET_PREFIX="${TARGET_PREFIX:-quay.io/${TEAM_NAME}}"
PLATFORM="${PLATFORM:-linux/amd64}"
PUSH="${PUSH:-1}"

CONTAINER_CMD="${CONTAINER_CMD:-}"
if [[ -z "${CONTAINER_CMD}" ]]; then
  if command -v podman >/dev/null 2>&1; then
    CONTAINER_CMD=podman
  else
    CONTAINER_CMD=docker
  fi
fi

# Three unique images to mirror. Kubernetes runs four workloads, but vote-bot reuses emojivoto-web.
# (emojivoto-svc-base is only used when building from source — not pulled from Buoyant upstream.)
IMAGES=(emojivoto-web emojivoto-emoji-svc emojivoto-voting-svc)

require_registry_login() {
  local registry="$1"
  if ! "${CONTAINER_CMD}" login --get-login "${registry}" >/dev/null 2>&1; then
    echo "ERROR: Not logged in to ${registry}." >&2
    echo "  Run: ${CONTAINER_CMD} login ${registry}" >&2
    echo "  Use your Quay username + password, or a robot account + token with push access." >&2
    exit 1
  fi
}

echo "==> Mirror Emojivoto images to Quay"
echo "    Source:  ${SOURCE_PREFIX}/*:${SOURCE_TAG} (3 images)"
echo "    Target:  ${TARGET_PREFIX}/*:${VERSION}"
echo "    Platform: ${PLATFORM}"
echo "    Engine:  ${CONTAINER_CMD}"
echo ""
echo "Workloads: web, vote-bot (same image as web), emoji-svc, voting-svc → 3 Quay repos:"
for img in "${IMAGES[@]}"; do
  echo "  - ${TARGET_PREFIX}/${img}"
done
echo ""

if [[ "${PUSH}" == "1" ]]; then
  echo "==> Checking registry logins..."
  require_registry_login docker.io
  require_registry_login quay.io
  echo ""
fi

for img in "${IMAGES[@]}"; do
  src="${SOURCE_PREFIX}/${img}:${SOURCE_TAG}"
  dst="${TARGET_PREFIX}/${img}:${VERSION}"
  echo "==> Pull  ${src}"
  "${CONTAINER_CMD}" pull --platform "${PLATFORM}" "${src}"
  echo "==> Tag   ${dst}"
  "${CONTAINER_CMD}" tag "${src}" "${dst}"
  if [[ "${PUSH}" == "1" ]]; then
    echo "==> Push  ${dst}"
    if ! "${CONTAINER_CMD}" push "${dst}"; then
      echo "" >&2
      echo "ERROR: push failed for ${dst}" >&2
      echo "  1. ${CONTAINER_CMD} login quay.io  (robot account needs Create + Write on the repo)" >&2
      echo "  2. Create the repository at https://quay.io/repository/${TEAM_NAME}/${img}" >&2
      echo "  3. Set repository visibility to Public if the cluster has no pull secret" >&2
      exit 1
    fi
  fi
  echo ""
done

cat <<EOF
Done.

Deploy (namespace is included in everything.yml):
  oc apply -f k8s-deployment-manifests/emojivoto/

Manifests should reference:
  ${TARGET_PREFIX}/emojivoto-web:${VERSION}
  ${TARGET_PREFIX}/emojivoto-emoji-svc:${VERSION}
  ${TARGET_PREFIX}/emojivoto-voting-svc:${VERSION}

If tags differ, run:
  make update-emojivoto-manifests TEAM_NAME=${TEAM_NAME} VERSION=${VERSION}
EOF
