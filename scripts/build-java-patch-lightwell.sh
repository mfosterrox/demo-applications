#!/usr/bin/env bash
# Build and push the Lightwell Java patch-age image to quay.io/${TEAM_NAME}.
#
# The base image and Spring Boot version live in the Lightwell Containerfile
# and pom. If image-builds/podman-build-secret-* already exists, that file is
# the Maven settings secret and the script does not prompt. Otherwise it asks
# for the Lightwell username and access token and saves
# image-builds/podman-build-secret-lightwell for the next run. The token is
# mounted only for the Maven build and is not stored in the image.
#
#   image-builds/java-patch-demo/lightwell/Containerfile
#   image-builds/java-patch-demo/lightwell/settings.xml
#
# With no arguments the script builds the image and pushes it to Quay.
#
# Usage:
#   ./scripts/build-java-patch-lightwell.sh         # build and push
#   ./scripts/build-java-patch-lightwell.sh build   # build only
#   ./scripts/build-java-patch-lightwell.sh push
#
# Requires: podman or docker, and python3. Push requires `podman login quay.io`.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${ROOT}/image-builds/java-patch-demo"

TEAM_NAME="${TEAM_NAME:-mfoster}"
REG="quay.io/${TEAM_NAME}"
PLATFORM="${PLATFORM:-linux/amd64}"
ACTION="push"
IMAGE_NAME="java-patch-demo"
if [[ $# -gt 1 ]]; then
  echo "Usage: $0 [build|push]" >&2
  exit 1
fi
if [[ $# -eq 1 ]]; then
  case "$1" in
    build | push) ACTION="$1" ;;
    *)
      echo "Usage: $0 [build|push]" >&2
      exit 1
      ;;
  esac
fi
LIGHTWELL_SETTINGS_TEMPLATE="${SRC}/lightwell/settings.xml"
LIGHTWELL_SETTINGS_FILE=""
SAVED_SECRET_FILE="${ROOT}/image-builds/podman-build-secret-lightwell"

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

prompt_lightwell_credentials() {
  if [[ ! -r /dev/tty ]]; then
    echo "ERROR: a terminal is required to enter the Lightwell username and access token." >&2
    exit 1
  fi
  local username token
  read -r -p "Lightwell username (orgId|name): " username </dev/tty
  read -r -s -p "Lightwell access token: " token </dev/tty
  echo >/dev/tty
  if [[ -z "${username}" || -z "${token}" ]]; then
    echo "ERROR: Lightwell username and access token are required." >&2
    exit 1
  fi
  export LIGHTWELL_USERNAME="${username}"
  export LIGHTWELL_PASSWORD="${token}"
}

find_podman_build_secret() {
  local candidate newest=""
  shopt -s nullglob
  for candidate in \
    "${ROOT}/image-builds"/podman-build-secret-* \
    "${SRC}"/podman-build-secret-* \
    "${SRC}/lightwell"/podman-build-secret-*
  do
    if [[ -f "${candidate}" && ( -z "${newest}" || "${candidate}" -nt "${newest}" ) ]]; then
      newest="${candidate}"
    fi
  done
  shopt -u nullglob
  if [[ -n "${newest}" ]]; then
    printf '%s\n' "${newest}"
  fi
}

write_lightwell_settings() {
  python3 - "${LIGHTWELL_SETTINGS_TEMPLATE}" "${SAVED_SECRET_FILE}" <<'PY'
import os
import pathlib
import sys
from xml.sax.saxutils import escape

template, dest = sys.argv[1:3]
text = pathlib.Path(template).read_text()
user_token = "__LIGHTWELL_USERNAME__"
pass_token = "__LIGHTWELL_PASSWORD__"
if text.count(user_token) < 1 or text.count(pass_token) < 1:
    sys.exit("settings template must contain the credential placeholders")
if text.count(user_token) != text.count(pass_token):
    sys.exit("username and password placeholders must appear the same number of times")
text = text.replace(user_token, escape(os.environ["LIGHTWELL_USERNAME"]))
text = text.replace(pass_token, escape(os.environ["LIGHTWELL_PASSWORD"]))
path = pathlib.Path(dest)
path.write_text(text)
path.chmod(0o600)
PY
}

prepare_lightwell_settings() {
  if [[ ! -f "${LIGHTWELL_SETTINGS_TEMPLATE}" ]]; then
    echo "ERROR: missing ${LIGHTWELL_SETTINGS_TEMPLATE}" >&2
    exit 1
  fi
  LIGHTWELL_SETTINGS_FILE="$(find_podman_build_secret || true)"
  if [[ -n "${LIGHTWELL_SETTINGS_FILE}" ]]; then
    echo "Using ${LIGHTWELL_SETTINGS_FILE}."
    return
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 is required to write the Lightwell Maven settings." >&2
    exit 1
  fi
  prompt_lightwell_credentials
  write_lightwell_settings
  LIGHTWELL_SETTINGS_FILE="${SAVED_SECRET_FILE}"
  echo "Saved Lightwell credentials to ${LIGHTWELL_SETTINGS_FILE}."
}

build_lightwell() {
  local image="${REG}/${IMAGE_NAME}:lightwell"
  local dir="${SRC}/lightwell"
  if [[ ! -f "${dir}/Containerfile" ]]; then
    echo "ERROR: missing ${dir}/Containerfile" >&2
    exit 1
  fi
  echo "==> ${image}"
  echo "    ${dir}/Containerfile"
  "${CONTAINER_CMD}" build \
    --platform "${PLATFORM}" \
    --pull=always \
    --secret "id=lightwell_maven_settings,src=${LIGHTWELL_SETTINGS_FILE}" \
    -f "${dir}/Containerfile" \
    -t "${image}" \
    "${SRC}"
}

push_lightwell() {
  local image="${REG}/${IMAGE_NAME}:lightwell"
  echo "==> Pushing ${image}"
  if ! "${CONTAINER_CMD}" push "${image}"; then
    echo "ERROR: push failed for ${image}. Run '${CONTAINER_CMD} login quay.io' and retry." >&2
    exit 1
  fi
}

prepare_lightwell_settings

case "${ACTION}" in
  build)
    build_lightwell
    ;;
  push)
    build_lightwell
    push_lightwell
    ;;
esac
