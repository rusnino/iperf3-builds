# iperf3-builds Implementation Plan

> **Status:** completed. The repository, watcher workflow, Linux x86_64 static/dynamic builds, and initial release pipeline described here are all functional. Subsequent work is tracked in `2026-10-17-migrate-to-zig-cc.md` and the platform coverage spec.
>
> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create and configure the `rusnino/iperf3-builds` GitHub repository so it automatically detects new releases of `esnet/iperf`, builds static (musl) and dynamic (glibc) Linux x86_64 binaries, and publishes them as GitHub Releases with SHA256 checksums and upstream release notes.

**Architecture:** A watcher workflow runs daily and triggers a build-and-release workflow for each missing upstream release (backfill up to 10). The build workflow compiles iperf3 twice (static on Alpine/musl, dynamic on Ubuntu 20.04/glibc), packages archives, computes SHA256SUMS, and creates a GitHub Release only if both builds succeed. All source is fetched by git tag so stable and rc/pre-release builds work identically.

**Tech Stack:** GitHub Actions, shell scripts, `gh` CLI, `musl-tools`/Alpine, autotools.

**Spec:** `/root/projects/iperf3-binares/docs/superpowers/specs/2026-10-16-iperf3-builds-design.md`

## Global Constraints

- Repository name: `rusnino/iperf3-builds`.
- Upstream repository: `esnet/iperf`.
- Target platform: Linux x86_64.
- Build variants: static (musl) and dynamic (glibc).
- Release tags must match upstream exactly, e.g. `v3.17.1`.
- Release asset names use version without `v`, e.g. `iperf3-3.17.1-linux-x86_64-static.tar.gz`.
- Backfill limit: 10 most recent upstream releases.
- If either build fails, the entire release is aborted.
- Watcher runs daily at 04:00 UTC and supports manual `workflow_dispatch`.
- `gh` is already authenticated as `rusnino`.

## Review Focus

- **Backfill on first run:** The watcher must build up to 10 missing releases without creating duplicates or skipping releases. Covered by Task 4 tests/verification.
- **Pre-release/rc handling:** Upstream pre-releases must be published as GitHub pre-releases here. Covered by Task 4 tests/verification.
- **Static binary portability:** The static binary must not depend on glibc or other dynamic libs. Covered by Task 2 verification.
- **Dynamic binary compatibility:** The dynamic binary must run on CentOS Stream 8 / guestshell (glibc ~2.28). Covered by Task 3 verification.
- **Partial failure abort:** If one build variant fails, no GitHub Release is created. Covered by Task 5 verification.
- **Release notes copy:** The created release must contain the upstream release body. Covered by Task 5 verification.

---

### Task 1: Create the `rusnino/iperf3-builds` repository

**Files:**
- Create: remote GitHub repository `rusnino/iperf3-builds`.
- Modify: local git remote in `/root/projects/iperf3-binares` to point to the new repository (or clone fresh).

**Interfaces:**
- Produces: a GitHub repository named `rusnino/iperf3-builds` with default branch `main`.

- [ ] **Step 1: Create the repository via `gh`**

Run: `gh repo create rusnino/iperf3-builds --public --description "Automated iperf3 builds for Linux x86_64" --confirm`

Expected: command succeeds and prints the repository URL.

- [ ] **Step 2: Configure local repository to point to the new remote**

Run:
```bash
cd /root/projects/iperf3-binares
git remote rename origin old-origin 2>/dev/null || true
git remote add origin git@github.com:rusnino/iperf3-builds.git
```

Expected: `git remote -v` shows `origin` pointing to `git@github.com:rusnino/iperf3-builds.git`.

- [ ] **Step 3: Commit and push the design/plan files to `main`**

Run:
```bash
git add docs/
git commit -m "docs: add iperf3-builds design and implementation plan"
git push -u origin main
```

Expected: `git push` succeeds; `gh repo view rusnino/iperf3-builds` shows the files.

---

### Task 2: Add the static (musl) build script

**Files:**
- Create: `scripts/build-static.sh`
- Create: `.github/workflows/build-release.yml` (partial, expanded in later tasks)

**Interfaces:**
- Consumes: environment variable `IPERF_VERSION` (e.g. `v3.17.1` or `3.17.1`).
- Produces: file `iperf3-{version}-linux-x86_64-static.tar.gz` in the current working directory, containing `iperf3-{version}-linux-x86_64-static/iperf3`, `README.md`, and `LICENSE`.

- [ ] **Step 1: Write `scripts/build-static.sh`**

The script must:
1. Accept `IPERF_VERSION` (strip leading `v` if present).
2. Install build deps (`build-essential`, `musl-tools`) or run in an Alpine container.
3. Clone `https://github.com/esnet/iperf.git` at tag `v${VERSION}`.
4. Run `autoreconf -fi` and `./configure CC=musl-gcc CFLAGS="-static" --disable-shared`.
5. Run `make`.
6. Verify the resulting binary is statically linked: `ldd src/iperf3` should report "not a dynamic executable".
7. Create output directory `iperf3-{VERSION}-linux-x86_64-static`, copy binary as `iperf3`, add `README.md` and `LICENSE`.
8. Create `iperf3-{VERSION}-linux-x86_64-static.tar.gz`.

