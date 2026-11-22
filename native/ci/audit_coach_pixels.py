"""Audit original sRGB XCTest pixels; excludes antialiased text edges.
Run with Pillow installed. This is not a perceptual or physical-display audit.
"""
from collections import Counter
import json
from pathlib import Path
import re
import subprocess
from typing import Iterable, cast
from PIL import Image
from test_coach_contrast import contrast

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT/'docs/coach-bold-glass-evidence'
# These are retained historical bold-glass screenshots, not the soft-red candidate.
source = subprocess.check_output(['git', 'show', 'e542fda2d9be22792227e4c8676fe19d302f8b80:native/App/CoachView.swift'], cwd=ROOT, text=True)
colors = {}
for name in ('success', 'incorrect', 'user'):
    line = next(line for line in source.splitlines() if f'static let {name} =' in line)
    values = re.findall(r'UIColor\(red: ([\d.]+), green: ([\d.]+), blue: ([\d.]+), alpha: 1\)', line)
    colors[name] = dict(zip(('dark','light'), [tuple(round(float(v)*255) for v in rgb) for rgb in values]))
rows = []
for directory in ('normal-light','normal-dark','se-light','se-dark'):
    theme = directory.split('-')[-1]
    for shot, status in (('stable-result','incorrect'), ('context-correct','success')):
        path = EVIDENCE/directory/(shot+'.png')
        image = Image.open(path)
        assert 'srgb' in image.info, path
        rgb = image.convert('RGB')
        pixels = list(cast(Iterable[tuple[int, int, int]], rgb.getdata()))
        counts = Counter(pixels)
        for role in (status,'user'):
            expected = colors[role][theme]
            # UIKit quantization rounds half values differently from Python's
            # ties-to-even round (0.70 * 255). Inspect actual modal pixels within
            # one sRGB code value, and calculate contrast from the real pixels.
            candidates = [(count, pixel) for pixel, count in counts.items()
                          if all(abs(a-b) <= 1 for a,b in zip(pixel, expected))]
            assert candidates, (path,role,expected)
            count, color = max(candidates)
            assert count > 500, (path,role,color,count)
            # Count opaque white interiors only between this fill's left/right
            # extents on the same row, inset away from rounded boundary pixels.
            # This avoids counting the white page between separate user bubbles.
            white = 0
            width, height = rgb.size
            for y in range(height):
                row = pixels[y*width:(y+1)*width]
                matches = [x for x, pixel in enumerate(row) if pixel == color]
                if len(matches) > 16:
                    white += row[matches[0]+8:matches[-1]-8].count((255,255,255))
            assert white > 50, (path, role, white)
            ratio = contrast((1,1,1), tuple(c/255 for c in color))
            assert ratio >= 4.5, (path,role,ratio)
            rows.append(dict(file=str(path.relative_to(EVIDENCE)),role=role,rgb=color,solid_pixels=counts[color],white_pixels_in_bounds=white,contrast=round(ratio,3)))
(EVIDENCE/'pixel-contrast.json').write_text(json.dumps(rows,indent=2)+'\n')
print(json.dumps({'samples':len(rows),'minimum_contrast':min(row['contrast'] for row in rows)},indent=2))
