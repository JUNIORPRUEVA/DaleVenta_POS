"""Regresion del encuadre, transparencia y resoluciones del icono Windows."""

import contextlib
import io
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from PIL import Image

import generate_app_icons as icons


class WindowsIconTests(unittest.TestCase):
    def test_windows_only_preserves_other_platforms_and_legacy_fill(self):
        with tempfile.TemporaryDirectory(prefix="fullpos-icon-cli-test-") as directory:
            root = Path(directory)
            source = root / "source.png"
            master = root / "master.png"
            output = root / "app.ico"
            Image.new("RGBA", (32, 32), (25, 87, 230, 255)).save(source)
            master.write_bytes(b"existing master")
            for extra_args, expected_width in [([], 32), (["--fill", "0.5"], 16)]:
                with (
                    self.subTest(extra_args=extra_args),
                    mock.patch.object(icons, "REPO_ROOT", root),
                    mock.patch.object(icons, "MASTER_OUTPUT", master),
                    mock.patch.object(icons, "ICO_OUTPUT", output),
                    mock.patch.object(icons, "write_android_icons") as android,
                    mock.patch.object(icons, "write_ios_icons") as ios,
                    mock.patch("sys.argv", ["generate_app_icons.py", "--source", str(source), "--windows-only", *extra_args]),
                    contextlib.redirect_stdout(io.StringIO()),
                ):
                    self.assertEqual(icons.main(), 0)
                    android.assert_not_called()
                    ios.assert_not_called()
                    self.assertEqual(master.read_bytes(), b"existing master")
                    with Image.open(output) as image:
                        left, _, right, _ = icons.content_bbox(image.ico.getimage((32, 32)))
                        self.assertEqual(right - left, expected_width)

    def test_preserves_soft_edge_opacity(self):
        source = Image.new("RGBA", (4, 4), (25, 87, 230, 128))
        result = icons.build_square_icon(source, 4, fill=1)
        self.assertEqual(result.getpixel((2, 2)), (25, 87, 230, 128))

    def test_fills_available_width_without_distorting_logo(self):
        source = Image.new("RGBA", (10, 10))
        source.paste((25, 87, 230, 255), (3, 4, 7, 6))
        result = icons.build_square_icon(source, 32, fill=icons.WINDOWS_CONTENT_FILL)
        self.assertEqual(icons.content_bbox(result), (0, 8, 32, 24))
        self.assertEqual(result.getpixel((0, 0))[3], 0)

    def test_writes_all_native_icon_sizes(self):
        source = Image.new("RGBA", (32, 32), (25, 87, 230, 255))
        with tempfile.TemporaryDirectory(prefix="fullpos-icon-test-") as directory:
            output = Path(directory) / "app.ico"
            icons.write_ico([
                icons.build_square_icon(source, size, fill=icons.WINDOWS_CONTENT_FILL)
                for size in icons.ICO_SIZES
            ], output)
            with Image.open(output) as image:
                self.assertEqual(image.ico.sizes(), {(size, size) for size in icons.ICO_SIZES})
                for size in icons.ICO_SIZES:
                    frame = image.ico.getimage((size, size))
                    self.assertEqual(icons.content_bbox(frame), (0, 0, size, size))


if __name__ == "__main__":
    unittest.main()
