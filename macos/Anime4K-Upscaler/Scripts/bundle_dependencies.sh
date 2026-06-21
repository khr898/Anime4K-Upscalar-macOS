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

# --- 0. INSTALL MOLTENVK IF MISSING ---
if command -v brew >/dev/null 2>&1; then
    if ! brew list molten-vk >/dev/null 2>&1; then
        echo "🍺 Installing molten-vk via Homebrew..."
        brew install molten-vk
    fi
fi

build_custom_ffmpeg() {
    echo "🛠️  Building custom FFmpeg with Vulkan and libplacebo..."
    local temp_build_dir="${SRCROOT}/ffmpeg_build"
    mkdir -p "$temp_build_dir"
    cd "$temp_build_dir"
    
    if [[ ! -d "ffmpeg" ]]; then
        git clone --depth 1 https://git.ffmpeg.org/ffmpeg.git ffmpeg
    fi
    cd ffmpeg
    
    ./configure \
        --prefix="${temp_build_dir}/dist" \
        --enable-vulkan \
        --enable-libplacebo \
        --enable-gpl \
        --enable-nonfree \
        --disable-shared \
        --enable-static
    make -j$(sysctl -n hw.ncpu)
    make install
    
    FFMPEG_BIN="${temp_build_dir}/dist/bin/ffmpeg"
    FFPROBE_BIN="${temp_build_dir}/dist/bin/ffprobe"
    cd "${SRCROOT}"
}

# --- 1. LOCATE FFMPEG & FFPROBE ---
FFMPEG_BIN=""
FFPROBE_BIN=""

# 1a. Check if we already have a fully functioning vendored ffmpeg
if [[ -x "$VENDORED_FFMPEG" && -x "$VENDORED_FFPROBE" ]]; then
    # Test if it runs. If it fails due to dyld (missing libavdevice/etc.), we can try downloading it.
    if "$VENDORED_FFMPEG" -version >/dev/null 2>&1; then
        FFMPEG_BIN="$VENDORED_FFMPEG"
        FFPROBE_BIN="$VENDORED_FFPROBE"
        echo "📦 Using working vendored ffmpeg tools from: $VENDORED_TOOLS_DIR"
    fi
fi

# 1b. If not found or not working, check device's system/homebrew ffmpeg
if [[ -z "$FFMPEG_BIN" ]]; then
    BREW_FFMPEG_PREFIX=""
    if command -v brew >/dev/null 2>&1; then
        BREW_FFMPEG_PREFIX=$(brew --prefix ffmpeg 2>/dev/null || true)
    fi

    CANDIDATE_FFMPEG=""
    CANDIDATE_FFPROBE=""
    if [[ -n "$BREW_FFMPEG_PREFIX" && -x "$BREW_FFMPEG_PREFIX/bin/ffmpeg" ]]; then
        CANDIDATE_FFMPEG="$BREW_FFMPEG_PREFIX/bin/ffmpeg"
        CANDIDATE_FFPROBE="$BREW_FFMPEG_PREFIX/bin/ffprobe"
    else
        CANDIDATE_FFMPEG=$(command -v ffmpeg 2>/dev/null || echo "/opt/homebrew/bin/ffmpeg")
        CANDIDATE_FFPROBE=$(command -v ffprobe 2>/dev/null || echo "/opt/homebrew/bin/ffprobe")
    fi

    # Check if the device candidate actually supports libplacebo
    if [[ -x "$CANDIDATE_FFMPEG" ]] && otool -L "$CANDIDATE_FFMPEG" 2>/dev/null | grep -q "libplacebo"; then
        FFMPEG_BIN="$CANDIDATE_FFMPEG"
        FFPROBE_BIN="$CANDIDATE_FFPROBE"
        echo "📦 Using device ffmpeg with libplacebo from: $FFMPEG_BIN"
    fi
fi

# 1c. If still not found, download the prebuilt binaries from the release DMG
if [[ -z "$FFMPEG_BIN" ]]; then
    echo "📥 No working ffmpeg with libplacebo found. Downloading from release..."
    mkdir -p "${VENDORED_TOOLS_DIR}"
    
    # Download DMG
    DMG_PATH="/tmp/Anime4K_Upscaler_download.dmg"
    curl -L -o "$DMG_PATH" "https://github.com/khr898/Anime4K-Upscalar-macOS/releases/download/v1.1.07042026/Anime4K_Upscaler_v1.1.07042026_arm64.dmg"
    
    # Mount DMG
    MNT_DIR="/tmp/mnt_anime4k_download"
    mkdir -p "$MNT_DIR"
    hdiutil attach "$DMG_PATH" -mountpoint "$MNT_DIR" -nobrowse -quiet
    
    # Extract
    cp -f "$MNT_DIR/Anime4K Upscaler.app/Contents/Frameworks/ffmpeg" "${VENDORED_FFMPEG}"
    cp -f "$MNT_DIR/Anime4K Upscaler.app/Contents/Frameworks/ffprobe" "${VENDORED_FFPROBE}"
    
    # Also extract the libplacebo that matches it to the vendored dylibs dir
    mkdir -p "${VENDORED_LIB_DIR}"
    cp -f "$MNT_DIR/Anime4K Upscaler.app/Contents/Frameworks/libplacebo.351.dylib" "${VENDORED_LIBPLACEBO}"
    
    # Detach and clean up
    hdiutil detach "$MNT_DIR" -quiet
    rm -rf "$MNT_DIR" "$DMG_PATH"
    
    chmod +x "${VENDORED_FFMPEG}" "${VENDORED_FFPROBE}"
    
    FFMPEG_BIN="$VENDORED_FFMPEG"
    FFPROBE_BIN="$VENDORED_FFPROBE"
    echo "✅ Downloaded and prepared vendored ffmpeg."
