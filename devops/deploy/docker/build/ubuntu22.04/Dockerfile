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
# PostGIS build container for Apache Cloudberry
#
# Step 1 of 2: this image provides a build environment with every prerequisite
# needed to compile PostGIS for Cloudberry:
#   - distro packages (build-essential, GEOS/PROJ/GDAL headers, protobuf, ...)
#   - from-source deps installed under /usr/local: PROJ, GDAL, CGAL, SFCGAL, GEOS
#   - linker paths registered via /etc/ld.so.conf.d + ldconfig
#
# Ref: https://cloudberry.apache.org/docs/advanced-analytics/postgis/
#
# Build:  docker build -t cloudberry-postgis-build .
# =============================================================================
FROM cloudberry-db-base-env:latest

# Never prompt during apt operations inside the image build.
ENV DEBIAN_FRONTEND=noninteractive

# Pinned dependency versions (matches the manual build steps).
ARG PROJ_VERSION=6.0.0
ARG GDAL_VERSION=3.5.3
ARG CGAL_VERSION=5.6.1
ARG SFCGAL_VERSION=1.4.1
ARG GEOS_VERSION=3.10.2

# -----------------------------------------------------------------------------
# 1. Prerequisite packages
# -----------------------------------------------------------------------------
RUN sudo apt-get update && \
    sudo apt-get install -y --no-install-recommends --allow-unauthenticated \
        build-essential \
        libgeos-dev \
        libproj-dev \
        libgdal-dev \
        libjson-c-dev \
        libxml2-dev \
        libexpat1-dev \
        libprotobuf-c-dev \
        sqlite3 \
        libgmp10 \
        libgmp-dev \
        libcgal-dev \
        protobuf-compiler \
        protobuf-c-compiler \
        xsltproc \
        libboost-all-dev \
        wget \
        ca-certificates \
        cmake \
        pkg-config \
        xz-utils \
        bzip2 && \
    sudo rm -rf /var/lib/apt/lists/*

# The base image runs as the unprivileged `gpadmin` user. `WORKDIR` would
# create this dir owned by root, and gpadmin could not write downloads into it
# (that is the `wget` "File I/O error", exit code 3). Create it explicitly and
# hand ownership to gpadmin.
RUN sudo mkdir -p /tmp/build && sudo chown -R gpadmin:gpadmin /tmp/build
WORKDIR /tmp/build

# NOTE: builds run as gpadmin, but every `make install` writes to /usr/local,
# so the install step (only) is run with sudo — matching the manual steps.

# -----------------------------------------------------------------------------
# 2. Build PROJ + GDAL
# -----------------------------------------------------------------------------
RUN wget -q https://download.osgeo.org/proj/proj-${PROJ_VERSION}.tar.gz && \
    tar -xzf proj-${PROJ_VERSION}.tar.gz && \
    cd proj-${PROJ_VERSION} && \
    ./configure --prefix=/usr/local/proj6 && \
    make -j"$(nproc)" && sudo make install && \
    cd /tmp/build && rm -rf proj-${PROJ_VERSION}*

RUN wget -q https://download.osgeo.org/gdal/${GDAL_VERSION}/gdal-${GDAL_VERSION}.tar.gz && \
    tar xf gdal-${GDAL_VERSION}.tar.gz && \
    cd gdal-${GDAL_VERSION} && \
    ./configure --prefix=/usr/local/gdal-${GDAL_VERSION} \
                --with-proj=/usr/local/proj6 && \
    make -j"$(nproc)" && sudo make install && \
    cd /tmp/build && rm -rf gdal-${GDAL_VERSION}*

# -----------------------------------------------------------------------------
# 3. Build CGAL (header-only, but installed under a versioned prefix)
# -----------------------------------------------------------------------------
RUN wget -q https://github.com/CGAL/cgal/releases/download/v${CGAL_VERSION}/CGAL-${CGAL_VERSION}.tar.xz && \
    tar -xf CGAL-${CGAL_VERSION}.tar.xz && \
    cd CGAL-${CGAL_VERSION} && \
    mkdir build && cd build && \
    cmake -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_INSTALL_PREFIX=/usr/local/cgal-${CGAL_VERSION} .. && \
    make -j"$(nproc)" && sudo make install && \
    cd /tmp/build && rm -rf CGAL-${CGAL_VERSION}*

# -----------------------------------------------------------------------------
# 4. Build SFCGAL (needs CGAL headers on the include path)
# -----------------------------------------------------------------------------
RUN wget -q https://gitlab.com/sfcgal/SFCGAL/-/archive/v${SFCGAL_VERSION}/SFCGAL-v${SFCGAL_VERSION}.tar.gz && \
    tar xf SFCGAL-v${SFCGAL_VERSION}.tar.gz && \
    cd SFCGAL-v${SFCGAL_VERSION} && \
    mkdir build && cd build && \
    cmake -DCMAKE_INSTALL_PREFIX=/usr/local/sfcgal-${SFCGAL_VERSION} \
          -DCGAL_DIR=/usr/local/cgal-${CGAL_VERSION}/lib/cmake/CGAL .. && \
    make -j"$(nproc)" && sudo make install && \
    cd /tmp/build && rm -rf SFCGAL-v${SFCGAL_VERSION}*

# -----------------------------------------------------------------------------
# 5. Build GEOS
# -----------------------------------------------------------------------------
RUN wget -q https://download.osgeo.org/geos/geos-${GEOS_VERSION}.tar.bz2 && \
    tar xf geos-${GEOS_VERSION}.tar.bz2 && \
    cd geos-${GEOS_VERSION} && \
    mkdir build && cd build && \
    cmake -DCMAKE_INSTALL_PREFIX=/usr/local/geos-${GEOS_VERSION} .. && \
    make -j"$(nproc)" && sudo make install && \
    cd /tmp/build && rm -rf geos-${GEOS_VERSION}*

# -----------------------------------------------------------------------------
# 6. Register the custom lib dirs with the dynamic linker
# -----------------------------------------------------------------------------
# A plain `>` redirect runs as gpadmin and cannot write under /etc; pipe into
# `sudo tee` instead. ldconfig also needs root.
RUN printf '%s\n' \
        "/usr/local/sfcgal-${SFCGAL_VERSION}/lib64/" \
        "/usr/local/gdal-${GDAL_VERSION}/lib/" \
        "/usr/local/geos-${GEOS_VERSION}/lib64/" \
        "/usr/local/proj6/lib/" \
        | sudo tee /etc/ld.so.conf.d/cloudberry-postgis.conf && \
    sudo ldconfig

WORKDIR /tmp/build
