#!/usr/bin/env python3
"""
App Store screenshot composer for 三秒·记一笔
Produces Apple-style marketing screenshots for 6.7" (iPhone 16 Plus) and 6.9" (iPhone 16 Pro Max) slots.
"""

from PIL import Image, ImageDraw, ImageFilter, ImageFont
import os, math

# ── Paths ─────────────────────────────────────────────────────────────────────
SRC  = "/Users/ansel_li/Documents/Claude/SanJiao-iOS/Design/预览/"
OUT  = "/Users/ansel_li/Documents/Claude/SanJiao-iOS/Design/AppStore截图/"
PINGFANG = "/System/Library/AssetsV2/com_apple_MobileAsset_Font8/86ba2c91f017a3749571a82f2c6d890ac7ffb2fb.asset/AssetData/PingFang.ttc"

# PingFang SC indices
PF_SEMIBOLD = 11
PF_MEDIUM   = 7
PF_REGULAR  = 3
PF_LIGHT    = 15

os.makedirs(OUT, exist_ok=True)

# ── Brand palette ──────────────────────────────────────────────────────────────
# 晴空蓝渐变：深湖蓝 → 晴空蓝 → 浅天蓝
GRAD_TOP    = (38,  98, 210)   # #2662D2  深湖蓝
GRAD_MID    = (55, 125, 238)   # #377DEE  晴空蓝
GRAD_BOT    = (90, 162, 255)   # #5AA2FF  浅天蓝
ACCENT      = (107, 184, 255)  # #6BB8FF
ACCENT_GLOW = (61, 142, 240, 75)  # semi-transparent glow
WHITE       = (255, 255, 255)
WHITE_70    = (255, 255, 255, 178)  # 70% opacity
WHITE_50    = (255, 255, 255, 128)
WHITE_40    = (255, 255, 255, 102)

# ── Screen configs ─────────────────────────────────────────────────────────────
# (headline, subline, badge_text)
SCREENS = [
    {
        "key":   "01_首页",
        "plus":  "首页今日支出 - iPhone 16 Plus - 2026-04-27 at 15.45.37.png",
        "s17":   "首页今日支出- iPhone 17 - 2026-04-27 at 14.47.32.png",
        "h1":    "3 秒，记完一笔",
        "h2":    "比打开备忘录还快",
        "badge": "极速记账",
    },
    {
        "key":   "02_账单",
        "plus":  "账单页 - iPhone 16 Plus - 2026-04-27 at 15.45.43.png",
        "s17":   "账单页 - iPhone 17 - 2026-04-27 at 14.48.50.png",
        "h1":    "每一笔，清清楚楚",
        "h2":    "收支结余，一眼掌控",
        "badge": "账单总览",
    },
    {
        "key":   "03_月度统计",
        "plus":  "月度统计 - iPhone 16 Plus - 2026-04-27 at 15.45.48.png",
        "s17":   "月度账单 - iPhone 17 - 2026-04-27 at 14.47.56.png",
        "h1":    "钱花在哪里？",
        "h2":    "支出分布，一图看懂",
        "badge": "月度分析",
    },
    {
        "key":   "04_年度统计",
        "plus":  "年度统计 - iPhone 16 Plus - 2026-04-27 at 15.45.52.png",
        "s17":   "年度账单 - iPhone 17 - 2026-04-27 at 14.48.06.png",
        "h1":    "一整年，攒了多少",
        "h2":    "年度结余 · 储蓄率 · 消费亮点",
        "badge": "年度报告",
    },
    {
        "key":   "05_导入",
        "plus":  "微信支付宝导入 - iPhone 16 Plus - 2026-04-27 at 15.45.56.png",
        "s17":   "微信支付宝导入 - iPhone 17 - 2026-04-27 at 14.49.17.png",
        "h1":    "历史账单，一键导入",
        "h2":    "微信支付 · 支付宝 · 轻账备份",
        "badge": "智能导入",
    },
]

# ── Helpers ────────────────────────────────────────────────────────────────────

