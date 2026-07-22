#!/bin/sh
set -e

step () {
    echo "[$1/$TOTAL] $2"
}

# compare dotted numeric version strings; returns 0 if $1 < $2, 1 otherwise
older () {
    L="$1"
    R="$2"
    while true; do
        l="${L%%.*}"
        r="${R%%.*}"
        if [ "${l:-0}" -lt "${r:-0}" ]; then return 0; fi
        if [ "${l:-0}" -gt "${r:-0}" ]; then return 1; fi
        [ "$l" = "$L" ] && [ "$r" = "$R" ] && break
        L="${L#*.}"
        R="${R#*.}"
    done
    return 1
}

QUIP_DIR="$HOME/.quip"
DOWNLOAD_DIR="$QUIP_DIR/downloads"
BIN_DIR="$QUIP_DIR/bin"
LIB_DIR="$QUIP_DIR/lib"
VERSION_FILE="$QUIP_DIR/VERSION"

TOTAL=7

step 1 "Detecting platform"
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
case "$ARCH" in
    x86_64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac
echo "    OS: $OS, Arch: $ARCH"

step 2 "Checking latest release"
LATEST_VERSION=$(curl -s https://api.github.com/repos/oskiv6/quipc/releases/latest | grep '"tag_name":' | sed 's/.*"tag_name": "//' | sed 's/".*//')
LATEST_VERSION=$(echo "$LATEST_VERSION" | sed 's/^v//')  # strip leading v
LATEST_BARE=$(echo "$LATEST_VERSION" | sed 's/[-+].*//')  # strip pre-release suffix
echo "    Latest: v$LATEST_VERSION"

if [ -f "$VERSION_FILE" ]; then
    CURRENT_VERSION=$(cat "$VERSION_FILE")
    CURRENT_BARE=$(echo "$CURRENT_VERSION" | sed 's/[-+].*//')
    echo "    Installed: v$CURRENT_VERSION"
    if older "$CURRENT_BARE" "$LATEST_BARE"; then
        echo "    Update available, proceeding..."
    else
        echo "    Already up-to-date, nothing to do."
        exit 0
    fi
else
    echo "    No existing install found, proceeding..."
fi

mkdir -p "$BIN_DIR" "$LIB_DIR" "$DOWNLOAD_DIR"

step 3 "Downloading compiler"
DOWNLOAD_URL="https://github.com/oskiv6/quipc/releases/latest/download/quipc-${OS}-${ARCH}.tar.gz"
QUIPC_TAR="quipc.tar.gz"
curl -L --progress-bar "$DOWNLOAD_URL" -o "$DOWNLOAD_DIR/$QUIPC_TAR"

step 4 "Extracting toolchain"
tar -xzf "$DOWNLOAD_DIR/$QUIPC_TAR" -C "$BIN_DIR" --strip-components=1
rm "$DOWNLOAD_DIR/$QUIPC_TAR"
if [ "$OS" = "darwin" ]; then
    xattr -d com.apple.quarantine "$BIN_DIR/quipc" 2>/dev/null || true
fi
echo "    Extracted to $BIN_DIR"

step 5 "Compiling runtime"
if command -v clang >/dev/null 2>&1; then
    COMPILER="clang"
elif command -v gcc >/dev/null 2>&1; then
    COMPILER="gcc"
else
    COMPILER="cc"
fi
$COMPILER -O3 -fPIC -c "$BIN_DIR/libq.c" -o "$LIB_DIR/libq.o"
rm "$BIN_DIR/libq.c"
echo "    libq.o -> $LIB_DIR/libq.o"

step 6 "Installing standard library"
STD_URL="https://github.com/oskiv6/quipc/archive/refs/heads/main.tar.gz"
STD_TAR="quipc-main.tar.gz"
curl -L --progress-bar "$STD_URL" -o "$DOWNLOAD_DIR/$STD_TAR"
tar -xzf "$DOWNLOAD_DIR/$STD_TAR" -C "$LIB_DIR" --strip-components=2 "quipc-main/library/std/"
rm "$DOWNLOAD_DIR/$STD_TAR"
echo "    -> $LIB_DIR/std"

step 7 "Configuring shell"
PROFILE=""
if [ -n "$ZSH_VERSION" ] || [ -f "$HOME/.zshrc" ]; then
    PROFILE="$HOME/.zshrc"
elif [ -n "$BASH_VERSION" ] || [ -f "$HOME/.bashrc" ]; then
    PROFILE="$HOME/.bashrc"
fi

if [ -n "$PROFILE" ]; then
    if ! grep -q "$BIN_DIR" "$PROFILE"; then
        echo "" >> "$PROFILE"
        echo "export PATH=\"$BIN_DIR:\$PATH\"" >> "$PROFILE"
        echo "    Injected PATH into $PROFILE"
    else
        echo "    PATH already set in $PROFILE"
    fi
else
    echo "    Could not detect shell profile — add $BIN_DIR to your PATH manually"
fi

echo "$LATEST_VERSION" > "$VERSION_FILE"
echo ""
echo "  Done. Restart your terminal or run: source $PROFILE"
echo "  Version:   v$LATEST_VERSION"
echo "  Compiler:  $BIN_DIR/quipc"
echo "  Runtime:   $LIB_DIR/libq.o"
echo "  Std lib:   $LIB_DIR/std"
