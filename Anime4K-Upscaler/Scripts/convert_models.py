"""
Corrected Real-ESRGAN -> CoreML conversion.

Root fix vs. the original convert_models.py:
  * The original used ct.ImageType OUTPUT together with EnumeratedShapes INPUT.
    CoreML cannot resolve a concrete output image size for a flexible input, so
    the saved mlprogram has an undefined (1x1) output image constraint and
    CRASHES in libBNNS at inference on every compute unit.
  * Fix: use a SINGLE FIXED input tile shape (like the working PiperSR model),
    and wrap the network so its [0,1] float output is scaled to the 0-255 range
    an RGB image output expects (clamped). Concrete input -> concrete output ->
    no crash.

Tile size 256x256 matches CoreMLUpscaler's tiling loop (it crops/pads to the
model's single enumerated size).

Phase 2 (special-pipeline-fps-fix) changes:
  * Keep OUTPUT as ct.ImageType. The original crash was ImageType output +
    EnumeratedShapes (flexible) INPUT — CoreML couldn't resolve a concrete
    output size. With a SINGLE FIXED input shape, ImageType output resolves
    concretely and is safe (the old bundled 256x256 models are ImageType out
    and work). TensorType output was considered (plan Appendix A) to let Swift
    skip the image wrap, but it would force a Phase 3 MLMultiArray→CVPixelBuffer
    path in CoreMLUpscaler — not worth it when fixed-shape ImageType already
    works. The fps win comes from the full-frame SHAPE, not the I/O type.
  * Force compute_precision=FLOAT16 — FP32 bars ANE (no FP32 units). Default
    precision can leak FP32 into conv/activation tails and force CPU placement
    (Phase 1 VM audit showed 0 ANE ops; bare-metal baseline confirmed ANE
    placement with only the ImageWrapper mul+cast tail on CPU — 2 ops).
  * Parameterize input shape (H, W). BARE-METAL FINDING (Phase 2): the win is
    NOT fewer tiles — it is fitting the ANE SRAM. A feature map of input^2 x
    channels x 2B must stay under ~32MB or CoreML silently falls back to CPU
    (the MLComputePlan audit shows static ANE placement; runtime dispatch is
    separate). 540x540x64ch = 37MB -> CPU -> 1.5fps (SLOWER than the 1.9fps
    full-frame CPU baseline). 256x256x64ch = 8.4MB fits -> ANE. Revert to 256,
    confirm the ANE fps jump on metal, THEN bump tile size toward the SRAM
    ceiling to cut dispatch count. RRDB concat hits 192ch so it stays at 256
    (256^2 x 192ch x 2B = 25MB).
  * Keep ImageWrapper clamp*255 (the mul+cast tail — 2 CPU-fallback ops on
    metal, acceptable).
  * Keep activations as-is (PReLU/LeakyReLU). Bare-metal MLComputePlan showed
    ios17.prelu / ios17.leaky_relu place on ANE (not CPU) on real hardware, so
    the Phase 7 PReLU->SiLU swap is unnecessary on this metal. Only the
    ImageWrapper mul+cast tail remains on CPU.
"""
import os, sys, urllib.request
import torch
import torch.nn as nn
from torch.nn import functional as F
import coremltools as ct

TILE = 256  # legacy default fixed square input tile (H=W)


class ResidualDenseBlock(nn.Module):
    def __init__(self, num_feat=64, num_grow_ch=32, bias=True):
        super().__init__()
        self.conv1 = nn.Conv2d(num_feat, num_grow_ch, 3, 1, 1, bias=bias)
        self.conv2 = nn.Conv2d(num_feat + num_grow_ch, num_grow_ch, 3, 1, 1, bias=bias)
        self.conv3 = nn.Conv2d(num_feat + 2 * num_grow_ch, num_grow_ch, 3, 1, 1, bias=bias)
        self.conv4 = nn.Conv2d(num_feat + 3 * num_grow_ch, num_grow_ch, 3, 1, 1, bias=bias)
        self.conv5 = nn.Conv2d(num_feat + 4 * num_grow_ch, num_feat, 3, 1, 1, bias=bias)
        self.lrelu = nn.LeakyReLU(negative_slope=0.2, inplace=True)

    def forward(self, x):
        x1 = self.lrelu(self.conv1(x))
        x2 = self.lrelu(self.conv2(torch.cat((x, x1), 1)))
        x3 = self.lrelu(self.conv3(torch.cat((x, x1, x2), 1)))
        x4 = self.lrelu(self.conv4(torch.cat((x, x1, x2, x3), 1)))
        x5 = self.conv5(torch.cat((x, x1, x2, x3, x4), 1))
        return x5 * 0.2 + x


