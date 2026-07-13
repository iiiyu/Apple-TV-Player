#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import subprocess
import tempfile
import unicodedata

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[2]
RAW_ROOT = ROOT / "AppleTVMultiplatformUITests/SnapshotUITests/App-Store/__Snapshots__/AppStoreSnapshotUITests"
OUTPUT_ROOT = ROOT / "AppStoreAssets/screenshots"
APP_ICON = ROOT / "AppleTVMultiplatform/Resources/Assets.xcassets/AppIcon.appiconset/ios-appicon-1024.png"

LOCALES = [
    "ar-SA", "de-DE", "en-US", "es-ES", "es-MX", "fr-FR", "hi", "id",
    "it", "ja", "ko", "pt-BR", "ru", "th", "tr", "vi", "zh-Hans",
]

COPY = {
    "ar-SA": {
        "library": "تلفزيونك منظم بأناقة",
        "add": "أضف قائمة تشغيل خلال ثوانٍ",
        "browse": "اعثر على القناة بسرعة",
        "watch": "بث مباشر سلس مع دليل البرامج",
        "theme": "مظهر فاتح وداكن",
        "control": "خصوصية وتحكم مدمجان",
    },
    "de-DE": {
        "library": "Dein TV. Perfekt organisiert",
        "add": "Playlists in Sekunden hinzufügen",
        "browse": "Kanäle schneller finden",
        "watch": "Live-TV mit EPG genießen",
        "theme": "Für Hell- und Dunkelmodus",
        "control": "Privatsphäre und Kontrolle",
    },
    "en-US": {
        "library": "Your TV. Beautifully organised.",
        "add": "Add any playlist in seconds",
        "browse": "Find the channel you want, fast",
        "watch": "Smooth live TV with EPG",
        "theme": "Made for light and dark",
        "control": "Privacy and control, built in",
    },
    "es-ES": {
        "library": "Tu TV, perfectamente organizada",
        "add": "Añade playlists en segundos",
        "browse": "Encuentra canales al instante",
        "watch": "TV en directo con EPG",
        "theme": "Diseñada para claro y oscuro",
        "control": "Privacidad y control incluidos",
    },
    "es-MX": {
        "library": "Tu TV, perfectamente organizada",
        "add": "Agrega playlists en segundos",
        "browse": "Encuentra canales al instante",
        "watch": "TV en vivo con EPG",
        "theme": "Diseñada para claro y oscuro",
        "control": "Privacidad y control incluidos",
    },
    "fr-FR": {
        "library": "Toute votre TV, bien organisée",
        "add": "Ajoutez une playlist en quelques secondes",
        "browse": "Trouvez vos chaînes en un instant",
        "watch": "TV en direct avec EPG",
        "theme": "Clair ou sombre, à votre goût",
        "control": "Confidentialité et contrôle",
    },
    "hi": {
        "library": "आपका टीवी, खूबसूरती से व्यवस्थित",
        "add": "सेकंड में प्लेलिस्ट जोड़ें",
        "browse": "मनचाहा चैनल तुरंत खोजें",
        "watch": "EPG के साथ सहज लाइव टीवी",
        "theme": "लाइट और डार्क, दोनों में शानदार",
        "control": "निजता और नियंत्रण, अंदर ही",
    },
    "id": {
        "library": "TV Anda, tertata sempurna",
        "add": "Tambah playlist dalam hitungan detik",
        "browse": "Temukan saluran dengan cepat",
        "watch": "TV langsung lancar dengan EPG",
        "theme": "Nyaman dalam mode terang dan gelap",
        "control": "Privasi dan kendali bawaan",
    },
    "it": {
        "library": "La tua TV, sempre in ordine",
        "add": "Aggiungi playlist in pochi secondi",
        "browse": "Trova subito il canale",
        "watch": "TV in diretta con EPG",
        "theme": "Perfetta in chiaro e scuro",
        "control": "Privacy e controllo integrati",
    },
    "ja": {
        "library": "テレビを美しく整理",
        "add": "プレイリストを数秒で追加",
        "browse": "見たいチャンネルがすぐ見つかる",
        "watch": "EPG対応の快適なライブ視聴",
        "theme": "ライトもダークも美しく",
        "control": "プライバシーと操作性を両立",
    },
    "ko": {
        "library": "TV를 깔끔하게 한곳에",
        "add": "몇 초 만에 재생목록 추가",
        "browse": "원하는 채널을 빠르게",
        "watch": "EPG와 함께 매끄러운 라이브 TV",
        "theme": "라이트와 다크 모드 모두 지원",
        "control": "개인정보 보호와 편리한 제어",
    },
    "pt-BR": {
        "library": "Sua TV, perfeitamente organizada",
        "add": "Adicione playlists em segundos",
        "browse": "Encontre canais rapidamente",
        "watch": "TV ao vivo com EPG",
        "theme": "Feita para claro e escuro",
        "control": "Privacidade e controle",
    },
    "ru": {
        "library": "Ваше ТВ — всегда в порядке",
        "add": "Добавьте плейлист за секунды",
        "browse": "Быстро находите каналы",
        "watch": "Прямой эфир с EPG",
        "theme": "Светлая и тёмная темы",
        "control": "Приватность и контроль",
    },
    "th": {
        "library": "ทีวีของคุณ จัดระเบียบอย่างสวยงาม",
        "add": "เพิ่มเพลย์ลิสต์ในไม่กี่วินาที",
        "browse": "ค้นหาช่องที่ต้องการได้ทันที",
        "watch": "ดูทีวีสดลื่นไหลพร้อม EPG",
        "theme": "สวยทั้งโหมดสว่างและมืด",
        "control": "ความเป็นส่วนตัวและการควบคุม",
    },
    "tr": {
        "library": "TV’niz, kusursuz düzenli",
        "add": "Listeleri saniyeler içinde ekleyin",
        "browse": "Kanalları anında bulun",
        "watch": "EPG ile canlı TV",
        "theme": "Açık ve koyu tema",
        "control": "Gizlilik ve kontrol",
    },
    "vi": {
        "library": "TV của bạn, gọn gàng đẹp mắt",
        "add": "Thêm playlist chỉ trong vài giây",
        "browse": "Tìm kênh mong muốn thật nhanh",
        "watch": "TV trực tiếp mượt mà với EPG",
        "theme": "Đẹp ở cả chế độ sáng và tối",
        "control": "Riêng tư và kiểm soát tích hợp",
    },
    "zh-Hans": {
        "library": "你的电视，井然有序",
        "add": "几秒添加播放列表",
        "browse": "快速找到想看的频道",
        "watch": "流畅直播与 EPG 节目单",
        "theme": "浅色深色，随心切换",
        "control": "隐私与控制，内置其中",
    },
}

