# Experimental Linux architecture expansion (Phase 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add new Linux static targets beyond the current 15 stable ones using the same Zig + OpenSSL-from-source pipeline, validate them in an isolated experimental workflow, and promote the working ones to the stable release matrix.

**Architecture:** Extend the existing `targets.json` catalog with a `stable` boolean. The stable release workflow filters on `stable: true`; a new manually triggered `experimental-builds.yml` workflow filters on `stable: false`. Both workflows reuse `scripts/build-static.sh` and `scripts/verify-elf.sh`. Feasibility research for each candidate is recorded before any catalog entry is added, and promotion to stable requires repeated successful builds plus documented runtime testing.

**Tech Stack:** Zig 0.17.0, OpenSSL 3.x LTS, autotools, QEMU user-mode, GitHub Actions, Python 3 for matrix generation.

**Spec:** `docs/superpowers/specs/2026-10-17-iperf3-builds-platform-coverage.md` (sections 4–6, 11)

## Global Constraints

- Free GitHub Actions runners only.
- Existing 15 stable Linux targets, macOS universal2, and dynamic x86_64 pipelines must keep working unchanged.
- Experimental builds must never block the stable release workflow.
- No release assets are published from experimental builds; artifacts stay in the workflow run.
- Preserve archive naming: `iperf3-<version>-linux-<arch>-static[-auth].tar.gz`.
- Maintain a single `targets.json` catalog as the source of truth; do not duplicate architecture lists in scripts or workflows.
- Auth variants are built only when the catalog explicitly marks `auth: true` and the OpenSSL Configure target exists.

## Review Focus

1. **Blocking the stable release:** if experimental matrix is included in the release job, a broken experimental target can prevent stable releases. Caught by filtering `stable: true` in `build-release.yml`.
2. **Wrong target triple:** a guessed Zig triple can silently build for the wrong ISA/endianness. Caught by documenting the source of each triple and running `verify-elf.sh` plus QEMU smoke tests.
3. **Missing OpenSSL Configure target:** OpenSSL may fail or fall back to a generic target that does not match the architecture. Caught by requiring a known Configure target and by checking ELF machine/endianness on the auth binary.
4. **QEMU silently passing the wrong binary:** `qemu-*-static` may run a host binary if binfmt is misconfigured. Caught by explicit ELF machine checks before QEMU and by verifying the binary under QEMU prints the expected architecture string.
5. **Unclear promotion status:** a target that builds once might be promoted prematurely. Caught by requiring documented passing builds across multiple releases and explicit `stable: true` flip.

---

### Task 1: Add a `stable` flag to `targets.json`

**Files:**
- Modify: `targets.json`
- Modify: `.github/workflows/build-release.yml`

**Interfaces:**
- Consumes: existing 15 stable entries.
- Produces: each entry has `stable: true`; later tasks add `stable: false` entries.

- [ ] **Step 1: Add `stable: true` to every existing arch entry**

Insert `"stable": true` as the first field in each arch object (or any consistent position).

- [ ] **Step 2: Validate JSON syntax**

Run:
```bash
python3 -m json.tool targets.json > /dev/null
```
Expected: no output, exit 0.

- [ ] **Step 3: Update release matrix generator to filter on `stable: true`**

In `.github/workflows/build-release.yml`, change the matrix generation loop in `generate-linux-static-matrix` from:
```python
for arch, meta in data['arch'].items():
    matrix['include'].append({'arch': arch, 'auth': False})
    if meta.get('auth', True):
        matrix['include'].append({'arch': arch, 'auth': True})
```
to:
```python
for arch, meta in data['arch'].items():
    if not meta.get('stable', False):
        continue
    matrix['include'].append({'arch': arch, 'auth': False})
    if meta.get('auth', True):
        matrix['include'].append({'arch': arch, 'auth': True})
```

- [ ] **Step 4: Validate workflow YAML**

