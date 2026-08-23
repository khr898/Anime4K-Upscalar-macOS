"""Phase 2 lever test: TensorType INPUT (not ImageType).

Hypothesis: ImageType input (uint8 image + scale=1/255) inserts a cast/
normalize op that taints the graph and forces conv onto CPU. ModelPiper uses
pure tensor I/O. Switching input to TensorType(float16) may remove the taint
and let conv place on ANE.

Tests animevideov3 @256 (small, fast) and RRDB @256 (large) with:
  - TensorType float16 input (1,3,H,W), no scale
  - TensorType float16 output
  - CPU_AND_NE, FLOAT16, macOS14

ImageWrapper clamp*255 is kept (output 0-255 range) — Swift converts tensor
to CVPixelBuffer (Phase 3). Input is now 0-255 float16 tensor; the net's own
normalize (divide by 255) must be baked into the graph since we removed the
ImageType scale. So wrap input: x/255 before net.
"""
import os, sys, time, shutil
sys.path.insert(0, "/Volumes/My Shared Files/Windows Shared Folder/Anime4K-Upscalar/Anime4K-Upscaler/Scripts")
import convert_models as cm
import coremltools as ct
import torch
import torch.nn as nn
import numpy as np

REPO = "/Volumes/My Shared Files/Windows Shared Folder/Anime4K-Upscalar"
tmp = "/tmp/models_pth"
os.makedirs(tmp, exist_ok=True)

t0 = time.time()
def log(s): print(f"[{time.time()-t0:.1f}s] {s}", flush=True)


class TensorInputWrapper(nn.Module):
    """Input is a 0-255 float16 tensor. Divide by 255 to get 0-1 for the net,
    then ImageWrapper clamps+ scales output back to 0-255."""
    def __init__(self, net):
        super().__init__()
        self.net = net

    def forward(self, x):
        y = self.net(x / 255.0)
        return torch.clamp(y, 0.0, 1.0) * 255.0


def convert_tensorio(net, out_path, H, W):
    net.eval()
    wrapped = TensorInputWrapper(net).eval()
    example = torch.rand(1, 3, H, W) * 255.0
    traced = torch.jit.trace(wrapped, example)
    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="input", shape=(1, 3, H, W), dtype=np.float16)],
        outputs=[ct.TensorType(name="output", dtype=np.float16)],
        convert_to="mlprogram",
        compute_units=ct.ComputeUnit.CPU_AND_NE,
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.macOS14,
    )
    if os.path.exists(out_path):
        shutil.rmtree(out_path)
    mlmodel.save(out_path)
    log(f"saved {out_path} ({H}x{W}) tensorIO")


# animevideov3
video_pth = os.path.join(tmp, "realesr-animevideov3.pth")
cm.download("https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesr-animevideov3.pth", video_pth)
m = cm.SRVGGNetCompact(num_feat=64, num_conv=18, upscale=4, act_type='prelu')
sd = torch.load(video_pth, map_location='cpu')
sd = sd.get('params', sd)
m.load_state_dict(sd, strict=True)
out = os.path.join(REPO, ".claude/plans/models-v2/tensorio_animevideov3/realesr-animevideov3.mlpackage")
os.makedirs(os.path.dirname(out), exist_ok=True)
convert_tensorio(m, out, 256, 256)

# RRDB
anime_pth = os.path.join(tmp, "RealESRGAN_x4plus_anime_6B.pth")
cm.download("https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.2.4/RealESRGAN_x4plus_anime_6B.pth", anime_pth)
m = cm.RRDBNet(scale=4, num_feat=64, num_block=6, num_grow_ch=32)
sd = torch.load(anime_pth, map_location='cpu')
sd = sd.get('params_ema', sd.get('params', sd))
m.load_state_dict(sd, strict=True)
out = os.path.join(REPO, ".claude/plans/models-v2/tensorio_rrdb/realesrgan-x4plus-anime.mlpackage")
os.makedirs(os.path.dirname(out), exist_ok=True)
convert_tensorio(m, out, 256, 256)
log("ALL DONE")