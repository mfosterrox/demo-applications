#!/usr/bin/env bash
# Build, push, or mirror RHACS vulnmgmt shop demo images to quay.io/${TEAM_NAME}.
#
# Usage:
#   ./scripts/build-vulnmgmt.sh build
#   ./scripts/build-vulnmgmt.sh push
#   ./scripts/build-vulnmgmt.sh copy-prod-mirror
#
# Requires: podman (or docker), registry.redhat.io pull access, quay.io push access.
# JARs: image-builds/shop-api/download-jars.sh (not committed).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

TEAM_NAME="${TEAM_NAME:-mfoster}"
REG="quay.io/${TEAM_NAME}"
PLATFORM="${PLATFORM:-linux/amd64}"
ACTION="${1:-build}"

CONTAINER_CMD="${CONTAINER_CMD:-}"
if [[ -z "${CONTAINER_CMD}" ]]; then
  if command -v podman >/dev/null 2>&1; then
    CONTAINER_CMD=podman
  elif command -v docker >/dev/null 2>&1; then
    CONTAINER_CMD=docker
  else
    echo "ERROR: neither podman nor docker found" >&2
    exit 1
  fi
fi

BASE_OPENJDK="${REG}/base-ubi9-openjdk:1.0"
BASE_EAP8="${REG}/base-eap8:1.0"
BASE_EAP8_REPACKED="${REG}/base-eap8-repacked:1.0"
SHOP_API_100="${REG}/shop-api:1.0.0"
SHOP_API_110="${REG}/shop-api:1.1.0"
SHOP_API_FEATURE="${REG}/shop-api:feature-x-abc1234"
SHOP_WEB="${REG}/shop-web:1.0.0"
PROD_API="${REG}/prod-mirror-shop-api:1.0.0"
PROD_WEB="${REG}/prod-mirror-shop-web:1.0.0"

PUSH_IMAGES=(
  "${BASE_OPENJDK}"
  "${BASE_EAP8}"
  "${BASE_EAP8_REPACKED}"
  "${SHOP_API_100}"
  "${SHOP_API_110}"
  "${SHOP_API_FEATURE}"
  "${SHOP_WEB}"
)

download_jars() {
  chmod +x "${ROOT}/image-builds/shop-api/download-jars.sh"
  "${ROOT}/image-builds/shop-api/download-jars.sh"
}

REUSE_SH="${ROOT}/scripts/quay-reuse.sh"

maybe_build() {
  local image="$1"
  local dockerfile="$2"
  shift 2
  echo "==> ${image}"
  if bash "${REUSE_SH}" skip-build "${image}" "${dockerfile}"; then
    return 0
  fi
  "${CONTAINER_CMD}" build --platform "${PLATFORM}" -t "${image}" "$@"
}

build_images() {
  echo "==> Vulnmgmt shop images (${PLATFORM})"
  maybe_build "${BASE_OPENJDK}" image-builds/base-ubi9-openjdk/Containerfile \
    -f image-builds/base-ubi9-openjdk/Containerfile \
    image-builds/base-ubi9-openjdk

  maybe_build "${BASE_EAP8}" image-builds/base-eap8/Containerfile \
    -f image-builds/base-eap8/Containerfile \
    image-builds/base-eap8

  maybe_build "${BASE_EAP8_REPACKED}" image-builds/base-eap8-repacked/Containerfile \
    -f image-builds/base-eap8-repacked/Containerfile \
    image-builds/base-eap8-repacked

  local need_shop=0
  if ! bash "${REUSE_SH}" skip-build "${SHOP_API_100}" image-builds/shop-api/Containerfile >/dev/null; then
    need_shop=1
  fi
  if ! bash "${REUSE_SH}" skip-build "${SHOP_API_110}" image-builds/shop-api/Containerfile.fixed >/dev/null; then
    need_shop=1
  fi
  if [[ "${need_shop}" -eq 1 ]]; then
    download_jars
  fi

  maybe_build "${SHOP_API_100}" image-builds/shop-api/Containerfile \
    --build-arg "BASE_IMAGE=${BASE_EAP8}" \
    --build-arg APP_VERSION=1.0.0 \
    -f image-builds/shop-api/Containerfile \
    image-builds/shop-api

  echo "==> Tagging ${SHOP_API_FEATURE} from ${SHOP_API_100}"
  "${CONTAINER_CMD}" tag "${SHOP_API_100}" "${SHOP_API_FEATURE}"

  maybe_build "${SHOP_API_110}" image-builds/shop-api/Containerfile.fixed \
    --build-arg "BASE_IMAGE=${BASE_EAP8}" \
    -f image-builds/shop-api/Containerfile.fixed \
    image-builds/shop-api

  maybe_build "${SHOP_WEB}" image-builds/shop-web/Containerfile \
    --build-arg "BASE_IMAGE=${BASE_OPENJDK}" \
    --build-arg APP_VERSION=1.0.0 \
    -f image-builds/shop-web/Containerfile \
    image-builds/shop-web

  echo "==> Built or reused:"
  for img in "${PUSH_IMAGES[@]}"; do
    echo "  ${img}"
  done
}

push_images() {
  echo "==> Pushing vulnmgmt images to ${REG}"
  local img
  for img in "${PUSH_IMAGES[@]}"; do
    echo "==> ${img}"
    if bash "${REUSE_SH}" skip-push "${img}"; then
      continue
    fi
    "${CONTAINER_CMD}" push "${img}"
  done
}

copy_one_prod_mirror() {
  local src="$1"
  local dst="$2"
  if command -v skopeo >/dev/null 2>&1; then
    local transport="containers-storage"
    if [[ "${CONTAINER_CMD}" == "docker" ]]; then
      transport="docker-daemon"
    fi
    echo "==> skopeo copy ${src} -> ${dst}"
    skopeo copy "${transport}:${src}" "docker://${dst}"
  else
    echo "==> skopeo not found; using ${CONTAINER_CMD} tag + push for ${dst}"
    "${CONTAINER_CMD}" tag "${src}" "${dst}"
    "${CONTAINER_CMD}" push "${dst}"
  fi
}

copy_prod_mirror() {
  copy_one_prod_mirror "${SHOP_API_100}" "${PROD_API}"
  copy_one_prod_mirror "${SHOP_WEB}" "${PROD_WEB}"
  echo "==> Prod mirror images (same digest as shop-*:1.0.0):"
  echo "  ${PROD_API}"
  echo "  ${PROD_WEB}"
}

case "${ACTION}" in
  build)
    build_images
    ;;
  push)
    push_images
    ;;
  copy-prod-mirror)
    copy_prod_mirror
    ;;
  *)
    echo "Usage: $0 {build|push|copy-prod-mirror}" >&2
    exit 1
    ;;
esac
