#!/bin/zsh
set -euo pipefail

# =============================================================================
#  Anime4K Upscaler — Dependency Bundling Script
#  Locates, copies, rewires, and codesigns ffmpeg + all dylibs + shaders
# =============================================================================

FRAMEWORKS_DIR="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}"
RESOURCES_DIR="${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
SHADERS_SRC="${SRCROOT}/Anime4K-Upscaler/Resources/Shaders"
VENDORED_TOOLS_DIR="${SRCROOT}/Anime4K-Upscaler/Resources/VendoredTools"

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

# --- 0. ENSURE libplacebo + MoltenVK + libdav1d are latest (Homebrew) ---
# libplacebo 360.0 had an intermittent color-patch bug in custom_shader
# dispatch, fixed in 360.1. MoltenVK must be latest for matching Vulkan
# behavior. libdav1d (Homebrew formula `dav1d`) is the software AV1 decoder
# the from-source ffmpeg is configured with (--enable-libdav1d). Install if
# missing and UPGRADE every build so the bottles stay current — permanent,
# not a one-off. Not pinned: `brew upgrade` pulls the latest stable.
# libplacebo is sourced from Homebrew only (the vendored libplacebo.351.dylib
# is removed from the repo).
#
# CRITICAL: the dylib refresh in copy_dylibs_recursive relies on this step
# actually pulling the newest bottles — if `brew upgrade` is skipped, the
# bundled libplacebo stays at the old (color-patch) version even though the
# copy-refresh re-copies it, because the source it copies from is still old.
if command -v brew >/dev/null 2>&1; then
    echo "🍺 Ensuring libplacebo + molten-vk + dav1d are latest via Homebrew..."
    brew install libplacebo molten-vk dav1d 2>/dev/null || true
    brew upgrade libplacebo molten-vk dav1d 2>/dev/null || true
    LP_VER=$(brew list --versions libplacebo 2>/dev/null | awk '{print $2}')
    MVK_VER=$(brew list --versions molten-vk 2>/dev/null | awk '{print $2}')
    DAV1D_VER=$(brew list --versions dav1d 2>/dev/null | awk '{print $2}')
    echo "   libplacebo: $LP_VER"
    echo "   molten-vk:  $MVK_VER"
    echo "   dav1d:      $DAV1D_VER"

    # Strict version assertion: libplacebo must be >= 7.360.1 (fixes color patch bug)
    if [[ -n "$LP_VER" ]]; then
        # Check if version starts with 7.360.0 (or below 7.360.1)
        if [[ "$LP_VER" == 7.360.0* || "$LP_VER" == [0-6].* || "$LP_VER" == 7.[0-3][0-5][0-9].* ]]; then
            echo "error: libplacebo version $LP_VER is below required minimum 7.360.1 (color patch bug present)."
            exit 1
        fi
        echo "   ✅ libplacebo version $LP_VER meets >= 7.360.1 requirement."
    fi

    # Strict version assertion: molten-vk must be >= 1.4.2
    if [[ -n "$MVK_VER" ]]; then
        if [[ "$MVK_VER" == 1.[0-3].* || "$MVK_VER" == 1.4.[0-1] || "$MVK_VER" == 0.* ]]; then
            echo "error: molten-vk version $MVK_VER is below required minimum 1.4.2."
            exit 1
        fi
        echo "   ✅ molten-vk version $MVK_VER meets >= 1.4.2 requirement."
    fi
fi

