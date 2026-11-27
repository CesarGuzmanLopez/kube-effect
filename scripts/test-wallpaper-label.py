#!/usr/bin/env python3
"""Maximised E<n> window: per-desktop identity for the nested KWin harness.

Plasma 6.8.3 cannot give each virtual desktop its own wallpaper (see
scripts/make-test-wallpaper.py), so the harness labels desktops with a
window instead: one flat colour per desktop (well separated in tone), a
giant off-centre "E<n>" and a small "ESCRITORIO n" tag in the TOP-LEFT.
Like the wallpaper, nothing is symmetric: in the cube, face k must show
desk colour k with the tag top-left, which verifies ADR-004 face-to-desktop
mapping and betrays mirrors through the window itself.

Run inside the nested session; the harness positions it per desktop with
the same busctl setCurrentDesktop trick it uses for KUBE_NESTED_APPS.

Usage: test-wallpaper-label.py --desktop N
"""

import argparse
import sys

from PySide6.QtGui import QColor, QFont, QPainter, QPen
from PySide6.QtWidgets import QApplication, QWidget

# Flat, well-separated tones; cycled when there are more desktops than
# entries. None of them equals the wallpaper's steel blue.
PALETTE = (
    QColor("#1565c0"),  # blue
    QColor("#2e7d32"),  # green
    QColor("#ef6c00"),  # orange
    QColor("#6a1b9a"),  # purple
    QColor("#00838f"),  # cyan
    QColor("#c62828"),  # red
)


class DesktopLabel(QWidget):
    def __init__(self, desktop: int) -> None:
        super().__init__()
        self.desktop = desktop
        self.color = PALETTE[(desktop - 1) % len(PALETTE)]
        self.setWindowTitle(f"E{desktop}")

    def paintEvent(self, _event) -> None:  # Qt naming (camelCase hook)
        painter = QPainter(self)
        rect = self.rect()
        w, h = rect.width(), rect.height()
        painter.fillRect(rect, self.color)

        # Darker frame: shows where the window ends and the wallpaper starts.
        painter.setPen(QPen(self.color.darker(170), max(8, h // 60)))
        painter.drawRect(rect.adjusted(4, 4, -4, -4))

        # Giant number, deliberately OFF-centre (asymmetric on purpose).
        big = QFont("DejaVu Sans")
        big.setBold(True)
        big.setPixelSize(max(80, int(h * 0.45)))
        painter.setFont(big)
        painter.setPen(QColor("#ffffff"))
        painter.drawText(int(w * 0.40), int(h * 0.62), f"E{self.desktop}")

        # Unique corner tag: top-left, small.
        small = QFont("DejaVu Sans")
        small.setBold(True)
        small.setPixelSize(max(20, h // 20))
        painter.setFont(small)
        painter.drawText(
            max(24, w // 60), max(48, h // 12), f"ESCRITORIO {self.desktop}"
        )


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument(
        "--desktop", required=True, type=int, help="1-based virtual desktop"
    )
    args = ap.parse_args()
    if args.desktop < 1:
        print("error: --desktop must be >= 1", file=sys.stderr)
        return 2

    app = QApplication(sys.argv)
    label = DesktopLabel(args.desktop)
    label.showMaximized()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