fi

echo "📦 Bundling ffmpeg from: $FFMPEG_BIN"
echo "📦 Bundling ffprobe from: $FFPROBE_BIN"

# Check libplacebo-backed ffmpeg using linkage checks
PLACEBO_ABI=$(otool -L "$FFMPEG_BIN" 2>/dev/null | sed -n 's/.*libplacebo\.\([0-9][0-9]*\)\.dylib.*/\1/p' | head -1)
if [[ -z "$PLACEBO_ABI" ]]; then
    if otool -L "$FFMPEG_BIN" 2>/dev/null | grep -q "libplacebo"; then
        PLACEBO_ABI="dylib"
    else
        echo "error: selected ffmpeg is not linked against libplacebo"
        exit 1
    fi
fi
echo "✅ Using libplacebo ABI/suffix: $PLACEBO_ABI"

# Verify if libplacebo is linked against libMoltenVK or if Vulkan support is present
if [[ "$FFMPEG_BIN" != "$VENDORED_FFMPEG" ]]; then
    if ! otool -L "$FFMPEG_BIN" 2>/dev/null | grep -qi "MoltenVK"; then
        echo "⚠️  Selected ffmpeg does not show direct MoltenVK linkage."
        # If Homebrew ffmpeg lacks Vulkan/MoltenVK support, build custom fallback
        if [[ "${BREW_FFMPEG_PREFIX:-}" != "" ]]; then
            echo "⚠️  Homebrew ffmpeg might lack Vulkan support. Attempting custom build fallback..."
            build_custom_ffmpeg
        fi
    fi
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
    local moltenvk_ref
    moltenvk_ref=$(otool -L "$binary" 2>/dev/null | awk 'NR>1 {print $1}' | grep "libMoltenVK" | head -1 || true)
    if [[ -n "$moltenvk_ref" ]]; then
        install_name_tool -change "$moltenvk_ref" "@executable_path/../Frameworks/libMoltenVK.dylib" "$binary" 2>/dev/null || true
    fi
}

relink_libplacebo_refs() {
    local binary="$1"
    local placebo_ref
    placebo_ref=$(otool -L "$binary" 2>/dev/null | awk 'NR>1 {print $1}' | grep "libplacebo" | head -1 || true)
    if [[ -n "$placebo_ref" ]]; then
        local placebo_name
        placebo_name=$(basename "$placebo_ref")
        install_name_tool -change "$placebo_ref" "@executable_path/../Frameworks/$placebo_name" "$binary" 2>/dev/null || true
    fi
}

