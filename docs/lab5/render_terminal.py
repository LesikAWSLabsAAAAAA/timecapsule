#!/usr/bin/env python3
"""Render a UTF-8 terminal transcript as PNG (requires rsvg-convert)."""

import argparse
import html
from pathlib import Path
import subprocess
import unicodedata


def cells(char: str) -> int:
    if unicodedata.combining(char):
        return 0
    return 2 if unicodedata.east_asian_width(char) in {"F", "W"} else 1


def wrap(line: str, columns: int) -> list[str]:
    rows = []
    start = width = 0
    for index, char in enumerate(line):
        size = cells(char)
        if width + size > columns:
            rows.append(line[start:index])
            start, width = index, 0
        width += size
    rows.append(line[start:])
    return rows


def render(text: str, columns: int = 110) -> str:
    rows = [row for line in text.splitlines() for row in wrap(line.expandtabs(8), columns)]
    width = 56 + 10 * max(52, max((sum(map(cells, row)) for row in rows), default=0))
    height = 80 + 23 * len(rows)
    contents = []
    for index, row in enumerate(rows):
        color = "#e0e6ed"
        if row.startswith(("Error:", "│ Error:")):
            color = "#ff9492"
        elif row.startswith(("Plan:", "Apply complete!", "Success!", "$ ")):
            color = "#99dba9"
        contents.append(
            f'<text x="28" y="{70 + 23 * index}" fill="{color}">{html.escape(row)}</text>'
        )
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}">
<rect width="{width}" height="{height}" rx="11" fill="#14191f"/>
<path d="M11 0 H{width - 11} Q{width} 0 {width} 11 V40 H0 V11 Q0 0 11 0Z" fill="#272e37"/>
<circle cx="20" cy="20" r="4.5" fill="#ff6b6b"/>
<circle cx="35" cy="20" r="4.5" fill="#ffd166"/>
<circle cx="50" cy="20" r="4.5" fill="#70c694"/>
<text x="{width // 2}" y="25" text-anchor="middle" font-family="sans-serif" font-size="14" fill="#c6d0da">Terminal</text>
<g xml:space="preserve" font-family="DejaVu Sans Mono,monospace" font-size="16">
{"".join(contents)}
</g></svg>"""


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("transcript", type=Path)
    parser.add_argument("png", type=Path)
    args = parser.parse_args()
    svg = render(args.transcript.read_text(encoding="utf-8"))
    subprocess.run(["rsvg-convert", "-o", str(args.png)], input=svg.encode("utf-8"), check=True)


if __name__ == "__main__":
    main()
