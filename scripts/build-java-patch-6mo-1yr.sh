#!/usr/bin/env bash
# Build and push the 6-month and 1-year Java patch-age images to quay.io/${TEAM_NAME}.
#
# Each cohort has its own Containerfile and pom. This script does not pass
# base images, library versions, or Lightwell credentials.
#
#   image-builds/java-patch-demo/6mo/Containerfile
#   image-builds/java-patch-demo/1yr/Containerfile
#
# With no arguments the script builds both images and pushes them to Quay.
#
# Usage:
#   ./scripts/build-java-patch-6mo-1yr.sh              # build and push 6mo and 1yr
#   ./scripts/build-java-patch-6mo-1yr.sh 6mo          # build and push one cohort
#   ./scripts/build-java-patch-6mo-1yr.sh build [6mo|1yr|all]
#   ./scripts/build-java-patch-6mo-1yr.sh push  [6mo|1yr|all]
#
# Requires: podman or docker, and `podman login quay.io` before a push.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${ROOT}/image-builds/java-patch-demo"

TEAM_NAME="${TEAM_NAME:-mfoster}"
REG="quay.io/${TEAM_NAME}"
PLATFORM="${PLATFORM:-linux/amd64}"
ACTION="push"
COHORT="all"
IMAGE_NAME="java-patch-demo"

if [[ $# -gt 2 ]]; then
  echo "Usage: $0 [build|push] [6mo|1yr|all]" >&2
  exit 1
fi
if [[ $# -ge 1 ]]; then
  case "$1" in
    build | push) ACTION="$1" ;;
    6mo | 1yr | all) COHORT="$1" ;;
    *)
      echo "Usage: $0 [build|push] [6mo|1yr|all]" >&2
      exit 1
      ;;
  esac
fi
if [[ $# -eq 2 ]]; then
  case "$1" in
    build | push) ;;
    *)
      echo "Usage: $0 [build|push] [6mo|1yr|all]" >&2
      exit 1
      ;;
  esac
  case "$2" in
    6mo | 1yr | all) COHORT="$2" ;;
    *)
      echo "ERROR: cohort must be 6mo, 1yr, or all" >&2
      exit 1
      ;;
  esac
fi

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

image_ref() {
  echo "${REG}/${IMAGE_NAME}:${1}"
}

selected_cohorts() {
  case "${COHORT}" in
    all) printf '%s\n' 6mo 1yr ;;
    6mo | 1yr) printf '%s\n' "${COHORT}" ;;
    *)
      echo "ERROR: cohort must be 6mo, 1yr, or all" >&2
      return 1
      ;;
  esac
}

build_cohort() {
  local cohort="$1"
  local dir image
  dir="${SRC}/${cohort}"
  image="$(image_ref "${cohort}")"
  if [[ ! -f "${dir}/Containerfile" ]]; then
    echo "ERROR: missing ${dir}/Containerfile" >&2
    exit 1
  fi
  echo "==> ${image}"
  echo "    ${dir}/Containerfile"
  "${CONTAINER_CMD}" build \
    --platform "${PLATFORM}" \
    --pull=always \
    -f "${dir}/Containerfile" \
    -t "${image}" \
    "${SRC}"
}

push_cohort() {
  local image
  image="$(image_ref "$1")"
  echo "==> Pushing ${image}"
  if ! "${CONTAINER_CMD}" push "${image}"; then
    echo "ERROR: push failed for ${image}. Run '${CONTAINER_CMD} login quay.io' and retry." >&2
    exit 1
  fi
}

if ! selected="$(selected_cohorts)"; then
  exit 1
fi

while IFS= read -r cohort; do
  [[ -z "${cohort}" ]] && continue
  build_cohort "${cohort}"
  if [[ "${ACTION}" == "push" ]]; then
    push_cohort "${cohort}"
  fi
done <<< "${selected}"