build_custom_ffmpeg() {
    echo "🛠️  Building custom FFmpeg 9 with Vulkan, libplacebo (>=7.360.1), and libdav1d..."
    temp_build_dir="${SRCROOT}/ffmpeg_build"
    mkdir -p "$temp_build_dir"
    cd "$temp_build_dir"

    if [[ ! -d "ffmpeg" ]]; then
        git clone --depth 1 https://git.ffmpeg.org/ffmpeg.git ffmpeg
    else
        cd ffmpeg
        GIT_CONFIG_GLOBAL=/dev/null git pull --ff-only 2>/dev/null || true
        cd ..
    fi
    cd ffmpeg

    # --enable-libplacebo: compiles against the Homebrew libplacebo (>=7.360.1)
    # headers so the binary and the shipped dylib share one ABI (360). The 360.0
    # color-patch bug in custom_shader dispatch is fixed in 360.1.
    # --enable-libdav1d: software AV1 decoder (fallback for devices without AV1
    # VideoToolbox decode — Intel / M1 / M2). The native `av1` decoder is
    # hardware-only, so without libdav1d AV1 sources decode to zero frames and
    # the Special (Core ML) pipeline fails. VideoToolbox AV1 hwaccel is also
    # compiled in (autodetected on macOS) for Apple Silicon that supports it.
    ./configure \
        --prefix="${temp_build_dir}/dist" \
        --enable-vulkan \
        --enable-libplacebo \
        --enable-libdav1d \
        --enable-gpl \
        --enable-nonfree \
        --disable-shared \
        --enable-static
    # Build only the executables. `make install` (and a full `make`) fail on the
    # libavfilter.a static-archive step (metal filter objects), but the ffmpeg/
    # ffprobe binaries link the object files directly and build cleanly — and
    # the bundler only needs the binaries, not the static archives.
    make -j$(sysctl -n hw.ncpu) ffmpeg ffprobe

    FFMPEG_BIN="${temp_build_dir}/ffmpeg/ffmpeg"
    FFPROBE_BIN="${temp_build_dir}/ffmpeg/ffprobe"
    cd "${SRCROOT}"
}

# --- 1. BUILD FFMPEG + FFPROBE (against Homebrew libplacebo >=7.360.1) ---
# Always build from source so the binary is compiled against the latest
# libplacebo headers — the shipped dylib and the binary then share one ABI
# (360). The vendored libplacebo.351.dylib is removed; vendored/DMG/prebuilt
# ffmpegs ship unknown libplacebo ABIs (351 vs 360 mismatch caused the
# intermittent color patches) and are no longer used. `build_custom_ffmpeg`
# is idempotent: clones only if absent, `make` is a no-op if already built.
build_custom_ffmpeg

if [[ ! -x "$FFMPEG_BIN" || ! -x "$FFPROBE_BIN" ]]; then
    echo "error: custom ffmpeg build did not produce binaries at $FFMPEG_BIN"
    exit 1
fi

echo "📦 Bundling ffmpeg from: $FFMPEG_BIN"
echo "📦 Bundling ffprobe from: $FFPROBE_BIN"

# Sanity: built ffmpeg must link libplacebo (not pinned to a version —
# `brew upgrade` in Step 0 keeps it at latest stable, currently 7.360.1).
PLACEBO_ABI=$(otool -L "$FFMPEG_BIN" 2>/dev/null | sed -n 's/.*libplacebo\.\([0-9][0-9]*\)\.dylib.*/\1/p' | head -1)
if [[ -z "$PLACEBO_ABI" ]]; then
    if otool -L "$FFMPEG_BIN" 2>/dev/null | grep -q "libplacebo"; then
        PLACEBO_ABI="dylib"
    else
        echo "error: built ffmpeg is not linked against libplacebo."
        exit 1
    fi
fi
echo "✅ Built ffmpeg links libplacebo.$PLACEBO_ABI"

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