- [ ] **Step 2: Test the script locally for the latest iperf3 tag**

Run:
```bash
cd /tmp
rm -rf iperf3-builds-test
mkdir iperf3-builds-test && cd iperf3-builds-test
IPERF_VERSION=$(gh api repos/esnet/iperf/releases/latest --jq '.tag_name')
bash /root/projects/iperf3-binares/scripts/build-static.sh
```

Expected: archive `iperf3-*.tar.gz` is created and the extracted binary reports `ldd: not a dynamic executable`.

- [ ] **Step 3: Commit the script**

Run:
```bash
cd /root/projects/iperf3-binares
git add scripts/build-static.sh
git commit -m "build: add static musl build script"
```

---

### Task 3: Add the dynamic (glibc) build script

**Files:**
- Create: `scripts/build-dynamic.sh`

**Interfaces:**
- Consumes: environment variable `IPERF_VERSION`.
- Produces: file `iperf3-{version}-linux-x86_64-dynamic.tar.gz` in the current working directory.

- [ ] **Step 1: Write `scripts/build-dynamic.sh`**

The script must:
1. Accept `IPERF_VERSION` (strip leading `v` if present).
2. Install build deps (`build-essential`).
3. Clone `https://github.com/esnet/iperf.git` at tag `v${VERSION}`.
4. Run `autoreconf -fi` and `./configure`.
5. Run `make`.
6. Create output directory `iperf3-{VERSION}-linux-x86_64-dynamic`, copy binary as `iperf3`, add `README.md` and `LICENSE`.
7. Create `iperf3-{VERSION}-linux-x86_64-dynamic.tar.gz`.

- [ ] **Step 2: Verify the dynamic binary is linked against glibc**

Run:
```bash
IPERF_VERSION=$(gh api repos/esnet/iperf/releases/latest --jq '.tag_name')
bash /root/projects/iperf3-binares/scripts/build-dynamic.sh
ldd iperf3-*/iperf3 | grep -E 'libc\.so|libpthread|libm'
```

Expected: output shows `libc.so.6` and compatible versions.

- [ ] **Step 3: Test the dynamic binary on CentOS Stream 8/guestshell if possible, or via a container**

Run:
```bash
docker run --rm -v "$(pwd):/tmp/build" quay.io/centos/centos:stream8 /tmp/build/iperf3-*/iperf3 --version
```

Expected: binary prints iperf3 version (or starts without "version `GLIBC_...` not found").

- [ ] **Step 4: Commit the script**

Run:
```bash
cd /root/projects/iperf3-binares
git add scripts/build-dynamic.sh
git commit -m "build: add dynamic glibc build script"
```

---

### Task 4: Add the release watcher workflow

**Files:**
- Create: `.github/workflows/release-watcher.yml`

**Interfaces:**
- Consumes: GitHub API for `esnet/iperf` releases.
- Produces: workflow dispatches of `.github/workflows/build-release.yml` for each missing upstream release.

- [ ] **Step 1: Write the watcher workflow**

Workflow `release-watcher.yml`:
- Triggers: `schedule: cron("0 4 * * *")` and `workflow_dispatch`.
- Job runs on `ubuntu-latest`.
- Steps:
  1. Fetch the last 10 releases from `https://api.github.com/repos/esnet/iperf/releases?per_page=10` using `GITHUB_TOKEN`.
  2. List existing tags in `rusnino/iperf3-builds` using `gh release list --limit 100` or `gh api repos/rusnino/iperf3-builds/tags`.
  3. For each upstream release whose tag does not exist locally, trigger `build-release.yml` via `gh workflow run build-release.yml -f version=<tag>`.
  4. If no new releases, exit successfully.

- [ ] **Step 2: Verify the watcher logic locally (dry run)**

Run a shell snippet that lists upstream releases and compares with local tags. Do not trigger workflows during the test.

Expected: output clearly shows which releases are missing locally.

- [ ] **Step 3: Commit the workflow**

Run:
```bash
git add .github/workflows/release-watcher.yml
git commit -m "ci: add daily release watcher workflow"
```

---

### Task 5: Add the build-and-release workflow

**Files:**
- Create/expand: `.github/workflows/build-release.yml`

**Interfaces:**
- Consumes: input `version` (e.g. `v3.17.1`).
- Produces: GitHub Release with assets and SHA256SUMS.

- [ ] **Step 1: Define workflow inputs and structure**

Workflow `build-release.yml`:
- Triggers: `workflow_call` with input `version` and `workflow_dispatch` with input `version`.
- Jobs:
  - `build-static`: runs on `ubuntu-latest`, calls `scripts/build-static.sh`, uploads artifact.
  - `build-dynamic`: runs on `ubuntu-20.04`, calls `scripts/build-dynamic.sh`, uploads artifact.
  - `release`: needs `[build-static, build-dynamic]`, downloads artifacts, creates SHA256SUMS, creates GitHub Release.

