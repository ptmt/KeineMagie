"""Observed sRGB fill/text/border pixels, not a physical-display certification."""
from collections import Counter
import hashlib
import json
from pathlib import Path
from typing import Iterable, cast
import re
from PIL import Image
from test_coach_contrast import contrast

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT/'docs/coach-soft-red-evidence'
source = (ROOT/'native/App/CoachView.swift').read_text()
palette = {}
for name in ('success', 'incorrect', 'incorrectBorder', 'user'):
    line = next(line for line in source.splitlines() if f'static let {name} =' in line)
    values = re.findall(r'UIColor\(red: ([\d.]+), green: ([\d.]+), blue: ([\d.]+), alpha: ([\d.]+)\)', line)
    palette[name] = dict(zip(('dark', 'light'), [tuple(map(float, rgba)) for rgba in values]))

def observed(counts, expected, minimum):
    candidates = [(n, c) for c, n in counts.items() if all(abs(a-b) <= 1 for a,b in zip(c,expected))]
    assert candidates, expected
    n, color = max(candidates)
    assert n > minimum, (color, n)
    return color, n

rows = []
for directory in ('normal-light', 'normal-dark', 'se-light', 'se-dark'):
    theme = directory.split('-')[-1]
    page = 0 if theme == 'dark' else 1
    for shot, status in (('stable-result', 'incorrect'), ('context-correct', 'success')):
        path = EVIDENCE/directory/(shot+'.png')
        image = Image.open(path)
        assert 'srgb' in image.info, path
        rgb = image.convert('RGB')
        pixels = list(cast(Iterable[tuple[int, int, int]], rgb.getdata()))
        counts = Counter(pixels)
        for role in (status, 'user'):
            r,g,b,a = palette[role][theme]
            expected = tuple(round((v*a + page*(1-a))*255) for v in (r,g,b))
            fill, count = observed(counts, expected, 500)
            text = (0,0,0) if role == 'incorrect' and theme == 'light' else (255,255,255)
            interiors = 0
            width,height = rgb.size
            for y in range(height):
                row = pixels[y*width:(y+1)*width]
                matches = [x for x,pixel in enumerate(row) if pixel == fill]
                if len(matches) > 16:
                    interiors += row[matches[0]+8:matches[-1]-8].count(text)
            assert interiors > 50, (path,role,interiors)
            ratio = contrast(tuple(v/255 for v in text), tuple(v/255 for v in fill))
            assert ratio >= 4.5, (path,role,ratio)
            receipt = dict(file=str(path.relative_to(EVIDENCE)),role=role,fill=fill,text=text,solid_fill_pixels=count,text_pixels_in_bounds=interiors,text_contrast=round(ratio,3))
            if role == 'incorrect':
                border, border_count = observed(counts, tuple(round(v*255) for v in palette['incorrectBorder'][theme][:3]), 100)
                border_ratio = contrast(tuple(v/255 for v in border),tuple(v/255 for v in fill))
                assert border_ratio >= 3, (path,border_ratio)
                receipt.update(border=border,border_pixels=border_count,border_fill_contrast=round(border_ratio,3))
            rows.append(receipt)
# Verify every retained attachment against its source export receipt.
for directory in EVIDENCE.iterdir():
    if not directory.is_dir(): continue
    manifest = json.loads((directory/'manifest.json').read_text())
    assert len({row['file'] for row in manifest}) == len(manifest)
    for row in manifest:
        assert hashlib.sha256((directory/row['file']).read_bytes()).hexdigest() == row['sha256']
(EVIDENCE/'pixel-contrast.json').write_text(json.dumps(rows,indent=2)+'\n')
print(json.dumps(dict(samples=len(rows),minimum_text_contrast=min(row['text_contrast'] for row in rows),minimum_border_contrast=min(row['border_fill_contrast'] for row in rows if 'border_fill_contrast' in row)),indent=2))
