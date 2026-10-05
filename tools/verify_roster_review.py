"""Read-only native-source and encoded phone-review verification.

Large movies, probe logs and extracted review frames stay outside the repository.
This checks the final MP4 rather than treating a successful encode as verification.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import tempfile

from PIL import Image
from build_power_art import read_ase

ROOT = Path(__file__).resolve().parents[1]
CLIPS = [
    ('redline_overcap', 'redline-overcap', 18, [0.7, 13.9, 16.5]),
    ('redline_mutation', 'redline-mutation', 18, [0.7, 14.5, 16.4]),
    ('speed_build', 'speed-build', 18, [3.5, 11.5]),
    ('ghost_circuit', 'ghost', 18, [4.25, 4.55, 8.5, 12.6]),
    ('iron_comet', 'iron-comet', 18, [0.95, 2.0, 4.8, 5.1]),
    ('comeback', 'comeback', 24, [5.2, 8.9, 10.4, 15.8]),
    ('late_build', 'late-build', 22, [0.5, 5.0, 12.0]),
]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def native_sources(aseprite):
    result = {}
    manifest = json.loads((ROOT / 'assets/powers/roster_manifest.json').read_text())
    for group in ['effects', 'cards', 'icons']:
        meta = manifest[group]
        source = ROOT / meta['source']
        texture = ROOT / 'assets/powers' / meta['texture']
        frames, source_meta = read_ase(source)
        w, h = source_meta['cell']
        columns = meta['columns']
        sheet = Image.new('RGBA', (w * columns, h * math.ceil(len(frames) / columns)))
        for i, frame in enumerate(frames):
            sheet.alpha_composite(frame, (i % columns * w, i // columns * h))
        runtime = Image.open(texture).convert('RGBA')
        assert sheet.size == runtime.size and sheet.tobytes() == runtime.tobytes()
        with tempfile.TemporaryDirectory() as temporary:
            native = Path(temporary) / 'native.png'
            subprocess.run([aseprite, '-b', str(source), '--sheet-columns', str(columns), '--sheet', str(native)], check=True, capture_output=True)
            exported = Image.open(native).convert('RGBA')
            assert sheet.size == exported.size and sheet.tobytes() == exported.tobytes()
        result[group] = {
            'source': str(source), 'texture': str(texture),
            'source_sha256': digest(source), 'texture_sha256': digest(texture),
            'frames': len(frames), 'tags': len(source_meta['tags']),
            'layers': source_meta['layers'], 'pivot': source_meta['pivot'],
            'sheet_size': list(sheet.size), 'native_export_pixel_exact': True,
        }
    assert result['effects']['frames'] == 120 and result['effects']['tags'] == 20
    assert result['cards']['frames'] == 108 and result['cards']['tags'] == 18
    assert result['icons']['frames'] == 18 and result['icons']['tags'] == 18
    return result


def probe_clip(clip, qa, ffmpeg):
    name, prefix, seconds, times = clip
    video = qa / f'002c5_{name}.mp4'
    manifest_path = qa / f'{prefix}-capture.json'
    captured = json.loads(manifest_path.read_text())
    info = subprocess.run([ffmpeg, '-hide_banner', '-i', str(video)], capture_output=True, text=True).stderr
    (qa / f'{prefix}-probe.log').write_text(info)
    video_line = next(line for line in info.splitlines() if 'Video:' in line)
    audio_line = next(line for line in info.splitlines() if 'Audio:' in line)
    duration = re.search(r'Duration: (\d+):(\d+):(\d+(?:\.\d+)?)', info)
    duration_seconds = int(duration[1]) * 3600 + int(duration[2]) * 60 + float(duration[3])
    assert abs(duration_seconds - seconds) < 0.1, (name, duration_seconds)
    assert 'h264' in video_line and '1280x720' in video_line and '60 fps' in video_line, video_line
    assert 'aac' in audio_line, audio_line
    volume = subprocess.run([ffmpeg, '-hide_banner', '-i', str(video), '-vn', '-af', 'volumedetect', '-f', 'null', 'NUL'], capture_output=True, text=True, check=True).stderr
    (qa / f'{prefix}-audio-probe.log').write_text(volume)
    mean = float(re.search(r'mean_volume: (-?[\d.]+) dB', volume)[1])
    maximum = float(re.search(r'max_volume: (-?[\d.]+) dB', volume)[1])
    assert mean > -80 and maximum > -60, (name, mean, maximum)
    frames = []
    for time in times:
        frame = qa / 'encoded-frames' / f'{name}-{time:.2f}.png'
        subprocess.run([ffmpeg, '-hide_banner', '-loglevel', 'error', '-y', '-ss', str(time), '-i', str(video), '-frames:v', '1', str(frame)], check=True, capture_output=True)
        assert Image.open(frame).size == (1280, 720)
        frames.append({'movie_time': time, 'path': str(frame)})
    runs = captured.get('runs', [captured])
    compact_runs = []
    for run in runs:
        rows = run.get('rows', [])
        # Controlled comeback rows include real fast-forward history; isolate the filmed window.
        active_end = run.get('active_seconds', rows[-1]['time'] if rows else 0)
        active_start = 140 if name == 'comeback' else 250 if name == 'late_build' else 0
        filmed = [row for row in rows if row['time'] >= active_start]
        compact_runs.append({
            'preset': run.get('preset'), 'seed': run['seed'],
            'active_window': [active_start, active_end],
            'rpm_range_in_window': [min(row['rpm'] for row in filmed), max(row['rpm'] for row in filmed)],
            'procs': run.get('procs', rows[-1].get('procs', {})),
            'events_in_window': [event for event in run.get('events', []) if event['time'] >= active_start and event['kind'] in ['comet_charge', 'comet_release', 'clutch_activate', 'clutch_recover', 'ghost_preview', 'ghost_closure', 'ghost_activation', 'runaway_hit', 'orbit_drift']],
            'simulation_ms': run.get('simulation_ms'),
            'draw_submission_ms': run.get('draw_submission_ms'),
        })
    result = {
        'name': name, 'required': name != 'drift', 'path': str(video), 'size_bytes': video.stat().st_size,
        'sha256': digest(video), 'capture_manifest': str(manifest_path),
        'duration_seconds': duration_seconds, 'resolution': [1280, 720], 'fps': 60,
        'video_codec': 'h264', 'audio_codec': 'aac', 'gameplay_audio_mean_db': mean,
        'gameplay_audio_peak_db': maximum, 'authenticity': captured['authenticity'],
        'runs': compact_runs, 'extracted_encoded_frames': frames,
    }
    print(f'{name}: H.264 720p60 / AAC / {duration_seconds:g}s / audio peak {maximum:g} dB')
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--qa', required=True)
    parser.add_argument('--ffmpeg', required=True)
    parser.add_argument('--aseprite', required=True)
    parser.add_argument('--bonus', action='store_true')
    parser.add_argument('--report', required=True)
    args = parser.parse_args()
    qa = Path(args.qa)
    (qa / 'encoded-frames').mkdir(exist_ok=True)
    clips = CLIPS + ([('drift', 'drift', 16, [2.65, 5.65, 8.65, 11.65])] if args.bonus else [])
    source_result = native_sources(args.aseprite)
    with ThreadPoolExecutor(max_workers=3) as pool:
        clip_result = list(pool.map(lambda clip: probe_clip(clip, qa, args.ffmpeg), clips))
    regression_path = ROOT / 'tests/results/task002c5-regression-results.json'
    regression = json.loads(regression_path.read_text())
    assert regression['passed_suites'] == len(regression['suites'])
    assert all(suite['passed'] for suite in regression['suites'])
    presentation = next(suite for suite in regression['suites'] if suite['suite'] == 'roster_presentation')
    audio_manifest = json.loads((ROOT / 'assets/audio/roster_manifest.json').read_text())
    assert len(audio_manifest['cues']) == 12
    audio = {name: dict(cue, sha256=digest(ROOT / 'assets/audio' / cue['file'])) for name, cue in audio_manifest['cues'].items()}
    assert all(not cue['loop'] and cue['duration_ms'] <= 500 for cue in audio.values())
    report = {
        'scope': 'Native authoring/export verification and final encoded phone-review media. Static matrix and held stress fixture are labelled separately from genuine gameplay.',
        'native_art': source_result, 'clips': clip_result,
        'finite_audio_cues': audio,
        'runtime_source_sha256': {str(path.relative_to(ROOT)).replace('\\', '/'): digest(path) for path in [ROOT / 'scripts' / name for name in ['battle.gd', 'power_runtime.gd', 'roster_runtime.gd', 'power_visuals.gd', 'signature_visuals.gd', 'sound.gd']]},
        'static_matrix': {'scope': 'Eighteen labelled static native 640×360 QA states; never gameplay evidence.', 'directory': str(qa / 'matrix-final'), 'frames': [str(path) for path in sorted((qa / 'matrix-final').glob('*.png'))]},
        'held_stress_performance': json.loads((qa / 'roster-performance.json').read_text()),
        'automated_regression': {'latest_source_suites': regression['passed_suites'], 'checks': regression['counted_checks'], 'roster_presentation_checks': presentation['checks'], 'source': str(regression_path)},
        'agent_frame_review': {'status': 'pending', 'note': 'Extracted encoded MP4 frames must be inspected visually before final acceptance.'},
        'limits': ['No physical phone inspection or human acceptance claimed.', 'CPU draw submission excludes asynchronous GPU; held stress wall measurements include harness overhead.', 'Opening builds are labelled controlled; only late_build shows a naturally drafted build. Comeback starts at normal reserve, fast-forwards real inputs and retains the same player.'],
    }
    Path(args.report).write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
