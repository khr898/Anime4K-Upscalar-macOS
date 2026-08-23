"""Phase 2 placement probe: at 256x256, test which levers move conv/prelu off CPU.

Levers (plan Research Appendix A + D):
  - deployment target: macOS14 (ios17 ops) vs macOS15 (ios18) vs iOS26 (newest)
  - activation: PReLU (stock) vs SiLU (M3 LUT-native, plan Phase 7)

Each variant converted into its own staging subdir so MLComputePlanAudit can
scan them independently via MODELS_DIR.

Quality note: SiLU swap without fine-tune changes output — this probe tests
PLACEMENT only. Quality is a Phase 6/8 gate.
"""
import os, sys, time, shutil
sys.path.insert(0, "/Volumes/My Shared Files/Windows Shared Folder/Anime4K-Upscalar/Anime4K-Upscaler/Scripts")
import convert_models as cm
import coremltools as ct
import torch
import torch.nn as nn
from torch.nn import functional as F

REPO = "/Volumes/My Shared Files/Windows Shared Folder/Anime4K-Upscalar"
STAGING = os.path.join(REPO, ".claude/plans/models-v2")
tmp = "/tmp/models_pth"
os.makedirs(tmp, exist_ok=True)

t0 = time.time()
def log(s): print(f"[{time.time()-t0:.1f}s] {s}", flush=True)

video_pth = os.path.join(tmp, "realesr-animevideov3.pth")
cm.download("https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesr-animevideov3.pth", video_pth)


def build_net(silu=False):
    m = cm.SRVGGNetCompact(num_feat=64, num_conv=18, upscale=4, act_type='prelu')
    sd = torch.load(video_pth, map_location='cpu')
    sd = sd.get('params', sd)
    m.load_state_dict(sd, strict=True)
    if silu:
        # Swap PReLU -> SiLU (placement probe only; not quality-preserving).
        new_body = nn.Sequential()
        for name, mod in m.body.named_children():
            if isinstance(mod, nn.PReLU):
                new_body.add_module(name, nn.SiLU())
            else:
                new_body.add_module(name, mod)
        m.body = new_body
    m.eval()
    return m


def convert_variant(net, out_path, H, W, target):
    wrapped = cm.ImageWrapper(net).eval()
    example = torch.rand(1, 3, H, W)
    traced = torch.jit.trace(wrapped, example)
    mlmodel = ct.convert(
        traced,
        inputs=[ct.ImageType(name="input", shape=(1, 3, H, W),
                             scale=1.0 / 255.0, color_layout=ct.colorlayout.RGB)],
        outputs=[ct.TensorType(name="output", dtype=__import__('numpy').float16)],
        convert_to="mlprogram",
        compute_units=ct.ComputeUnit.CPU_AND_NE,
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=target,
    )
    if os.path.exists(out_path):
        shutil.rmtree(out_path)
    mlmodel.save(out_path)
    log(f"saved {out_path} ({H}x{W}) target={target}")


VARIANTS = [
    ("macOS15_prelu",   False, ct.target.macOS15),
    ("iOS26_prelu",     False, ct.target.iOS26),
    ("macOS14_silu",    True,  ct.target.macOS14),
    ("macOS15_silu",    True,  ct.target.macOS15),
    ("iOS26_silu",      True,  ct.target.iOS26),
]

for name, silu, target in VARIANTS:
    log(f"=== variant {name} silu={silu} ===")
    net = build_net(silu=silu)
    out_dir = os.path.join(STAGING, name)
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, "realesr-animevideov3.mlpackage")
    convert_variant(net, out, 256, 256, target)
log("ALL DONE")