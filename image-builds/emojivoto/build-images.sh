#!/usr/bin/env bash
# Build and optionally push Emojivoto images to Quay (or another registry).
#
# Prerequisites:
#   podman or docker, make, network for go mod / npm during web build
#   podman login quay.io   # before PUSH=1
#
# Usage:
#   ./build-images.sh
#   PUSH=1 ./build-images.sh
#   TEAM_NAME=myorg VERSION=0.2.0 PUSH=1 ./build-images.sh
#   CONTAINER_CMD=docker PUSH=1 ./build-images.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${ROOT}"

# Match repo root makefile defaults (quay.io/<team>/<image>:<version>)
QUAY_REGISTRY="${QUAY_REGISTRY:-quay.io}"
TEAM_NAME="${TEAM_NAME:-mfoster}"
VERSION="${VERSION:-${IMAGE_TAG:-0.1.0}}"
REGISTRY_PREFIX="${REGISTRY_PREFIX:-${QUAY_REGISTRY}/${TEAM_NAME}}"
IMAGE_TAG="${IMAGE_TAG:-${VERSION}}"
PUSH="${PUSH:-0}"
CONTAINER_CMD="${CONTAINER_CMD:-}"
PLATFORM="${PLATFORM:-linux/amd64}"

if [[ -z "${CONTAINER_CMD}" ]]; then
  if command -v podman >/dev/null 2>&1; then
    CONTAINER_CMD=podman
  else
    CONTAINER_CMD=docker
  fi
fi

export REGISTRY_PREFIX IMAGE_TAG CONTAINER_CMD
MAKEFLAGS=(REGISTRY_PREFIX="${REGISTRY_PREFIX}" IMAGE_TAG="${IMAGE_TAG}" CONTAINER_CMD="${CONTAINER_CMD}")

SERVICES=(emojivoto-web emojivoto-emoji-svc emojivoto-voting-svc)
BASE_IMAGE="${REGISTRY_PREFIX}/emojivoto-svc-base:${IMAGE_TAG}"

echo "==> Registry:  ${REGISTRY_PREFIX}"
echo "==> Tag:       ${IMAGE_TAG}"
echo "==> Platform:  ${PLATFORM}"
echo "==> Engine:    ${CONTAINER_CMD}"
echo ""

echo "==> Building base image ${BASE_IMAGE}"
make "${MAKEFLAGS[@]}" build-base-docker-image

images_to_push=("${BASE_IMAGE}")
for svc in "${SERVICES[@]}"; do
  image="${REGISTRY_PREFIX}/${svc}:${IMAGE_TAG}"
  echo "==> Building ${image} (protoc, compile, container)"
  # package = protoc + compile (+ package-web for web) + build-container
  make "${MAKEFLAGS[@]}" -C "${svc}" package BASE_IMAGE="${BASE_IMAGE}"
  images_to_push+=("${image}")
done

if [[ "${PUSH}" == "1" ]]; then
  echo ""
  echo "==> Pushing images to ${QUAY_REGISTRY}"
  for image in "${images_to_push[@]}"; do
    echo "    push ${image}"
    "${CONTAINER_CMD}" push "${image}"
  done
fi

cat <<EOF

Build complete.

Images:
  ${BASE_IMAGE}
$(for svc in "${SERVICES[@]}"; do echo "  ${REGISTRY_PREFIX}/${svc}:${IMAGE_TAG}"; done)

Kubernetes manifests expect:
  quay.io/${TEAM_NAME}/emojivoto-web:${IMAGE_TAG}
  quay.io/${TEAM_NAME}/emojivoto-emoji-svc:${IMAGE_TAG}
  quay.io/${TEAM_NAME}/emojivoto-voting-svc:${IMAGE_TAG}

Deploy:
  kubectl apply -f k8s-deployment-manifests/-namespaces/namespace-emojivoto.yaml
  kubectl apply -f k8s-deployment-manifests/emojivoto/

If your Quay org or tag differs, run from repo root:
  make update-emojivoto-manifests TEAM_NAME=${TEAM_NAME} VERSION=${IMAGE_TAG}
EOF
