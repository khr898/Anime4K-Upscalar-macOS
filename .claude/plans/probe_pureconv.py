"""Phase 2 diagnostic: minimal pure-conv net to calibrate MLComputePlan.

If a trivial 3-conv FP16 net places conv on ANE -> the SR models' non-conv ops
(pixel_shuffle, upsample_nearest_neighbor, clip, mul tail) taint the graph and
force CPU. If pure conv also CPU -> MLComputePlan/.cpuAndNeuralEngine or the
audit itself is the issue (and ModelPiper's 44fps ANE claim would imply
MLComputePlan is conservative vs runtime).
"""
import os, sys, shutil
sys.path.insert(0, "/Volumes/My Shared Files/Windows Shared Folder/Anime4K-Upscalar/Anime4K-Upscaler/Scripts")
import coremltools as ct
import torch
import torch.nn as nn
import numpy as np

REPO = "/Volumes/My Shared Files/Windows Shared Folder/Anime4K-Upscalar"
OUT = os.path.join(REPO, ".claude/plans/models-v2/pureconv/realesr-animevideov3.mlpackage")
os.makedirs(os.path.dirname(OUT), exist_ok=True)


class PureConv(nn.Module):
    def __init__(self):
        super().__init__()
        self.c1 = nn.Conv2d(3, 16, 3, 1, 1)
        self.c2 = nn.Conv2d(16, 16, 3, 1, 1)
        self.c3 = nn.Conv2d(16, 3, 3, 1, 1)
    def forward(self, x):
        return self.c3(torch.relu(self.c2(torch.relu(self.c1(x)))))

m = PureConv().eval()
example = torch.rand(1, 3, 256, 256)
traced = torch.jit.trace(m, example)
mlmodel = ct.convert(
    traced,
    inputs=[ct.TensorType(name="input", shape=(1, 3, 256, 256), dtype=np.float16)],
    outputs=[ct.TensorType(name="output", dtype=np.float16)],
    convert_to="mlprogram",
    compute_units=ct.ComputeUnit.CPU_AND_NE,
    compute_precision=ct.precision.FLOAT16,
    minimum_deployment_target=ct.target.macOS14,
)
if os.path.exists(OUT):
    shutil.rmtree(OUT)
mlmodel.save(OUT)
print("saved pureconv")