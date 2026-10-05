"""Read-only production retention, native art and organisation equivalence checks.

Capture before and after an infrastructure change into external QA folders,
then compare the diagnostic JSON. No production files or real player saves are
written. Headless test drivers use their existing isolated smoke/test saves.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from workspace import find_tool, repo_root

TEXT_EXTENSIONS = {'.gd', '.json', '.tscn', '.tres', '.godot', '.cfg', '.uid',
                   '.import', '.md', '.txt', '.gpl', '.svg'}
DIAGNOSTIC_SUITES = ('starter_physics', 'threat_director', 'roster_draft',
                     'ability_rebalance', 'ability_rebalance_integration')


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def git(project: Path, *args) -> bytes:
    return subprocess.check_output(['git', '-C', str(project), *args])


def production_retention(project: Path, parent: str) -> dict:
    parent = git(project, 'rev-parse', '--verify', parent + '^{commit}').decode().strip()
    paths = git(project, 'ls-tree', '-r', '--name-only', '-z', parent).decode().split('\0')
    records = []
    for relative in paths:
        if not (relative.startswith(('scripts/', 'assets/')) or relative in {'project.godot', 'main.tscn'}):
            continue
        current = project / relative
        if not current.is_file():
            records.append({'path': relative, 'unchanged': False, 'missing': True})
            continue
        old = git(project, 'show', parent + ':' + relative)
        actual = current.read_bytes()
        text = current.suffix.lower() in TEXT_EXTENSIONS
        expected = old.replace(b'\r\n', b'\n') if text else old
        normalized = actual.replace(b'\r\n', b'\n') if text else actual
        records.append({'path': relative, 'unchanged': expected == normalized,
                        'comparison': 'canonical text line endings' if text else 'exact binary bytes',
                        'parent_sha256': digest(expected), 'current_sha256': digest(normalized),
                        'checkout_sha256': digest(actual)})
    changed = [r for r in records if not r['unchanged']]
    report = {'parent': parent, 'production_file_count': len(records),
              'unchanged': not changed, 'changed': changed, 'files': records,
              'scope': 'Every parent production script, runtime asset, saved art master, resource metadata and project/scene config. Only CRLF checkout differences are normalized for text; binary files must match exactly. Build/export configuration and tooling are outside gameplay scope.'}
    return report


def execute(engine: str, project: Path, output: Path, suite: str, arguments=()) -> dict:
    log = output / (suite + '.log')
    command = [engine, '--headless', '--path', str(project), '--script',
               'res://tests/' + suite + '.gd']
    if arguments:
        command += ['--', *map(str, arguments)]
    began = time.monotonic()
    with log.open('wb') as stream:
        result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, timeout=600)
    contents = log.read_text(errors='replace')
    errors = bool(re.search(r'SCRIPT ERROR|ERROR:|FAIL:|failures=[1-9]|\b[1-9]\d*\s+failures\b(?![=:])', contents))
    row = {'suite': suite, 'exit_code': result.returncode, 'passed': result.returncode == 0 and not errors,
           'seconds': round(time.monotonic() - began, 3), 'log': str(log), 'arguments': list(arguments)}
    print(json.dumps(row), flush=True)
    if not row['passed']:
        raise RuntimeError(f'{suite} failed; inspect {log}')
    return row


def capture(project: Path, output: Path, parent: str, engine: str, include_prototype: bool) -> dict:
    rows = []
    for name in DIAGNOSTIC_SUITES:
        suite = 'test_' + name
        rows.append(execute(engine, project, output, suite, ['--report=' + str(output / (suite + '.json'))]))
    rows.append(execute(engine, project, output, 'diagnose_roster_runs',
                        ['--profiles=overclock,speed', '--starters=breaker', '--ceiling=120',
                         '--report=' + str(output / 'natural-runs.json')]))
    baseline = output / 'parent_battle.gd'
    baseline.write_bytes(git(project, 'show', parent + ':scripts/battle.gd'))
    rows.append(execute(engine, project, output, 'test_baseline_physics', ['--baseline-source=' + str(baseline)]))
    if include_prototype:
        rows.append(execute(engine, project, output, 'test_prototype',
                            ['--report=' + str(output / 'prototype-QA.txt'),
                             '--balance-report=' + str(output / 'prototype-balance-results.json')]))
    payloads = ['natural-runs.json'] + ['test_' + name + '.json' for name in DIAGNOSTIC_SUITES]
    if include_prototype:
        payloads.append('prototype-balance-results.json')
    report = {'diagnostics': rows, 'deterministic_json': {name: digest((output / name).read_bytes()) for name in payloads},
              'scope': 'Exact pre/post organisation diagnostics: four genuine seeded Runs (overclock/speed, seeds421/7341, 120 seconds or actual defeat), real RPM ledgers/curves/procs/director decisions/draft offers; eight900-second synthetic director seeds,256-seed draft study, physical starter and ability metrics. Physics differential uses the supplied provisional parent checkpoint; obsolete Task001 equations are not treated as current balance.'}
    return report


def native_art(project: Path, parent: str, aseprite: str) -> dict:
    from PIL import Image
    sys.path.insert(0, str(project / 'tools'))
    from build_power_art import read_ase

    mappings = {}
    masters = []

    def discover(node, manifest):
        if isinstance(node, dict):
            if all(k in node for k in ('source', 'texture', 'columns')):
                source, texture = node['source'], node['texture']
                if isinstance(source, str) and source.endswith('.aseprite'):
                    src = (project / source if source.startswith('assets/') else manifest.parent / source).resolve()
                    dst = (project / texture.removeprefix('res://') if texture.startswith('res://') else manifest.parent / texture).resolve()
                    mappings[(src, dst)] = int(node['columns'])
            for value in node.values():
                discover(value, manifest)
        elif isinstance(node, list):
            for value in node:
                discover(value, manifest)

    for manifest in sorted((project / 'assets').rglob('*.json')):
        discover(json.loads(manifest.read_text()), manifest)
    for source in sorted((project / 'assets/source-art').rglob('*.aseprite')):
        frames, metadata = read_ase(source)
        masters.append({'source': source.relative_to(project).as_posix(), 'sha256': digest(source.read_bytes()),
                        'frames': len(frames), 'layers': metadata['layers'], 'tags': len(metadata['tags']),
                        'pivot': metadata.get('pivot'), 'timing_entries': len(metadata['durations_ms'])})
    atlases = []
    for (source, runtime), columns in mappings.items():
        with tempfile.TemporaryDirectory(prefix='topgame_native_readonly_') as temporary:
            sheet = Path(temporary) / 'sheet.png'
            subprocess.run([aseprite, '-b', str(source), '--sheet-columns', str(columns), '--sheet', str(sheet)],
                           check=True, capture_output=True)
            expected, actual = Image.open(sheet).convert('RGBA'), Image.open(runtime).convert('RGBA')
            if expected.size != actual.size:
                raise RuntimeError(f'Native atlas dimensions differ: {runtime}')
            left, right = expected.tobytes(), actual.tobytes()
            different = [i for i in range(0, len(left), 4) if (left[i+3] or right[i+3]) and left[i:i+4] != right[i:i+4]]
            maximum = max((abs(left[i+j] - right[i+j]) for i in different for j in range(4)), default=0)
        same_parent = all(git(project, 'show', parent + ':' + p.relative_to(project).as_posix()) == p.read_bytes() for p in (source, runtime))
        if not same_parent:
            raise RuntimeError(f'Source or runtime changed during organisation: {runtime}')
        if 'power_identity_002c5' in source.parts and different:
            raise RuntimeError(f'Current power identity native parity differs: {runtime}')
        atlases.append({'source': source.relative_to(project).as_posix(), 'runtime': runtime.relative_to(project).as_posix(),
                       'source_sha256': digest(source.read_bytes()), 'runtime_sha256': digest(runtime.read_bytes()),
                       'columns': columns, 'native_visible_rgba_pixel_exact': not different,
                       'different_visible_pixels': len(different), 'maximum_channel_difference': maximum,
                       'source_and_runtime_byte_identical_to_parent': same_parent})
    differences = [r for r in atlases if not r['native_visible_rgba_pixel_exact']]
    return {'status': 'pass_with_preserved_historical_export_differences' if differences else 'pass',
            'master_count': len(masters), 'native_atlas_count': len(atlases),
            'exact_atlas_count': len(atlases) - len(differences), 'masters': masters,
            'source_runtime_maps': atlases, 'historical_export_differences': differences,
            'scope': 'Read-only saved-master parsing and native Aseprite exports to temporary files. Current39identityatlases are exact. Legacy exporter differences are quantified while all source/runtime bytes remain the parent checkpoint. Original arena/top foundation masters are preserved; the arena master predates guarded runtime revisions and must not blindly replace them.'}


def compare(before: Path, after: Path) -> dict:
    left = json.loads((before / 'organisation-validation.json').read_text())
    right = json.loads((after / 'organisation-validation.json').read_text())
    checks = {name: left['deterministic_json'][name] == right['deterministic_json'].get(name)
              for name in left['deterministic_json']}
    return {'passed': all(checks.values()), 'before': str(before), 'after': str(after),
            'exact_json_equivalence': checks, 'scope': left['scope']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=repo_root())
    parser.add_argument('--parent', default='a3fff35dc362856339fc6bfb0ded185edf48bb46')
    parser.add_argument('--out', type=Path, required=True)
    commands = parser.add_subparsers(dest='command', required=True)
    run = commands.add_parser('capture')
    run.add_argument('--engine')
    run.add_argument('--include-prototype', action='store_true')
    commands.add_parser('source')
    art = commands.add_parser('native-art')
    art.add_argument('--aseprite')
    equivalence = commands.add_parser('compare')
    equivalence.add_argument('--before', type=Path, required=True)
    equivalence.add_argument('--after', type=Path, required=True)
    args = parser.parse_args()
    project, output = args.repo.resolve(), args.out.resolve()
    if project == output or project in output.parents:
        parser.error('Validation output must stay outside the game repository')
    output.mkdir(parents=True, exist_ok=True)
    if args.command == 'capture':
        report = capture(project, output, args.parent, find_tool('godot', args.engine), args.include_prototype)
        filename = 'organisation-validation.json'
    elif args.command == 'source':
        report = production_retention(project, args.parent)
        filename = 'production-source-retention.json'
    elif args.command == 'native-art':
        report = native_art(project, args.parent, find_tool('aseprite', args.aseprite))
        filename = 'source-art-integrity.json'
    else:
        report = compare(args.before, args.after)
        filename = 'deterministic-equivalence.json'
    (output / filename).write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    summary = {key: report[key] for key in ('unchanged', 'production_file_count', 'passed', 'status',
                                         'master_count', 'native_atlas_count', 'exact_atlas_count') if key in report}
    print(json.dumps(summary), flush=True)
    if report.get('unchanged', True) is False or report.get('passed', True) is False:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
