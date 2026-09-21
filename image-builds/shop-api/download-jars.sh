#!/usr/bin/env bash
# Download scanner-only JARs for shop-api images. These are never executed.
# JARs are gitignored (see repo .gitignore); rebuilds must run this script first.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${ROOT}/lib"
LIB_FIXED="${ROOT}/lib-fixed"

mkdir -p "${LIB}" "${LIB_FIXED}"

download() {
  local url="$1"
  local dest="$2"
  if [[ -f "${dest}" ]] && [[ -s "${dest}" ]]; then
    echo "Already present: ${dest}"
    return 0
  fi
  echo "Downloading $(basename "${dest}")"
  curl -fL --retry 3 --retry-delay 2 "${url}" -o "${dest}"
  if [[ ! -s "${dest}" ]]; then
    echo "ERROR: empty download: ${dest}" >&2
    exit 1
  fi
}

download "https://repo1.maven.org/maven2/org/apache/logging/log4j/log4j-core/2.14.1/log4j-core-2.14.1.jar" \
  "${LIB}/log4j-core-2.14.1.jar"
download "https://repo1.maven.org/maven2/org/apache/commons/commons-text/1.9/commons-text-1.9.jar" \
  "${LIB}/commons-text-1.9.jar"
download "https://repo1.maven.org/maven2/org/apache/logging/log4j/log4j-core/2.17.1/log4j-core-2.17.1.jar" \
  "${LIB_FIXED}/log4j-core-2.17.1.jar"

cp "${LIB}/commons-text-1.9.jar" "${LIB_FIXED}/commons-text-1.9.jar"

echo "shop-api JARs ready in ${LIB} and ${LIB_FIXED}"
ls -lh "${LIB}" "${LIB_FIXED}"
