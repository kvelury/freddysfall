#!/usr/bin/env python3
"""Fake-engine regressions for the gate itself; no Godot installation needed."""
import contextlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
import test_runner as runner


class RunnerTest(unittest.TestCase):
    def attempt(self, source, **kwargs):
        with contextlib.redirect_stdout(io.StringIO()) as out, contextlib.redirect_stderr(io.StringIO()) as err:
            failure = None
            try:
                runner.run([sys.executable, '-c', source], timeout=kwargs.pop('timeout', 2), marker=r'^FAKE pass$', **kwargs)
            except RuntimeError as error:
                failure = str(error)
        return failure, out.getvalue() + err.getvalue()

    def test_nonzero_preserves_output(self):
        failure, output = self.attempt("import sys; print('FAKE pass'); print('reason', file=sys.stderr); sys.exit(42)")
        self.assertIn('exit status 42', failure or '')
        self.assertIn('reason', output)
        self.assertIn('FAKE pass', output)

    def test_script_error_even_with_pass_and_zero(self):
        failure, _ = self.attempt("print('SCRIPT ERROR: broken'); print('FAKE pass')")
        self.assertIn('script failure', failure or '')

    def test_missing_marker(self):
        failure, _ = self.attempt("print('nothing completed')")
        self.assertIn('missing final success marker', failure or '')

    def test_marker_must_be_final(self):
        failure, _ = self.attempt("print('FAKE pass'); print('unfinished work')")
        self.assertIn('missing final success marker', failure or '')

    def test_timeout_preserves_output(self):
        failure, output = self.attempt("import time; print('started', flush=True); time.sleep(30)", timeout=0.1)
        self.assertIn('timed out', failure or '')
        self.assertIn('started', output)

    def test_normal_pass(self):
        self.assertIsNone(self.attempt("print('FAKE pass')")[0])

    def test_intentional_diagnostic_is_narrow(self):
        diagnostic = [{'pattern': 'ERROR: fake invalid fixture', 'reason': 'Deliberate invalid-input fixture.'}]
        source = "print('ERROR: fake invalid fixture'); print('FAKE pass')"
        self.assertIsNone(self.attempt(source, diagnostics=diagnostic)[0])
        self.assertIn('unexpected engine error', self.attempt(source.replace('fixture', 'other'), diagnostics=diagnostic)[0] or '')
        self.assertIn('shutdown/fixture cleanup', self.attempt("print('WARNING: ObjectDB instances leaked at exit'); print('FAKE pass')", diagnostics=diagnostic)[0] or '')

    def test_manifest_coverage(self):
        runner.manifest()

    def test_pixel_script_propagates_renderer_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'tools').mkdir()
            (root / 'tests').mkdir()
            for name in ('pixel_check.sh', 'test_runner.py'):
                shutil.copyfile(runner.ROOT / 'tools' / name, root / 'tools' / name)
            data = runner.manifest()
            (root / 'tests/test_manifest.json').write_text(json.dumps(data))
            for name in [t['script'] for t in data['tests']] + list(data['excluded_scripts']):
                (root / name).touch()
            engine = root / 'godot'
            engine.write_text('#!/bin/sh\ncase "$*" in\n --version) echo "4.7.2.stable.official.fake" ;;\n *--import*) echo "[ DONE ] loading_editor_layout" ;;\n *) echo "injected renderer failure"; exit 42 ;;\nesac\n')
            engine.chmod(0o755)
            environment = dict(os.environ, PATH=str(root) + os.pathsep + os.environ['PATH'], DISPLAY='fake')
            result = subprocess.run(['sh', str(root / 'tools/pixel_check.sh')], env=environment, capture_output=True, text=True, timeout=10)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('exit status 42', result.stderr)
            self.assertIn('injected renderer failure', result.stdout)


if __name__ == '__main__':
    unittest.main()