def font(size, weight=PF_SEMIBOLD):
    return ImageFont.truetype(PINGFANG, size, index=weight)

def make_gradient(w, h):
    """3-stop vertical gradient: GRAD_TOP → GRAD_MID → GRAD_BOT"""
    img = Image.new("RGB", (w, h))
    draw = ImageDraw.Draw(img)
    mid_y = int(h * 0.42)
    for y in range(h):
        if y <= mid_y:
            t = y / mid_y
            r = int(GRAD_TOP[0] + (GRAD_MID[0]-GRAD_TOP[0]) * t)
            g = int(GRAD_TOP[1] + (GRAD_MID[1]-GRAD_TOP[1]) * t)
            b = int(GRAD_TOP[2] + (GRAD_MID[2]-GRAD_TOP[2]) * t)
        else:
            t = (y - mid_y) / (h - mid_y)
            r = int(GRAD_MID[0] + (GRAD_BOT[0]-GRAD_MID[0]) * t)
            g = int(GRAD_MID[1] + (GRAD_BOT[1]-GRAD_MID[1]) * t)
            b = int(GRAD_MID[2] + (GRAD_BOT[2]-GRAD_MID[2]) * t)
        draw.line([(0, y), (w, y)], fill=(r, g, b))
    return img

def add_glow(canvas, cx, cy, radius, color_rgba):
    """Radial glow (soft circle) drawn on an RGBA overlay."""
    glow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(glow)
    steps = 24
    r, g, b, a = color_rgba
    for i in range(steps):
        ratio = 1 - i / steps
        cur_r = int(radius * (1 - i / steps * 0.9))
        cur_a = int(a * ratio * ratio)
        d.ellipse([cx - cur_r, cy - cur_r, cx + cur_r, cy + cur_r],
                  fill=(r, g, b, cur_a))
    glow = glow.filter(ImageFilter.GaussianBlur(radius // 6))
    return Image.alpha_composite(canvas.convert("RGBA"), glow)

def round_corners(img, radius):
    """Apply rounded corners to an image."""
    mask = Image.new("L", img.size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([0, 0, img.width - 1, img.height - 1],
                            radius=radius, fill=255)
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out

def draw_shadow(canvas_rgba, x, y, w, h, radius=40, strength=120):
    """Draw a soft drop shadow behind a region."""
    shadow_layer = Image.new("RGBA", canvas_rgba.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow_layer)
    sd.rounded_rectangle(
        [x + 10, y + 20, x + w - 10, y + h + 30],
        radius=radius, fill=(0, 0, 0, strength)
    )
    shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(28))
    return Image.alpha_composite(canvas_rgba, shadow_layer)

def centered_text(draw, text, y, fnt, fill=(255,255,255), canvas_w=1290):
    bb = fnt.getbbox(text)
    text_w = bb[2] - bb[0]
    x = (canvas_w - text_w) // 2
    draw.text((x, y - bb[1]), text, font=fnt, fill=fill)
    return bb[3] - bb[1]  # return actual text height

def draw_badge(canvas_rgba, text, cy, fnt, canvas_w):
    """Pill-shaped badge with accent border."""
    tmp = Image.new("RGBA", canvas_rgba.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(tmp)
    bb = fnt.getbbox(text)
    tw = bb[2] - bb[0]
    th = bb[3] - bb[1]
    pad_x, pad_y = 28, 14
    pill_w = tw + pad_x * 2
    pill_h = th + pad_y * 2
    x0 = (canvas_w - pill_w) // 2
    y0 = cy
    # Pill background: white at 18% opacity
    d.rounded_rectangle([x0, y0, x0 + pill_w, y0 + pill_h],
                         radius=pill_h // 2, fill=(255, 255, 255, 46))
    # Pill border: white 50% opacity
    d.rounded_rectangle([x0, y0, x0 + pill_w, y0 + pill_h],
                         radius=pill_h // 2, outline=(255, 255, 255, 160), width=2)
    # Text: white 85%
    tx = x0 + pad_x - bb[0]
    ty = y0 + pad_y - bb[1]
    d.text((tx, ty), text, font=fnt, fill=(255, 255, 255, 217))
    return Image.alpha_composite(canvas_rgba, tmp), y0 + pill_h

def compose(screen, w, h, src_key, device_suffix):
    """
    Build one App Store screenshot.
    Layout (proportions tuned for both device sizes):
      ┌─────────────────────────────┐
      │   [badge]   y ≈ 8%          │
      │   [H1]      y ≈ 13%         │
      │   [H2]      y ≈ 23%         │
      │                             │
      │   ╔═══════════════════╗     │
      │   ║   app screenshot  ║     │  ← 68% width, rounded corners
      │   ║                   ║     │
      │   ╚═══════════════════╝     │
      └─────────────────────────────┘
    """
    # 1. Gradient background
    bg = make_gradient(w, h).convert("RGBA")

    # 2. Subtle decorative glow behind where screenshot will sit
    glow_cy = int(h * 0.64)
    bg = add_glow(bg, w // 2, glow_cy, int(w * 0.68), (90, 78, 200, 60))

    # 3. Typography
    draw = ImageDraw.Draw(bg)

    badge_size  = max(30, int(w * 0.034))
    h1_size     = max(72, int(w * 0.088))
    h2_size     = max(44, int(w * 0.054))

    badge_fnt = font(badge_size, PF_MEDIUM)
    h1_fnt    = font(h1_size,   PF_SEMIBOLD)
    h2_fnt    = font(h2_size,   PF_LIGHT)

    badge_y  = int(h * 0.075)
    bg, badge_bottom = draw_badge(bg, screen["badge"], badge_y, badge_fnt, w)
    draw = ImageDraw.Draw(bg)  # redraw after alpha_composite

    h1_y = badge_bottom + int(h * 0.022)
    h1_h = centered_text(draw, screen["h1"], h1_y, h1_fnt, canvas_w=w)

    h2_y = h1_y + h1_h + int(h * 0.018)
    centered_text(draw, screen["h2"], h2_y, h2_fnt,
                  fill=(235, 232, 255, 200), canvas_w=w)

    # 4. Load + scale app screenshot
    shot_path = SRC + screen[src_key]
    shot = Image.open(shot_path).convert("RGBA")

    # Scale to 68% of canvas width, preserve aspect ratio
    scr_w = int(w * 0.68)
    scr_h = int(scr_w * shot.height / shot.width)
    shot = shot.resize((scr_w, scr_h), Image.LANCZOS)

    # Apply rounded corners matching iPhone display radius (~12% of width)
    corner_r = int(scr_w * 0.10)
    shot = round_corners(shot, corner_r)

    # Position: horizontally centered, vertical start at 29% of canvas
    scr_x = (w - scr_w) // 2
    scr_y = int(h * 0.290)

    # 5. Drop shadow
    bg = draw_shadow(bg, scr_x, scr_y, scr_w, scr_h,
                     radius=corner_r, strength=130)

    # 6. Paste screenshot
    bg.paste(shot, (scr_x, scr_y), shot)

    # 7. Save
    fname = f"{screen['key']}_{device_suffix}.png"
    out_path = OUT + fname
    bg.convert("RGB").save(out_path, "PNG", optimize=True)
    print(f"  ✓ {fname}  ({w}×{h})")

# ── Main ───────────────────────────────────────────────────────────────────────

print("Composing App Store screenshots …\n")
for screen in SCREENS:
    print(f"[{screen['key']}]")
    # Both sizes use iPhone 17 source screenshots (1206×2622)
    # The compose() function scales the source to fit any canvas size
    compose(screen, 1290, 2796, "s17", "6.7in_1290x2796")   # App Store 6.7" slot
    compose(screen, 1320, 2868, "s17", "6.9in_1320x2868")   # App Store 6.9" slot

print("\nDone! Files saved to:", OUT)