class RRDB(nn.Module):
    def __init__(self, num_feat=64, num_grow_ch=32, bias=True):
        super().__init__()
        self.rdb1 = ResidualDenseBlock(num_feat, num_grow_ch, bias=bias)
        self.rdb2 = ResidualDenseBlock(num_feat, num_grow_ch, bias=bias)
        self.rdb3 = ResidualDenseBlock(num_feat, num_grow_ch, bias=bias)

    def forward(self, x):
        out = self.rdb1(x)
        out = self.rdb2(out)
        out = self.rdb3(out)
        return out * 0.2 + x


class RRDBNet(nn.Module):
    def __init__(self, num_in_ch=3, num_out_ch=3, scale=4, num_feat=64, num_block=6, num_grow_ch=32):
        super().__init__()
        self.scale = scale
        self.conv_first = nn.Conv2d(num_in_ch, num_feat, 3, 1, 1)
        self.body = nn.Sequential(*[RRDB(num_feat, num_grow_ch) for _ in range(num_block)])
        self.conv_body = nn.Conv2d(num_feat, num_feat, 3, 1, 1)
        self.conv_up1 = nn.Conv2d(num_feat, num_feat, 3, 1, 1)
        self.conv_up2 = nn.Conv2d(num_feat, num_feat, 3, 1, 1)
        self.conv_hr = nn.Conv2d(num_feat, num_feat, 3, 1, 1)
        self.conv_last = nn.Conv2d(num_feat, num_out_ch, 3, 1, 1)
        self.lrelu = nn.LeakyReLU(negative_slope=0.2, inplace=True)

    def forward(self, x):
        feat = self.conv_first(x)
        body_feat = self.conv_body(self.body(feat))
        feat = feat + body_feat
        feat = self.lrelu(self.conv_up1(F.interpolate(feat, scale_factor=2, mode='nearest')))
        if self.scale == 4:
            feat = self.lrelu(self.conv_up2(F.interpolate(feat, scale_factor=2, mode='nearest')))
        out = self.conv_last(self.lrelu(self.conv_hr(feat)))
        return out


class SRVGGNetCompact(nn.Module):
    def __init__(self, num_in_ch=3, num_out_ch=3, num_feat=64, num_conv=18, upscale=4, act_type='prelu'):
        super().__init__()
        self.upscale = upscale
        self.body = nn.Sequential()
        self.body.add_module('0', nn.Conv2d(num_in_ch, num_feat, 3, 1, 1))
        self.body.add_module('1', nn.PReLU(num_parameters=num_feat))
        for i in range(num_conv - 2):
            self.body.add_module(f'{2*i+2}', nn.Conv2d(num_feat, num_feat, 3, 1, 1))
            self.body.add_module(f'{2*i+3}', nn.PReLU(num_parameters=num_feat))
        self.body.add_module(f'{2*num_conv-2}', nn.Conv2d(num_feat, num_out_ch * upscale * upscale, 3, 1, 1))
        self.pixel_shuffle = nn.PixelShuffle(upscale)

    def forward(self, x):
        out = self.body(x)
        out = self.pixel_shuffle(out)
        base = F.interpolate(x, scale_factor=self.upscale, mode='nearest')
        out += base
        return out


class ImageWrapper(nn.Module):
    """Scale the network's ~[0,1] float output to the 0-255 range an RGB image
    output expects, and clamp. This bakes the de-normalization into the graph so
    the CoreML output is a valid image (no post-scaling needed in Swift)."""
    def __init__(self, net):
        super().__init__()
        self.net = net

    def forward(self, x):
        y = self.net(x)
        return torch.clamp(y, 0.0, 1.0) * 255.0


