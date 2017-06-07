#!/bin/bash
#
# american fuzzy lop - QEMU build script
# --------------------------------------
#
# Written by Andrew Griffiths <agriffiths@google.com> and
#            Michal Zalewski <lcamtuf@google.com>
#
# Copyright 2015, 2016 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at:
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# This script downloads, patches, and builds a version of QEMU with
# minor tweaks to allow non-instrumented binaries to be run under
# afl-fuzz. 
#
# The modifications reside in patches/*. The standalone QEMU binary
# will be written to ../afl-qemu-trace.
#

QEMU_URL="http://download.qemu-project.org/qemu-2.8.0.tar.xz"
QEMU_SHA384="c305ec10747cb2a67f2435f20f37cb78ed59d8ab4e9d1c6e9b17fe8111fe462f8053b34f317af8526a8a4f4eda7b6481"

echo "[*] Performing basic sanity checks..."

if [ ! "`uname -s`" = "Linux" ]; then

  echo "[-] Error: QEMU instrumentation is supported only on Linux."
  exit 1

fi

if [ ! -f "patches/afl-qemu-cpu-inl.h" -o ! -f "../config.h" ]; then

  echo "[-] Error: key files not found - wrong working directory?"
  exit 1

fi

if [ ! -f "../afl-showmap" ]; then

  echo "[-] Error: ../afl-showmap not found - compile AFL first!"
  exit 1

fi


for i in libtool wget python automake autoconf sha384sum bison iconv; do

  T=`which "$i" 2>/dev/null`

  if [ "$T" = "" ]; then

    echo "[-] Error: '$i' not found, please install first."
    exit 1

  fi

done

if [ ! -d "/usr/include/glib-2.0/" -a ! -d "/usr/local/include/glib-2.0/" ]; then

  echo "[-] Error: devel version of 'glib2' not found, please install first."
  exit 1

fi

if echo "$CC" | grep -qF /afl-; then

  echo "[-] Error: do not use afl-gcc or afl-clang to compile this tool."
  exit 1

fi

echo "[+] All checks passed!"

ARCHIVE="`basename -- "$QEMU_URL"`"

CKSUM=`sha384sum -- "$ARCHIVE" 2>/dev/null | cut -d' ' -f1`

if [ ! "$CKSUM" = "$QEMU_SHA384" ]; then

  echo "[*] Downloading QEMU 2.8.0 from the web..."
  rm -f "$ARCHIVE"
  wget -O "$ARCHIVE" -- "$QEMU_URL" || exit 1

  CKSUM=`sha384sum -- "$ARCHIVE" 2>/dev/null | cut -d' ' -f1`

fi

if [ "$CKSUM" = "$QEMU_SHA384" ]; then

  echo "[+] Cryptographic signature on $ARCHIVE checks out."

else

  echo "[-] Error: signature mismatch on $ARCHIVE (perhaps download error?)."
  exit 1

fi

echo "[*] Uncompressing archive (this will take a while)..."

rm -rf "qemu-2.8.0" || exit 1
tar xf "$ARCHIVE" || exit 1

echo "[+] Unpacking successful."

echo "[*] Applying patches..."

patch -p0 <patches/qemu-2.8.0.diff || exit 1

echo "[+] Patching done."

echo "[*] Configuring QEMU..."

cd qemu-2.8.0 || exit 1

CC=gcc
CXX=g++

CFLAGS="-O3" ./configure --python=/usr/bin/python2 --disable-system \
  --enable-linux-user --disable-gtk --disable-sdl --disable-vnc \
  --target-list="aarch64-linux-user armeb-linux-user arm-linux-user i386-linux-user mips64el-linux-user mips64-linux-user mipsel-linux-user mips-linux-user mipsn32el-linux-user mipsn32-linux-user ppc64abi32-linux-user ppc64le-linux-user ppc64-linux-user ppc-linux-user x86_64-linux-user" || exit 1

echo "[+] Configuration complete."

echo "[*] Attempting to build QEMU..."

make || exit 1

echo "[+] Build process successful!"

echo "[*] Copying binary..."

for CPU_TARGET in "aarch64" "armeb" "arm" "i386" "mips64el" "mips64" "mipsel" "mips" "mipsn32el" "mipsn32" "ppc64abi32" "ppc64le" "ppc64" "ppc" "x86_64"
do
  mkdir "../../afl-qemu-trace-${CPU_TARGET}"
  cp -f "${CPU_TARGET}-linux-user/qemu-${CPU_TARGET}" "../../afl-qemu-trace-${CPU_TARGET}/afl-qemu-trace" || exit 1
  strip -s "../../afl-qemu-trace-${CPU_TARGET}/afl-qemu-trace"
done

cp -f "../../afl-qemu-trace-$(uname -m)/afl-qemu-trace" "../../afl-qemu-trace" || exit 1

cd ..
ls -l ../afl-qemu-trace* || exit 1

echo "[+] Successfully created '../afl-qemu-trace'."

echo "[*] Testing the build..."

cd ..

make >/dev/null || exit 1

gcc test-instr.c -o test-instr || exit 1

unset AFL_INST_RATIO

echo 0 | ./afl-showmap -m none -Q -q -o .test-instr0 ./test-instr || exit 1
echo 1 | ./afl-showmap -m none -Q -q -o .test-instr1 ./test-instr || exit 1

rm -f test-instr

cmp -s .test-instr0 .test-instr1
DR="$?"

rm -f .test-instr0 .test-instr1

if [ "$DR" = "0" ]; then

  echo "[-] Error: afl-qemu-trace instrumentation doesn't seem to work!"
  exit 1

fi

echo "[+] Instrumentation tests passed. "
echo "[+] All set, you can now use the -Q mode in afl-fuzz!"

exit 0
