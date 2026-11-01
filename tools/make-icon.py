"""
生成「拾漫」应用图标：蓝紫渐变圆角底 + 白色对话气泡 + 一行橙色高亮。

选型过程：先后试过「三层卡片」「摊开的书」，在 96px 下都读不出是漫画 App
（书页被看成两张卡片）。对话气泡是漫画的通用符号，剪影最稳，小尺寸也不糊。
全部程序化绘制，无外部素材；3 倍超采样后降采样。
"""
import os
from PIL import Image, ImageDraw, ImageFilter

S, SS = 1024, 3
W = S * SS
TOP = (0x41, 0x7B, 0xFF)
BOTTOM = (0x6B, 0x5C, 0xE8)
GLOW = (0x9C, 0xC0, 0xFF)
PAPER = (0xFF, 0xFF, 0xFF)
LINE = (0xC9, 0xD8, 0xFB)
ACCENT = (0xFF, 0xC1, 0x6B)


def gradient(size):
    small = 192
    img = Image.new('RGB', (small, small))
    px = img.load()
    for y in range(small):
        for x in range(small):
            t = (x / small) * 0.42 + (y / small) * 0.58
            px[x, y] = (int(TOP[0] + (BOTTOM[0] - TOP[0]) * t),
                        int(TOP[1] + (BOTTOM[1] - TOP[1]) * t),
                        int(TOP[2] + (BOTTOM[2] - TOP[2]) * t))
    return img.resize(size, Image.BICUBIC)


def round_mask(size, radius):
    m = Image.new('L', size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255)
    return m


def main():
    base = gradient((W, W)).convert('RGBA')
    glow = Image.new('L', (W, W), 0)
    ImageDraw.Draw(glow).ellipse([-int(W * .30), -int(W * .42), int(W * .80), int(W * .60)], fill=255)
    glow = glow.filter(ImageFilter.GaussianBlur(W // 7)).point(lambda v: int(v * 0.30))
    base = Image.composite(Image.new('RGBA', (W, W), GLOW + (255,)), base, glow)

    cx = W // 2
    bw, bh = int(W * 0.62), int(W * 0.455)
    x0, x1 = cx - bw // 2, cx + bw // 2
    y0 = int(W * 0.245)
    y1 = y0 + bh
    r = int(W * 0.10)

    bubble = Image.new('RGBA', (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(bubble)
    d.rounded_rectangle([x0, y0, x1, y1], radius=r, fill=PAPER + (255,))
    # 尾巴：左下角伸出的小三角，带圆角感
    tail = Image.new('L', (W, W), 0)
    ImageDraw.Draw(tail).polygon([
        (x0 + int(bw * 0.15), y1 - int(bh * 0.16)),
        (x0 + int(bw * 0.38), y1 - int(bh * 0.16)),
        (x0 + int(bw * 0.20), y1 + int(bh * 0.28)),
    ], fill=255)
    tail = tail.filter(ImageFilter.GaussianBlur(int(W * 0.016))).point(lambda v: 255 if v > 118 else 0)
    bubble.paste(Image.new('RGBA', (W, W), PAPER + (255,)), (0, 0), tail)

    # 气泡里两行文字
    lines = Image.new('RGBA', (W, W), (0, 0, 0, 0))
    ld = ImageDraw.Draw(lines)
    h = int(W * 0.026)
    # 明确写死每条的长度占气泡宽度的比例：短、中、短（橙色高亮）
    spans = [(0.27, 0.30, LINE), (0.485, 0.50, LINE), (0.70, 0.26, ACCENT)]
    left = x0 + int(bw * 0.13)
    for frac, width, color in spans:
        y = y0 + int(bh * frac)
        ld.rounded_rectangle([left, y, left + int(bw * width), y + h],
                             radius=h // 2, fill=color + (255,))

    out = Image.alpha_composite(base, bubble)
    out = Image.alpha_composite(out, lines)

    final = Image.new('RGBA', (W, W), (0, 0, 0, 0))
    final.paste(out, (0, 0), round_mask((W, W), int(W * 0.225)))
    return final.resize((S, S), Image.LANCZOS)


if __name__ == '__main__':
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
    img = main()
    for rel in ['app/AppScope/resources/base/media/app_icon.png',
                'app/entry/src/main/resources/base/media/app_icon.png',
                'app/entry/src/main/resources/base/media/startIcon.png']:
        p = os.path.join(root, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        img.save(p)
        print('written', p, os.path.getsize(p), 'bytes')
    img.resize((256, 256), Image.LANCZOS).save(os.path.join(root, 'tools', 'icon-preview-256.png'))
    img.resize((96, 96), Image.LANCZOS).save(os.path.join(root, 'tools', 'icon-preview-96.png'))
    print('previews saved')
