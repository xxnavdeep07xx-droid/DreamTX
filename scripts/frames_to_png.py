#!/usr/bin/env python3
"""Convert the frame dump written by app/test/frames_dump_test.dart into
PNGs, plus a zoomed close-up of the filmstrip tab region for the settled
Files-open frame (the opaque-tab check).

Run after:  DREAMTX_DUMP=1 flutter test test/frames_dump_test.dart
Then:      python3 scripts/frames_to_png.py [frames_dir]
"""
import json
import sys
from pathlib import Path
from PIL import Image


def main() -> None:
    frames_dir = Path(sys.argv[1] if len(sys.argv) > 1 else
                      '/home/z/my-project/download/frames')
    manifest_path = frames_dir / 'manifest.json'
    manifest = json.loads(manifest_path.read_text())

    for run in manifest['runs']:
        run_dir = frames_dir / run['run']
        png_dir = run_dir / 'png'
        png_dir.mkdir(exist_ok=True)
        for f in run['frames']:
            raw = (frames_dir / f['file']).read_bytes()
            img = Image.frombytes('RGBA', (f['w'], f['h']), raw)
            img.convert('RGB').save(png_dir / (Path(f['file']).stem + '.png'))
        print(f"{run['run']}: {len(run['frames'])} frames -> {png_dir}")

    # Close-up: from the settled entrance (frame index len-1 of the first
    # run), crop the tray's divider tab region (x 270-390, y 607-671 — the
    # divider band around the raised tab) and upscale x6.
    run = manifest['runs'][0]
    last = run['frames'][-1]
    raw = (frames_dir / last['file']).read_bytes()
    img = Image.frombytes('RGBA', (last['w'], last['h']), raw).convert('RGB')
    crop = img.crop((270, 600, 390, 720))
    crop = crop.resize((crop.width * 6, crop.height * 6), Image.NEAREST)
    out = frames_dir / 'tab_closeup.png'
    crop.save(out)
    print(f'close-up: {out}')


if __name__ == '__main__':
    main()
