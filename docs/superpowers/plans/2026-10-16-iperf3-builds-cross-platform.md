# Cross-platform iperf3 builds — implementation plan

> **Status:** completed in spirit; the Linux ARM64/ARM32 and macOS universal2 goals were delivered, but the implementation now uses the Zig-based approach from `2026-10-17-migrate-to-zig-cc.md` instead of the musl.cc toolchains described below. Treat this file as historical context, not as the current implementation plan.
>
> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the existing Linux x86_64 release pipeline to also produce Linux ARM64 / ARM32 static builds and a macOS universal2 build for every upstream iperf3 release.

**Architecture:** Keep the existing `build-release.yml` workflow shape, but add a matrix job for Linux static cross builds and three macOS jobs (x86_64 build, arm64 build, universal packaging). Build logic lives in small shell scripts. The release job downloads only artifacts whose names start with `release-`, computes `SHA256SUMS`, and publishes everything together.

**Tech Stack:** Bash, GitHub Actions, musl.cc cross toolchains, QEMU user-mode, `lipo`, `codesign`.

**Spec:** `docs/superpowers/specs/2026-10-16-iperf3-builds-cross-platform-design.md`

## Global Constraints

- Free GitHub Actions runners only.
- Linux x86_64 static/dynamic behavior and filenames must stay unchanged.
- Release tags mirror upstream exactly (no `v` prefix).
- Asset filenames use version without `v`: `iperf3-<version>-<os>-<arch>[-variant].tar.gz`.
- If any build or packaging job fails, the `release` job must not run — no partial releases.
- macOS deployment target: `11.0` (Big Sur).
- macOS binaries are ad-hoc signed only (`codesign -s -`); no Apple Developer ID notarization.

## Review Focus

- A cross-compiled ARM binary must actually execute on the target architecture; `file`/`readelf` checks are not enough.
- The macOS universal2 binary must contain both x86_64 and arm64 slices and must run on Apple Silicon.
- The release job must publish only final tarballs, not intermediate raw macOS single-arch binaries.
- Existing x86_64 static and dynamic Linux archives keep their exact current names and contents.
- A single failed platform must abort the whole release.

---

### Task 1: Refactor `scripts/build-static.sh` for cross-compilation

**Files:**
- Modify: `scripts/build-static.sh`
- Test: run script locally for x86_64

**Interfaces:**
- Consumes: `IPERF_VERSION` (required), `ARCH` (optional, default `x86_64`; also accepts `aarch64`, `armv7`).
- Produces: tarball `iperf3-${VERSION}-linux-${ARCH}-static.tar.gz` in the current working directory.

- [ ] **Step 1: Add `ARCH` handling and cross toolchain download**

  In `scripts/build-static.sh`, after validating `IPERF_VERSION`:
  - Set `ARCH="${ARCH:-x86_64}"`.
  - For `x86_64`, continue using host `musl-gcc` (installed from `musl-tools`).
  - For `aarch64`, download `https://musl.cc/aarch64-linux-musl-cross.tgz`, extract to `/opt/cross`, and set `CC=/opt/cross/bin/aarch64-linux-musl-gcc` and `HOST=aarch64-linux-musl`.
  - For `armv7`, download `https://musl.cc/arm-linux-musleabihf-cross.tgz`, extract to `/opt/cross`, and set `CC=/opt/cross/bin/arm-linux-musleabihf-gcc` and `HOST=arm-linux-musleabihf`.
  - If `ARCH` is anything else, fail with an error message.

- [ ] **Step 2: Update configure invocation for cross builds**

  - For `x86_64`, keep `./configure CC=musl-gcc CFLAGS="-static" LDFLAGS="-static" --disable-shared --enable-static-bin`.
  - For cross builds, use `./configure CC="$CC" CFLAGS="-static" LDFLAGS="-static" --host="$HOST" --disable-shared --enable-static-bin`.

- [ ] **Step 3: Update output directory, README and archive name**

  - Replace hardcoded `linux-x86_64-static` with `linux-${ARCH}-static` in `OUTPUT_DIR`, `README.md` header, and `ARCHIVE`.
  - Make the README header say `iperf3 ${VERSION} — static build for Linux ${ARCH}`.
  - Build inside a temporary subdirectory (e.g. `iperf3-build-static-${ARCH}`) and copy the final `iperf3-${VERSION}-linux-${ARCH}-static.tar.gz` to the current working directory so the GitHub Actions upload path is consistent across architectures.

- [ ] **Step 4: Replace `ldd` static check with cross-friendly checks**

  - Verify the binary is statically linked by running `readelf -d src/iperf3` and ensuring `NEEDED` is empty.
  - Verify architecture with `file src/iperf3` and grep for the expected architecture string:
    - `x86_64`: `x86-64`
    - `aarch64`: `aarch64` or `ARM aarch64`
    - `armv7`: `ARM` (and not `AArch64`)

