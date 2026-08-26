#!/bin/bash
# --------------------------------------------------------------------
#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements. See the NOTICE file distributed
# with this work for additional information regarding copyright
# ownership. The ASF licenses this file to You under the Apache
# License, Version 2.0 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of the
# License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied. See the License for the specific language governing
# permissions and limitations under the License.
#
# --------------------------------------------------------------------
#
# Script: build-postgis.sh
#
# Description:
#   Builds the PostGIS extension against an already-built Apache
#   Cloudberry installation and (optionally) stages ONLY the
#   PostGIS-produced files into a directory suitable for .deb packaging.
#
#   This is the scripted form of the manual steps:
#     source /usr/local/cloudberry-db/cloudberry-env.sh
#     cd postgis/build/postgis-3.3.2/
#     ./autogen.sh
#     ./configure --with-pgconfig=$GPHOME/bin/pg_config \
#                 --with-raster --without-topology \
#                 --with-gdalconfig=... --with-sfcgal=... \
#                 --with-geosconfig=... --with-projdir=...
#     make -j$(nproc)
#     sudo make install
#
# Required environment:
#   GPHOME       - Apache Cloudberry install prefix (from cloudberry-env.sh),
#                  e.g. /usr/local/cloudberry-db
#   POSTGIS_SRC  - Path to the unpacked PostGIS source, e.g.
#                  <repo>/postgis/build/postgis-3.3.2
#
# Optional environment (defaults match the build-env image):
#   GDAL_CONFIG    - default /usr/local/gdal-3.5.3/bin/gdal-config
#   SFCGAL_CONFIG  - default /usr/local/sfcgal-1.4.1/bin/sfcgal-config
#   GEOS_CONFIG    - default /usr/local/geos-3.10.2/bin/geos-config
#   PROJ_DIR       - default /usr/local/proj6
#   DEB_BUILD_DIR  - if set, the package payload is staged here mirroring the
#                    target filesystem (absolute paths). A DESTDIR install
#                    captures ONLY the extension's own files under GPHOME.
#   GPHOME_PKG_TARGET - where the extension files should live on the INSTALLED
#                    system. Defaults to /usr/cloudberry-db, the real directory
#                    the Apache Cloudberry .deb ships (it symlinks
#                    /usr/local/cloudberry-db -> /usr/cloudberry-db). PostGIS is
#                    built against GPHOME (/usr/local/cloudberry-db) but its
#                    files are re-rooted here so the package co-populates the
#                    Cloudberry tree without conflicting with the symlink.
#   BUNDLE_GEO_LIBS - if not "false" (default true) and DEB_BUILD_DIR is set,
#                    also bundle the custom GEOS/PROJ/GDAL/SFCGAL runtime trees
#                    (lib/lib64/share) plus the ld.so.conf.d entry, so the
#                    package is self-contained.
#   SKIP_REAL_INSTALL - if "true", skip the `sudo make install` into GPHOME
#                    (useful when you only want the staged package payload).
# --------------------------------------------------------------------

set -euo pipefail

: "${GPHOME:?GPHOME must be set (source cloudberry-env.sh first)}"
: "${POSTGIS_SRC:?POSTGIS_SRC must point at the PostGIS source directory}"

GDAL_CONFIG="${GDAL_CONFIG:-/usr/local/gdal-3.5.3/bin/gdal-config}"
SFCGAL_CONFIG="${SFCGAL_CONFIG:-/usr/local/sfcgal-1.4.1/bin/sfcgal-config}"
GEOS_CONFIG="${GEOS_CONFIG:-/usr/local/geos-3.10.2/bin/geos-config}"
PROJ_DIR="${PROJ_DIR:-/usr/local/proj6}"
DEB_BUILD_DIR="${DEB_BUILD_DIR:-}"
GPHOME_PKG_TARGET="${GPHOME_PKG_TARGET:-/usr/cloudberry-db}"
BUNDLE_GEO_LIBS="${BUNDLE_GEO_LIBS:-true}"
SKIP_REAL_INSTALL="${SKIP_REAL_INSTALL:-false}"

echo "==> Building PostGIS"
echo "      POSTGIS_SRC   = ${POSTGIS_SRC}"
echo "      GPHOME        = ${GPHOME}"
echo "      GDAL_CONFIG   = ${GDAL_CONFIG}"
echo "      SFCGAL_CONFIG = ${SFCGAL_CONFIG}"
echo "      GEOS_CONFIG   = ${GEOS_CONFIG}"
echo "      PROJ_DIR      = ${PROJ_DIR}"

cd "${POSTGIS_SRC}"

./autogen.sh

./configure \
  --with-pgconfig="${GPHOME}/bin/pg_config" \
  --with-raster --without-topology \
  --with-gdalconfig="${GDAL_CONFIG}" \
  --with-sfcgal="${SFCGAL_CONFIG}" \
  --with-geosconfig="${GEOS_CONFIG}" \
  --with-projdir="${PROJ_DIR}"

make -j"$(nproc)"

