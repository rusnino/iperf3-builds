# Migrate stable Linux static builds to zig cc + OpenSSL from source

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `userdocs/qbt-musl-cross-make` toolchains and `userdocs/openssl` prebuilt assets with `zig cc` and OpenSSL built from source, while preserving all 15 existing stable Linux static targets and their `-auth` variants.

**Architecture:** A single `zig cc` compiler handles every cross target; a machine-readable catalog (`targets.json`) defines the zig target triple and OpenSSL Configure target for each public ARCH name. `scripts/build-static.sh` reads the catalog, installs zig, builds OpenSSL from source when auth is requested, then builds and smoke-tests iperf3. The workflow matrix is generated from the catalog.

**Tech Stack:** zig 0.14.1 official release, OpenSSL source tarball, autotools, QEMU user-mode for non-x86 smoke tests.

**Spec:** docs/superpowers/specs/2026-10-17-iperf3-builds-platform-coverage.md

## Global Constraints

- Free GitHub Actions runners only.
- Preserve existing archive naming: `iperf3-<version>-linux-<arch>-static[-auth].tar.gz`.
- Preserve existing 15 stable Linux static target names: `x86_64`, `x86`, `aarch64`, `arm`, `armhf`, `armv7`, `mips`, `mipsel`, `mips64`, `mips64el`, `powerpc`, `ppc64le`, `s390x`, `riscv64`, `loongarch64`.
- Keep Linux x86_64 dynamic/dynamic-auth and macOS universal2 pipelines unchanged.
- Smoke-test every cross build; native x86_64/x86 run without QEMU.
- No reliance on `userdocs` release assets for Linux static builds.
- The workflow must not run the release job if any stable build fails.

## Review Focus

1. **Wrong target mapping:** a typo in the catalog causes a binary built for a different architecture. Caught by explicit ELF machine/endianness/ABI checks and QEMU smoke test.
2. **OpenSSL Configure mismatch:** OpenSSL refuses to build or produces wrong code for an architecture. Caught by successful static link and `--version` reporting `authentication` on auth builds.
3. **Dynamic leakage:** iperf3 links dynamically against glibc or OpenSSL. Caught by `readelf` checks for `PT_INTERP` and `DT_NEEDED`.
4. **QEMU smoke test false confidence:** native x86 builds must not silently cross to x86_64. Caught by ELF machine check.
5. **Workflow matrix drift:** the matrix and the catalog get out of sync. Caught by generating the matrix from the catalog file.

---

## File structure

- `targets.json` — public ARCH → zig target triple, OpenSSL Configure target, QEMU binary, auth support, notes.
- `scripts/build-static.sh` — install zig, read catalog, build OpenSSL (auth), build iperf3, verify ELF, smoke test, package.
- `.github/workflows/build-release.yml` — matrix generated from `targets.json`, install zig step.
- `scripts/verify-elf.sh` — helper to assert ELF machine/class/endian/static linkage.
- `README.md` — updated table of stable targets.

---

### Task 1: Create stable targets catalog

**Files:**
- Create: `targets.json`

**Interfaces:**
- Produces: `targets.json` with top-level `arch` key mapping public ARCH name to an object containing `zig_target`, `openssl_target`, `qemu`, `auth`, `notes`.

- [ ] **Step 1: Draft catalog for all 15 stable targets**