- [ ] **Step 2: Implement static build job**

Use `actions/checkout`, install deps, run `scripts/build-static.sh` with `IPERF_VERSION=${{ inputs.version }}`, upload `iperf3-*-static.tar.gz` as artifact.

- [ ] **Step 3: Implement dynamic build job**

Use `runs-on: ubuntu-20.04`, install deps, run `scripts/build-dynamic.sh` with `IPERF_VERSION=${{ inputs.version }}`, upload `iperf3-*-dynamic.tar.gz` as artifact.

- [ ] **Step 4: Implement release job**

- Download both artifacts.
- Run `sha256sum iperf3-*.tar.gz > SHA256SUMS`.
- Fetch upstream release notes via GitHub API: `gh api repos/esnet/iperf/releases/tags/${{ inputs.version }}`.
- Determine `prerelease` flag from upstream response.
- Create release:
  ```bash
  gh release create ${{ inputs.version }} \
    --title "iperf3 ${{ inputs.version }} builds" \
    --notes "$RELEASE_NOTES" \
    $(if [ "$PRERELEASE" = "true" ]; then echo "--prerelease"; fi) \
    iperf3-*.tar.gz SHA256SUMS
  ```
- If either build job fails, the release job does not run.

- [ ] **Step 5: Validate the workflow syntax**

Run:
```bash
cd /root/projects/iperf3-binares
gh workflow list
```

Expected: both `release-watcher` and `build-release` appear without syntax errors.

- [ ] **Step 6: Commit the workflow**

Run:
```bash
git add .github/workflows/build-release.yml
git commit -m "ci: add build and release workflow"
```

---

### Task 6: Add project README and metadata

**Files:**
- Create: `README.md`
- Create: `.gitignore`

**Interfaces:**
- Produces: human-readable documentation and ignored build artifacts.

- [ ] **Step 1: Write `README.md`**

Contents must include:
- Purpose of the repository.
- Where to download releases (GitHub Releases page).
- Difference between static and dynamic builds.
- Usage example: `tar -xzf iperf3-...-static.tar.gz && ./iperf3-.../iperf3 --version`.
- How often releases are checked.
- Manual trigger instructions for maintainers.

- [ ] **Step 2: Add `.gitignore`**

Ignore local build artifacts:
```
*.tar.gz
iperf3-*/
iperf/
```

- [ ] **Step 3: Commit metadata**

Run:
```bash
git add README.md .gitignore
git commit -m "docs: add README and .gitignore"
```

---

### Task 7: Push everything and trigger a test release

**Files:**
- Modify: remote `main` branch.

**Interfaces:**
- Produces: pushed commits and a triggered GitHub Actions workflow run.

- [ ] **Step 1: Push all commits to `main`**

Run:
```bash
cd /root/projects/iperf3-binares
git push origin main
```

Expected: push succeeds.

- [ ] **Step 2: Trigger the watcher manually or run the build workflow for the latest upstream release**

Run:
```bash
LATEST=$(gh api repos/esnet/iperf/releases/latest --jq '.tag_name')
gh workflow run build-release.yml --repo rusnino/iperf3-builds -f version="$LATEST"
```

Expected: workflow run starts; URL is printed.

- [ ] **Step 3: Verify the workflow run succeeds and a release is published**

Wait for the workflow to complete, then run:
```bash
gh release view "$LATEST" --repo rusnino/iperf3-builds
```

Expected: release exists, contains both `.tar.gz` files and `SHA256SUMS`, release notes match upstream.

- [ ] **Step 4: Verify binaries run without dynamic library errors**

Download and test:
```bash
gh release download "$LATEST" --repo rusnino/iperf3-builds -p '*-static.tar.gz'
tar -xzf iperf3-*-static.tar.gz
./iperf3-*/iperf3 --version
```

Expected: `iperf3 --version` prints version.

Repeat for dynamic build if a CentOS Stream 8/guestshell environment is available, or note that dynamic binary was built on `ubuntu-20.04`.

---

## Self-Review Checklist

- [ ] **Spec coverage:** Every goal in the design doc maps to a task: watcher (Task 4), static build (Task 2), dynamic build (Task 3), release creation (Task 5), README (Task 6), end-to-end verification (Task 7).
- [ ] **Step scan:** Each step asks the implementer to write or run exactly one thing. No vague steps.
- [ ] **Type consistency:** Environment variable is consistently called `IPERF_VERSION` in build scripts; workflow input is consistently called `version`.
- [ ] **Review focus coverage:** Backfill, pre-release, static portability, dynamic compatibility, partial failure, release notes — each maps to a verification step.
- [ ] **Proportion:** Plan describes files and interfaces; it does not contain full shell or YAML bodies.
