#!/bin/zsh
set -euo pipefail

# =============================================================================
#  Anime4K Upscaler — Dependency Bundling Script
#  Locates, copies, rewires, and codesigns ffmpeg + all dylibs + shaders
# =============================================================================

FRAMEWORKS_DIR="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}"
RESOURCES_DIR="${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
SHADERS_SRC="${SRCROOT}/Anime4K-Upscaler/Resources/Shaders"
VENDORED_LIB_DIR="${SRCROOT}/Anime4K-Upscaler/Resources/VendoredDylibs"
VENDORED_LIBPLACEBO="${VENDORED_LIB_DIR}/libplacebo.351.dylib"
VENDORED_TOOLS_DIR="${SRCROOT}/Anime4K-Upscaler/Resources/VendoredTools"
VENDORED_FFMPEG="${VENDORED_TOOLS_DIR}/ffmpeg"
VENDORED_FFPROBE="${VENDORED_TOOLS_DIR}/ffprobe"

case "${A4K_SKIP_ADHOC_SIGNING:-0}" in
    1|true|TRUE|yes|YES)
        SKIP_ADHOC_SIGNING=1
        ;;
    *)
        SKIP_ADHOC_SIGNING=0
        ;;
esac

mkdir -p "${FRAMEWORKS_DIR}"
mkdir -p "${RESOURCES_DIR}/Shaders"

# --- 1. LOCATE FFMPEG & FFPROBE ---
if [[ -x "$VENDORED_FFMPEG" && -x "$VENDORED_FFPROBE" ]]; then
    FFMPEG_BIN="$VENDORED_FFMPEG"
    FFPROBE_BIN="$VENDORED_FFPROBE"
    echo "📦 Using vendored ffmpeg tools from: $VENDORED_TOOLS_DIR"
else
    BREW_FFMPEG_PREFIX=""
    if command -v brew >/dev/null 2>&1; then
        BREW_FFMPEG_PREFIX=$(brew --prefix ffmpeg 2>/dev/null || true)
    fi

    if [[ -n "$BREW_FFMPEG_PREFIX" && -x "$BREW_FFMPEG_PREFIX/bin/ffmpeg" ]]; then
        FFMPEG_BIN="$BREW_FFMPEG_PREFIX/bin/ffmpeg"
        FFPROBE_BIN="$BREW_FFMPEG_PREFIX/bin/ffprobe"
    else
        FFMPEG_BIN=$(command -v ffmpeg 2>/dev/null || echo "/opt/homebrew/bin/ffmpeg")
        FFPROBE_BIN=$(command -v ffprobe 2>/dev/null || echo "/opt/homebrew/bin/ffprobe")
    fi
fi

if [[ ! -f "$FFMPEG_BIN" ]]; then
    echo "error: ffmpeg not found. Install via: brew install ffmpeg"
    exit 1
fi

if [[ ! -f "$FFPROBE_BIN" ]]; then
    echo "error: ffprobe not found."
    exit 1
fi

echo "📦 Bundling ffmpeg from: $FFMPEG_BIN"
echo "📦 Bundling ffprobe from: $FFPROBE_BIN"

# Enforce libplacebo-backed ffmpeg. Fail fast if ffmpeg was built without the filter.
if ! "$FFMPEG_BIN" -hide_banner -filters 2>/dev/null | grep -qE '[[:space:]]libplacebo[[:space:]]'; then
    echo "error: selected ffmpeg does not include libplacebo filter support"
    echo "error: selected ffmpeg path: $FFMPEG_BIN"
    exit 1
fi

PLACEBO_VERSION=$(
    pkg-config --modversion libplacebo 2>/dev/null \
    || otool -L "$FFMPEG_BIN" 2>/dev/null | sed -n 's/.*libplacebo\.\([0-9][0-9]*\)\.dylib.*/\1/p' | head -1
)
if [[ "$PLACEBO_VERSION" != "7.351.0" && "$PLACEBO_VERSION" != "351" ]]; then
    echo "error: required libplacebo version is 7.351.0 (ABI 351), found: ${PLACEBO_VERSION:-unknown}"
    exit 1
fi
echo "✅ Using libplacebo version: $PLACEBO_VERSION"