PALETTES = {
    "library": ((6, 16, 34), (15, 46, 82), (44, 170, 255), (255, 71, 126)),
    "add": ((11, 17, 38), (39, 24, 78), (135, 92, 255), (255, 89, 111)),
    "browse": ((4, 25, 35), (8, 68, 77), (25, 220, 184), (43, 151, 255)),
    "watch": ((20, 8, 31), (80, 18, 50), (255, 70, 105), (255, 184, 66)),
    "theme": ((8, 13, 28), (34, 32, 65), (121, 105, 255), (41, 212, 255)),
    "control": ((10, 18, 29), (29, 50, 61), (70, 225, 170), (255, 196, 72)),
}

PORTRAIT_CROP = {
    "library": 0.76,
    "add": 0.56,
    "browse": 0.72,
    "watch": 0.48,
    "theme": 0.76,
    "control": 0.80,
}

COMPLEX_SCRIPT_FONTS = {
    "hi": "/System/Library/Fonts/Supplemental/Devanagari Sangam MN.ttc",
    "th": "/System/Library/Fonts/Supplemental/SukhumvitSet.ttc",
}


def feature_for(path: Path) -> str:
    name = path.name
    if "Playlist-Add" in name:
        return "add"
    if "Stream" in name:
        return "watch"
    if "Playlist-Settings" in name:
        return "control"
    if "Dark_Playlists" in name:
        return "theme"
    if "Light_Playlist_" in name:
        return "browse"
    return "library"


def font_spec(locale: str, bold: bool) -> tuple[str, int]:
    fonts = Path("/System/Library/Fonts")
    if locale == "ar-SA":
        return str(fonts / "SFArabicRounded.ttf"), 0
    if locale == "ja":
        return str(fonts / ("ヒラギノ角ゴシック W6.ttc" if bold else "ヒラギノ角ゴシック W3.ttc")), 0
    if locale == "ko":
        return str(fonts / "AppleSDGothicNeo.ttc"), 0
    if locale == "zh-Hans":
        return str(fonts / ("STHeiti Medium.ttc" if bold else "STHeiti Light.ttc")), 0
    if locale == "hi":
        return str(fonts / "SFIndia.ttc"), 0
    if locale == "th":
        return str(fonts / "ThonburiUI.ttc"), 0
    return str(fonts / "Helvetica.ttc"), 1 if bold else 0