# Search paths for resolving @rpath references
SEARCH_LIB_DIRS=(
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

    # Get ALL non-system dependencies: /opt/homebrew, /usr/local, @rpath, AND
    # @executable_path/../Frameworks/ refs on a pre-rewrapped vendored binary
    # (e.g. the release-DMG ffmpeg whose xcb deps were never extracted to
    # VendoredTools). Those refs point at files that may not exist in this
    # fresh FRAMEWORKS_DIR yet — resolve them from Homebrew by basename below.
    local all_refs
    all_refs=$(otool -L "$binary" 2>/dev/null | awk 'NR>1 {gsub(/^[[:space:]]+/, ""); print $1}' | grep -E '^(/opt/homebrew|/usr/local|@rpath/|@executable_path/\.\./Frameworks/)' || true)

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

        # Refresh from Homebrew when the source bottle differs from what's
        # bundled — a `brew upgrade` (Step 0) to a newer libplacebo/MoltenVK
        # bottle MUST actually replace the bundled dylib. The previous
        # `! -f "$dest"` guard copied each dylib ONCE and never refreshed, so a
        # libplacebo 360.0→360.1 upgrade (360.0 had the custom_shader
        # color-patch bug, fixed in 360.1) never reached the bundle and the
        # stale 360.0 dylib shipped indefinitely → persistent color patches.
        # `cmp -s` on the raw Homebrew source vs the bundled (relinked) copy
        # returns "differ" whenever the source changed OR the dest was relinked
        # — either way we re-copy and let step 4 re-fix install names/refs (it
        # already runs on every dylib each build). Cheap: short-circuits on the
        # first differing byte. Recurse so a newer bottle's transitive deps are
        # pulled too.
        if [[ -z "$actual_path" || ! -f "$actual_path" ]]; then
            echo "  ⚠️  Skipping (not found): $dep_name"
        elif [[ ! -f "$dest" ]] || ! cmp -s "$actual_path" "$dest" 2>/dev/null; then
            if [[ ! -f "$dest" ]]; then
                echo "  📎 Copying: $dep_name"
            else
                echo "  🔄 Refreshing (Homebrew upgrade): $dep_name"
            fi
            cp -f "$actual_path" "$dest"
            chmod 644 "$dest"
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

        # Fix all references within this dylib — homebrew paths, @rpath, AND
        # @executable_path/../Frameworks/ refs inherited from vendored binaries.
        all_refs=$(otool -L "$dylib" | awk 'NR>1 {gsub(/^[[:space:]]+/,""); print $1}' | grep -E '^(/opt/homebrew|/usr/local|@rpath/|@executable_path/\.\./Frameworks/)' || true)
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
    echo "error: libMoltenVK.dylib was not bundled. The app would not be self-contained."
    exit 1
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
    copy_dylibs_recursive "${RESOURCES_DIR}/realesrgan-ncnn-vulkan"
    if ! lipo -archs "${RESOURCES_DIR}/realesrgan-ncnn-vulkan" 2>/dev/null | grep -q arm64; then
        echo "error: realesrgan-ncnn-vulkan lacks an arm64 slice."
        exit 1
    fi

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

# --- 8b. FUNCTIONAL SMOKE TEST ---
# otool only sees link-time deps; a reference that was never rewritten (dep
# not found at bundle time) still leaves a launchable-looking bundle. Execute
# the bundled binaries with a clean environment (no Homebrew fallback) so any
# dyld failure fails the BUILD instead of shipping as a phantom
# "cancelled by user" on user machines (exactly how v1.1.07042026 shipped
# without libav*).
echo "🔍 Functional smoke test of bundled binaries..."
if ! env -i PATH=/usr/bin:/bin "${FRAMEWORKS_DIR}/ffmpeg" -version >/dev/null 2>&1; then
    echo "error: bundled ffmpeg failed to launch in a clean environment (dyld problem):"
    env -i PATH=/usr/bin:/bin "${FRAMEWORKS_DIR}/ffmpeg" -version 2>&1 | head -5 || true
    exit 1
fi
if ! env -i PATH=/usr/bin:/bin "${FRAMEWORKS_DIR}/ffprobe" -version >/dev/null 2>&1; then
    echo "error: bundled ffprobe failed to launch in a clean environment (dyld problem)."
    exit 1
fi
if [[ -f "${RESOURCES_DIR}/realesrgan-ncnn-vulkan" ]]; then
    # realesrgan exits non-zero on -h; only dyld failures print "Library not loaded"
    if env -i PATH=/usr/bin:/bin "${RESOURCES_DIR}/realesrgan-ncnn-vulkan" -h 2>&1 | grep -q "Library not loaded"; then
        echo "error: bundled realesrgan-ncnn-vulkan failed to launch (dyld problem)."
        exit 1
    fi
fi
echo "  ✅ Bundled binaries launch cleanly."

echo ""
echo "✅ Dependency bundling complete."
echo "   Frameworks: $(ls "${FRAMEWORKS_DIR}" | wc -l | tr -d ' ') items"
echo "   Shaders:    $(ls "${RESOURCES_DIR}/Shaders/"*.glsl 2>/dev/null | wc -l | tr -d ' ') files"
