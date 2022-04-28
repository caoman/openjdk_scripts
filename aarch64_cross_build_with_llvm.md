# How to cross-build OpenJDK 11u for aarch64 with LLVM-13+

This note documents my setup for using LLVM-13.0.1 to cross-build aarch64
OpenJDK 11u on an x86_64 Debian-based OS. The background is the discussion for
[JDK-8276453](https://bugs.openjdk.java.net/browse/JDK-8276453).

## Install/Download dependencies

```
$ sudo apt-get install build-essential crossbuild-essential-arm64
```

This should install essentially ARM tools and libraries in
`/usr/aarch64-linux-gnu`.

For LLVM, I downloaded `clang+llvm-13.0.1-x86_64-linux-gnu-ubuntu-18.04.tar.xz`
from https://github.com/llvm/llvm-project/releases/tag/llvmorg-13.0.1. The LLVM
archive is then extracted into a directory
`$HOME/aarch64_tools/x86_64_llvm13_0_1/`.

In addition, OpenJDK requires X11 libraries and headers for ARM64, which is not
included in the `crossbuild-essential-arm64` package group. These packages can
be downloaded from https://packages.debian.org/bullseye/:

```
libx11-6_1.7.2-1_arm64.deb
libx11-dev_1.7.2-1_arm64.deb
libxext6_1.3.3-1.1_arm64.deb
libxext-dev_1.3.3-1.1_arm64.deb
libxrender1_0.9.10-1_arm64.deb
libxrender-dev_0.9.10-1_arm64.deb
```

They are then extracted into a directory `$HOME/aarch64_tools/aarch64libs/`
using the command: `dpkg-deb -x <name>.deb $HOME/aarch64_tools/aarch64libs/`

We also need an x86_64 OpenJDK 11 for the boot JDK. I downloaded one for x64
Linux from https://adoptopenjdk.net/upstream.html?variant=openjdk11&ga=ga, and
it was extracted to `$HOME/jdk/java-11-openjdk-amd64`.

## Create Clang wrapper scripts

OpenJDK 11's configure/autoconf rule does not natively support cross-build with
LLVM/Clang. Thus, we need to create wrapper scripts and use them for autoconf's
`CC`, `CXX` variables.

The following scripts are created:

`$HOME/aarch64_tools/cc_wrapper.sh`:

```
#!/bin/bash
exec /usr/local/google/home/manc/aarch64_tools/x86_64_llvm13_0_1/bin/clang --target=aarch64-linux-gnu "$@"
```

`$HOME/aarch64_tools/cxx_wrapper.sh`:

```
#!/bin/bash
exec /usr/local/google/home/manc/aarch64_tools/x86_64_llvm13_0_1/bin/clang++ --target=aarch64-linux-gnu "$@"
```

## Run configure and make

Now we are ready to run configure and make. We need to specify various tools
explicitly to use llvm's version of them.

```
$ (LLVMROOT="$HOME/aarch64_tools/x86_64_llvm13_0_1/bin" \
CC="$HOME/aarch64_tools/cc_wrapper.sh" \
CXX="$HOME/aarch64_tools/cxx_wrapper.sh" \
AR="$LLVMROOT/llvm-ar" \
CXXFILT="$LLVMROOT/llvm-cxxfilt" \
NM="$LLVMROOT/llvm-nm" \
OBJCOPY="$LLVMROOT/llvm-objcopy" \
OBJDUMP="$LLVMROOT/llvm-objdump" \
READELF="$LLVMROOT/llvm-readelf" \
STRIP="$LLVMROOT/llvm-strip" \
BUILD_CC="$LLVMROOT/clang" \
BUILD_CXX="$LLVMROOT/clang++" \
BUILD_AR="$AR" \
BUILD_NM="$NM" \
BUILD_OBJCOPY="$OBJCOPY" \
BUILD_STRIP="$STRIP" \
bash configure --openjdk-target=aarch64-linux-gnu --with-debug-level=fastdebug --with-toolchain-type=clang \
--disable-precompiled-headers --disable-warnings-as-errors --with-freetype=bundled \
--with-boot-jdk="$HOME/jdk/java-11-openjdk-amd64" \
--x-includes="$HOME/aarch64_tools/aarch64libs/usr/include/X11" \
--x-libraries="$HOME/aarch64_tools/aarch64libs/usr/lib/aarch64-linux-gnu")

$ make jdk-image JOBS=30
```

We have to use `--disable-warnings-as-errors` because LLVM/Clang tends to
reports more warnings as errors than GCC does. In addition,
`--disable-precompiled-headers` is useful to expose subtle dependency errors in
`#include` statements.

At the time of writing, the build for fastdebug JVM fails for OpenJDK 11u
because necessary changes such as
[JDK-8276453](https://bugs.openjdk.java.net/browse/JDK-8276453) and
[JDK-8229258](https://bugs.openjdk.java.net/browse/JDK-8229258) have not yet
been backported to 11u.
