#!/bin/sh
set -e
echo "Installing Quip compiler"

# detect os and arch
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    ARCH="amd64"
elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    ARCH="arm64"
else
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

echo "Detected OS: $OS, Architecture: $ARCH"
QUIP_DIR="$HOME/.quip"
BIN_DIR="$QUIP_DIR/bin"
LIB_DIR="$QUIP_DIR/lib"

mkdir -p "$BIN_DIR"
mkdir -p "$LIB_DIR"

DOWNLOAD_URL="https://github.com/oskiv6/quipc/releases/latest/download/quipc-${OS}-${ARCH}.tar.gz"
echo "Downloading from $DOWNLOAD_URL..."

curl -L -s "$DOWNLOAD_URL" -o quip.tar.gz

# unpack directly into ~/.quip/bin
echo "Extracting toolchain..."
tar -xzf quip.tar.gz -C "$BIN_DIR" --strip-components=1
rm quip.tar.gz

# remove Apple quarantine attribute to bypass 'potential malware' warning
if [ "$OS" = "darwin" ]; then
    xattr -d com.apple.quarantine "$BIN_DIR/quipc" 2>/dev/null || true
fi

echo "Compiling Quip runtime (libq.o)..."
if command -v clang >/dev/null 2>&1; then
    COMPILER="clang"
elif command -v gcc >/dev/null 2>&1; then
    COMPILER="gcc"
else
    COMPILER="cc"
fi

$COMPILER -O3 -fPIC -c "$BIN_DIR/libq.c" -o "$LIB_DIR/libq.o"
rm "$BIN_DIR/libq.c" # cleanup the source file after compiling
echo "Runtime compiled successfully."

PROFILE=""
if [ -n "$ZSH_VERSION" ] || [ -f "$HOME/.zshrc" ]; then
    PROFILE="$HOME/.zshrc"
elif [ -n "$BASH_VERSION" ] || [ -f "$HOME/.bashrc" ]; then
    PROFILE="$HOME/.bashrc"
fi

if [ -n "$PROFILE" ]; then
    # only inject if it's not already there to prevent PATH bloat
    if ! grep -q "$BIN_DIR" "$PROFILE"; then
        echo "" >> "$PROFILE"
        echo "export PATH=\"$BIN_DIR:\$PATH\"" >> "$PROFILE"
        echo "Injected Quip into $PROFILE"
    fi
else
    echo "Could not detect shell profile. Add $BIN_DIR to your PATH manually."
fi

echo "quipc installed successfully. Restart your terminal or run: source $PROFILE"
