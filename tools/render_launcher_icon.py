#!/usr/bin/env python3
"""Renders Conductore's launcher PNGs (pre-Android 8 mipmaps, the iOS
AppIcon set and the flutter_launcher_icons sources) from the geometry of
android/app/src/main/res/drawable/ic_launcher_foreground.xml, plus the
desktop icons (Windows .ico, macOS AppIcon set, Linux window icon).

Usage: tools/render_launcher_icon.py [--desktop]
  (run from the repo root; needs Pillow; --desktop renders only the desktop
  icons and leaves the mobile ones untouched)
"""
import json
import sys

from PIL import Image, ImageDraw

IOS_ICONS = 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
MACOS_ICONS = 'macos/Runner/Assets.xcassets/AppIcon.appiconset'
WINDOWS_ICON = 'windows/runner/resources/app_icon.ico'
LINUX_ICON = 'linux/runner/resources/conductore.png'

BG = (0x2D, 0x35, 0x3B)
CHEVRON = (0xA7, 0xC0, 0x80)
BATON = (0xD3, 0xC6, 0xAA)
HANDLE = (0xE0, 0x9D, 0x7F)
SS = 4


def line(draw, points, width, color, s):
    pts = [(x * s, y * s) for x, y in points]
    draw.line(pts, fill=color, width=round(width * s), joint='curve')
    r = width * s / 2
    for x, y in pts:
        draw.ellipse((x - r, y - r, x + r, y + r), fill=color)


def glyph(draw, s, offset=(0, 0), scale=1.0, mono=None):
    def p(x, y):
        return (offset[0] + x * scale, offset[1] + y * scale)
    c = mono or CHEVRON
    line(draw, [p(32.4, 39.6), p(49.2, 54), p(32.4, 68.4)], 6.6 * scale, c, s)
    line(draw, [p(55.8, 70.8), p(76.8, 36)], 3.3 * scale, mono or BATON, s)
    cx, cy = p(55.8, 70.8)
    r = 5.1 * scale * s
    draw.ellipse((cx * s - r, cy * s - r, cx * s + r, cy * s + r), fill=mono or HANDLE)


def render(size, *, background=True, radius=0.0, mono=None, crop=1.0):
    """crop < 1 zooms into the 108 canvas centre (legacy icons have no
    adaptive safe-zone padding)."""
    big = size * SS
    image = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    if background:
        draw.rounded_rectangle((0, 0, big - 1, big - 1), radius=radius * big, fill=BG)
    unit = size / (108 * crop)
    offset = (-(108 - 108 * crop) / 2 * 1.0, -(108 - 108 * crop) / 2 * 1.0)
    glyph(draw, SS * unit, offset=offset, mono=mono)
    return image.resize((size, size), Image.LANCZOS)


def render_macos(size):
    """macOS (Big Sur and later) does not mask icons: the rounded square is
    drawn at 824/1024 of the canvas with transparent margins, per Apple's
    template."""
    inner = round(size * 824 / 1024)
    tile = render(inner, radius=0.225, crop=0.8)
    image = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    image.paste(tile, ((size - inner) // 2, (size - inner) // 2), tile)
    return image


def desktop():
    with open(f'{MACOS_ICONS}/Contents.json') as contents:
        images = json.load(contents)['images']
    for image in images:
        points = float(image['size'].split('x')[0])
        pixels = round(points * int(image['scale'].rstrip('x')))
        render_macos(pixels).save(f"{MACOS_ICONS}/{image['filename']}")
    tile = render(256, radius=0.12, crop=0.8)
    tile.save(WINDOWS_ICON, sizes=[(n, n) for n in (16, 24, 32, 48, 64, 128, 256)])
    render(512, radius=0.12, crop=0.8).save(LINUX_ICON)


def main():
    if '--desktop' in sys.argv[1:]:
        desktop()
        return
    for folder, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
        render(size, radius=0.12, crop=0.8).save(
            f'android/app/src/main/res/mipmap-{folder}/ic_launcher.png')
    render(1024, crop=0.8).save('assets/icon/icon.png')
    render(1024, background=False).save('assets/icon/icon_foreground.png')
    render(1024, background=False, mono=(255, 255, 255)).save('assets/icon/icon_monochrome.png')
    # iOS masks the corners itself and rejects icons with an alpha channel.
    with open(f'{IOS_ICONS}/Contents.json') as contents:
        images = json.load(contents)['images']
    for image in images:
        points = float(image['size'].split('x')[0])
        pixels = round(points * int(image['scale'].rstrip('x')))
        render(pixels, crop=0.8).convert('RGB').save(f"{IOS_ICONS}/{image['filename']}")
    desktop()


if __name__ == '__main__':
    main()
