#!/usr/bin/env python3
"""Genera los iconos de aplicacion de FullPOS.

Fuente unica de verdad
----------------------
El PNG con transparencia del logo FullPOS. Por defecto:
``apps/fulltech_app/assets/image/nuevologo.png``

No rediseña el logo: recorta el contenido a su bounding box real, lo centra en
un lienzo cuadrado y lo reescala con correccion de alfa premultiplicado (evita
halos oscuros en los bordes transparentes).

Salidas
-------
* ``apps/fulltech_app/assets/image/logo_launcher.png``
  Maestro cuadrado 1024x1024 con transparencia. Es el ``image_path`` de
  ``flutter_launcher_icons`` en ``pubspec.yaml`` (iconos launcher de Android).
* ``apps/fulltech_app/windows/runner/resources/app_icon.ico``
  ICO multi-resolucion (16, 24, 32, 48, 64, 128, 256) en formato BMP 32bpp.
  Lo usan el ejecutable Windows, la barra de tareas, el acceso directo y el
  instalador Inno Setup.

Notas
-----
* ``flutter_launcher_icons`` queda con ``windows.generate: false`` para que no
  sobrescriba este ICO con uno de una sola resolucion.
* La regeneracion de los iconos de Android se hace aparte con
  ``flutter_launcher_icons`` a partir del maestro.

Uso
---
    python scripts/branding/generate_app_icons.py
    python scripts/branding/generate_app_icons.py --analyze
    python scripts/branding/generate_app_icons.py --source <ruta-al-png>
"""

from __future__ import annotations

import argparse
import struct
from pathlib import Path

from PIL import Image

REPO_ROOT = Path(__file__).resolve().parents[2]
APP_DIR = REPO_ROOT / "apps" / "fulltech_app"

DEFAULT_SOURCE = APP_DIR / "assets" / "image" / "nuevologo.png"
MASTER_OUTPUT = APP_DIR / "assets" / "image" / "logo_launcher.png"
ICO_OUTPUT = APP_DIR / "windows" / "runner" / "resources" / "app_icon.ico"

MASTER_SIZE = 1024
ICO_SIZES = (16, 24, 32, 48, 64, 128, 256)

# Fraccion del lienzo cuadrado que ocupa el lado mayor del contenido.
# Deja margen uniforme para que el logo no quede pegado al borde.
CONTENT_FILL = 0.88

# Alfa minima para considerar un pixel como parte del contenido.
ALPHA_THRESHOLD = 12


def load_rgba(path: Path) -> Image.Image:
    if not path.is_file():
        raise SystemExit(f"No existe la imagen fuente: {path}")
    return Image.open(path).convert("RGBA")


def content_bbox(image: Image.Image, threshold: int = ALPHA_THRESHOLD) -> tuple[int, int, int, int]:
    """Bounding box de los pixeles con alfa >= threshold."""
    mask = image.getchannel("A").point(lambda value: 255 if value >= threshold else 0)
    bbox = mask.getbbox()
    if bbox is None:
        raise SystemExit("La imagen fuente no tiene contenido visible (todo transparente).")
    return bbox


def resize_rgba(image: Image.Image, width: int, height: int) -> Image.Image:
    """Reescala RGBA con alfa premultiplicado para evitar halos oscuros."""
    if image.size == (width, height):
        return image.copy()
    premultiplied = image.convert("RGBa")  # RGBa = alfa premultiplicado
    resized = premultiplied.resize((width, height), Image.LANCZOS)
    return resized.convert("RGBA")