```json
{
  "arch": {
    "x86_64": {
      "zig_target": "x86_64-linux-musl",
      "openssl_target": "linux-x86_64",
      "qemu": null,
      "auth": true,
      "cpu": "x86-64",
      "abi": "sysv",
      "endianness": "little",
      "notes": "Native 64-bit x86; runs without QEMU"
    },
    "x86": {
      "zig_target": "x86-linux-musl",
      "openssl_target": "linux-elf",
      "qemu": null,
      "auth": true,
      "cpu": "i686",
      "abi": "sysv",
      "endianness": "little",
      "notes": "32-bit x86; runs natively on x86_64 hosts"
    },
    "aarch64": {
      "zig_target": "aarch64-linux-musl",
      "openssl_target": "linux-aarch64",
      "qemu": "qemu-aarch64-static",
      "auth": true,
      "cpu": "aarch64",
      "abi": "sysv",
      "endianness": "little",
      "notes": "ARM64"
    },
    "arm": {
      "zig_target": "arm-linux-musleabi",
      "openssl_target": "linux-arm",
      "qemu": "qemu-arm-static",
      "auth": true,
      "cpu": "armv5",
      "abi": "eabi",
      "endianness": "little",
      "notes": "ARMv5 soft-float"
    },
    "armhf": {
      "zig_target": "arm-linux-musleabihf",
      "openssl_target": "linux-armv4",
      "qemu": "qemu-arm-static",
      "auth": true,
      "cpu": "armv6",
      "abi": "eabihf",
      "endianness": "little",
      "notes": "ARMv6 hard-float"
    },
    "armv7": {
      "zig_target": "arm-linux-musleabihf",
      "openssl_target": "linux-armv4",
      "qemu": "qemu-arm-static",
      "auth": true,
      "cpu": "armv7",
      "abi": "eabihf",
      "endianness": "little",
      "notes": "ARMv7 hard-float (same ABI as armhf, baseline tuned for v7)"
    },
    "mips": {
      "zig_target": "mips-linux-musl",
      "openssl_target": "linux-mips",
      "qemu": "qemu-mips-static",
      "auth": true,
      "cpu": "mips",
      "abi": "o32",
      "endianness": "big",
      "notes": "MIPS 32-bit big-endian o32"
    },
    "mipsel": {
      "zig_target": "mipsel-linux-musl",
      "openssl_target": "linux-mips",
      "qemu": "qemu-mipsel-static",
      "auth": true,
      "cpu": "mips",
      "abi": "o32",
      "endianness": "little",
      "notes": "MIPS 32-bit little-endian o32"
    },
    "mips64": {
      "zig_target": "mips64-linux-musl",
      "openssl_target": "linux-mips64",
      "qemu": "qemu-mips64-static",
      "auth": true,
      "cpu": "mips64",
      "abi": "n64",
      "endianness": "big",
      "notes": "MIPS 64-bit big-endian n64"
    },
    "mips64el": {
      "zig_target": "mips64el-linux-musl",
      "openssl_target": "linux-mips64",
      "qemu": "qemu-mips64el-static",
      "auth": true,
      "cpu": "mips64",
      "abi": "n64",
      "endianness": "little",
      "notes": "MIPS 64-bit little-endian n64"
    },
    "powerpc": {
      "zig_target": "powerpc-linux-musl",
      "openssl_target": "linux-ppc",
      "qemu": "qemu-ppc-static",
      "auth": true,
      "cpu": "powerpc",
      "abi": "sysv",
      "endianness": "big",
      "notes": "32-bit PowerPC"
    },
    "ppc64le": {
      "zig_target": "powerpc64le-linux-musl",
      "openssl_target": "linux-ppc64le",
      "qemu": "qemu-ppc64le-static",
      "auth": true,
      "cpu": "powerpc64",
      "abi": "elfv2",
      "endianness": "little",
      "notes": "64-bit little-endian PowerPC"
    },
    "s390x": {
      "zig_target": "s390x-linux-musl",
      "openssl_target": "linux64-s390x",
      "qemu": "qemu-s390x-static",
      "auth": true,
      "cpu": "s390x",
      "abi": "sysv",
      "endianness": "big",
      "notes": "IBM Z / s390x"
    },
    "riscv64": {
      "zig_target": "riscv64-linux-musl",
      "openssl_target": "linux-riscv64",
      "qemu": "qemu-riscv64-static",
      "auth": true,
      "cpu": "riscv64",
      "abi": "lp64",
      "endianness": "little",
      "notes": "RISC-V 64-bit"
    },
    "loongarch64": {
      "zig_target": "loongarch64-linux-musl",
      "openssl_target": "linux-loongarch64",
      "qemu": "qemu-loongarch64-static",
      "auth": true,
      "cpu": "loongarch64",
      "abi": "sysv",
      "endianness": "little",
      "notes": "LoongArch 64-bit"
    }
  }
}
```

- [ ] **Step 2: Validate JSON syntax**

Run: `python3 -m json.tool targets.json > /dev/null`
Expected: no output, exit 0.

- [ ] **Step 3: Commit**

```bash
git add targets.json
git commit -m "chore: add stable Linux static targets catalog"
```

---

### Task 2: ELF verification helper

**Files:**
- Create: `scripts/verify-elf.sh`

**Interfaces:**
- Consumes: binary path, target metadata (machine, class, endianness) from catalog.
- Produces: exit 0 on success, stderr diagnostics and exit 1 on failure.

- [ ] **Step 1: Implement helper**

`scripts/verify-elf.sh` reads machine/class/endianness from `readelf -h`, ensures no `PT_INTERP` and no `DT_NEEDED` from `readelf -l`/`-d`.

- [ ] **Step 2: Test helper against known-good aarch64 binary**