# --- 2. COPY BINARIES ---
cp -f "$FFMPEG_BIN" "${FRAMEWORKS_DIR}/ffmpeg"
cp -f "$FFPROBE_BIN" "${FRAMEWORKS_DIR}/ffprobe"
chmod +x "${FRAMEWORKS_DIR}/ffmpeg"
chmod +x "${FRAMEWORKS_DIR}/ffprobe"

# --- 3. RECURSIVE DYLIB RESOLUTION & COPY ---

# Skip libraries that are not needed at runtime or cause bundling issues.
# NOTE: X11/XCB libs and libintl MUST be bundled — ffmpeg and its transitive
# deps (libfontconfig, libglib) link against them at load time. Without them
# the dynamic linker fails inside the app sandbox, producing "cancelled by user."
# Only skip Linux-only or build-time-only libraries.
SKIP_DYLIBS=(
    libxshmfence libdrm libGL libEGL libwayland
    libgettextlib libgettextsrc
)

should_skip_dylib() {
    local name="$1"
    for skip in "${SKIP_DYLIBS[@]}"; do
        if [[ "$name" == ${skip}* ]]; then
            return 0
        fi
    done
    return 1
}

# Search paths for resolving @rpath references (prefer vendored dylibs first)
SEARCH_LIB_DIRS=(
    "$VENDORED_LIB_DIR"
    "/opt/homebrew/lib"
    "/usr/local/lib"
)

# Resolve an @rpath reference to an actual file path
resolve_rpath_dep() {
    local dep_name="$1"
    for dir in "${SEARCH_LIB_DIRS[@]}"; do
        if [[ -f "$dir/$dep_name" ]]; then
            echo "$dir/$dep_name"
            return 0
        fi
    done
    # Try find as last resort
    local found
    found=$(find /opt/homebrew/lib -name "$dep_name" -maxdepth 2 2>/dev/null | head -1)
    if [[ -n "$found" ]]; then
        echo "$found"
        return 0
    fi
    return 1
}

