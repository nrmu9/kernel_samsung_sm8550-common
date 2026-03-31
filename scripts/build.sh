#!/usr/bin/env bash
set -euo pipefail

# (env-overridable)
KERNEL_DEFCONFIG=${KERNEL_DEFCONFIG:-gki_defconfig}
CLANG_VERSION=${CLANG_VERSION:-clang-r584948}
OUT_DIR=${OUT_DIR:-out}
CLANG_DIR=${CLANG_DIR:-"$HOME/tools/google-clang"}
CLANG_BINARY="$CLANG_DIR/bin/clang"
START_TIME=$(date +%s)

# --- pretty logs ---
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info(){ echo -e "${GREEN}[INFO]${NC} $*"; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $*"; }
err(){  echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

setup_clang() {
  download_file() {
    local url="$1"
    local output="$2"

    if command -v curl >/dev/null 2>&1; then
      curl -fsSL \
        --retry 5 \
        --retry-delay 2 \
        --connect-timeout 20 \
        --max-time 1200 \
        -o "$output" \
        "$url"
    elif command -v wget >/dev/null 2>&1; then
      wget -q \
        --tries=5 \
        --waitretry=2 \
        --timeout=20 \
        -O "$output" \
        "$url"
    else
      err "Need curl or wget to download the toolchain."
    fi
  }

  is_valid_tarball() {
    local tarball="$1"
    [ -s "$tarball" ] && gzip -t "$tarball" >/dev/null 2>&1 && tar -tzf "$tarball" >/dev/null 2>&1
  }

  info "Checking for Clang ($CLANG_VERSION)..."
  if [ ! -x "$CLANG_BINARY" ]; then
    warn "Clang not found. Fetching..."
    mkdir -p "$CLANG_DIR"

    tmpdir="$(mktemp -d)"
    TARBALL="$tmpdir/${CLANG_VERSION}.tar.gz"

    URL_BASE="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive"
    URLS=(
      "$URL_BASE/refs/heads/main/${CLANG_VERSION}.tar.gz"
      "$URL_BASE/refs/heads/master/${CLANG_VERSION}.tar.gz"
      "$URL_BASE/mirror-goog-main-llvm-toolchain-source/${CLANG_VERSION}.tar.gz"
    )

    downloaded=0
    for url in "${URLS[@]}"; do
      info "Downloading toolchain from: $url"
      rm -f "$TARBALL"
      if download_file "$url" "$TARBALL" && is_valid_tarball "$TARBALL"; then
        downloaded=1
        break
      fi
      warn "Failed or invalid archive from: $url"
    done

    if [ "$downloaded" -ne 1 ]; then
      rm -rf "$tmpdir"
      err "Could not fetch a valid ${CLANG_VERSION} archive from known sources."
    fi

    # Remove partial leftovers from previous failed extractions.
    find "$CLANG_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +

    info "Extracting toolchain..."
    tar -xzf "$TARBALL" -C "$CLANG_DIR"
    rm -rf "$tmpdir"

    [ -x "$CLANG_BINARY" ] || err "Clang binary missing after extraction: $CLANG_BINARY"
  fi

  export PATH="$CLANG_DIR/bin:$PATH"
  ver="$("$CLANG_BINARY" --version | head -n1)"
  ver="$(echo "$ver" | sed -E 's/\(http[^)]*\)//g; s/[[:space:]]+/ /g; s/[[:space:]]+$//')"
  export KBUILD_COMPILER_STRING="$ver"
}

build_kernel() {
  info "Starting kernel build..."
  setup_clang
  mkdir -p "$OUT_DIR"

  make -j"$(nproc --all)" O="$OUT_DIR" ARCH=arm64 CC=clang LD=ld.lld LLVM=1 LLVM_IAS=1 \
       "$KERNEL_DEFCONFIG" || err "defconfig failed"

  make -j"$(nproc --all)" O="$OUT_DIR" ARCH=arm64 CC=clang LD=ld.lld LLVM=1 LLVM_IAS=1 \
       || err "build failed"

  total=$(( $(date +%s) - START_TIME ))
  info "Build finished in $((total/60))m $((total%60))s."
}

# Always build
build_kernel
