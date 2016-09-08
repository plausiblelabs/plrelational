#!/bin/sh

# For reasons unknown to me, the Swift compiler currently segfaults if given a module
# map pointing to /usr/include/sqlite3.h. The workaround is to point the compiler to
# the header in the SDK. Since the SDK path can potentially vary, we don't want to
# hardcode it. Instead, this script generates a modulemap file at build time based on
# the current SDK path. This script must be set to run in a shell script build phase
# that runs before files are compiled, then the Import Paths setting for the compiler
# must be set to $(TARGET_BUILD_DIR)/modules for the compiler to see the output.

OUT_DIR="$TARGET_BUILD_DIR/modules"
OUT_FILE="$OUT_DIR/module.modulemap"

mkdir -p "$OUT_DIR"

if [ ! -f "$OUT_FILE" ] || [ "$0" -nt "$OUT_FILE" ]; then
    cat > "$OUT_FILE" <<MODULE

    module sqlite3 [system] {
        header "$SDKROOT/usr/include/sqlite3.h"
        link "sqlite3"
        export *
    }

    module CommonCrypto [system] {
        header "$SDKROOT/usr/include/CommonCrypto/CommonCrypto.h"
        link "System"
        export *
    }
MODULE
fi
