<!--
  Licensed to the Apache Software Foundation (ASF) under one
  or more contributor license agreements.  See the NOTICE file
  distributed with this work for additional information
  regarding copyright ownership.  The ASF licenses this file
  to you under the Apache License, Version 2.0 (the
  "License"); you may not use this file except in compliance
  with the License.  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing,
  software distributed under the License is distributed on an
  "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
  KIND, either express or implied.  See the License for the
  specific language governing permissions and limitations
  under the License.
-->

# PostGIS-for-Cloudberry packaging (devops)

Two-step process to produce a Debian package containing **only** the PostGIS
extension, built against Apache Cloudberry.

Layout mirrors the main Cloudberry repo's `devops/` directory.

```
devops/
├── deploy/docker/
│   ├── build/ubuntu22.04/Dockerfile      # Step 1: build-environment image
│   └── package/ubuntu22.04/Dockerfile    # Step 2: builds Cloudberry + PostGIS, makes the .deb
└── build/
    ├── automation/postgis/scripts/
    │   └── build-postgis.sh              # configure/make/install PostGIS + stage payload
    └── packaging/deb/
        ├── build-deb.sh                  # runs dpkg-buildpackage
        └── ubuntu22.04/                  # debian metadata (extension-only control)
            ├── control  rules  install  changelog  compat
            └── source/{format,local-options}
```

## Step 1 — build-environment image

Installs the PostGIS build prerequisites and compiles the geospatial stack
(PROJ, GDAL, CGAL, SFCGAL, GEOS) under `/usr/local`.

```bash
docker build \
  -f devops/deploy/docker/build/ubuntu22.04/Dockerfile \
  -t cloudberry-postgis-build:latest .
```

> The `FROM` in that Dockerfile is the Cloudberry base env image
> (`cloudberry-db-base-env:latest`); it runs as the `gpadmin` user with
> passwordless `sudo`.

## Step 2 — build Cloudberry + PostGIS and produce the .deb

The base image ships no Cloudberry binaries, so this stage first builds Apache
Cloudberry from source into `/usr/local/cloudberry-db` (using Cloudberry's own
`configure-cloudberry.sh` / `build-cloudberry.sh`), then builds PostGIS against
it and packages only the extension files.

```bash
docker build \
  -f devops/deploy/docker/package/ubuntu22.04/Dockerfile \
  --build-arg BUILD_IMAGE=cloudberry-postgis-build:latest \
  --build-arg CLOUDBERRY_REF=main \
  -t cloudberry-postgis-deb:latest .

# extract the artifact
id=$(docker create cloudberry-postgis-deb:latest)
docker cp "$id":/home/gpadmin/output ./output
docker rm "$id"
```

## Notes

- **Package name encodes the Cloudberry branch:**
  `apache-cloudberry-db-postgis-<branch>` (e.g. `-main`, `-rel-2-stable`). PostGIS
  bakes in the PostgreSQL major of the Cloudberry it was built against, so a
  `REL_2_STABLE` (PG14) build cannot load in a `main` (PG16) server. The branch
  comes from `-b` / `$CBDB_BRANCH` / `$CLOUDBERRY_REF` (the step-2 Dockerfile
  passes `--build-arg CLOUDBERRY_REF`), sanitized to a valid package name. Each
  variant `Provides/Conflicts/Replaces: apache-cloudberry-db-postgis`, so
  installing one branch's package cleanly swaps out another's (they share the
  same `/usr/cloudberry-db` files and only one Cloudberry lives on a host).
- `Depends: apache-cloudberry-db-incubating` plus the geospatial runtime libs
  (auto-detected via `${shlibs:Depends}` and a few explicit base libs).
- **Extension files:** `build-postgis.sh` performs a `make install DESTDIR=` so
  only PostGIS's own files are captured. They are built against GPHOME
  (`/usr/local/cloudberry-db`) but **re-rooted onto `/usr/cloudberry-db`** — the
  real directory the Apache Cloudberry `.deb` owns (it symlinks
  `/usr/local/cloudberry-db → /usr/cloudberry-db`). This co-populates the
  Cloudberry tree without conflicting with the symlink. Override with
  `GPHOME_PKG_TARGET` if your Cloudberry lives elsewhere.
- **Bundled runtime libs:** the same script also stages the custom
  GEOS/PROJ/GDAL/SFCGAL trees (`lib`/`lib64`/`share`, so PROJ's `proj.db` and
  GDAL's data ship too) at their `/usr/local` prefixes, plus the
  `/etc/ld.so.conf.d/cloudberry-postgis.conf` entry. The package's `postinst`
  runs `ldconfig`, so it is self-contained — no separate geospatial install is
  needed on the target. Set `BUNDLE_GEO_LIBS=false` to opt out.
- **Staging layout:** everything is staged under `debian/build` mirroring the
  target filesystem (absolute paths), and `debian/install` (`debian/build/* /`)
  drops it onto the target root as-is.
- **Versions** are `ARG`s at the top of each Dockerfile — keep the geospatial
  versions in sync between the two stages, and set `POSTGIS_VERSION` /
  `CLOUDBERRY_REF` as needed.
```