def download(url, path):
    if not os.path.exists(path):
        print(f"downloading {url}")
        urllib.request.urlretrieve(url, path)


def convert(net, out_path, H=TILE, W=TILE):
    # Resumable: skip if already converted (delete the .mlpackage to force).
    if os.path.exists(out_path):
        print(f"skip {out_path} (exists)")
        return
    net.eval()
    wrapped = ImageWrapper(net).eval()
    example = torch.rand(1, 3, H, W)
    traced = torch.jit.trace(wrapped, example)
    # scale=1/255 turns the 0-255 image input into the 0-1 tensor the net wants.
    # ImageType output + FIXED input shape: concrete output size resolves, no
    # libBNNS crash (the crash was ImageType out + flexible/EnumeratedShapes in).
    # Swift gets a CVPixelBuffer back from prediction — no tensor conversion.
    mlmodel = ct.convert(
        traced,
        inputs=[ct.ImageType(name="input", shape=(1, 3, H, W),
                             scale=1.0 / 255.0, color_layout=ct.colorlayout.RGB)],
        outputs=[ct.ImageType(name="output", color_layout=ct.colorlayout.RGB)],
        convert_to="mlprogram",
        compute_units=ct.ComputeUnit.CPU_AND_NE,
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.macOS14,
    )
    if os.path.exists(out_path):
        import shutil
        shutil.rmtree(out_path)
    mlmodel.save(out_path)
    print(f"saved {out_path} ({H}x{W})")


def main():
    out_dir = sys.argv[1]
    tmp = "/tmp/models_pth"
    os.makedirs(tmp, exist_ok=True)

    anime_pth = os.path.join(tmp, "RealESRGAN_x4plus_anime_6B.pth")
    download("https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.2.4/RealESRGAN_x4plus_anime_6B.pth", anime_pth)
    m = RRDBNet(scale=4, num_feat=64, num_block=6, num_grow_ch=32)
    sd = torch.load(anime_pth, map_location='cpu')
    sd = sd.get('params_ema', sd.get('params', sd))
    m.load_state_dict(sd, strict=True)
    # RRDB concat feature maps hit 192ch (64 + 4x32 grow). M3 Pro ANE shared SRAM
    # is 16MB (NOT 32 — that was M4 Max per Orion/SlugWiki). 540x540x192ch x2B =
    # 112MB, 256x256x192ch = 25MB, both overflow -> silent CPU fallback (measured
    # 1.9->1.5fps drop). 128x128x192ch x2B = 6.3MB (+8.7MB weights +intermediates)
    # is the best fit at the 16MB ceiling; per-operand streaming handles the
    # >2MB single-tensor limit. 128^2 is also the proven pipersr ANE size. RRDB
    # is the "quality" preset (slow/offline) so more tiles is acceptable.
    convert(m, os.path.join(out_dir, "realesrgan-x4plus-anime.mlpackage"), H=128, W=128)

    video_pth = os.path.join(tmp, "realesr-animevideov3.pth")
    download("https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesr-animevideov3.pth", video_pth)
    m = SRVGGNetCompact(num_feat=64, num_conv=18, upscale=4, act_type='prelu')
    sd = torch.load(video_pth, map_location='cpu')
    sd = sd.get('params', sd)
    m.load_state_dict(sd, strict=True)
    # SRVGGNetCompact, 64ch throughout (no concat). M3 Pro ANE shared SRAM = 16MB.
    # 540x540x64ch x2B = 37MB -> CPU fallback (measured 1.5fps, SLOWER than the
    # 1.9fps full-frame CPU baseline because 12 CPU tiles + overlap > 1 CPU tile).
    # 256x256x64ch = 8.4MB x3 live intermediates = 25MB > 16MB -> still spills.
    # 192x192x64ch = 4.7MB x3 = 14MB < 16MB -> FITS, ANE-resident. 192^2 is the
    # M3 Pro sweet spot (per-operand 2MB limit -> 128^2 is fully resident but
    # 4x more tiles; 192^2 balances tile count vs SRAM at the 16MB ceiling).
    convert(m, os.path.join(out_dir, "realesr-animevideov3.mlpackage"), H=192, W=192)


if __name__ == "__main__":
    main()