- [ ] **Step 5: Add architecture-aware smoke tests**

  - For `x86_64`, run `"${OUTPUT_DIR}/iperf3" --version` directly (existing behavior).
  - For `aarch64`, install `qemu-user-static` and run `qemu-aarch64-static "${OUTPUT_DIR}/iperf3" --version`.
  - For `armv7`, install `qemu-user-static` and run `qemu-arm-static "${OUTPUT_DIR}/iperf3" --version`.
  - Make the script exit non-zero if the smoke test fails.

- [ ] **Step 6: Run local x86_64 test**

  Run: `IPERF_VERSION=3.22 ./scripts/build-static.sh`
  Expected: `iperf3-3.22-linux-x86_64-static.tar.gz` exists, can be extracted, and `./iperf3-3.22-linux-x86_64-static/iperf3 --version` prints `3.22`.

- [ ] **Step 7: Commit**

  ```bash
  git add scripts/build-static.sh
  git commit -m "build: support aarch64 and armv7 static musl cross builds"
  ```

---

### Task 2: Create macOS single-architecture build script

**Files:**
- Create: `scripts/build-macos-arch.sh`
- Test: `bash -n scripts/build-macos-arch.sh`

**Interfaces:**
- Consumes: `IPERF_VERSION` (required), `ARCH` (required, `x86_64` or `arm64`).
- Produces: directory `macos-build-${ARCH}/` in the current working directory, containing `iperf3` and `LICENSE`.

- [ ] **Step 1: Scaffold the script**

  Create `scripts/build-macos-arch.sh` with `#!/usr/bin/env bash` and `set -euo pipefail`.
  Validate that `IPERF_VERSION` and `ARCH` are set and that `ARCH` is either `x86_64` or `arm64`.

- [ ] **Step 2: Fetch source with macOS-friendly fallback**

  - Try to download `https://github.com/esnet/iperf/releases/download/${VERSION}/iperf-${VERSION}.tar.gz`.
  - If the tarball is missing, clone the tag from GitHub and install autotools:
    ```bash
    brew install autoconf automake libtool
    git clone --branch "${VERSION}" --depth 1 https://github.com/esnet/iperf.git "iperf-${VERSION}"
    cd "iperf-${VERSION}"
    autoreconf -fi
    ```

- [ ] **Step 3: Configure and build**

  - `cd` into the source directory.
  - Export `MACOSX_DEPLOYMENT_TARGET=11.0`.
  - Run:
    ```bash
    ./configure --disable-shared
    make -j"$(sysctl -n hw.ncpu)"
    ```

- [ ] **Step 4: Prepare output directory**

  - Create `macos-build-${ARCH}/`.
  - Copy `src/iperf3` to `macos-build-${ARCH}/iperf3`.
  - Copy `LICENSE` to `macos-build-${ARCH}/LICENSE`.

- [ ] **Step 5: Verify and smoke test**

  - Run `file macos-build-${ARCH}/iperf3` and confirm the architecture string matches `ARCH`:
    - `x86_64`: `x86_64`
    - `arm64`: `arm64`
  - Run `./macos-build-${ARCH}/iperf3 --version` and confirm the output contains the version.

- [ ] **Step 6: Syntax check**

  Run: `bash -n scripts/build-macos-arch.sh`
  Expected: no output (no syntax errors).

- [ ] **Step 7: Commit**

  ```bash
  git add scripts/build-macos-arch.sh
  git commit -m "build: add macOS single-arch build script"
  ```

---

### Task 3: Create macOS universal2 packaging script

**Files:**
- Create: `scripts/build-macos-universal.sh`
- Test: `bash -n scripts/build-macos-universal.sh`

**Interfaces:**
- Consumes: `IPERF_VERSION` (required). Expects `macos-build-x86_64/iperf3`, `macos-build-arm64/iperf3`, and one `macos-build-*/LICENSE` in the current working directory.
- Produces: `iperf3-${VERSION}-macos-universal2.tar.gz` in the current working directory.

- [ ] **Step 1: Scaffold the script**

  Create `scripts/build-macos-universal.sh` with `#!/usr/bin/env bash` and `set -euo pipefail`.
  Validate `IPERF_VERSION`.

- [ ] **Step 2: Merge single-arch binaries**

  - Ensure `macos-build-x86_64/iperf3` and `macos-build-arm64/iperf3` exist.
  - Run `lipo -create macos-build-x86_64/iperf3 macos-build-arm64/iperf3 -output iperf3`.
  - Run `codesign -s - iperf3` (ad-hoc sign).

