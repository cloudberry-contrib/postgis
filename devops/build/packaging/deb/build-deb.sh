#!/bin/bash
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#
# Script Name: build-deb.sh
#
# Description:
#   Builds the PostGIS-for-Cloudberry .deb package. Assumes the extension
#   payload has already been staged into debian/build (see build-postgis.sh).
#   Prepares the debian/ metadata directory for the detected OS distribution
#   and runs dpkg-buildpackage.
#
# Usage:
#   ./build-deb.sh -v <version> [-h] [-n|--dry-run]
#
# Prerequisites:
#   - dpkg-buildpackage (dpkg-dev) must be installed.
#   - The control file must exist at devops/build/packaging/deb/<os>/control.
#   - debian/build must be populated with the staged PostGIS payload.

set -euo pipefail

VERSION=""
DRY_RUN=false

usage() {
  echo "Usage: $0 -v <version> [-b <branch>] [-h] [-n|--dry-run]"
  echo "  -v, --version <version>  : PostGIS version (e.g. 3.3.2)"
  echo "  -b, --branch <branch>    : Cloudberry branch the extension was built"
  echo "                             for (e.g. main, REL_2_STABLE). Encoded into"
  echo "                             the package name. Falls back to \$CBDB_BRANCH,"
  echo "                             then \$CLOUDBERRY_REF, then 'main'."
  echo "  -h, --help               : Display this help and exit"
  echo "  -n, --dry-run            : Show what would be done"
  exit 1
}

check_commands() {
  for cmd in dpkg-buildpackage; do
    if ! command -v "$cmd" &> /dev/null; then
      echo "Error: Required command '$cmd' not found. Please install dpkg-dev."
      exit 1
    fi
  done
}

print_changelog() {
cat <<EOF
${PKG_SOURCE_NAME} (${POSTGIS_PKG_VERSION}) stable; urgency=low

  * ${PKG_SOURCE_NAME} autobuild

 -- ${BUILD_USER} <${BUILD_USER}@$(hostname)>  $(date +'%a, %d %b %Y %H:%M:%S %z')
EOF
}

BRANCH=""
while [[ "$#" -gt 0 ]]; do
  case $1 in
    -v|--version) VERSION="$2"; shift 2 ;;
    -b|--branch) BRANCH="$2"; shift 2 ;;
    -h|--help) usage ;;
    -n|--dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown option: ($1)"; shift ;;
  esac
done

if [ -z "${VERSION}" ]; then
  echo "Error: version is required (-v <version>)."
  usage
fi

export POSTGIS_FULL_VERSION="${VERSION}"

if [ -z "${BUILD_NUMBER+x}" ]; then
  export BUILD_NUMBER=1
fi

if [ -z "${BUILD_USER+x}" ]; then
  export BUILD_USER=github
fi

# Cloudberry branch the extension was built for. Encoded into the package name
# so builds for different Cloudberry branches (different PostgreSQL majors)
# stay distinct and are never installed against the wrong server. Precedence:
# -b/--branch, then $CBDB_BRANCH, then $CLOUDBERRY_REF, then 'main'.
CBDB_BRANCH_RAW="${BRANCH:-${CBDB_BRANCH:-${CLOUDBERRY_REF:-main}}}"
# Sanitize to a valid Debian package-name fragment: lowercase, only [a-z0-9-].
CBDB_BRANCH="$(echo "${CBDB_BRANCH_RAW}" | tr '[:upper:]' '[:lower:]' \
  | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
[ -n "${CBDB_BRANCH}" ] || CBDB_BRANCH="main"
export CBDB_BRANCH
PKG_SOURCE_NAME="apache-cloudberry-db-postgis-${CBDB_BRANCH}"
echo "Cloudberry branch: ${CBDB_BRANCH_RAW} -> package name ${PKG_SOURCE_NAME}"

# Detect OS distribution (e.g. ubuntu22.04).
if [ -z "${OS_DISTRO+x}" ]; then
  if [ -f /etc/os-release ]; then
    set +u
    . /etc/os-release
    set -u
    OS_DISTRO=$(echo "${ID:-unknown}${VERSION_ID:-}" | tr '[:upper:]' '[:lower:]')
  else
    OS_DISTRO="unknown"
  fi
fi
export OS_DISTRO=${OS_DISTRO:-unknown}

# Version stamped onto the package; consumed by debian/rules.
export POSTGIS_PKG_VERSION=${POSTGIS_FULL_VERSION}-${BUILD_NUMBER}-${OS_DISTRO}

check_commands

# Project root = four levels up from this script (devops/build/packaging/deb/).
PROJECT_ROOT="$(cd "$(dirname "$0")/../../../../" && pwd)"

# The debian metadata for the detected OS distribution.
DEBIAN_SRC_DIR="$(cd "$(dirname "$0")" && pwd)/${OS_DISTRO}"

if [ ! -d "$DEBIAN_SRC_DIR" ]; then
  echo "Error: Debian metadata not found at $DEBIAN_SRC_DIR."
  exit 1
fi

echo "Preparing debian directory from $DEBIAN_SRC_DIR..."
mkdir -p "$PROJECT_ROOT/debian"
# Preserve an already-staged debian/build payload while refreshing metadata.
cp -rf "$DEBIAN_SRC_DIR"/. "$PROJECT_ROOT/debian/"

CONTROL_FILE="$PROJECT_ROOT/debian/control"
if [ ! -f "$CONTROL_FILE" ]; then
  echo "Error: Control file not found at $CONTROL_FILE."
  exit 1
fi

# Encode the Cloudberry branch into the source/package name.
sed -i "s/@CBDB_BRANCH@/${CBDB_BRANCH}/g" "$CONTROL_FILE"
echo "Package name resolved to: $(grep -m1 '^Package: ' "$CONTROL_FILE" | cut -d' ' -f2)"

if [ -z "$(ls -A "$PROJECT_ROOT/debian/build" 2>/dev/null)" ]; then
  echo "Error: debian/build is empty. Stage the PostGIS payload first"
  echo "       (run build-postgis.sh with DEB_BUILD_DIR=$PROJECT_ROOT/debian/build)."
  exit 1
fi

# Binary-only build (native package, no upstream tarball needed).
DEBBUILD_CMD="dpkg-buildpackage -us -uc -b"

if [ "${DRY_RUN}" = true ]; then
  echo "Dry-run mode: this is what would be done:"
  print_changelog
  echo ""
  echo "$DEBBUILD_CMD"
  exit 0
fi

echo "Building DEB version $POSTGIS_PKG_VERSION in $PROJECT_ROOT ..."
print_changelog > "$PROJECT_ROOT/debian/changelog"

cd "$PROJECT_ROOT"
if ! eval "$DEBBUILD_CMD"; then
  echo "Error: deb build failed."
  exit 1
fi

echo "DEB build completed successfully: apache-cloudberry-db-postgis ${POSTGIS_PKG_VERSION}"
