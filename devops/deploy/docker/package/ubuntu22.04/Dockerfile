# syntax=docker/dockerfile:1
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

# =============================================================================
# PostGIS .deb packaging container for Apache Cloudberry   (Step 2 of 2)
#
# Consumes the build-environment image produced by step 1
#   devops/deploy/docker/build/ubuntu22.04/Dockerfile
# (PROJ / GDAL / CGAL / SFCGAL / GEOS already installed under /usr/local),
# then:
#   1. Builds Apache Cloudberry from source into /usr/local/cloudberry-db.
#      The base image ships NO cloudberry binaries, so we generate them with
#      the very same scripts Cloudberry CI uses
#      (configure-cloudberry.sh + build-cloudberry.sh), as in
#      .github/workflows/build-deb-cloudberry.yml.
#   2. Builds the PostGIS extension against that Cloudberry's pg_config and
#      the custom /usr/local geospatial stack (build-postgis.sh).
#   3. Stages ONLY the PostGIS-produced files and wraps them in a .deb whose
#      debian/control lists just the extension payload (build-deb.sh).
#
# The resulting .deb is left in /home/gpadmin/output inside the image.
#
# Build (run from the repo root so the whole repo is the build context):
#   docker build \
#     -f devops/deploy/docker/package/ubuntu22.04/Dockerfile \
#     --build-arg BUILD_IMAGE=cloudberry-postgis-build:latest \
#     --build-arg CLOUDBERRY_REF=main \
#     -t cloudberry-postgis-deb .
#
# Extract the artifact:
#   id=$(docker create cloudberry-postgis-deb)
#   docker cp "$id":/home/gpadmin/output ./output
#   docker rm "$id"
# =============================================================================

# Image produced by step 1 (devops/deploy/docker/build/ubuntu22.04/Dockerfile).
ARG BUILD_IMAGE=cloudberry-postgis-build:latest
FROM ${BUILD_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive

# --- versions (keep in sync with the build-env image) ------------------------
ARG GDAL_VERSION=3.5.3
ARG SFCGAL_VERSION=1.4.1
ARG GEOS_VERSION=3.10.2
ARG POSTGIS_VERSION=3.3.2

# --- Apache Cloudberry source used to generate the binaries ------------------
ARG CLOUDBERRY_REPO=https://github.com/apache/cloudberry.git
ARG CLOUDBERRY_REF=main

# Tools needed for cloning Cloudberry and for dpkg packaging. Most compile
# dependencies already exist in the Cloudberry base / build-env image.
RUN sudo apt-get update && \
    sudo apt-get install -y --no-install-recommends --allow-unauthenticated \
        git \
        debhelper \
        dpkg-dev \
        fakeroot \
        lsb-release && \
    sudo rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# 1. Generate Apache Cloudberry binaries -> /usr/local/cloudberry-db
#    (mirrors .github/workflows/build-deb-cloudberry.yml)
# -----------------------------------------------------------------------------
ENV CLOUDBERRY_SRC=/home/gpadmin/cloudberry
ENV BUILD_DESTINATION=/usr/local/cloudberry-db

RUN git clone --depth 1 --branch "${CLOUDBERRY_REF}" \
        "${CLOUDBERRY_REPO}" "${CLOUDBERRY_SRC}"

# configure-cloudberry.sh prepares/chowns BUILD_DESTINATION; build-cloudberry.sh
# runs `make` + `make install` into it. Both are the repo's own CI scripts.
RUN cd "${CLOUDBERRY_SRC}" && \
    mkdir ${CLOUDBERRY_SRC}/build-logs && \
    chmod +x devops/build/automation/cloudberry/scripts/*.sh && \
    SRC_DIR="${CLOUDBERRY_SRC}" \
    BUILD_DESTINATION="${BUILD_DESTINATION}" \
    ENABLE_DEBUG=false \
    ./devops/build/automation/cloudberry/scripts/configure-cloudberry.sh && \
    SRC_DIR="${CLOUDBERRY_SRC}" \
    BUILD_DESTINATION="${BUILD_DESTINATION}" \
    ./devops/build/automation/cloudberry/scripts/build-cloudberry.sh

# -----------------------------------------------------------------------------
# 2 + 3. Build PostGIS against Cloudberry, stage the payload, build the .deb
# -----------------------------------------------------------------------------
ENV POSTGIS_REPO=/home/gpadmin/postgis
COPY --chown=gpadmin:gpadmin . ${POSTGIS_REPO}

# Build PostGIS and stage ONLY its files into debian/build.
RUN cd "${POSTGIS_REPO}" && \
    chmod +x devops/build/automation/postgis/scripts/build-postgis.sh \
             devops/build/packaging/deb/build-deb.sh \
             devops/build/packaging/deb/ubuntu22.04/rules && \
    bash -c 'source "${BUILD_DESTINATION}/cloudberry-env.sh" && \
      GPHOME="${BUILD_DESTINATION}" \
      POSTGIS_SRC="${POSTGIS_REPO}/postgis/build/postgis-${POSTGIS_VERSION}" \
      GDAL_CONFIG="/usr/local/gdal-${GDAL_VERSION}/bin/gdal-config" \
      SFCGAL_CONFIG="/usr/local/sfcgal-${SFCGAL_VERSION}/bin/sfcgal-config" \
      GEOS_CONFIG="/usr/local/geos-${GEOS_VERSION}/bin/geos-config" \
      PROJ_DIR="/usr/local/proj6" \
      DEB_BUILD_DIR="${POSTGIS_REPO}/debian/build" \
      ./devops/build/automation/postgis/scripts/build-postgis.sh'

# Package the staged payload into a .deb and collect it under /home/gpadmin/output.
# The Cloudberry branch (-b) is encoded into the package name so builds for
# different branches / PostgreSQL majors stay distinct.
RUN cd "${POSTGIS_REPO}" && \
    ./devops/build/packaging/deb/build-deb.sh -v "${POSTGIS_VERSION}" -b "${CLOUDBERRY_REF}" && \
    mkdir -p /home/gpadmin/output && \
    cp /home/gpadmin/*.deb /home/gpadmin/output/ && \
    echo "=== Built packages ===" && ls -l /home/gpadmin/output && \
    echo "=== Package contents ===" && dpkg --contents /home/gpadmin/output/*.deb

WORKDIR /home/gpadmin/output
