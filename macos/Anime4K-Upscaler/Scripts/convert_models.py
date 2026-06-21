import os
import sys
import urllib.request
import torch
import torch.nn as nn
from torch.nn import functional as F
import coremltools as ct

# Define architectures

class ResidualDenseBlock(nn.Module):
    def __init__(self, num_feat=64, num_grow_ch=32, bias=True):
        super(ResidualDenseBlock, self).__init__()
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
        super(RRDB, self).__init__()
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
        super(RRDBNet, self).__init__()
        self.scale = scale
        self.conv_first = nn.Conv2d(num_in_ch, num_feat, 3, 1, 1)
        self.body = nn.Sequential(*[RRDB(num_feat, num_grow_ch) for _ in range(num_block)])
        self.conv_body = nn.Conv2d(num_feat, num_feat, 3, 1, 1)
        # upsample
        self.conv_up1 = nn.Conv2d(num_feat, num_feat, 3, 1, 1)
        self.conv_up2 = nn.Conv2d(num_feat, num_feat, 3, 1, 1)
        self.conv_hr = nn.Conv2d(num_feat, num_feat, 3, 1, 1)
        self.conv_last = nn.Conv2d(num_feat, num_out_ch, 3, 1, 1)
        self.lrelu = nn.LeakyReLU(negative_slope=0.2, inplace=True)

    def forward(self, x):
        feat = self.conv_first(x)
        body_feat = self.conv_body(self.body(feat))
        feat = feat + body_feat

        # upsample
        feat = self.lrelu(self.conv_up1(F.interpolate(feat, scale_factor=2, mode='nearest')))
        if self.scale == 4:
            feat = self.lrelu(self.conv_up2(F.interpolate(feat, scale_factor=2, mode='nearest')))
        out = self.conv_last(self.lrelu(self.conv_hr(feat)))
        return out

class SRVGGNetCompact(nn.Module):
    def __init__(self, num_in_ch=3, num_out_ch=3, num_feat=64, num_conv=18, upscale=4, act_type='prelu'):
        super(SRVGGNetCompact, self).__init__()
        self.num_in_ch = num_in_ch
        self.num_out_ch = num_out_ch
        self.num_feat = num_feat
        self.num_conv = num_conv
        self.upscale = upscale
        self.act_type = act_type

        self.body = nn.Sequential()
        # first conv
        self.body.add_module('0', nn.Conv2d(num_in_ch, num_feat, 3, 1, 1))
        if act_type == 'prelu':
            self.body.add_module('1', nn.PReLU(num_parameters=num_feat))
        elif act_type == 'leaky':
            self.body.add_module('1', nn.LeakyReLU(negative_slope=0.1, inplace=True))
        else:
            self.body.add_module('1', nn.ReLU(inplace=True))

        # middle convs
        for i in range(num_conv - 2):
            self.body.add_module(f'{2*i+2}', nn.Conv2d(num_feat, num_feat, 3, 1, 1))
            if act_type == 'prelu':
                self.body.add_module(f'{2*i+3}', nn.PReLU(num_parameters=num_feat))
            elif act_type == 'leaky':
                self.body.add_module(f'{2*i+3}', nn.LeakyReLU(negative_slope=0.1, inplace=True))
            else:
                self.body.add_module(f'{2*i+3}', nn.ReLU(inplace=True))

        # last conv
        self.body.add_module(f'{2*num_conv-2}', nn.Conv2d(num_feat, num_out_ch * upscale * upscale, 3, 1, 1))
        self.pixel_shuffle = nn.PixelShuffle(upscale)

    def forward(self, x):
        out = self.body(x)
        out = self.pixel_shuffle(out)
        # residual connection
        base = F.interpolate(x, scale_factor=self.upscale, mode='nearest')
        out += base
        return out

# Download weights helper
def download_file(url, path):
    if not os.path.exists(path):
        print(f"Downloading {url} to {path}...")
        urllib.request.urlretrieve(url, path)
    else:
        print(f"{path} already exists.")

