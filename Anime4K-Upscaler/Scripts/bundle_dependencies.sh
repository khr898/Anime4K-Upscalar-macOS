#!/bin/zsh
set -euo pipefail

# =============================================================================
#  Anime4K Upscaler — Dependency Bundling Script
#  Locates, copies, rewires, and codesigns ffmpeg + all dylibs + shaders
# =============================================================================

FRAMEWORKS_DIR="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}"
RESOURCES_DIR="${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
SHADERS_SRC="${SRCROOT}/Anime4K-Upscaler/Resources/Shaders"
METAL_SOURCES_DEST="${RESOURCES_DIR}/metal_sources"

METAL_SOURCE_CANDIDATES=(
    "${SRCROOT}/Anime4K-Upscaler/Resources/metal_sources"
    "${SRCROOT}/Resources/metal_sources"
)

mkdir -p "${FRAMEWORKS_DIR}"
mkdir -p "${RESOURCES_DIR}/Shaders"
mkdir -p "${METAL_SOURCES_DEST}"

# --- 1. LOCATE FFMPEG & FFPROBE ---
FFMPEG_BIN=$(which ffmpeg 2>/dev/null || echo "/opt/homebrew/bin/ffmpeg")
FFPROBE_BIN=$(which ffprobe 2>/dev/null || echo "/opt/homebrew/bin/ffprobe")

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

# --- Optional libplacebo probe (informational only) ---
echo "🔍 Probing libplacebo availability (informational)..."
LP_PROBE_OUTPUT=$("$FFMPEG_BIN" -hide_banner -v verbose -f lavfi -i color=size=16x16:rate=1:color=black -vf libplacebo -frames:v 1 -f null - 2>&1 || true)
LP_VERSION=$(echo "$LP_PROBE_OUTPUT" | sed -nE 's/.*libplacebo[[:space:]]+v?([0-9]+\.[0-9]+(\.[0-9]+)?).*/\1/p' | head -n1)

if [[ -n "$LP_VERSION" ]]; then
    echo "ℹ️  libplacebo runtime version detected: $LP_VERSION"
else
    echo "ℹ️  libplacebo not detected in ffmpeg runtime output (OK for Metal pipeline)"
fi

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

# Homebrew search paths for resolving @rpath references
HOMEBREW_LIB_DIRS=(
    "/opt/homebrew/lib"
    "/usr/local/lib"
)

# Resolve an @rpath reference to an actual file path
resolve_rpath_dep() {
    local dep_name="$1"
    for dir in "${HOMEBREW_LIB_DIRS[@]}"; do
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
MOLTENVK_PATHS=(
    "/opt/homebrew/lib/libMoltenVK.dylib"
    "/opt/homebrew/opt/molten-vk/lib/libMoltenVK.dylib"
    "/usr/local/lib/libMoltenVK.dylib"
)

MOLTENVK_FOUND=false
for mvk_path in "${MOLTENVK_PATHS[@]}"; do
    if [[ -f "$mvk_path" ]]; then
        echo "📦 Bundling MoltenVK from: $mvk_path"
        cp -f "$mvk_path" "${FRAMEWORKS_DIR}/libMoltenVK.dylib"
        chmod 644 "${FRAMEWORKS_DIR}/libMoltenVK.dylib"
        install_name_tool -id "@executable_path/../Frameworks/libMoltenVK.dylib" "${FRAMEWORKS_DIR}/libMoltenVK.dylib" 2>/dev/null || true
        MOLTENVK_FOUND=true
        break
    fi
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

# --- 6b. COPY TRANSLATED METAL SOURCES ---
METAL_SRC_DIR=""
for candidate in "${METAL_SOURCE_CANDIDATES[@]}"; do
    if [[ -d "$candidate" ]]; then
        METAL_SRC_DIR="$candidate"
        break
    fi
done

if [[ -n "$METAL_SRC_DIR" ]]; then
    echo "📦 Copying translated .metal sources from: $METAL_SRC_DIR"
    cp -f "${METAL_SRC_DIR}"/Anime4K_*.metal "${METAL_SOURCES_DEST}/" 2>/dev/null || echo "warning: No Anime4K_*.metal files found in ${METAL_SRC_DIR}"
else
    echo "warning: Could not locate translated .metal source directory"
fi

# --- 7. CODESIGN EVERYTHING ---
echo "🔏 Codesigning all bundled binaries and dylibs..."
for item in "${FRAMEWORKS_DIR}/ffmpeg" "${FRAMEWORKS_DIR}/ffprobe" "${FRAMEWORKS_DIR}"/*.dylib; do
    [[ ! -f "$item" ]] && continue
    codesign --force --sign - --timestamp=none "$item" 2>/dev/null || true
    echo "  ✅ Signed: $(basename "$item")"
done

echo ""
echo "✅ Dependency bundling complete."
echo "   Frameworks: $(ls "${FRAMEWORKS_DIR}" | wc -l | tr -d ' ') items"
echo "   Shaders:    $(ls "${RESOURCES_DIR}/Shaders/"*.glsl 2>/dev/null | wc -l | tr -d ' ') files"
echo "   Metal src:  $(ls "${METAL_SOURCES_DEST}/"*.metal 2>/dev/null | wc -l | tr -d ' ') files"