- [ ] **Step 3: Package the universal binary**

  - Create `iperf3-${VERSION}-macos-universal2/`.
  - Move the merged `iperf3` into it.
  - Copy `macos-build-x86_64/LICENSE` (or `macos-build-arm64/LICENSE`) into it.
  - Create `iperf3-${VERSION}-macos-universal2/README.md` describing:
    - This is a universal2 build for macOS Intel and Apple Silicon.
    - macOS 11.0 (Big Sur) or newer is required.
    - Browser downloads may be quarantined; users can run `xattr -d com.apple.quarantine iperf3` if needed.
  - Create `iperf3-${VERSION}-macos-universal2.tar.gz`.

- [ ] **Step 4: Verify the universal binary**

  - `lipo -info iperf3-${VERSION}-macos-universal2/iperf3` must list both `x86_64` and `arm64`.
  - `file iperf3-${VERSION}-macos-universal2/iperf3` must confirm universal binary.
  - Run `./iperf3-${VERSION}-macos-universal2/iperf3 --version` on the Apple Silicon runner and confirm it prints the version.

- [ ] **Step 5: Syntax check**

  Run: `bash -n scripts/build-macos-universal.sh`
  Expected: no output.

- [ ] **Step 6: Commit**

  ```bash
  git add scripts/build-macos-universal.sh
  git commit -m "build: add macOS universal2 packaging script"
  ```

---

### Task 4: Update `.github/workflows/build-release.yml`

**Files:**
- Modify: `.github/workflows/build-release.yml`
- Test: validate YAML syntax and trigger a test run

**Interfaces:**
- Consumes: `inputs.version`.
- Produces: GitHub Release containing all final `iperf3-*.tar.gz` assets and `SHA256SUMS`.

- [ ] **Step 1: Rename existing Linux artifact uploads**

  - In the `build-static` job, change the upload step to:
    ```yaml
    - name: Upload static artifact
      uses: actions/upload-artifact@v6
      with:
        name: release-linux-x86_64-static
        path: iperf3-*-linux-x86_64-static.tar.gz
        if-no-files-found: error
    ```
  - In the `build-dynamic` job, change the upload step to:
    ```yaml
    - name: Upload dynamic artifact
      uses: actions/upload-artifact@v6
      with:
        name: release-linux-x86_64-dynamic
        path: iperf3-*-linux-x86_64-dynamic.tar.gz
        if-no-files-found: error
    ```

- [ ] **Step 2: Add Linux static cross-build matrix job**

  Add a new job:
  ```yaml
  build-linux-static-cross:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: true
      matrix:
        arch: [aarch64, armv7]
    steps:
      - name: Validate version input
        env:
          VERSION: ${{ inputs.version }}
        run: |
          set -euo pipefail
          if [ -z "$VERSION" ]; then
            echo "ERROR: version input is empty" >&2
            exit 1
          fi
          if [[ "$VERSION" == *[/\\]* || "$VERSION" == *..* ]]; then
            echo "ERROR: invalid version input: $VERSION" >&2
            exit 1
          fi
      - name: Checkout repository
        uses: actions/checkout@v5
      - name: Build static (${{ matrix.arch }}) binary
        env:
          IPERF_VERSION: ${{ inputs.version }}
          ARCH: ${{ matrix.arch }}
        run: |
          set -euo pipefail
          ./scripts/build-static.sh
      - name: Upload static artifact
        uses: actions/upload-artifact@v6
        with:
          name: release-linux-${{ matrix.arch }}-static
          path: iperf3-*-linux-${{ matrix.arch }}-static.tar.gz
          if-no-files-found: error
  ```

- [ ] **Step 3: Add macOS x86_64 build job**

  Add:
  ```yaml
  build-macos-x86_64:
    runs-on: macos-26-intel
    steps:
      - uses: actions/checkout@v5
      - name: Build macOS x86_64 binary
        env:
          IPERF_VERSION: ${{ inputs.version }}
          ARCH: x86_64
        run: ./scripts/build-macos-arch.sh
      - uses: actions/upload-artifact@v6
        with:
          name: build-macos-x86_64
          path: macos-build-x86_64/**
          if-no-files-found: error
  ```

- [ ] **Step 4: Add macOS arm64 build job**

  Add:
  ```yaml
  build-macos-arm64:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v5
      - name: Build macOS arm64 binary
        env:
          IPERF_VERSION: ${{ inputs.version }}
          ARCH: arm64
        run: ./scripts/build-macos-arch.sh
      - uses: actions/upload-artifact@v6
        with:
          name: build-macos-arm64
          path: macos-build-arm64/**
          if-no-files-found: error
  ```

