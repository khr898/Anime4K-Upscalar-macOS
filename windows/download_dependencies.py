import os
import sys
import urllib.request
import zipfile
import shutil
import tempfile
import subprocess
import json

X64_URL = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip"
REALESRGAN_URL = "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesrgan-ncnn-vulkan-20220424-windows.zip"

def get_latest_arm64_url():
    url = "https://api.github.com/repos/tordona/ffmpeg-win-arm64/releases/latest"
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    try:
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read().decode())
            for asset in data['assets']:
                name = asset['name']
                if name.endswith("essentials-static-win-arm64.7z"):
                    return asset['browser_download_url']
    except Exception as e:
        print(f"Error fetching latest ARM64 release from GitHub API: {e}", file=sys.stderr)
        
    # Fallback tag URL if API limit is exceeded or fails
    return "https://github.com/tordona/ffmpeg-win-arm64/releases/download/latest-autobuild-2026.06.03.0/ffmpeg-master-latest-essentials-static-win-arm64.7z"

def download_file(url, filepath):
    print(f"Downloading from {url}...")
    headers = {'User-Agent': 'Mozilla/5.0'}
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req) as response, open(filepath, 'wb') as out_file:
        shutil.copyfileobj(response, out_file)

def extract_archive(filepath, extract_dir):
    print(f"Extracting {filepath}...")
    os.makedirs(extract_dir, exist_ok=True)
    if filepath.endswith(".zip"):
        with zipfile.ZipFile(filepath, 'r') as zip_ref:
            zip_ref.extractall(extract_dir)
    elif filepath.endswith(".7z"):
        try:
            subprocess.run(["tar", "-xf", filepath, "-C", extract_dir], check=True)
        except Exception as e:
            print(f"Error extracting 7z with tar: {e}. Trying to invoke 7z directly.", file=sys.stderr)
            # Fallback if 7z command-line is in PATH
            subprocess.run(["7z", "x", filepath, f"-o{extract_dir}", "-y"], check=True)

def process_architecture(url, archive_ext, target_dir):
    with tempfile.TemporaryDirectory() as tmpdir:
        archive_path = os.path.join(tmpdir, f"archive{archive_ext}")
        download_file(url, archive_path)
        
        extract_dir = os.path.join(tmpdir, "extracted")
        extract_archive(archive_path, extract_dir)
        
        # Locate ffmpeg.exe and ffprobe.exe recursively
        os.makedirs(target_dir, exist_ok=True)
        found_ffmpeg = False
        found_ffprobe = False
        for root, dirs, files in os.walk(extract_dir):
            for file in files:
                if file.lower() == "ffmpeg.exe":
                    shutil.copy2(os.path.join(root, file), os.path.join(target_dir, "ffmpeg.exe"))
                    found_ffmpeg = True
                elif file.lower() == "ffprobe.exe":
                    shutil.copy2(os.path.join(root, file), os.path.join(target_dir, "ffprobe.exe"))
                    found_ffprobe = True
                    
        if found_ffmpeg and found_ffprobe:
            print(f"Successfully placed ffmpeg.exe and ffprobe.exe in {target_dir}")
        else:
            print(f"Error: Could not find ffmpeg.exe/ffprobe.exe in the extracted folder.", file=sys.stderr)
            sys.exit(1)

def process_realesrgan(target_dir):
    print(f"Downloading Real-ESRGAN from {REALESRGAN_URL}...")
    with tempfile.TemporaryDirectory() as tmpdir:
        archive_path = os.path.join(tmpdir, "realesrgan.zip")
        download_file(REALESRGAN_URL, archive_path)
        
        extract_dir = os.path.join(tmpdir, "extracted")
        extract_archive(archive_path, extract_dir)
        
        # We need to find realesrgan-ncnn-vulkan.exe (models are tracked in Git)
        found_exe = False
        found_models = True
        for root, dirs, files in os.walk(extract_dir):
            for file in files:
                if file.lower() == "realesrgan-ncnn-vulkan.exe":
                    shutil.copy2(os.path.join(root, file), os.path.join(target_dir, "realesrgan-ncnn-vulkan.exe"))
                    found_exe = True
            # Models are now tracked in Git, so we comment out the copying code to prevent overwrites:
            # if "models" in dirs:
            #     src_models = os.path.join(root, "models")
            #     dest_models = os.path.join(target_dir, "models")
            #     if os.path.exists(dest_models):
            #         shutil.rmtree(dest_models)
            #     shutil.copytree(src_models, dest_models)
            #     found_models = True
                
        if found_exe and found_models:
            print(f"Successfully placed realesrgan-ncnn-vulkan.exe in {target_dir}")
        else:
            print(f"Error: Could not find realesrgan-ncnn-vulkan.exe in extracted files.", file=sys.stderr)
            sys.exit(1)

def main():
    base_dir = os.path.dirname(os.path.abspath(__file__))
    vendor_dir = os.path.join(base_dir, "vendor")
    
    x64_target = os.path.join(vendor_dir, "x64")
    arm64_target = os.path.join(vendor_dir, "arm64")
    
    print("--- DOWNLOADING X64 DEPENDENCIES ---")
    process_architecture(X64_URL, ".zip", x64_target)
    process_realesrgan(x64_target)
    
    print("\n--- DOWNLOADING ARM64 DEPENDENCIES ---")
    arm64_url = get_latest_arm64_url()
    process_architecture(arm64_url, ".7z", arm64_target)
    process_realesrgan(arm64_target)
    
    print("\nDone! All dependencies downloaded and verified.")

if __name__ == "__main__":
    main()