find_moltenvk_path() {
    local candidate

    if command -v brew >/dev/null 2>&1; then
        local brew_prefix
        brew_prefix=$(brew --prefix molten-vk 2>/dev/null || true)
        if [[ -n "$brew_prefix" && -f "$brew_prefix/lib/libMoltenVK.dylib" ]]; then
            echo "$brew_prefix/lib/libMoltenVK.dylib"
            return 0
        fi
    fi

    local moltenvk_paths=(
        "/opt/homebrew/lib/libMoltenVK.dylib"
        "/opt/homebrew/opt/molten-vk/lib/libMoltenVK.dylib"
        "/usr/local/lib/libMoltenVK.dylib"
    )

    for candidate in "${moltenvk_paths[@]}"; do
        if [[ -f "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done

    for candidate in /opt/homebrew/Cellar/molten-vk/*/lib/libMoltenVK.dylib /usr/local/Cellar/molten-vk/*/lib/libMoltenVK.dylib; do
        if [[ -f "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done

    return 1
}

relink_moltenvk_refs() {
    local binary="$1"
    local moltenvk_refs=(
        "@rpath/libMoltenVK.dylib"
        "/opt/homebrew/lib/libMoltenVK.dylib"
        "/opt/homebrew/opt/molten-vk/lib/libMoltenVK.dylib"
        "/usr/local/lib/libMoltenVK.dylib"
    )

    local ref
    for ref in "${moltenvk_refs[@]}"; do
        install_name_tool -change "$ref" "@executable_path/../Frameworks/libMoltenVK.dylib" "$binary" 2>/dev/null || true
    done
}

relink_libplacebo_refs() {
    local binary="$1"
    local placebo_refs=(
        "@rpath/libplacebo.351.dylib"
        "@rpath/libplacebo.dylib"
        "/opt/homebrew/lib/libplacebo.351.dylib"
        "/opt/homebrew/opt/libplacebo/lib/libplacebo.351.dylib"
        "/usr/local/lib/libplacebo.351.dylib"
    )

    local ref
    for ref in "${placebo_refs[@]}"; do
        install_name_tool -change "$ref" "@executable_path/../Frameworks/libplacebo.351.dylib" "$binary" 2>/dev/null || true
    done
}

copy_dylibs_recursive() {
    local binary="$1"
    local depth="${2:-0}"

    # Limit recursion depth to prevent runaway chains
    if (( depth > 8 )); then
        return
    fi

    # Get ALL non-system dependencies: /opt/homebrew, /usr/local, AND @rpath
    local all_refs
    all_refs=$(otool -L "$binary" 2>/dev/null | awk 'NR>1 {gsub(/^[[:space:]]+/, ""); print $1}' | grep -E '^(/opt/homebrew|/usr/local|@rpath/)' || true)

    if [[ -z "$all_refs" ]]; then
        return
    fi

    local dep
    while IFS= read -r dep; do
        [[ -z "$dep" ]] && continue

        local dep_name
        dep_name=$(basename "$dep")
        local dest="${FRAMEWORKS_DIR}/${dep_name}"
        local actual_path=""

        # Skip unwanted libraries
        if should_skip_dylib "$dep_name"; then
            continue
        fi

        # Resolve actual file path
        if [[ "$dep" == @rpath/* ]]; then
            actual_path=$(resolve_rpath_dep "$dep_name" 2>/dev/null || true)
        else
            actual_path="$dep"
        fi

        if [[ ! -f "$dest" ]]; then
            if [[ -z "$actual_path" || ! -f "$actual_path" ]]; then
                echo "  ⚠️  Skipping (not found): $dep_name"
                continue
            fi
            echo "  📎 Copying: $dep_name"
            cp -f "$actual_path" "$dest"
            chmod 644 "$dest"
            # Recurse into this dylib's dependencies
            copy_dylibs_recursive "$dest" $((depth + 1))
        fi

        # Rewrite the reference in the binary
        install_name_tool -change "$dep" "@executable_path/../Frameworks/${dep_name}" "$binary" 2>/dev/null || true
    done <<< "$all_refs"
}

echo "🔗 Resolving dylib dependencies for ffmpeg..."
copy_dylibs_recursive "${FRAMEWORKS_DIR}/ffmpeg"

echo "🔗 Resolving dylib dependencies for ffprobe..."
copy_dylibs_recursive "${FRAMEWORKS_DIR}/ffprobe"

if [[ -f "$VENDORED_LIBPLACEBO" ]]; then
    echo "📦 Using vendored libplacebo from: $VENDORED_LIBPLACEBO"
    cp -f "$VENDORED_LIBPLACEBO" "${FRAMEWORKS_DIR}/libplacebo.351.dylib"
    chmod 644 "${FRAMEWORKS_DIR}/libplacebo.351.dylib"
    install_name_tool -id "@executable_path/../Frameworks/libplacebo.351.dylib" "${FRAMEWORKS_DIR}/libplacebo.351.dylib" 2>/dev/null || true
fi

relink_libplacebo_refs "${FRAMEWORKS_DIR}/ffmpeg"
relink_libplacebo_refs "${FRAMEWORKS_DIR}/ffprobe"

# --- 4. REWRITE ALL DYLIBS' INTERNAL REFERENCES (multi-pass) ---
# Some dylibs reference others via @rpath which step 3 may not have
# reached from the binary roots. Run multiple passes until no new
# dylibs are discovered.
echo "🔧 Rewriting internal dylib references (multi-pass)..."
setopt nullglob 2>/dev/null || true

PASS=0
while true; do
    PASS=$((PASS + 1))
    NEW_FOUND=false

    for dylib in "${FRAMEWORKS_DIR}"/*.dylib; do
        [[ ! -f "$dylib" ]] && continue
        local_dylib_name=$(basename "$dylib")

        # Fix the dylib's own install name
        install_name_tool -id "@executable_path/../Frameworks/${local_dylib_name}" "$dylib" 2>/dev/null || true

        # Fix all references within this dylib — homebrew paths AND @rpath
        all_refs=$(otool -L "$dylib" | awk 'NR>1 {gsub(/^[[:space:]]+/,""); print $1}' | grep -E '^(/opt/homebrew|/usr/local|@rpath/)' || true)
        for ref in $all_refs; do
            ref_name=$(basename "$ref")

            if should_skip_dylib "$ref_name"; then
                continue
            fi

            # If the referenced dylib isn't bundled yet, copy it
            if [[ ! -f "${FRAMEWORKS_DIR}/${ref_name}" ]]; then
                local actual=""
                if [[ "$ref" == @rpath/* ]]; then
                    actual=$(resolve_rpath_dep "$ref_name" 2>/dev/null || true)
                else
                    actual="$ref"
                fi
                if [[ -n "$actual" && -f "$actual" ]]; then
                    echo "  📎 Pass $PASS: Copying $ref_name (needed by $local_dylib_name)"
                    cp -f "$actual" "${FRAMEWORKS_DIR}/${ref_name}"
                    chmod 644 "${FRAMEWORKS_DIR}/${ref_name}"
                    NEW_FOUND=true
                fi
            fi

            install_name_tool -change "$ref" "@executable_path/../Frameworks/${ref_name}" "$dylib" 2>/dev/null || true
        done
    done

    if [[ "$NEW_FOUND" == false ]]; then
        echo "  ✅ Converged after $PASS pass(es)"
        break
    fi

    if (( PASS > 5 )); then
        echo "  ⚠️  Exceeded 5 passes, stopping"
        break
    fi
done

# --- 5. COPY MOLTENVK ---
MOLTENVK_FOUND=false
MOLTENVK_PATH=$(find_moltenvk_path 2>/dev/null || true)

if [[ -n "$MOLTENVK_PATH" && -f "$MOLTENVK_PATH" ]]; then
    echo "📦 Bundling MoltenVK from: $MOLTENVK_PATH"
    cp -f "$MOLTENVK_PATH" "${FRAMEWORKS_DIR}/libMoltenVK.dylib"
    chmod 644 "${FRAMEWORKS_DIR}/libMoltenVK.dylib"
    install_name_tool -id "@executable_path/../Frameworks/libMoltenVK.dylib" "${FRAMEWORKS_DIR}/libMoltenVK.dylib" 2>/dev/null || true
    MOLTENVK_FOUND=true

    relink_moltenvk_refs "${FRAMEWORKS_DIR}/ffmpeg"
    relink_moltenvk_refs "${FRAMEWORKS_DIR}/ffprobe"
fi

for dylib in "${FRAMEWORKS_DIR}"/*.dylib; do
    [[ ! -f "$dylib" ]] && continue
    relink_libplacebo_refs "$dylib"
    relink_moltenvk_refs "$dylib"
done

if [[ "$MOLTENVK_FOUND" == "false" ]]; then
    echo "warning: libMoltenVK.dylib not found. Vulkan-based libplacebo shaders may not work."
    echo "warning: Install via: brew install molten-vk"
fi

# --- 6. COPY SHADERS ---
if [[ -d "$SHADERS_SRC" ]]; then
    echo "📦 Copying GLSL shaders..."
    cp -f "${SHADERS_SRC}"/*.glsl "${RESOURCES_DIR}/Shaders/" 2>/dev/null || echo "warning: No .glsl files found in ${SHADERS_SRC}"
else
    echo "warning: Shader directory not found at ${SHADERS_SRC}"
fi

# --- 7. OPTIONAL AD-HOC CODESIGN ---
if [[ "$SKIP_ADHOC_SIGNING" == "1" ]]; then
    echo "⏭️  Skipping ad-hoc signing of bundled binaries (A4K_SKIP_ADHOC_SIGNING=1)."
else
    echo "🔏 Codesigning all bundled binaries and dylibs..."
    for item in "${FRAMEWORKS_DIR}/ffmpeg" "${FRAMEWORKS_DIR}/ffprobe" "${FRAMEWORKS_DIR}"/*.dylib; do
        [[ ! -f "$item" ]] && continue
        codesign --force --sign - --timestamp=none "$item" 2>/dev/null || true
        echo "  ✅ Signed: $(basename "$item")"
    done
fi

echo ""
echo "✅ Dependency bundling complete."
echo "   Frameworks: $(ls "${FRAMEWORKS_DIR}" | wc -l | tr -d ' ') items"
echo "   Shaders:    $(ls "${RESOURCES_DIR}/Shaders/"*.glsl 2>/dev/null | wc -l | tr -d ' ') files"
