# RISC-V C Toolchain Setup

This project needs a C compiler that produces RV32I code AND ships
**newlib-nano** built for the `rv32i/ilp32` multilib. No pre-packaged
toolchain on Ubuntu 24.04 or in common IDE bundles satisfies both
constraints, so we build one from source.

Scope: only the `make c` target requires this toolchain. `make asm`
continues to use the system `riscv64-unknown-elf-gcc` from the Ubuntu
`gcc-riscv64-unknown-elf` package — assembly programs don't need libc.

## Canonical build

Tested on Ubuntu 24.04 (Intel B660 / DDR4 desktop). Wall-clock 7m 40s
(2026-04-21 build); disk cost 2.2 GB at the install prefix.

Prereqs (one-time):

```bash
sudo apt-get install -y autoconf automake autotools-dev curl python3 \
    python3-pip libmpc-dev libmpfr-dev libgmp-dev gawk build-essential \
    bison flex texinfo gperf libtool patchutils bc zlib1g-dev libexpat-dev \
    ninja-build git cmake libglib2.0-dev libslirp-dev
```

Clone, configure, build:

```bash
git clone https://github.com/riscv-collab/riscv-gnu-toolchain /tmp/riscv-gnu-toolchain
cd /tmp/riscv-gnu-toolchain

# --with-arch=rv32i --with-abi=ilp32 bakes the default multilib; nothing
# else in this project uses other variants, and pinning here avoids the
# disk/time cost of building every multilib combination.
./configure \
    --prefix=/opt/riscv \
    --with-arch=rv32i \
    --with-abi=ilp32 \
    --disable-linux \
    --disable-gdb

# First the full newlib, then the nano variant that layers on top.
# Both variants (regular + nano) are needed — the Makefile passes
# -specs=nano.specs, which expects lib{c,g,m,gloss}_nano.a alongside
# the regular libs. Current riscv-gnu-toolchain (post-2024) builds both
# from the single `make newlib` target; if your clone is older, also
# run `make newlib-nano`.
make newlib -j$(nproc)
```

If `sudo` isn't available, use `--prefix=$HOME/riscv` and drop any
`sudo` wrapper. The Makefile's discovery chain checks `/opt/riscv`
first and `$HOME/riscv` second, so either location works without
further configuration.

## Verification

After the build completes:

```bash
/opt/riscv/bin/riscv32-unknown-elf-gcc --version
/opt/riscv/bin/riscv32-unknown-elf-gcc -print-file-name=nano.specs
# Must print an absolute path ending in nano.specs, not the literal string.

ls /opt/riscv/riscv32-unknown-elf/lib/libc_nano.a
ls /opt/riscv/riscv32-unknown-elf/lib/libgloss_nano.a
# Both files must exist.
```

`make c PROG=hello_c` from the repo root should now succeed and emit a
section-size table showing `.text` well under 16 KB.

## Makefile discovery chain

The Makefile resolves the toolchain at parse time:

```
/opt/riscv/bin/riscv32-unknown-elf-gcc         (system-wide install)
$HOME/riscv/bin/riscv32-unknown-elf-gcc        (per-user install)
riscv32-unknown-elf-gcc on PATH                (any other location)
```

Override by passing `RISCV_GCC=/path/to/riscv32-unknown-elf-gcc` to
`make`. If none resolve, `make c` prints an actionable error and exits
nonzero — it does NOT silently fall back to a different toolchain.

## Why not X

We surveyed these before building from source:

- **Ubuntu `gcc-riscv64-unknown-elf` (version 13.2.0 on 24.04).**
  Ships GCC and binutils but NO newlib. `-print-file-name=nano.specs`
  returns the literal string `nano.specs`, which means gcc couldn't
  resolve it — i.e., the specs file isn't installed. There is no
  `libnewlib-*-riscv64-unknown-elf` package in the Ubuntu archive.
  Fine for `make asm` (pure assembly, no libc), unusable for `make c`.

- **Vivado 2025.2 bundled toolchain**
  (`/home/otacon/Vivado/2025.2/gnu/riscv/lin/bin/`). Has `nano.specs`
  present as a file for `rv32i/ilp32`, but the `lib{c,gloss}_nano.a`
  libraries it references were only built for the `rv32imac/ilp32`
  and `rv32imafc_zicsr/ilp32f` multilibs. For our target
  (`rv32i/ilp32`), linking with `-specs=nano.specs` fails with
  `cannot find -lc_nano`. Verified by `find` — no `libc_nano.a` for
  any rv32i-plain variant exists anywhere in the Vivado install.

- **Prebuilt tarballs (Embecosm, xPack riscv-none-elf-gcc).** Viable,
  and often ship a fuller multilib set. We opted to build from source
  for one-line reproducibility and to pin against a known commit of
  riscv-gnu-toolchain. If a future CI needs a faster bootstrap, a
  prebuilt tarball cached by the actions cache is the path.

## Disk and time cost

Observed on this machine (2026-04-21, Intel B660 / DDR4 desktop,
Ubuntu 24.04, `--depth 1` clone):

- Wall-clock: **7m 40s** for `make newlib -j$(nproc)`.
- Disk at `$HOME/riscv` after install: **2.2 GB**.

Expect 20-60 min on slower or CI-class hardware and a similar disk
footprint.
