#!/usr/bin/env python3
"""Generate Resources/AppIcon.iconset and Resources/AppIcon.icns.

The speaker glyph is the Material Symbols "speaker" (filled) icon and is
licensed under Apache 2.0 (https://github.com/google/material-design-icons).
Run with a Python that has PyObjC, e.g.:

    uv run --project ../ue-megaboom python scripts/make-icon.py
"""
from __future__ import annotations

import subprocess
from pathlib import Path

import AppKit

SPEAKER_PATH = (
    "M680-80H280q-33 0-56.5-23.5T200-160v-640q0-33 23.5-56.5T280-880h400q33 0 "
    "56.5 23.5T760-800v640q0 33-23.5 56.5T680-80ZM536.5-623.5Q560-647 560-680"
    "t-23.5-56.5Q513-760 480-760t-56.5 23.5Q400-713 400-680t23.5 56.5Q447-600 "
    "480-600t56.5-23.5ZM593-247q47-47 47-113t-47-113q-47-47-113-47t-113 47q-47 "
    "47-47 113t47 113q47 47 113 47t113-47Zm-169.5-56.5Q400-327 400-360t23.5-56.5"
    "Q447-440 480-440t56.5 23.5Q560-393 560-360t-23.5 56.5Q513-280 480-280t-56.5-23.5Z"
)

ROOT = Path(__file__).resolve().parent.parent
ICONSET = ROOT / "Resources" / "AppIcon.iconset"
ICNS = ROOT / "Resources" / "AppIcon.icns"
MASTER = 1024


def speaker_image(size: int) -> AppKit.NSImage:
    svg = (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 -960 960 960">'
        f'<path d="{SPEAKER_PATH}" fill="#FFFFFF"/></svg>'
    )
    source = AppKit.NSImage.alloc().initWithData_(svg.encode())
    canvas = AppKit.NSImage.alloc().initWithSize_(AppKit.NSMakeSize(size, size))
    canvas.lockFocus()

    inset = size * 0.09
    rect = AppKit.NSMakeRect(inset, inset, size - 2 * inset, size - 2 * inset)
    radius = rect.size.width * 0.2237
    path = AppKit.NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius_(
        rect, radius, radius
    )
    gradient = AppKit.NSGradient.alloc().initWithStartingColor_endingColor_(
        AppKit.NSColor.colorWithCalibratedRed_green_blue_alpha_(0.13, 0.59, 0.95, 1.0),
        AppKit.NSColor.colorWithCalibratedRed_green_blue_alpha_(0.05, 0.28, 0.63, 1.0),
    )
    gradient.drawInBezierPath_angle_(path, -90.0)

    glyph = size * 0.54
    source.drawInRect_(
        AppKit.NSMakeRect(
            (size - glyph) / 2, (size - glyph) / 2 - size * 0.01, glyph, glyph
        )
    )
    canvas.unlockFocus()
    return canvas


def write_png(image: AppKit.NSImage, pixels: int, destination: Path) -> None:
    rep = AppKit.NSBitmapImageRep.alloc().initWithBitmapDataPlanes_pixelsWide_pixelsHigh_bitsPerSample_samplesPerPixel_hasAlpha_isPlanar_colorSpaceName_bytesPerRow_bitsPerPixel_(
        None, pixels, pixels, 8, 4, True, False, AppKit.NSCalibratedRGBColorSpace, 0, 0
    )
    context = AppKit.NSGraphicsContext.graphicsContextWithBitmapImageRep_(rep)
    AppKit.NSGraphicsContext.saveGraphicsState()
    AppKit.NSGraphicsContext.setCurrentContext_(context)
    image.drawInRect_(AppKit.NSMakeRect(0, 0, pixels, pixels))
    AppKit.NSGraphicsContext.restoreGraphicsState()
    data = rep.representationUsingType_properties_(AppKit.NSBitmapImageFileTypePNG, {})
    destination.write_bytes(data)


def main() -> None:
    ICONSET.mkdir(parents=True, exist_ok=True)
    master = speaker_image(MASTER)
    for points in (16, 32, 128, 256, 512):
        write_png(master, points, ICONSET / f"icon_{points}x{points}.png")
        write_png(master, points * 2, ICONSET / f"icon_{points}x{points}@2x.png")
    subprocess.run(
        ["iconutil", "-c", "icns", str(ICONSET), "-o", str(ICNS)], check=True
    )
    print("wrote", ICNS)


if __name__ == "__main__":
    main()
