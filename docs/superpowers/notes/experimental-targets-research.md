# Experimental target research notes

This file records feasibility findings for candidate Linux static targets before they are promoted to stable.

## Method

1. Check whether Zig has a Linux/musl target triple (`zig targets`).
2. Build a tiny static `hello.c` with `zig cc -target <triple> -static`.
3. Inspect the resulting ELF with `readelf -h`.
4. Run the binary under the matching `qemu-*-static` user-mode emulator.
5. Check whether OpenSSL has a matching `Configure` target (`perl Configure LIST`).

## Zig 0.17.0 / OpenSSL 3.6.5 findings

| Target | Zig triple | ELF machine | ELF class | ELF endian | QEMU binary | OpenSSL Configure target | Auth support | Notes |
|---|---|---|---|---|---|---|---|---|
| `ppc64` | `powerpc64-linux-musl` | PowerPC64 | ELF64 | big | `qemu-ppc64-static` | `linux-ppc64` | yes | First queue. |
| `riscv32` | `riscv32-linux-musl` | RISC-V | ELF32 | little | `qemu-riscv32-static` | `linux32-riscv32` | yes | First queue. |
| `armeb` | `armeb-linux-musleabi` | ARM | ELF32 | big | `qemu-armeb-static` | none found | no | First queue. Plain-only until an OpenSSL big-endian ARM target is identified. |
| `mipsn32` | `mips64-linux-muslabin32` | MIPS R3000 | ELF32 | big | `qemu-mipsn32-static` | none found | no | First queue. Plain-only; OpenSSL has no n32 ABI target. |
| `mipsn32el` | `mips64el-linux-muslabin32` | MIPS R3000 | ELF32 | little | `qemu-mipsn32el-static` | none found | no | First queue. Plain-only. |
| `aarch64_be` | `aarch64_be-linux-musl` | AArch64 | ELF64 | big | `qemu-aarch64_be-static` | none found | no | Third queue. Plain-only. |
| `hexagon` | `hexagon-linux-musl` | QUALCOMM DSP6 Processor | ELF32 | little | `qemu-hexagon-static` | none found | no | Third queue. Plain-only. |
| `m68k` | `m68k-linux-musl` | — | — | — | `qemu-m68k-static` | none found | no | Zig 0.17.0 cannot instantiate this triple (`No available targets are compatible`), so skipped. |
| `loongarch32` | `loongarch32-linux-gnu` only | — | — | — | — | — | no | No musl target in Zig 0.17.0. |
| `riscv32be` | `riscv32be` arch only | — | — | — | — | — | no | No Linux/musl libc target. |

## Candidates dropped for this phase

- `m68k`: Zig 0.17.0 reports the triple as unsupported at compile time.
- `loongarch32`: No musl target.
- `riscv32be`: No Linux/musl target.
- `sparc`, `sparc64`, `alpha`, `hppa`, `hppa64`, `arc`, `csky`, `microblaze`, `or1k`, `sh4`, `xtensa`: Either no Linux/musl target in Zig 0.17.0 or no OpenSSL target; kept as future research only.

## Local validation results (iperf3 3.22, Zig 0.17.0, OpenSSL 3.6.5)

Builds run locally with `ARCH=<arch> IPERF_VERSION=3.22 ./scripts/build-static.sh`. Smoke tests run under the matching `qemu-*-static` user-mode emulator (`iperf3 --version`).

| Target | Plain build | Auth build | ELF verification | QEMU smoke test | Notes |
|---|---|---|---|---|---|
| `ppc64` | pass | pass | pass | pass | `authentication` feature listed in `--version` for `-auth` archive. |
| `riscv32` | pass | pass | pass | pass | `authentication` feature listed in `--version` for `-auth` archive. |
| `armeb` | pass | n/a (auth disabled) | pass | pass | Plain-only due to missing OpenSSL big-endian ARM target. |
| `mipsn32` | pass | n/a (auth disabled) | pass | pass | Plain-only due to missing OpenSSL n32 target. |
| `mipsn32el` | pass | n/a (auth disabled) | pass | pass | Plain-only due to missing OpenSSL n32 target. |
| `aarch64_be` | pass | n/a (auth disabled) | pass | pass | Plain-only due to missing OpenSSL big-endian AArch64 target. |
| `hexagon` | pass | n/a (auth disabled) | pass | pass | Plain-only due to missing OpenSSL Hexagon target. |

The GitHub Actions `experimental-builds.yml` workflow has not yet been triggered; it should be run for the next upstream release to confirm runner-side results match these local results.

## Next steps

- Trigger `experimental-builds.yml` for the next iperf3 release to confirm runner results.
- If runner results match local results for two consecutive releases, promote `ppc64` and `riscv32` to `stable: true`.
- Re-evaluate `armeb`, `mipsn32`, `mipsn32el`, `aarch64_be`, and `hexagon` for auth support when a suitable OpenSSL Configure target is identified.