# Real install into GPHOME (matches the manual `sudo make install`).
if [ "${SKIP_REAL_INSTALL}" != "true" ]; then
  echo "==> Installing PostGIS into ${GPHOME}"
  sudo make install
fi

# Stage the package payload for .deb building. Everything is placed under
# ${DEB_BUILD_DIR} mirroring the target filesystem (absolute paths), so
# debian/install can drop it onto the target root as-is.
if [ -n "${DEB_BUILD_DIR}" ]; then
  echo "==> Staging package payload -> ${DEB_BUILD_DIR}"
  mkdir -p "${DEB_BUILD_DIR}"

  # --- PostGIS extension files (ONLY PostGIS's own output) -------------------
  # A DESTDIR install writes just the files PostGIS produces, under
  # ${DESTDIR}${GPHOME}/... — exactly the extension payload we want. Re-root
  # them from the build-time GPHOME onto GPHOME_PKG_TARGET (the real directory
  # the Cloudberry .deb owns), so we co-populate that tree instead of writing
  # through the /usr/local/cloudberry-db symlink.
  STAGE_TMP="$(mktemp -d)"
  make install DESTDIR="${STAGE_TMP}"
  mkdir -p "${DEB_BUILD_DIR}${GPHOME_PKG_TARGET}"
  cp -a "${STAGE_TMP}${GPHOME}/." "${DEB_BUILD_DIR}${GPHOME_PKG_TARGET}/"
  rm -rf "${STAGE_TMP}"

  # --- Bundled geospatial runtime libraries ---------------------------------
  # Ship the custom GEOS/PROJ/GDAL/SFCGAL trees at their absolute /usr/local
  # prefixes so the package is self-contained. Prefixes are derived from the
  # *-config paths (e.g. /usr/local/gdal-3.5.3/bin/gdal-config -> the prefix).
  if [ "${BUNDLE_GEO_LIBS}" != "false" ]; then
    GDAL_PREFIX="$(dirname "$(dirname "${GDAL_CONFIG}")")"
    GEOS_PREFIX="$(dirname "$(dirname "${GEOS_CONFIG}")")"
    SFCGAL_PREFIX="$(dirname "$(dirname "${SFCGAL_CONFIG}")")"
    PROJ_PREFIX="${PROJ_DIR}"

    for prefix in "${PROJ_PREFIX}" "${GDAL_PREFIX}" "${SFCGAL_PREFIX}" "${GEOS_PREFIX}"; do
      echo "==> Bundling runtime tree: ${prefix}"
      # lib/lib64 hold the shared objects; share holds runtime data such as
      # PROJ's proj.db and GDAL's data files (needed at runtime).
      for sub in lib lib64 share; do
        if [ -d "${prefix}/${sub}" ]; then
          mkdir -p "${DEB_BUILD_DIR}${prefix}/${sub}"
          cp -a "${prefix}/${sub}/." "${DEB_BUILD_DIR}${prefix}/${sub}/"
        fi
      done
    done

    # Drop build-time-only artifacts that have no runtime purpose and only
    # bloat the package: static archives, libtool descriptors, and the
    # pkg-config / cmake metadata directories.
    find "${DEB_BUILD_DIR}" -type f \( -name '*.a' -o -name '*.la' \) -delete
    find "${DEB_BUILD_DIR}" -depth -type d \( -name pkgconfig -o -name cmake \) -exec rm -rf {} +

    # ld.so.conf.d entry so the dynamic linker finds the bundled libs after
    # the package's postinst runs ldconfig. Generate it from the lib dirs that
    # ACTUALLY exist in the staged tree (a given build may use lib or lib64),
    # rather than trusting a hard-coded list — otherwise ldconfig indexes the
    # wrong directory and e.g. libSFCGAL.so.1 stays unresolved.
    echo "==> Generating linker config from staged lib directories"
    mkdir -p "${DEB_BUILD_DIR}/etc/ld.so.conf.d"
    conf="${DEB_BUILD_DIR}/etc/ld.so.conf.d/cloudberry-postgis.conf"
    : > "${conf}"
    for prefix in "${PROJ_PREFIX}" "${GDAL_PREFIX}" "${SFCGAL_PREFIX}" "${GEOS_PREFIX}"; do
      for sub in lib lib64; do
        if [ -d "${DEB_BUILD_DIR}${prefix}/${sub}" ]; then
          echo "${prefix}/${sub}" >> "${conf}"
        fi
      done
    done
    echo "==> Linker config contents:"
    sed 's/^/    /' "${conf}"
  fi

  # Note: keep this summary SIGPIPE-safe. Piping `find` into `head` under
  # `set -o pipefail` makes the truncated pipeline return 141 (128+SIGPIPE),
  # which would abort the script — hence the `|| true`.
  staged_total="$(find "${DEB_BUILD_DIR}" -type f | wc -l | tr -d ' ')"
  echo "==> Staged ${staged_total} files under ${DEB_BUILD_DIR} (sample):"
  { find "${DEB_BUILD_DIR}" -type f | sed "s#^${DEB_BUILD_DIR}#  #" | head -n 40; } || true
fi

echo "==> PostGIS build complete"
