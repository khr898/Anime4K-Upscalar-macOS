"""Phase 2 probe: convert animevideov3 at a SMALL fixed shape (256x256) to
validate the conversion config (TensorType out + FP16 + CPU_AND_NE + macOS14)
produces 0 CPU fallback, before scaling to full-frame 1080p.

RED gate: MLComputePlanAudit on the OLD models showed 100% CPU (Phase 1).
GREEN gate: same audit on this reconverted model shows 0 CPU ops.

Reuses convert_models.convert() so the config under test is identical to the
production conversion path.
"""
import sys, os, time
sys.path.insert(0, "/Volumes/My Shared Files/Windows Shared Folder/Anime4K-Upscalar/Anime4K-Upscaler/Scripts")
import convert_models as cm
import torch

t0 = time.time()
def log(s): print(f"[{time.time()-t0:.1f}s] {s}", flush=True)

tmp = "/tmp/models_pth"
os.makedirs(tmp, exist_ok=True)
video_pth = os.path.join(tmp, "realesr-animevideov3.pth")
log("downloading animevideov3 weights")
cm.download("https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesr-animevideov3.pth", video_pth)
log("building SRVGGNetCompact upscale=4")
m = cm.SRVGGNetCompact(num_feat=64, num_conv=18, upscale=4, act_type='prelu')
sd = torch.load(video_pth, map_location='cpu')
sd = sd.get('params', sd)
m.load_state_dict(sd, strict=True)
log("loaded state_dict")
out = "/Volumes/My Shared Files/Windows Shared Folder/Anime4K-Upscalar/.claude/plans/models-v2/realesr-animevideov3.mlpackage"
log("converting at 256x256 -> models-v2")
cm.convert(m, out, H=256, W=256)
log("DONE")