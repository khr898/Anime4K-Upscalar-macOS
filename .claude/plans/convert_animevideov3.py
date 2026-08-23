import sys, os, time
sys.path.insert(0, os.path.join(os.path.dirname(__file__) or ".", "..", "Anime4K-Upscaler", "Scripts"))
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
log(f"converting at 1080x1920 -> {out}")
cm.convert(m, out, H=1080, W=1920)
log("DONE")