def build_square_icon(source: Image.Image, size: int, fill: float = CONTENT_FILL) -> Image.Image:
    """Recorta el contenido, lo centra y lo ajusta a un lienzo cuadrado transparente."""
    box = content_bbox(source)
    content = source.crop(box)
    content_width, content_height = content.size

    target = max(1, int(round(size * fill)))
    scale = min(target / content_width, target / content_height)
    draw_width = max(1, min(size, int(round(content_width * scale))))
    draw_height = max(1, min(size, int(round(content_height * scale))))

    logo = resize_rgba(content, draw_width, draw_height)

    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(logo, ((size - draw_width) // 2, (size - draw_height) // 2), logo)
    return canvas


def _bmp_entry(image: Image.Image) -> bytes:
    """Convierte a DIB 32bpp (bottom-up BGRA) + mascara AND, como en los .ico clasicos."""
    width, height = image.size
    pixels = image.load()

    header = struct.pack(
        "<IiiHHIIiiII",
        40,  # biSize
        width,
        height * 2,  # biHeight = XOR + AND
        1,  # biPlanes
        32,  # biBitCount
        0,  # biCompression = BI_RGB
        width * height * 4,  # biSizeImage
        0, 0, 0, 0,
    )

    xor_rows = []
    for y in range(height - 1, -1, -1):
        row = bytearray()
        for x in range(width):
            red, green, blue, alpha = pixels[x, y]
            row += bytes((blue, green, red, alpha))
        xor_rows.append(bytes(row))

    mask_row_bytes = ((width + 31) // 32) * 4
    mask_rows = []
    for y in range(height - 1, -1, -1):
        row = bytearray(mask_row_bytes)
        for x in range(width):
            if pixels[x, y][3] < 128:
                row[x // 8] |= 0x80 >> (x % 8)
        mask_rows.append(bytes(row))

    return header + b"".join(xor_rows) + b"".join(mask_rows)


def write_ico(images: list[Image.Image], path: Path) -> None:
    """Escribe un .ico con entradas BMP 32bpp (compatible con Windows e Inno Setup)."""
    blobs = [_bmp_entry(image) for image in images]

    header = struct.pack("<HHH", 0, 1, len(images))
    offset = 6 + 16 * len(images)

    directory = bytearray()
    payload = bytearray()
    for image, blob in zip(images, blobs):
        width, height = image.size
        directory += struct.pack(
            "<BBBBHHII",
            0 if width >= 256 else width,
            0 if height >= 256 else height,
            0,  # colores en paleta (0 = truecolor)
            0,  # reservado
            1,  # planos
            32,  # bits por pixel
            len(blob),
            offset,
        )
        payload += blob
        offset += len(blob)

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(header + bytes(directory) + bytes(payload))


def analyze(source: Image.Image) -> None:
    width, height = source.size
    alpha = source.getchannel("A")
    histogram = alpha.histogram()
    total = width * height
    invisible = histogram[0] + sum(histogram[1:ALPHA_THRESHOLD])
    soft = sum(histogram[ALPHA_THRESHOLD:200])
    solid = sum(histogram[200:])

    print(f"source size        : {width}x{height}")
    print(f"content bbox       : {content_bbox(source)}")
    print(f"transparent pixels : {invisible * 100 / total:.2f}%")
    print(f"soft edge pixels   : {soft * 100 / total:.2f}%")
    print(f"solid pixels       : {solid * 100 / total:.2f}%")
    print(f"corner alpha       : {[source.getpixel(c)[3] for c in ((0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1))]}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Genera los iconos de FullPOS.")
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE, help="PNG del logo FullPOS.")
    parser.add_argument("--fill", type=float, default=CONTENT_FILL, help="Fraccion del lienzo ocupada por el logo.")
    parser.add_argument("--analyze", action="store_true", help="Solo imprime el analisis de la fuente.")
    args = parser.parse_args()

    source = load_rgba(args.source)
    analyze(source)
    if args.analyze:
        return 0

    master = build_square_icon(source, MASTER_SIZE, args.fill)
    MASTER_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    master.save(MASTER_OUTPUT, "PNG", optimize=True)
    print(f"\nmaster written     : {MASTER_OUTPUT.relative_to(REPO_ROOT)} ({MASTER_SIZE}x{MASTER_SIZE})")

    write_ico([build_square_icon(source, size, args.fill) for size in ICO_SIZES], ICO_OUTPUT)
    print(f"ico written        : {ICO_OUTPUT.relative_to(REPO_ROOT)} ({', '.join(str(s) for s in ICO_SIZES)})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
