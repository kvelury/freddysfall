#!/usr/bin/env python3
"""Run the manifest gate without trusting Godot's exit status alone."""
import argparse
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")


def run(command, *, timeout, marker=None, diagnostics=()):
    """Capture both streams, bound the entire process group, and verify evidence."""
    print('==> ' + ' '.join(command), flush=True)
    process = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True, start_new_session=True)
    timed_out = False
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        os.killpg(process.pid, signal.SIGKILL)
        stdout, stderr = process.communicate()
    print(stdout, end='', flush=True)
    print(stderr, end='', file=sys.stderr, flush=True)
    output = ANSI.sub('', stdout + '\n' + stderr)
    failures = []
    if timed_out:
        failures.append(f'timed out after {timeout}s')
    if process.returncode != 0:
        failures.append(f'exit status {process.returncode}')
    final_line = next((line for line in reversed(ANSI.sub('', stdout).splitlines()) if line.strip()), '')
    if marker and not re.fullmatch(marker, final_line):
        failures.append(f'missing final success marker: {marker}')
    for line in output.splitlines():
        # Intentional diagnostics match one complete line and carry a reason in
        # the manifest. SCRIPT ERROR and shutdown/leak reports are never exempt.
        if re.search(r'SCRIPT ERROR|Parse Error|Compile Error', line):
            failures.append('script failure: ' + line)
        elif re.search(r'ObjectDB instances (?:were )?leaked|resources still in use|RID allocations|RIDs? .*leaked|Leaked instance', line):
            failures.append('shutdown/fixture cleanup: ' + line)
        elif re.match(r'\s*ERROR:', line) and not any(re.fullmatch(d['pattern'], line) for d in diagnostics):
            failures.append('unexpected engine error: ' + line)
    if failures:
        raise RuntimeError('; '.join(failures))


def manifest():
    data = json.loads((ROOT / 'tests/test_manifest.json').read_text())
    registered = [test['script'] for test in data['tests']]
    discovered = {str(path.relative_to(ROOT)) for path in (ROOT / 'tests').glob('*_test.gd')}
    if len(registered) != len(set(registered)) or set(registered) != discovered:
        raise ValueError(f'manifest coverage mismatch: missing {discovered - set(registered)}, stale {set(registered) - discovered}')
    excluded = data['excluded_scripts']
    other_scripts = {str(path.relative_to(ROOT)) for path in (ROOT / 'tests').glob('*.gd')} - discovered
    if set(excluded) != other_scripts or not all(excluded.values()):
        raise ValueError('every non-test GDScript must have an explicit exclusion reason')
    for test in data['tests']:
        if test['timeout_seconds'] <= 0 or not test['success_marker']:
            raise ValueError('tests need a positive timeout and final success marker')
        for diagnostic in test.get('intentional_diagnostics', []):
            if not diagnostic['reason']:
                raise ValueError('intentional diagnostics need a reason')
    return data


def version(data, templates=False):
    completed = subprocess.run(['godot', '--version'], cwd=ROOT, capture_output=True, text=True, timeout=15, check=True)
    expected = data['engine_version'].replace('-stable', '.stable.')
    if not completed.stdout.strip().startswith(expected):
        raise ValueError(f'expected Godot {data["engine_version"]}, got {completed.stdout.strip()}')
    if templates:
        location = Path(os.environ.get('GODOT_TEMPLATE_DIR', Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share')) / 'godot/export_templates' / data['engine_version'].replace('-stable', '.stable')))
        for name in ('web_nothreads_release.zip', 'web_nothreads_debug.zip'):
            if not (location / name).is_file():
                raise ValueError(f'missing {data["engine_version"]} export template: {location / name}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['tests', 'import', 'validate', 'version', 'engine-version', 'pixel', 'export'])
    parser.add_argument('selection', nargs='*')
    parser.add_argument('--templates', action='store_true')
    args, extra = parser.parse_known_args()
    data = manifest()
    if args.mode == 'engine-version':
        print(data['engine_version'])
        return
    version(data, args.templates)
    if args.mode == 'version':
        return
    base = ['godot', '--headless', '--path', '.']
    if args.mode == 'import':
        run(base + ['--import'], timeout=180, marker=r'^\[ DONE \]\s+loading_editor_layout\s*$')
    elif args.mode == 'validate':
        run(base + ['--script', 'tests/validate.gd', '--'] + args.selection + extra,
            timeout=2700, marker=r'^validate pass: .+$')
    elif args.mode == 'export':
        version(data, templates=True)
        run(base + ['--export-release', 'Web', 'build/web/index.html'], timeout=300)
    elif args.mode == 'pixel':
        mode = args.selection[0] if args.selection else 'compare'
        command = ['godot', '--audio-driver', 'Dummy', '--path', '.', '--rendering-driver', 'opengl3', '--fixed-fps', '90', '--script', 'tests/pixel_grid.gd', '--', mode]
        import shutil
        if not os.environ.get('DISPLAY') and shutil.which('xvfb-run'):
            command = ['xvfb-run', '-a'] + command
        run(command, timeout=960, marker=None if mode == 'shapes' else r'^PIXEL pass \(\d+ frames (?:captured|compared)\)$')
    else:
        if extra:
            parser.error('unknown arguments: ' + ' '.join(extra))
        names = {Path(t['script']).stem: t for t in data['tests']}
        selected = args.selection or list(names)
        for name in selected:
            key = Path(name).stem
            if key not in names:
                parser.error('unknown test: ' + name)
            test = names[key]
            run(base + ['--script', test['script']], timeout=test['timeout_seconds'],
                marker=test['success_marker'], diagnostics=test.get('intentional_diagnostics', []))
        print(f'TESTS pass: {len(selected)} tests' + (' (focused selection; not the release gate)' if args.selection else ''))


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, ValueError, OSError, subprocess.SubprocessError) as error:
        sys.exit(f'RUNNER FAIL: {error}')