def font(locale: str, size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    path, index = font_spec(locale, bold)
    return ImageFont.truetype(path, size=size, index=index)


def rounded_image(image: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", image.size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, image.width, image.height), radius=radius, fill=255)
    output = Image.new("RGBA", image.size)
    output.paste(image.convert("RGBA"), (0, 0), mask)
    return output


def background(size: tuple[int, int], feature: str) -> Image.Image:
    width, height = size
    top, bottom, glow_a, glow_b = PALETTES[feature]
    column = Image.new("RGB", (1, height))
    colors = []
    for y in range(height):
        ratio = y / max(height - 1, 1)
        eased = ratio * ratio * (3 - 2 * ratio)
        colors.append(tuple(int(top[i] * (1 - eased) + bottom[i] * eased) for i in range(3)))
    column.putdata(colors)
    canvas = column.resize((width, height)).convert("RGBA")

    glow = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(glow)
    diameter = int(max(width, height) * 0.72)
    draw.ellipse((-diameter // 3, -diameter // 3, diameter, diameter), fill=(*glow_a, 100))
    draw.ellipse(
        (width - diameter, height - diameter * 2 // 3, width + diameter // 3, height + diameter // 3),
        fill=(*glow_b, 92),
    )
    glow = glow.filter(ImageFilter.GaussianBlur(int(diameter * 0.28)))
    canvas.alpha_composite(glow)

    details = Image.new("RGBA", size, (0, 0, 0, 0))
    detail_draw = ImageDraw.Draw(details)
    spacing = max(86, width // 17)
    for x in range(-height, width + height, spacing):
        detail_draw.line((x, 0, x + height, height), fill=(255, 255, 255, 7), width=2)
    canvas.alpha_composite(details)
    return canvas


def wrap_text(draw: ImageDraw.ImageDraw, text: str, face: ImageFont.FreeTypeFont, max_width: int) -> str:
    units = text.split(" ") if " " in text else list(text)
    separator = " " if " " in text else ""
    lines: list[str] = []
    current = ""
    for unit in units:
        candidate = f"{current}{separator if current else ''}{unit}"
        if current and draw.textlength(candidate, font=face) > max_width:
            lines.append(current)
            current = unit
        else:
            current = candidate
    if current:
        lines.append(current)
    return "\n".join(lines)


def shape_arabic_line(text: str) -> str:
    def forms(character: str) -> dict[str, str]:
        name = unicodedata.name(character, "")
        if not name.startswith("ARABIC LETTER "):
            return {}
        output: dict[str, str] = {}
        for form_name in ("ISOLATED", "FINAL", "INITIAL", "MEDIAL"):
            try:
                output[form_name] = unicodedata.lookup(f"{name} {form_name} FORM")
            except KeyError:
                pass
        return output

    characters = list(text)
    shaped: list[str] = []
    for index, character in enumerate(characters):
        current = forms(character)
        if not current:
            shaped.append(character)
            continue
        previous = forms(characters[index - 1]) if index > 0 else {}
        following = forms(characters[index + 1]) if index + 1 < len(characters) else {}
        joins_previous = bool(previous.get("INITIAL") or previous.get("MEDIAL")) and bool(
            current.get("FINAL") or current.get("MEDIAL")
        )
        joins_following = bool(current.get("INITIAL") or current.get("MEDIAL")) and bool(
            following.get("FINAL") or following.get("MEDIAL")
        )
        if joins_previous and joins_following and current.get("MEDIAL"):
            shaped.append(current["MEDIAL"])
        elif joins_previous and current.get("FINAL"):
            shaped.append(current["FINAL"])
        elif joins_following and current.get("INITIAL"):
            shaped.append(current["INITIAL"])
        else:
            shaped.append(current.get("ISOLATED", character))
    return "".join(reversed(shaped))


def display_text(text: str, locale: str) -> str:
    if locale != "ar-SA":
        return text
    return "\n".join(shape_arabic_line(line) for line in text.splitlines())


def complex_title(text: str, locale: str, size: tuple[int, int], point_size: int) -> Image.Image:
    with tempfile.NamedTemporaryFile(suffix=".png") as temporary:
        subprocess.run(
            [
                "magick",
                "-background",
                "none",
                "-fill",
                "white",
                "-font",
                COMPLEX_SCRIPT_FONTS[locale],
                "-pointsize",
                str(point_size),
                "-gravity",
                "center",
                "-size",
                f"{size[0]}x{size[1]}",
                f"caption:{text}",
                temporary.name,
            ],
            check=True,
        )
        with Image.open(temporary.name) as rendered:
            return rendered.convert("RGBA")


def fitted_title(draw: ImageDraw.ImageDraw, text: str, locale: str, max_width: int, max_height: int, start: int) -> tuple[str, ImageFont.FreeTypeFont, int]:
    for size in range(start, 47, -2):
        face = font(locale, size, bold=True)
        wrapped = display_text(wrap_text(draw, text, face, max_width), locale)
        spacing = max(8, size // 7)
        box = draw.multiline_textbbox((0, 0), wrapped, font=face, spacing=spacing, align="center")
        if box[2] <= max_width and box[3] <= max_height:
            return wrapped, face, spacing
    face = font(locale, 48, bold=True)
    return display_text(wrap_text(draw, text, face, max_width), locale), face, 8


def draw_brand(canvas: Image.Image, locale: str, center: tuple[int, int], scale: float) -> None:
    icon_size = int(74 * scale)
    label_face = ImageFont.truetype(
        "/System/Library/Fonts/Helvetica.ttc", int(32 * scale), index=1
    )
    label = "Hi IPTV Player"
    overlay = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    temp_draw = ImageDraw.Draw(overlay)
    text_width = int(temp_draw.textlength(label, font=label_face))
    pill_width = icon_size + text_width + int(68 * scale)
    pill_height = int(104 * scale)
    x = center[0] - pill_width // 2
    y = center[1] - pill_height // 2
    temp_draw.rounded_rectangle(
        (x, y, x + pill_width, y + pill_height),
        radius=pill_height // 2,
        fill=(255, 255, 255, 30),
        outline=(255, 255, 255, 70),
        width=max(1, int(2 * scale)),
    )
    icon = Image.open(APP_ICON).convert("RGB").resize((icon_size, icon_size), Image.Resampling.LANCZOS)
    icon = rounded_image(icon, icon_size // 4)
    overlay.alpha_composite(icon, (x + int(15 * scale), y + (pill_height - icon_size) // 2))
    temp_draw.text(
        (x + icon_size + int(36 * scale), y + pill_height // 2),
        label,
        font=label_face,
        fill=(255, 255, 255, 242),
        anchor="lm",
    )
    canvas.alpha_composite(overlay)


def draw_chips(canvas: Image.Image, center: tuple[int, int], scale: float) -> None:
    overlay = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    chip_font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", int(25 * scale), index=1)
    labels = ("M3U", "M3U8", "EPG")
    widths = [int(draw.textlength(label, font=chip_font) + 42 * scale) for label in labels]
    gap = int(14 * scale)
    x = center[0] - (sum(widths) + gap * (len(labels) - 1)) // 2
    height = int(54 * scale)
    for label, width in zip(labels, widths):
        draw.rounded_rectangle(
            (x, center[1] - height // 2, x + width, center[1] + height // 2),
            radius=height // 2,
            fill=(255, 255, 255, 26),
            outline=(255, 255, 255, 42),
            width=max(1, int(2 * scale)),
        )
        draw.text((x + width // 2, center[1]), label, font=chip_font, fill=(255, 255, 255, 210), anchor="mm")
        x += width + gap
    canvas.alpha_composite(overlay)


def screenshot_card(screenshot: Image.Image, target_width: int, radius: int) -> Image.Image:
    scale = target_width / screenshot.width
    resized = screenshot.resize((target_width, int(screenshot.height * scale)), Image.Resampling.LANCZOS)
    return rounded_image(resized, radius)


def place_card(canvas: Image.Image, card: Image.Image, position: tuple[int, int], radius: int, border: int) -> None:
    x, y = position
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(
        (x - border, y + border * 3, x + card.width + border, y + card.height + border * 4),
        radius=radius + border,
        fill=(0, 0, 0, 145),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(border * 5))
    canvas.alpha_composite(shadow)
    frame = Image.new("RGBA", (card.width + border * 2, card.height + border * 2), (255, 255, 255, 0))
    frame_draw = ImageDraw.Draw(frame)
    frame_draw.rounded_rectangle(
        (0, 0, frame.width - 1, frame.height - 1),
        radius=radius + border,
        fill=(255, 255, 255, 225),
        outline=(255, 255, 255, 180),
        width=border,
    )
    frame.alpha_composite(card, (border, border))
    canvas.alpha_composite(frame, (x - border, y - border))


def compose_portrait(source: Path, destination: Path, locale: str, feature: str) -> None:
    screenshot = Image.open(source).convert("RGB")
    width, height = screenshot.size
    crop_height = int(height * PORTRAIT_CROP[feature])
    screenshot = screenshot.crop((0, 0, width, crop_height))
    canvas = background((width, height), feature)
    draw = ImageDraw.Draw(canvas)

    draw_brand(canvas, locale, (width // 2, 150), 1.0)
    if locale in COMPLEX_SCRIPT_FONTS:
        title_art = complex_title(COPY[locale][feature], locale, (width - 150, 330), 102)
        canvas.alpha_composite(title_art, (75, 285))
        chips_y = 680
    else:
        title, title_font, spacing = fitted_title(draw, COPY[locale][feature], locale, width - 150, 330, 102)
        draw.multiline_text(
            (width // 2, 410),
            title,
            font=title_font,
            fill=(255, 255, 255, 255),
            anchor="ma",
            align="center",
            spacing=spacing,
            stroke_width=1,
            stroke_fill=(255, 255, 255, 40),
        )
        title_box = draw.multiline_textbbox(
            (width // 2, 410),
            title,
            font=title_font,
            anchor="ma",
            align="center",
            spacing=spacing,
        )
        chips_y = max(650, title_box[3] + 72)
    draw_chips(canvas, (width // 2, chips_y), 1.0)

    card_width = int(width * 0.82)
    card = screenshot_card(screenshot, card_width, radius=68)
    card_y = max(810, chips_y + 105)
    place_card(canvas, card, ((width - card.width) // 2, card_y), radius=68, border=8)

    destination.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(destination, "PNG", compress_level=6)


def compose_landscape(source: Path, destination: Path, locale: str, feature: str) -> None:
    screenshot = Image.open(source).convert("RGB")
    width, height = screenshot.size
    canvas = background((width, height), feature)
    draw = ImageDraw.Draw(canvas)

    left_width = int(width * 0.38)
    brand_scale = width / 2752
    draw_brand(canvas, locale, (left_width // 2, int(height * 0.17)), brand_scale)
    title_width = left_width - int(width * 0.075)
    title_height = int(height * 0.46)
    if locale in COMPLEX_SCRIPT_FONTS:
        title_art = complex_title(
            COPY[locale][feature], locale, (title_width, title_height), int(height * 0.073)
        )
        canvas.alpha_composite(
            title_art,
            ((left_width - title_width) // 2, int(height * 0.29)),
        )
    else:
        title, title_font, spacing = fitted_title(
            draw,
            COPY[locale][feature],
            locale,
            title_width,
            title_height,
            int(height * 0.073),
        )
        draw.multiline_text(
            (left_width // 2, int(height * 0.35)),
            title,
            font=title_font,
            fill=(255, 255, 255, 255),
            anchor="ma",
            align="center",
            spacing=spacing,
        )
    draw_chips(canvas, (left_width // 2, int(height * 0.76)), brand_scale)

    card_width = int(width * 0.57)
    card = screenshot_card(screenshot, card_width, radius=int(width * 0.018))
    card_x = int(width * 0.40)
    card_y = (height - card.height) // 2
    place_card(canvas, card, (card_x, card_y), radius=int(width * 0.018), border=max(7, int(width * 0.004)))

    destination.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(destination, "PNG", compress_level=6)


def compose(source: Path, destination: Path, locale: str) -> None:
    with Image.open(source) as probe:
        portrait = probe.height > probe.width
    feature = feature_for(source)
    if portrait:
        compose_portrait(source, destination, locale, feature)
    else:
        compose_landscape(source, destination, locale, feature)


def raw_files(platform: str, kind: str, locale: str) -> list[Path]:
    directory = RAW_ROOT / platform / locale
    files = sorted(directory.glob("*.png"))
    if platform == "iOS" and kind == "iphone_67":
        return [path for path in files if "iPhone" in path.name]
    if platform == "iOS" and kind == "ipad_pro_3gen_129":
        return [path for path in files if "iPad" in path.name]
    if platform == "tvOS":
        return [path for path in files if "_26-4_" in path.name]
    return files


def build_set(platform: str, out_platform: str, kind: str) -> None:
    for locale in LOCALES:
        locale_dir = OUTPUT_ROOT / out_platform / locale / kind
        locale_dir.mkdir(parents=True, exist_ok=True)
        for existing in locale_dir.glob("*.png"):
            existing.unlink()
        files = raw_files(platform, kind, locale)
        if not files:
            raise RuntimeError(f"No raw screenshots for {platform}/{locale}/{kind}")
        for index, source in enumerate(files, start=1):
            destination = locale_dir / f"{index:02d}-{kind}.png"
            compose(source, destination, locale)


def main() -> None:
    build_set("iOS", "ios", "iphone_67")
    build_set("iOS", "ios", "ipad_pro_3gen_129")
    build_set("macOS", "macos", "desktop")
    build_set("tvOS", "tvos", "apple_tv")
    print(f"Wrote localized marketing screenshots to {OUTPUT_ROOT}")


if __name__ == "__main__":
    main()
