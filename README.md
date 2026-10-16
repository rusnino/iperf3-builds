# iperf3-builds

Automated builds of [esnet/iperf](https://github.com/esnet/iperf) for Linux x86_64.

This repository watches the upstream iperf3 project for new releases and
automatically compiles ready-to-use binaries. You do not need to install
build tools on your target system — just download a release archive and run
`iperf3`.

## Downloads

Pre-built binaries are published on the
[GitHub Releases](https://github.com/rusnino/iperf3-builds/releases) page.

Each upstream release produces two assets:

- **`iperf3-<version>-linux-x86_64-static.tar.gz`** — statically linked with
  [musl](https://musl.libc.org/). Use this if you want a single executable that
  runs on almost any Linux x86_64 system without extra libraries.
- **`iperf3-<version>-linux-x86_64-dynamic.tar.gz`** — dynamically linked with
  glibc, built on an AlmaLinux 8 / CentOS Stream 8 compatible environment. Use
  this if you prefer a glibc build and your target has glibc 2.28 or newer.

A `SHA256SUMS` file is included with every release so you can verify the
archives.

## Quick start

```bash
VERSION=3.22
wget https://github.com/rusnino/iperf3-builds/releases/download/${VERSION}/iperf3-${VERSION}-linux-x86_64-static.tar.gz
tar -xzf iperf3-${VERSION}-linux-x86_64-static.tar.gz
./iperf3-${VERSION}-linux-x86_64-static/iperf3 --version
```

## Build variants

| Variant | libc | Best for | Notes |
|---|---|---|---|
| static | musl | Maximum portability | No runtime dependencies |
| dynamic | glibc 2.28 | CentOS Stream 8 / RHEL 8 / AlmaLinux 8 targets | Smaller, but needs compatible glibc |

## Automation

A GitHub Actions workflow runs daily at 04:00 UTC, checks the last 10 upstream
releases, and builds any missing ones. Maintainers can also trigger a build
manually from the **Actions → Build and Release → Run workflow** tab.

## License

The build scripts in this repository are released under the same license as
iperf3 itself (BSD 3-clause). The upstream license is included in each release
archive.