copy_dylibs_recursive() {
    local binary="$1"
    local depth="${2:-0}"

    # Limit recursion depth to prevent runaway chains
    if (( depth > 12 )); then
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
            if [[ ! -f "$actual_path" ]]; then
                actual_path=$(resolve_rpath_dep "$dep_name" 2>/dev/null || true)
            fi
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
    local placebo_name
    placebo_name=$(basename "$VENDORED_LIBPLACEBO")
    cp -f "$VENDORED_LIBPLACEBO" "${FRAMEWORKS_DIR}/$placebo_name"
    chmod 644 "${FRAMEWORKS_DIR}/$placebo_name"
    install_name_tool -id "@executable_path/../Frameworks/$placebo_name" "${FRAMEWORKS_DIR}/$placebo_name" 2>/dev/null || true
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
        while IFS= read -r ref; do
            [[ -z "$ref" ]] && continue
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
                    if [[ ! -f "$actual" ]]; then
                        actual=$(resolve_rpath_dep "$ref_name" 2>/dev/null || true)
                    fi
                fi
                if [[ -n "$actual" && -f "$actual" ]]; then
                    echo "  📎 Pass $PASS: Copying $ref_name (needed by $local_dylib_name)"
                    cp -f "$actual" "${FRAMEWORKS_DIR}/${ref_name}"
                    chmod 644 "${FRAMEWORKS_DIR}/${ref_name}"
                    NEW_FOUND=true
                fi
            fi

            install_name_tool -change "$ref" "@executable_path/../Frameworks/${ref_name}" "$dylib" 2>/dev/null || true
        done <<< "$all_refs"
    done

    if [[ "$NEW_FOUND" == false ]]; then
        echo "  ✅ Converged after $PASS pass(es)"
        break
    fi

    if (( PASS > 8 )); then
        echo "  ⚠️  Exceeded 8 passes, stopping"
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

# --- 5b. BUNDLE REALESRGAN ---
REALESRGAN_BIN="${VENDORED_TOOLS_DIR}/realesrgan-ncnn-vulkan"

if [[ ! -x "$REALESRGAN_BIN" ]]; then
    echo "📥 realesrgan-ncnn-vulkan not found. Downloading..."
    mkdir -p "${VENDORED_TOOLS_DIR}"
    curl -L -o /tmp/realesrgan-macos.zip https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesrgan-ncnn-vulkan-20220424-macos.zip
    unzip -q /tmp/realesrgan-macos.zip -d /tmp/realesrgan-macos
    cp -f /tmp/realesrgan-macos/realesrgan-ncnn-vulkan "${REALESRGAN_BIN}"
    mkdir -p "${VENDORED_TOOLS_DIR}/models"
    cp -Rf /tmp/realesrgan-macos/models/* "${VENDORED_TOOLS_DIR}/models/"
    chmod +x "${REALESRGAN_BIN}"
    rm -rf /tmp/realesrgan-macos.zip /tmp/realesrgan-macos
fi

if [[ -f "$REALESRGAN_BIN" ]]; then
    echo "📦 Bundling realesrgan-ncnn-vulkan from: $REALESRGAN_BIN"
    cp -f "$REALESRGAN_BIN" "${RESOURCES_DIR}/realesrgan-ncnn-vulkan"
    chmod +x "${RESOURCES_DIR}/realesrgan-ncnn-vulkan"
    relink_moltenvk_refs "${RESOURCES_DIR}/realesrgan-ncnn-vulkan"
    
    echo "📦 Bundling realesrgan models..."
    mkdir -p "${RESOURCES_DIR}/models"
    cp -Rf "${VENDORED_TOOLS_DIR}/models/"* "${RESOURCES_DIR}/models/"
else
    echo "warning: realesrgan-ncnn-vulkan not found. ESRGAN modes will not work."
fi

# --- 5c. SETUP COREML MODELS ---
echo "📦 Setting up CoreML models..."
"${SRCROOT}/Anime4K-Upscaler/Scripts/download_models.sh"

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
    CO_ITEMS=("${FRAMEWORKS_DIR}/ffmpeg" "${FRAMEWORKS_DIR}/ffprobe" "${FRAMEWORKS_DIR}"/*.dylib)
    if [[ -f "${RESOURCES_DIR}/realesrgan-ncnn-vulkan" ]]; then
        CO_ITEMS+=("${RESOURCES_DIR}/realesrgan-ncnn-vulkan")
    fi
    for item in "${CO_ITEMS[@]}"; do
        [[ ! -f "$item" ]] && continue
        codesign --force --sign - --timestamp=none "$item" 2>/dev/null || true
        echo "  ✅ Signed: $(basename "$item")"
    done
fi

# --- 8. VERIFY ALL DYLIB REFERENCES ARE SELF-CONTAINED ---
echo "🔍 Verifying all dylib references are self-contained..."
UNRESOLVED=false
CHECK_ITEMS=("${FRAMEWORKS_DIR}/ffmpeg" "${FRAMEWORKS_DIR}/ffprobe" "${FRAMEWORKS_DIR}"/*.dylib)
if [[ -f "${RESOURCES_DIR}/realesrgan-ncnn-vulkan" ]]; then
    CHECK_ITEMS+=("${RESOURCES_DIR}/realesrgan-ncnn-vulkan")
fi

for item in "${CHECK_ITEMS[@]}"; do
    [[ ! -f "$item" ]] && continue
    EXTERNAL_REFS=$(otool -L "$item" 2>/dev/null | grep -v ':$' | awk 'NR>1 {gsub(/^[[:space:]]+/,""); print $1}' \
        | grep -v '^@executable_path' \
        | grep -v '^/usr/lib/' \
        | grep -v '^/System/' || true)
    if [[ -n "$EXTERNAL_REFS" ]]; then
        echo "  ❌ $(basename "$item") has unresolved external references:"
        echo "$EXTERNAL_REFS" | sed 's/^/      /'
        UNRESOLVED=true
    fi
done
if [[ "$UNRESOLVED" == "true" ]]; then
    echo "error: Unresolved dylib references found. The app will crash at runtime."
    exit 1
fi
echo "  ✅ All references are self-contained."

echo ""
echo "✅ Dependency bundling complete."
echo "   Frameworks: $(ls "${FRAMEWORKS_DIR}" | wc -l | tr -d ' ') items"
echo "   Shaders:    $(ls "${RESOURCES_DIR}/Shaders/"*.glsl 2>/dev/null | wc -l | tr -d ' ') files"
