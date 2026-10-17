# Plan: Expand iperf3-builds Linux architecture matrix

> **Status:** superseded by `2026-10-17-migrate-to-zig-cc.md` and the upcoming `2026-10-17-experimental-architectures.md`. This draft predates the Zig-based toolchain and the `targets.json` catalog; do not execute it as-is.

Spec: user request to add as many architectures as possible on free GitHub
runners, following the `userdocs` musl cross-compilation approach.

## Global constraints

- Use free GitHub Actions runners only.
- Keep existing x86_64 static/dynamic and macOS pipelines intact.
- Static musl builds for new Linux architectures; `-auth` variants for each.
- Smoke-test every cross build (native run for x86/x86_64, QEMU user-mode for
  the rest).
- Preserve asset naming: `iperf3-<version>-linux-<arch>-static[-auth].tar.gz`.

## Tasks

### Task 1: Extend `scripts/build-static.sh`
- Add architecture mapping for `x86`, `aarch64`, `arm`, `armhf`, `armv7`,
  `mips`, `mipsel`, `mips64`, `mips64el`, `powerpc`, `ppc64le`, `s390x`,
  `riscv64`, `loongarch64` using `userdocs/qbt-musl-cross-make` toolchains.
- Use `userdocs/openssl` prebuilt static OpenSSL for `-auth` builds where
  available.
- Smoke-test via QEMU user-mode for non-x86 architectures.

### Task 2: Expand GitHub Actions matrix
- Update `build-linux-static-cross` in `.github/workflows/build-release.yml`
  to include all supported architectures.
- Keep `fail-fast: false` so one failing architecture does not stop the
  others.

### Task 3: Update documentation
- Update `README.md` with the new architecture list and build-variants table.
- Update `docs/superpowers/notes/iperf3-builds-future-enhancements.md` to
  reflect completed platforms.

### Task 4: Local verification
- Run non-auth builds for every new cross architecture on a local x86_64 host.
- Run at least one `-auth` cross build to verify OpenSSL static linking.
- Confirm each produced archive and binary reports the correct architecture
  under QEMU.

### Task 5: Commit and push
- Commit changes on a feature branch.
- Push to `origin` and, if appropriate, merge after review.

## Review focus

- Correctness of architecture-to-toolchain mapping.
- QEMU binary names used in smoke tests.
- Artifact upload paths match the new matrix arch names.
- README accurately reflects supported platforms.
