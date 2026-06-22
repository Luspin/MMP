#!/bin/bash
# build.sh - cross-compile a debugging toolset for the
# SigmaStar Infinity2m / Miyoo Mini+ (SSD20x) device.
#
# Produces ARM (armhf, glibc 2.28) builds of:
#   binutils 2.32 -> readelf, objdump, nm, addr2line
#   strace 5.10
#   gdb 8.3.1     -> gdb + gdbserver
#   file 5.39     -> file + magic.mgc
#   ldd           -> shell wrapper (no build)
#
# Output is staged into ./binaries ready to scp to the device.
#
# Requires: the steward-fu cross toolchain under /opt/prebuilt,
# a host C/C++ compiler (for file's native magic compiler), wget, xz.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/src"
DL="$SRC/downloads"
STAGE="$ROOT/binaries"
JOBS="$(nproc)"

export PATH=/opt/prebuilt/bin:$PATH
HOST=arm-linux-gnueabihf
CC=$HOST-gcc
CXX=$HOST-g++

mkdir -p "$SRC" "$DL" "$STAGE"
cd "$SRC"

fetch() { [ -f "$DL/$2" ] || wget -q "$1" -O "$DL/$2"; }

# ---- binutils: readelf / objdump / nm / addr2line ----
fetch https://ftp.gnu.org/gnu/binutils/binutils-2.32.tar.xz binutils-2.32.tar.xz
[ -d binutils-2.32 ] || tar xf "$DL/binutils-2.32.tar.xz"
mkdir -p binutils-2.32/build-arm && cd binutils-2.32/build-arm
[ -f Makefile ] || ../configure --host=$HOST --target=$HOST \
    --disable-nls --disable-werror --disable-gdb --disable-readline \
    CC=$CC LDFLAGS="-s" MAKEINFO=true
make -j"$JOBS" MAKEINFO=true
cp binutils/readelf binutils/objdump binutils/addr2line "$STAGE/"
cp binutils/nm-new "$STAGE/nm"
cd "$SRC"

# ---- strace ----  (-lrt -lpthread needed for static glibc 2.28 timer_create)
fetch https://strace.io/files/5.10/strace-5.10.tar.xz strace-5.10.tar.xz
[ -d strace-5.10 ] || tar xf "$DL/strace-5.10.tar.xz"
cd strace-5.10
[ -f Makefile ] || ./configure --host=$HOST CC=$CC \
    LDFLAGS="-static -s" LIBS="-lrt -lpthread" \
    --enable-mpers=no st_cv_m32_mpers=no st_cv_mx32_mpers=no
make -j"$JOBS"
cp strace "$STAGE/"
cd "$SRC"

# ---- gdb + gdbserver ----
fetch https://ftp.gnu.org/gnu/gdb/gdb-8.3.1.tar.xz gdb-8.3.1.tar.xz
[ -d gdb-8.3.1 ] || tar xf "$DL/gdb-8.3.1.tar.xz"
# gdbserver (static)
cd gdb-8.3.1/gdb/gdbserver
[ -f Makefile ] || ./configure --host=$HOST --target=$HOST \
    CC=$CC CXX=$CXX LDFLAGS="-static -s" --disable-werror
make -j"$JOBS" MAKEINFO=true
cp gdbserver "$STAGE/"
cd "$SRC"
# gdb (dynamic, libstdc++/libgcc embedded so only glibc is needed on-device)
mkdir -p gdb-8.3.1/build-arm && cd gdb-8.3.1/build-arm
[ -f Makefile ] || ../configure --host=$HOST --target=$HOST \
    --disable-nls --disable-werror --without-python --without-guile \
    --disable-source-highlight --without-expat --without-mpfr \
    --without-babeltrace --disable-tui --without-curses --disable-gdbserver \
    CC=$CC CXX=$CXX LDFLAGS="-static-libstdc++ -static-libgcc -s" MAKEINFO=true
make -j"$JOBS" all-gdb MAKEINFO=true
cp gdb/gdb "$STAGE/"
cd "$SRC"

# ---- file (+ magic.mgc) ----
fetch ftp://ftp.astron.com/pub/file/file-5.39.tar.gz file-5.39.tar.gz
[ -d file-5.39 ] || tar xf "$DL/file-5.39.tar.gz"
# native first, to get a same-version magic compiler + magic.mgc
mkdir -p file-5.39/build-native && cd file-5.39/build-native
[ -f Makefile ] || ../configure --disable-shared
make -j"$JOBS"
NATIVE_FILE="$PWD/src/file"
cd "$SRC"
# cross the ARM binary, using native file to compile the magic db
mkdir -p file-5.39/build-arm && cd file-5.39/build-arm
[ -f Makefile ] || ../configure --host=$HOST --disable-shared CC=$CC LDFLAGS="-s"
make -j"$JOBS" FILE_COMPILE="$NATIVE_FILE"
cp src/file "$STAGE/"
cp magic/magic.mgc "$STAGE/"
cd "$ROOT"

# ---- ldd wrapper (no build) ----
# ldd is a hand-written shell script maintained directly in binaries/ (it is not
# compiled and has no upstream tarball), so there is nothing to stage here.
[ -f "$STAGE/ldd" ] || { echo "error: $STAGE/ldd missing" >&2; exit 1; }

chmod +x "$STAGE"/*
echo "=== staged in $STAGE ==="
ls -la "$STAGE"
