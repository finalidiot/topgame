"""Capture native inspection controls and preserve source/profile evidence."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import sys
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/workspace'))
sys.path.insert(0, str(ROOT / 'tools/build'))
import workspace
import windows_checkpoint as pipeline

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine')
    parser.add_argument('--qa-root', type=Path)
    parser.add_argument('--stem', default='003a1_ability_explanations')
    args = parser.parse_args()
    task = workspace.create_task_workspace('003A.1', args.qa_root)
    run_id = args.stem + '_' + datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%f')
    manifest = task / 'manifests' / (run_id + '.json')
    frames = task / 'frames' / run_id
    destination = task / 'images' / (args.stem + '.png')
    assert not any(path.exists() for path in [manifest, frames, destination]), 'Preserve prior evidence'
    # Capture dependencies only. Concurrent unrelated gameplay development is
    # outside this renderer; every actual input to these panels is fingerprinted.
    paths = [ROOT / 'scripts' / name for name in ['ability_inspection.gd', 'run_powers.gd', 'front_end.gd', 'power_identity.gd', 'defence_art.gd']]
    paths += [ROOT / 'project.godot', ROOT / 'tests/capture_ability_readability.gd', Path(__file__).resolve()]
    paths += [p for p in sorted((ROOT / 'assets').rglob('*')) if p.is_file() and p.suffix in ['.png', '.json', '.fnt', '.aseprite']]
    before = {path.relative_to(ROOT).as_posix(): pipeline.sha256(path) for path in paths}
    profile = pipeline.production_profile(ROOT)
    inputs = task / 'manifests' / (run_id + '_inputs.json')
    inputs.write_text(json.dumps({'source_before': before, 'profile_before': profile}, indent=2) + '\n')
    command = [workspace.find_tool('godot', args.engine), '--path', str(ROOT), '--script', 'res://tests/capture_ability_readability.gd', '--resolution', '640x360', '--audio-driver', 'Dummy', '--', '--frames=' + str(frames), '--manifest=' + str(manifest)]
    process = pipeline.run_logged(command, task / 'logs' / (run_id + '.log'), 90)
    data = json.loads(manifest.read_text())
    assert data['failures'] == []
    after = {path.relative_to(ROOT).as_posix(): pipeline.sha256(path) for path in paths}
    profile_after = pipeline.production_profile(ROOT)
    assert before == after, 'Capture inputs changed'
    assert profile == profile_after, 'Real player profile changed'
    # Crop the actual 188x242 controls; no rescaling, redrawing or substituted text.
    matrix = Image.new('RGB', (188 * 4, 242 * 2), (16, 21, 31))
    for index, item in enumerate(data['images']):
        source = Path(item['path'])
        pixels = Image.open(source).convert('RGB')
        assert pixels.size == (640, 360)
        x, y, width, height = item['panel_rect']
        matrix.paste(pixels.crop((x, y, x + width, y + height)), (index % 4 * width, index // 4 * height))
        item['sha256'] = pipeline.sha256(source)
    matrix.save(destination)
    data.update(matrix=str(destination), matrix_sha256=pipeline.sha256(destination), matrix_size=list(matrix.size), native_panel_size=[188, 242], source_before=before, source_after=after, source_unchanged=True, profile_before=profile, profile_after=profile_after, profile_unchanged=True, process=process, source_git_sha=pipeline.git(ROOT, 'rev-parse', 'HEAD'))
    manifest.write_text(json.dumps(data, indent=2) + '\n')
    print(json.dumps({'matrix': str(destination), 'manifest': str(manifest), 'panels': len(data['images']), 'native_pixels': True, 'source_unchanged': True, 'profile_unchanged': True}, indent=2))

if __name__ == '__main__': main()
