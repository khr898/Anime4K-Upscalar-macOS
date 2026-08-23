"""Phase 2 decisive probe: does the config fix (TensorType+FP16+fixed shape)
put a LARGE model on ANE? RRDB 6B (~16M params) is well above the ~1M
Core ML scheduler threshold, so it is the clean test of whether the config
fix is sufficient for ANE-eligible models.

If RRDB -> ANE: config fix valid; animevideov3 CPU is the <1M-param threshold
(plan risk), not a config bug.
If RRDB -> CPU: config fix insufficient; deeper issue (op set / precision).

Convert at 256x256 for speed (placement test, not throughput).
"""
import os, sys, time, shutil
sys.path.insert(0, "/Volumes/My Shared Files/Windows Shared Folder/Anime4K-Upscalar/Anime4K-Upscaler/Scripts")
import convert_models as cm
import torch

REPO = "/Volumes/My Shared Files/Windows Shared Folder/Anime4K-Upscalar"
STAGING = os.path.join(REPO, ".claude/plans/models-v2/rrdb_probe")
os.makedirs(STAGING, exist_ok=True)
tmp = "/tmp/models_pth"
os.makedirs(tmp, exist_ok=True)

t0 = time.time()
def log(s): print(f"[{time.time()-t0:.1f}s] {s}", flush=True)

anime_pth = os.path.join(tmp, "RealESRGAN_x4plus_anime_6B.pth")
cm.download("https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.2.4/RealESRGAN_x4plus_anime_6B.pth", anime_pth)
m = cm.RRDBNet(scale=4, num_feat=64, num_block=6, num_grow_ch=32)
sd = torch.load(anime_pth, map_location='cpu')
sd = sd.get('params_ema', sd.get('params', sd))
m.load_state_dict(sd, strict=True)
log("loaded RRDB state_dict")
out = os.path.join(STAGING, "realesrgan-x4plus-anime.mlpackage")
cm.convert(m, out, H=256, W=256)
log("DONE")