Run:
```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/build-release.yml'))"
```
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add targets.json .github/workflows/build-release.yml
git commit -m "chore: tag existing targets as stable and filter release matrix"
```

---

### Task 2: Research first-queue experimental targets

**Files:**
- Create: `docs/superpowers/notes/experimental-targets-research.md`
- Modify: `targets.json`

**Interfaces:**
- Consumes: candidate list from the spec (first queue: `armeb`, `ppc64`, `riscv32`, MIPS n32 BE/LE).
- Produces: catalog entries with `stable: false` for targets that have a known-good Zig triple, QEMU binary, and OpenSSL Configure target.

- [ ] **Step 1: Determine Zig target triples for each candidate**

Use `zig targets` and the Zig documentation to find the exact `zig cc -target` triples. Record the source URL or command output for each.

Known starting points:
- `ppc64` big-endian: `powerpc64-linux-musl`
- `riscv32`: `riscv32-linux-musl`
- `armeb`: `armeb-linux-musleabi` (to be confirmed)
- MIPS n32 BE: `mips-linux-musln32` (to be confirmed)
- MIPS n32 LE: `mipsel-linux-musln32` (to be confirmed)

- [ ] **Step 2: Determine OpenSSL Configure targets**

Look up the OpenSSL 3.x `Configure` target list. Record:
- `ppc64`: `linux-ppc64`
- `riscv32`: candidate `linux-riscv32` or fallback `linux-generic32`
- `armeb`: candidate `linux-armv4` with big-endian flags, or a specific `linux-armeb` target
- MIPS n32: candidate `linux-mips32` with ABI flag, or `linux-generic32`

If no suitable target exists, mark the target as `auth: false` or omit it until OpenSSL support is found.

- [ ] **Step 3: Determine QEMU user-mode binaries**

Check `qemu-ppc64-static`, `qemu-riscv32-static`, `qemu-armeb-static` (if available), `qemu-mipsn32-static`, `qemu-mipseln32-static`. If QEMU does not support a target, record `qemu: null` and set the testing level to `build-only`.

- [ ] **Step 4: Add feasible targets to `targets.json` with `stable: false`**

Example structure for a new entry:
```json
"ppc64": {
  "stable": false,
  "zig_target": "powerpc64-linux-musl",
  "openssl_target": "linux-ppc64",
  "qemu": "qemu-ppc64-static",
  "auth": true,
  "cpu": "powerpc64",
  "abi": "elfv1",
  "endianness": "big",
  "notes": "64-bit big-endian PowerPC (experimental)",
  "elf_machine": "PowerPC64",
  "elf_class": "ELF64",
  "elf_data": "2's complement, big endian"
}
```

- [ ] **Step 5: Validate JSON and commit**

```bash
python3 -m json.tool targets.json > /dev/null
git add targets.json docs/superpowers/notes/experimental-targets-research.md
git commit -m "chore: add first-queue experimental targets to catalog"
```

---

### Task 3: Create an experimental-build workflow

**Files:**
- Create: `.github/workflows/experimental-builds.yml`

**Interfaces:**
- Consumes: `targets.json` entries where `stable: false`.
- Produces: workflow artifacts named `experimental-linux-<arch>-static[-auth].tar.gz`; no release assets.

- [ ] **Step 1: Scaffold the workflow**

Create `.github/workflows/experimental-builds.yml` with:
- Trigger: `workflow_dispatch` with `version` input.
- Permission: `contents: read` only.
- A `generate-experimental-matrix` job that emits a matrix of `{arch, auth}` for all `stable: false` entries.
- An `build-experimental` job that reuses `scripts/build-static.sh` exactly like `build-linux-static`.

- [ ] **Step 2: Upload artifacts with an experimental prefix**

Use artifact names like `experimental-linux-${{ matrix.arch }}-static${{ matrix.auth && '-auth' || '' }}` so they cannot be confused with release artifacts.

- [ ] **Step 3: Validate YAML**

Run:
```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/experimental-builds.yml'))"
```
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/experimental-builds.yml
git commit -m "ci: add manually triggered experimental architecture workflow"
```

---

### Task 4: Validate first-queue experimental builds

