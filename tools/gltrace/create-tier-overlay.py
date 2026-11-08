#!/usr/bin/env python3
"""Create a separate game view with one GPU tier rule."""
import argparse
import base64
import hashlib
import json
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('game', type=Path)
parser.add_argument('output', type=Path, help='new directory; must not already exist')
parser.add_argument('--gpu', required=True, help='GPU name substring used by Bedrock')
parser.add_argument('--tier', type=int, choices=range(1, 6), default=4)
args = parser.parse_args()
source = args.game.resolve(strict=True)
output = args.output.absolute()
if output.exists() or output.is_symlink():
    parser.error('output already exists; choose a new directory')
if source == output or source in output.parents:
    parser.error('output must be outside the original install')
asset = Path('assets/assets/tiers.bin')
original = (source / asset).read_bytes()
data = json.loads(base64.b64decode(original))
if not isinstance(data.get('gpu'), dict) or not args.gpu.strip():
    parser.error('expected a GPU tier table and a nonempty GPU name')
data['gpu'][args.gpu] = args.tier


def overlay(src, dst, parts):
    dst.mkdir(parents=True, exist_ok=False)
    for child in src.iterdir():
        target = dst / child.name
        if child.name == parts[0]:
            if len(parts) > 1:
                overlay(child, target, parts[1:])
        else:
            target.symlink_to(child, target_is_directory=child.is_dir())


overlay(source, output, asset.parts)
(output / asset).write_bytes(base64.b64encode(json.dumps(data).encode()))
manifest = {'source': str(source), 'changed_asset': str(asset), 'gpu': args.gpu,
            'tier': args.tier, 'original_sha256': hashlib.sha256(original).hexdigest()}
(output / '.vv-overlay.json').write_text(json.dumps(manifest, indent=2) + '\n')
assert (source / asset).read_bytes() == original
print(output)
print('Original install unchanged; diagnostic rule: %s -> %d' % (args.gpu, args.tier))