# Main conversion logic
def main():
    if len(sys.argv) < 2:
        print("Usage: python convert_models.py <output_directory>")
        sys.exit(1)
        
    output_dir = sys.argv[1]
    os.makedirs(output_dir, exist_ok=True)
    
    tmp_pth_dir = "/tmp/models_pth"
    os.makedirs(tmp_pth_dir, exist_ok=True)
    
    # 1. realesrgan-x4plus-anime
    anime_pth_url = "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.2.4/RealESRGAN_x4plus_anime_6B.pth"
    anime_pth_path = os.path.join(tmp_pth_dir, "RealESRGAN_x4plus_anime_6B.pth")
    download_file(anime_pth_url, anime_pth_path)
    
    # Load model
    print("Loading realesrgan-x4plus-anime weight...")
    model_anime = RRDBNet(num_in_ch=3, num_out_ch=3, scale=4, num_feat=64, num_block=6, num_grow_ch=32)
    state_dict = torch.load(anime_pth_path, map_location=torch.device('cpu'))
    if 'params' in state_dict:
        state_dict = state_dict['params']
    elif 'params_ema' in state_dict:
        state_dict = state_dict['params_ema']
    model_anime.load_state_dict(state_dict, strict=True)
    model_anime.eval()
    
    # 2. realesr-animevideov3
    video_pth_url = "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesr-animevideov3.pth"
    video_pth_path = os.path.join(tmp_pth_dir, "realesr-animevideov3.pth")
    download_file(video_pth_url, video_pth_path)
    
    # Load model
    print("Loading realesr-animevideov3 weight...")
    model_video = SRVGGNetCompact(num_in_ch=3, num_out_ch=3, num_feat=64, num_conv=18, upscale=4, act_type='prelu')
    state_dict = torch.load(video_pth_path, map_location=torch.device('cpu'))
    if 'params' in state_dict:
        state_dict = state_dict['params']
    model_video.load_state_dict(state_dict, strict=True)
    model_video.eval()
    
    # Define CoreML input shapes (enumerated shapes matching CoreMLUpscaler.swift)
    shape_range = ct.EnumeratedShapes(
        shapes=[
            [1, 3, 90, 160],
            [1, 3, 135, 240],
            [1, 3, 270, 480],
        ]
    )
    
    # Convert realesrgan-x4plus-anime
    print("Converting realesrgan-x4plus-anime to CoreML...")
    example_input = torch.rand(1, 3, 90, 160)
    traced_anime = torch.jit.trace(model_anime, example_input)
    
    mlmodel_anime = ct.convert(
        traced_anime,
        inputs=[ct.ImageType(name="input", shape=shape_range, scale=1.0/255.0, color_layout=ct.colorlayout.RGB)],
        outputs=[ct.ImageType(name="output", color_layout=ct.colorlayout.RGB)],
        convert_to="mlprogram"
    )
    anime_output_path = os.path.join(output_dir, "realesrgan-x4plus-anime.mlpackage")
    mlmodel_anime.save(anime_output_path)
    print(f"Saved to {anime_output_path}")
    
    # Convert realesr-animevideov3
    print("Converting realesr-animevideov3 to CoreML...")
    traced_video = torch.jit.trace(model_video, example_input)
    
    mlmodel_video = ct.convert(
        traced_video,
        inputs=[ct.ImageType(name="input", shape=shape_range, scale=1.0/255.0, color_layout=ct.colorlayout.RGB)],
        outputs=[ct.ImageType(name="output", color_layout=ct.colorlayout.RGB)],
        convert_to="mlprogram"
    )
    video_output_path = os.path.join(output_dir, "realesr-animevideov3.mlpackage")
    mlmodel_video.save(video_output_path)
    print(f"Saved to {video_output_path}")

if __name__ == "__main__":
    main()
