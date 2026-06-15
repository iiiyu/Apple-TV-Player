#!/usr/bin/env python3
from __future__ import annotations

import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[2]
RAW_ROOT = ROOT / "AppleTVMultiplatformUITests/SnapshotUITests/App-Store/__Snapshots__/AppStoreSnapshotUITests"
OUTPUT_ROOT = ROOT / "AppStoreAssets/screenshots"

LOCALES = [
    "ar-SA",
    "de-DE",
    "en-US",
    "es-ES",
    "es-MX",
    "fr-FR",
    "hi",
    "id",
    "it",
    "ja",
    "ko",
    "pt-BR",
    "ru",
    "th",
    "tr",
    "vi",
    "zh-Hans",
]

HEADLINES = [
    ("Your playlists everywhere", "Private iCloud sync for iPhone, iPad, Mac, and Apple TV"),
    ("Add M3U in seconds", "Paste a playlist URL and start watching"),
    ("Organize large playlists", "Search, categories, favorites, and EPG"),
    ("Reliable playback options", "SGPlayer first with AVPlayer fallback"),
    ("Private by design", "PIN protection and no app account required"),
    ("Built for Apple screens", "A clean player experience across every device"),
]


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    candidates = [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/Supplemental/Helvetica.ttf",
    ]
    for candidate in candidates:
        path = Path(candidate)
        if path.exists():
            return ImageFont.truetype(str(path), size=size)
    return ImageFont.load_default()


def rounded_image(image: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", image.size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, image.width, image.height), radius=radius, fill=255)
    output = Image.new("RGBA", image.size)
    output.paste(image.convert("RGBA"), (0, 0), mask)
    return output


def gradient(size: tuple[int, int]) -> Image.Image:
    width, height = size
    top = (248, 250, 255)
    bottom = (228, 236, 246)
    img = Image.new("RGB", size)
    pixels = img.load()
    for y in range(height):
        ratio = y / max(height - 1, 1)
        color = tuple(int(top[i] * (1 - ratio) + bottom[i] * ratio) for i in range(3))
        for x in range(width):
            pixels[x, y] = color
    return img


def draw_centered_text(draw: ImageDraw.ImageDraw, xy: tuple[int, int], text: str, text_font: ImageFont.FreeTypeFont, fill: tuple[int, int, int], max_width: int) -> int:
    x, y = xy
    words = text.split()
    lines: list[str] = []
    current = ""
    for word in words:
        test = f"{current} {word}".strip()
        if draw.textbbox((0, 0), test, font=text_font)[2] <= max_width:
            current = test
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)

    line_gap = max(8, text_font.size // 5)
    for line in lines:
        bbox = draw.textbbox((0, 0), line, font=text_font)
        line_width = bbox[2] - bbox[0]
        draw.text((x - line_width / 2, y), line, font=text_font, fill=fill)
        y += text_font.size + line_gap
    return y


def compose(source: Path, destination: Path, index: int) -> None:
    screenshot = Image.open(source).convert("RGB")
    width, height = screenshot.size
    portrait = height > width
    canvas = gradient((width, height)).convert("RGBA")
    draw = ImageDraw.Draw(canvas)

    title, subtitle = HEADLINES[(index - 1) % len(HEADLINES)]
    title_size = max(56, int(width * (0.068 if portrait else 0.044)))
    subtitle_size = max(30, int(width * (0.034 if portrait else 0.022)))
    title_font = font(title_size, bold=True)
    subtitle_font = font(subtitle_size, bold=False)
    max_text_width = int(width * (0.84 if portrait else 0.78))
    text_y = int(height * (0.055 if portrait else 0.07))

    after_title = draw_centered_text(draw, (width // 2, text_y), title, title_font, (24, 30, 46), max_text_width)
    draw_centered_text(draw, (width // 2, after_title + int(height * 0.015)), subtitle, subtitle_font, (79, 88, 112), max_text_width)

    top_space = int(height * (0.22 if portrait else 0.27))
    bottom_margin = int(height * 0.045)
    max_w = int(width * (0.76 if portrait else 0.76))
    max_h = height - top_space - bottom_margin
    scale = min(max_w / screenshot.width, max_h / screenshot.height)
    target_size = (int(screenshot.width * scale), int(screenshot.height * scale))
    resized = screenshot.resize(target_size, Image.Resampling.LANCZOS)
    radius = max(32, int(min(target_size) * 0.045))
    card = rounded_image(resized, radius=radius)

    shadow = Image.new("RGBA", card.size, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle((0, 0, card.width, card.height), radius=radius, fill=(0, 0, 0, 80))
    shadow = shadow.filter(ImageFilter.GaussianBlur(max(18, int(width * 0.014))))

    x = (width - card.width) // 2
    y = min(top_space, height - card.height - bottom_margin)
    canvas.alpha_composite(shadow, (x, y + int(height * 0.012)))
    canvas.alpha_composite(card, (x, y))

    destination.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(destination, "PNG", optimize=True)


def raw_files(platform: str, kind: str) -> list[Path]:
    directory = RAW_ROOT / platform / "en-US"
    files = sorted(directory.glob("*.png"))
    if platform == "iOS" and kind == "iphone_67":
        return [path for path in files if "iPhone" in path.name]
    if platform == "iOS" and kind == "ipad_pro_3gen_129":
        return [path for path in files if "iPad" in path.name]
    if platform == "tvOS":
        return [path for path in files if "_26-4_" in path.name]
    return files


def build_set(platform: str, out_platform: str, kind: str) -> None:
    en_dir = OUTPUT_ROOT / out_platform / "en-US" / kind
    files = raw_files(platform, kind)
    for index, source in enumerate(files, start=1):
        destination = en_dir / f"{index:02d}-{kind}.png"
        compose(source, destination, index)

    for locale in LOCALES:
        if locale == "en-US":
            continue
        locale_dir = OUTPUT_ROOT / out_platform / locale / kind
        locale_dir.mkdir(parents=True, exist_ok=True)
        for image in sorted(en_dir.glob("*.png")):
            shutil.copy2(image, locale_dir / image.name)


def main() -> None:
    if OUTPUT_ROOT.exists():
        shutil.rmtree(OUTPUT_ROOT)
    build_set("iOS", "ios", "iphone_67")
    build_set("iOS", "ios", "ipad_pro_3gen_129")
    build_set("macOS", "macos", "desktop")
    build_set("tvOS", "tvos", "apple_tv")
    print(f"Wrote screenshots to {OUTPUT_ROOT}")


if __name__ == "__main__":
    main()
