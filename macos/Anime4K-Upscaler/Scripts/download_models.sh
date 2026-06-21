#!/bin/zsh
# =============================================================================
#  Anime4K Upscaler — CoreML Model Setup Script
#  Downloads PiperSR and converts Real-ESRGAN models to CoreML
# =============================================================================
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
RESOURCES_DIR="${SCRIPTS_DIR}/../Resources"
MODELS_DIR="${RESOURCES_DIR}/Models"

mkdir -p "${MODELS_DIR}"

# --- 1. DOWNLOAD PIPERSR ---
PIPERSR_DIR="${MODELS_DIR}/pipersr.mlpackage"
if [[ ! -d "$PIPERSR_DIR" ]]; then
    echo "📥 PiperSR model not found. Downloading from Hugging Face..."
    mkdir -p "${PIPERSR_DIR}/Data/com.apple.CoreML/weights"
    
    curl -L -o "${PIPERSR_DIR}/Manifest.json" \
        "https://huggingface.co/ModelPiper/PiperSR-2x/resolve/main/PiperSR_2x.mlpackage/Manifest.json"
        
    curl -L -o "${PIPERSR_DIR}/Data/com.apple.CoreML/model.mlmodel" \
        "https://huggingface.co/ModelPiper/PiperSR-2x/resolve/main/PiperSR_2x.mlpackage/Data/com.apple.CoreML/model.mlmodel"
        
    curl -L -o "${PIPERSR_DIR}/Data/com.apple.CoreML/weights/weight.bin" \
        "https://huggingface.co/ModelPiper/PiperSR-2x/resolve/main/PiperSR_2x.mlpackage/Data/com.apple.CoreML/weights/weight.bin"
        
    echo "✅ PiperSR model setup complete."
else
    echo "✓ PiperSR model already exists."
fi

# --- 2. CONVERT REAL-ESRGAN MODELS ---
REALESRGAN_ANIME="${MODELS_DIR}/realesrgan-x4plus-anime.mlpackage"
REALESRGAN_VIDEO="${MODELS_DIR}/realesr-animevideov3.mlpackage"

if [[ ! -d "$REALESRGAN_ANIME" || ! -d "$REALESRGAN_VIDEO" ]]; then
    echo "🛠️ Real-ESRGAN CoreML models not found. Preparing conversion environment..."
    
    # Locate a python3.12 (preferred due to coremltools compatibility) or python3
    PYTHON_EXE=""
    if command -v python3.12 >/dev/null 2>&1; then
        PYTHON_EXE=$(command -v python3.12)
    elif command -v python3 >/dev/null 2>&1; then
        PYTHON_EXE=$(command -v python3)
    fi
    
    if [[ -z "$PYTHON_EXE" ]]; then
        echo "error: python3 is required for model conversion."
        exit 1
    fi
    
    echo "Using python: $PYTHON_EXE"
    VENV_DIR="/tmp/venv_models_setup"
    if [[ ! -d "$VENV_DIR" ]]; then
        "$PYTHON_EXE" -m venv "$VENV_DIR"
    fi
    
    echo "Installing conversion dependencies (torch, coremltools)..."
    "$VENV_DIR/bin/pip" install torch torchvision coremltools urllib3 --quiet
    
    echo "Running model conversion script..."
    "$VENV_DIR/bin/python" "${SCRIPTS_DIR}/convert_models.py" "${MODELS_DIR}"
    
    echo "✅ Real-ESRGAN CoreML models conversion complete."
else
    echo "✓ Real-ESRGAN CoreML models already exist."
fi