**Files:**
- Modify: `docs/superpowers/notes/experimental-targets-research.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: `experimental-builds.yml` run output.
- Produces: documented results and a README table of experimental targets.

- [ ] **Step 1: Trigger the experimental workflow for a known iperf version**

Run:
```bash
gh workflow run experimental-builds.yml --repo rusnino/iperf3-builds -f version=3.22
```

- [ ] **Step 2: For each target, record build, ELF, and smoke-test results**

Record in `docs/superpowers/notes/experimental-targets-research.md`:
- plain build status;
- auth build status (if attempted);
- ELF machine/class/endian/static check result;
- QEMU smoke-test result (`--version`);
- failure logs or error category.

- [ ] **Step 3: Disable or adjust unsupported combinations**

If a target fails for a structural reason (e.g., no OpenSSL Configure target, no Zig triple), either:
- set `auth: false` and keep the plain build;
- remove it from `targets.json` and document why; or
- mark it `build_only: true` in the catalog and skip smoke tests.

Do not keep a target in the matrix if every build fails.

- [ ] **Step 4: Update README with an experimental targets table**

Add a section after the stable compatibility table:

| Target | Status | Auth | Known to work on | Known issues |
|---|---|---|---|---|
| `ppc64` | experimental | yes/no | QEMU powerpc64 | ... |

- [ ] **Step 5: Commit research notes and README changes**

```bash
git add docs/superpowers/notes/experimental-targets-research.md README.md targets.json
git commit -m "docs: record first-queue experimental build results"
```

---

### Task 5: Define promotion criteria and process

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/notes/iperf3-builds-future-enhancements.md`

**Interfaces:**
- Consumes: documented experimental results.
- Produces: clear rules for moving a target from `stable: false` to `stable: true`.

- [ ] **Step 1: Document promotion criteria**

A target may be promoted when:
1. Plain and auth builds pass for at least two consecutive upstream releases.
2. ELF verification passes for both variants.
3. QEMU smoke tests pass for both variants (`--version` and optionally server/client loopback).
4. The README table is updated with testing details.
5. There are no open known issues that affect correctness.

- [ ] **Step 2: Document the promotion action**

The promotion is a single change: flip `"stable": false` to `"stable": true` in `targets.json`, update the README status from "experimental" to "stable", and run a full release build to confirm the stable matrix still works.

- [ ] **Step 3: Update future enhancements**

In `docs/superpowers/notes/iperf3-builds-future-enhancements.md`, add an item:
- [ ] Promote validated experimental targets to stable and repeat for second/third queues.

- [ ] **Step 4: Commit**

```bash
git add README.md docs/superpowers/notes/iperf3-builds-future-enhancements.md
git commit -m "docs: document experimental target promotion criteria"
```

---

### Task 6: Research second- and third-queue candidates

**Files:**
- Modify: `docs/superpowers/notes/experimental-targets-research.md`
- Modify: `targets.json`

**Interfaces:**
- Consumes: candidate list from the spec (second queue: ARC, SuperH, MicroBlaze, OpenRISC, m68k, C-SKY, Xtensa; third queue: `aarch64_be`, `sparc`, `sparc64`, `alpha`, `hppa`, `parisc`, `x32`, `hexagon`, `powerpcspe`).
- Produces: additional `stable: false` entries only for targets with a viable Zig triple and QEMU or documented build-only status.

- [ ] **Step 1: Check Zig support for each second-queue family**

Use `zig targets` output. Many of these are not in Zig's target list; record which are unsupported.

- [ ] **Step 2: Check QEMU support**

Identify QEMU user-mode binaries: `qemu-sh4-static`, `qemu-m68k-static`, etc. Targets without QEMU support are `build-only`.

- [ ] **Step 3: Add feasible entries to `targets.json`**

Add only candidates that have a known Zig triple and a known OpenSSL Configure target or a documented fallback. Example:
```json
"aarch64_be": {
  "stable": false,
  "zig_target": "aarch64_be-linux-musl",
  "openssl_target": "linux-aarch64",
  "qemu": null,
  "auth": false,
  "cpu": "aarch64",
  "abi": "sysv",
  "endianness": "big",
  "notes": "ARM64 big-endian (experimental, build-only until QEMU support is confirmed)",
  "elf_machine": "AArch64",
  "elf_class": "ELF64",
  "elf_data": "2's complement, big endian"
}
```

- [ ] **Step 4: Commit**

```bash
git add targets.json docs/superpowers/notes/experimental-targets-research.md
git commit -m "chore: add second/third-queue experimental targets (research phase)"
```

---

## Self-review checklist

- [ ] Spec coverage: first-queue candidates, experimental workflow, promotion criteria, second/third queues are represented.
- [ ] Step scan: each step is one concrete action with a checkable result.
- [ ] Type consistency: `stable` boolean and catalog field names match the existing `targets.json` schema.
- [ ] Review Focus: stable release is protected by `stable: true` filter; target correctness is protected by research notes + ELF + QEMU; OpenSSL issue handled by requiring Configure target; promotion is gated by documented criteria.
- [ ] Proportion: plan is shorter than the spec; unknown triples are left as research steps rather than guessed values.
