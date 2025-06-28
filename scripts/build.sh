#!/bin/bash
set -e

KERNEL_DEFCONFIG=gki_defconfig
CLANG_VERSION=clang-r563880

OUT_DIR=out
CLANG_DIR="$HOME/tools/google-clang"
CLANG_BINARY="$CLANG_DIR/bin/clang"
START_TIME=$(date +%s)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

usage() {
    echo "Usage: $0 [clean]"
    echo "  No arguments: Builds the kernel."
    echo "  clean: Removes the build output directory."
    exit 1
}

setup_clang() {
    info "Checking for Clang toolchain..."
    if ! [ -d "$CLANG_DIR" ]; then
        warn "Clang not found! Cloning..."
        mkdir -p "$CLANG_DIR"
        if ! wget --show-progress -O "$CLANG_DIR/${CLANG_VERSION}.tar.gz" "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/tags/ndk-r29-beta2/${CLANG_VERSION}.tar.gz"; then
            error "Cloning failed! Aborting..."
        fi
        info "Extracting the toolchain..."
        tar -xzf "$CLANG_DIR/${CLANG_VERSION}.tar.gz" -C "$CLANG_DIR"
        rm "$CLANG_DIR/${CLANG_VERSION}.tar.gz"
    fi
    info "Clang is ready."
    export PATH="$CLANG_DIR/bin:$PATH"
    export KBUILD_COMPILER_STRING="$($CLANG_BINARY --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')"
}

build_kernel() {
    info "Starting kernel build..."
    setup_clang

    if [ ! -d "$OUT_DIR" ]; then
        info "Creating output directory: $OUT_DIR"
        mkdir -p "$OUT_DIR"
    fi

    info "Generating .config file using $KERNEL_DEFCONFIG..."
    make -j$(nproc --all) O=$OUT_DIR \
                          ARCH=arm64 \
                          CC=clang \
                          LD=ld.lld \
                          LLVM=1 \
                          LLVM_IAS=1 \
                          $KERNEL_DEFCONFIG || error "make defconfig failed."

    info "Starting main build..."
    make -j$(nproc --all) O=$OUT_DIR \
                          ARCH=arm64 \
                          CC=clang \
                          LD=ld.lld \
                          LLVM=1 \
                          LLVM_IAS=1 || error "make build failed."

    END_TIME=$(date +%s)
    TOTAL_TIME=$((END_TIME - START_TIME))
    info "Build finished successfully in $(($TOTAL_TIME / 60)) minutes and $(($TOTAL_TIME % 60)) seconds."
}

clean_build() {
    info "Cleaning build artifacts..."
    if [ -d "$OUT_DIR" ]; then
        rm -rf "$OUT_DIR"
        info "Output directory removed."
    else
        warn "Output directory not found, nothing to clean."
    fi
}


if [ "$1" == "clean" ]; then
    clean_build
elif [ -n "$1" ]; then
    usage
else
    build_kernel
fi
