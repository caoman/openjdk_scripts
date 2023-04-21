#!/bin/bash

set -euo pipefail

TARGET_DIR="$HOME"/workspace/jdkHEADgensrc
JDK_BUILD_DIR=$(pwd)

if [[ ! -d "$TARGET_DIR" ]]; then
  mkdir -p "$TARGET_DIR"
fi

cp -r "$JDK_BUILD_DIR"/images/jdk/include/* "$TARGET_DIR"/
cp -r "$JDK_BUILD_DIR"/hotspot/variant-server/gensrc/* "$TARGET_DIR"/

find "$TARGET_DIR" -regextype posix-extended -regex ".*[.](cmdline|log)$" | xargs rm

echo "Copied to $TARGET_DIR"