Run: `ARCH=aarch64 ./scripts/build-static.sh` from previous userdocs-based build to produce a binary, then `scripts/verify-elf.sh iperf3-build-static-aarch64/iperf-3.22/src/iperf3 aarch64`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add scripts/verify-elf.sh
git commit -m "feat: add ELF verification helper"
```

---

### Task 3: Refactor build-static.sh to use zig cc

**Files:**
- Modify: `scripts/build-static.sh`

**Interfaces:**
- Consumes: `targets.json`, environment variables `IPERF_VERSION`, `ARCH`, `AUTH`.
- Produces: archive `iperf3-${VERSION}-linux-${ARCH}-static${AUTH_SUFFIX}.tar.gz`.

- [ ] **Step 1: Add zig installation**

Download zig 0.14.1 x86_64-linux tarball, verify sha256, extract to a temp dir, add to PATH.

- [ ] **Step 2: Read target metadata from catalog**

Use `python3 -c 'import json; ...'` or `jq` to extract `zig_target`, `openssl_target`, `qemu`, etc.

- [ ] **Step 3: Create zig cc wrapper script**

Write a wrapper `/tmp/zig-cc-$ARCH` that executes `zig cc -target <zig_target> "$@"`. Set `CC` to this wrapper.

- [ ] **Step 4: Build non-auth iperf3**

Configure with `--host=<zig_target> --disable-shared --enable-static-bin --without-openssl`, build, verify static linkage.

- [ ] **Step 5: Smoke test non-auth**

Run native or under QEMU with `--version`.

- [ ] **Step 6: Build auth variant (when AUTH=true)**

Download OpenSSL source (stable 3.x LTS), configure with `CC=<wrapper> ./Configure <openssl_target> no-shared no-zlib ...`, install to a prefix, then build iperf3 `--with-openssl=<prefix>`.

- [ ] **Step 7: Verify auth binary**

Check static linkage and that `--version` includes `authentication`.

- [ ] **Step 8: Package and commit**

```bash
git add scripts/build-static.sh
git commit -m "feat: migrate build-static.sh to zig cc and OpenSSL from source"
```

---

### Task 4: Update GitHub Actions workflow

**Files:**
- Modify: `.github/workflows/build-release.yml`

**Interfaces:**
- Consumes: `targets.json`.
- Produces: matrix `arch` populated from catalog.

- [ ] **Step 1: Generate matrix in workflow**

Use a step that runs `python3` to read `targets.json` and emit JSON matrix. Keep auth dimension `[false, true]` but skip `true` where catalog `auth` is false.

- [ ] **Step 2: Remove toolchain download step**

The script now installs zig itself; no `qbt-musl-cross-make` download.

- [ ] **Step 3: Validate workflow YAML**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/build-release.yml'))"`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/build-release.yml
git commit -m "ci: generate Linux static matrix from targets.json and use zig cc"
```

---

### Task 5: Local verification of all 15 stable targets

**Files:**
- Modify: ledger/progress if using executing-plans.

**Interfaces:**
- Consumes: updated `scripts/build-static.sh`.
- Produces: 30 archives (15 plain + 15 auth) and verification logs.

- [ ] **Step 1: Run non-auth builds for all 15 arches**

Loop over `x86_64 x86 aarch64 arm armhf armv7 mips mipsel mips64 mips64el powerpc ppc64le s390x riscv64 loongarch64`.
For each: `ARCH=$arch IPERF_VERSION=3.22 ./scripts/build-static.sh`.
Expected: each builds, ELF verification passes, smoke test passes.

- [ ] **Step 2: Run auth builds for a representative subset**

At minimum: `x86_64`, `aarch64`, `armv7`, `mips64el`, `powerpc`, `s390x`, `riscv64`, `loongarch64`.
Expected: each builds, `--version` reports `authentication`, ELF static.

- [ ] **Step 3: Document any failures**

If a target fails, note whether it is plain, auth, or both, and the error. Decide with human partner whether to disable auth for that target or fix.

---

### Task 6: Update README and documentation

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/notes/iperf3-builds-future-enhancements.md`

**Interfaces:**
- Consumes: `targets.json`.
- Produces: user-facing table of stable targets and updated backlog.

- [ ] **Step 1: Replace old variants table**

Add a single table with columns: Target, ISA/CPU baseline, ABI, Endianness, FPU, Auth, Testing, Limitations.

- [ ] **Step 2: Note toolchain/source provenance**

Mention that builds use official `zig cc` and OpenSSL source, not third-party prebuilt toolchains.

- [ ] **Step 3: Update future enhancements**

Mark Linux static toolchain migration as done; list Phase 2 expansion candidates.

- [ ] **Step 4: Commit**

```bash
git add README.md docs/superpowers/notes/iperf3-builds-future-enhancements.md
git commit -m "docs: document zig cc based stable targets and provenance"
```

---

## Self-review checklist

- [x] Spec coverage: migration to zig cc, catalog, OpenSSL source, ELF checks, workflow matrix, docs are all represented.
- [ ] Step scan: each step is one actionable item with a checkable result.
- [ ] Type consistency: JSON field names match between catalog, script, workflow.
- [ ] Review Focus: each risk has a verification step in Task 3 or Task 5.
- [ ] Proportion: plan is shorter than the spec; bodies left to implementer except exact values.