- [ ] **Step 5: Add macOS universal packaging job**

  Add:
  ```yaml
  package-macos-universal:
    needs: [build-macos-x86_64, build-macos-arm64]
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v5
      - uses: actions/download-artifact@v7
        with:
          pattern: build-macos-*
          merge-multiple: true
      - name: Package universal2 binary
        env:
          IPERF_VERSION: ${{ inputs.version }}
        run: ./scripts/build-macos-universal.sh
      - uses: actions/upload-artifact@v6
        with:
          name: release-macos-universal2
          path: iperf3-*-macos-universal2.tar.gz
          if-no-files-found: error
  ```

- [ ] **Step 6: Update `release` job dependencies**

  Change:
  ```yaml
  release:
    needs: [build-static, build-dynamic, build-linux-static-cross, package-macos-universal]
  ```

- [ ] **Step 7: Update artifact download and release creation**

  Replace the download step with:
  ```yaml
  - name: Download artifacts
    uses: actions/download-artifact@v7
    with:
      path: artifacts
      pattern: release-*
      merge-multiple: true
  ```

  Update the release creation section to collect all tarballs flat:
  ```bash
  cp release-notes.md artifacts/
  cd artifacts
  if ! ls iperf3-*.tar.gz >/dev/null 2>&1; then
    echo "ERROR: no release archives found" >&2
    exit 1
  fi
  sha256sum iperf3-*.tar.gz > SHA256SUMS
  gh release create "${VERSION}" \
    --title "iperf3 ${VERSION} builds" \
    --notes-file release-notes.md \
    ${prerelease_flag} \
    ${latest_flag} \
    iperf3-*.tar.gz SHA256SUMS
  ```

- [ ] **Step 8: Validate YAML and push**

  Run:
  ```bash
  python3 -c "import yaml; yaml.safe_load(open('.github/workflows/build-release.yml'))"
  ```
  Expected: no errors.

  Then commit and push:
  ```bash
  git add .github/workflows/build-release.yml
  git commit -m "ci: add ARM and macOS builds to release pipeline"
  git push
  ```

---

### Task 5: Update `README.md`

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Document supported platforms**

  In the Downloads section, list all assets produced per release:
  - Linux x86_64 static / dynamic (existing)
  - Linux aarch64 static
  - Linux armv7 static
  - macOS universal2 (Intel + Apple Silicon)

- [ ] **Step 2: Add macOS quarantine note**

  Add a short note:
  > If you download the macOS archive through a browser, macOS may quarantine the binary. If Terminal says the developer cannot be verified, run `xattr -d com.apple.quarantine iperf3` in the extracted directory, or allow it in System Settings → Privacy & Security.

- [ ] **Step 3: Commit**

  ```bash
  git add README.md
  git commit -m "docs: document cross-platform release assets"
  ```

---

### Task 6: Verification run

**Files:** none changed; validates the pipeline.

- [ ] **Step 1: Trigger a build for an existing version**

  Run:
  ```bash
  gh workflow run build-release.yml --repo rusnino/iperf3-builds -f version=3.22
  ```

- [ ] **Step 2: Inspect build job results**

  Open the Actions run. Confirm:
  - `build-static` succeeds.
  - `build-dynamic` succeeds.
  - `build-linux-static-cross` succeeds for both `aarch64` and `armv7`.
  - `build-macos-x86_64` and `build-macos-arm64` succeed.
  - `package-macos-universal` succeeds and the universal binary smoke test passes.
  - No Node.js 20 deprecation warnings.

- [ ] **Step 3: Handle expected release failure**

  The `release` job will fail because version `3.22` already exists. This is expected for this test. Download the produced artifacts from the workflow run page and inspect:
  - `release-linux-aarch64-static` tarball exists and contains a static ARM64 ELF.
  - `release-linux-armv7-static` tarball exists and contains a static ARM ELF.
  - `release-macos-universal2` tarball exists.

- [ ] **Step 4: Optional full end-to-end test**

  If a full release creation test is needed, delete a low-priority pre-release such as `3.16-beta1` and re-trigger `build-release.yml` for that version:
  ```bash
  gh release delete 3.16-beta1 --repo rusnino/iperf3-builds --yes
  gh workflow run build-release.yml --repo rusnino/iperf3-builds -f version=3.16-beta1
  ```
  Then verify on the Releases page that all new assets and `SHA256SUMS` are present.

---

## Self-review checklist

- [ ] Spec coverage: every supported platform from the design doc has a corresponding job/script.
- [ ] Step scan: each step names one concrete action and the exact expected result.
- [ ] Type/interface consistency: scripts use `IPERF_VERSION` and `ARCH`; workflow passes them as env vars.
- [ ] Review focus: smoke tests for ARM use QEMU, macOS universal uses `lipo -info` and execution, release job filters `release-*` artifacts.
- [ ] Proportion: plan describes decisions (filenames, artifact names, env vars) without duplicating the script bodies.
