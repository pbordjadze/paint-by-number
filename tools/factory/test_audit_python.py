"""Regression probes for F23's Python audit fixes."""
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from factory.taste import accounting, kit, loop, runners, schema
from factory.taste.pieces import color_names, panel_name
import render
import reveal_sheet
import verify

ROOT = loop.REPO


class AuditTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=os.environ.get('FACTORY_TEST_OUT', tempfile.gettempdir()))
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.job = dict(id='proposer-moon', round=1, attempt=0, role='proposer', guardian='moon',
                        model='test', effort='low', images=[], prompt='test', reply_schema={})
        self.log = self.root / 'agent.output'
        self.log.write_text('{}')

    def test_job_ids_rounds_and_attempts_are_validated(self):
        for field, values in [('id', ['', ' ', '../escape', '/absolute', 'a/b', 'a\\b', '.', '..']),
                              ('round', [0, -1, True, 1.5, '1']), ('attempt', [-1, 2, True, 0.5, '0'])]:
            for value in values:
                job = {**self.job, field: value}
                with self.subTest(field=field, value=value):
                    for action in (lambda: runners.destination(self.root, job),
                                   lambda: accounting.record(self.root, job, self.log)):
                        with self.assertRaises(ValueError):
                            action()

    def test_runner_negative_job_fixtures_do_not_write_or_dispatch(self):
        self.log.write_text(json.dumps({'message': {'content': [{'type': 'tool_use',
            'name': 'SubagentHandback', 'input': {'message': '{"ok":true}'}}]}}))
        run, out = self.root / 'run', self.root / 'scratch'
        for bad_id in ('../../../escape', '/absolute'):
            fixture = self.root / 'job.json'
            fixture.write_text(json.dumps({**self.job, 'id': bad_id}))
            with patch.object(runners.subprocess, 'run') as dispatch:
                for action in (lambda: runners.claude(run, fixture, self.log),
                               lambda: runners.codex(run, fixture, out)):
                    with self.assertRaises(ValueError): action()
                dispatch.assert_not_called()
        self.assertFalse(run.exists())
        self.assertFalse(out.exists())

    def test_legacy_collect_rejects_empty_names(self):
        source = ROOT / 'factory/pieces/color-names/run'
        run = self.root / 'colors'
        shutil.copytree(source, run)
        proposal = loop.load(run / 'proposals/medea.json')
        proposal['names']['1'] = [{'name': '', 'why': 'empty'}, {'name': '   ', 'why': 'whitespace'}]
        loop.save(run / 'proposals/medea.json', proposal)
        with patch.object(color_names, 'RUN', str(run)), contextlib.redirect_stdout(io.StringIO()):
            color_names.collect()
        candidates = [c['name'] for slot in loop.load(run / 'slots.json') for c in slot['candidates']]
        self.assertTrue(all(name.strip() for name in candidates))
        rejected = loop.load(run / 'rejected.json')
        self.assertEqual(sum(not candidate['name'].strip() for candidate in rejected), 2)

    def test_render_cli_refuses_symlinked_children_before_dispatch(self):
        out = self.root / 'render'
        out.mkdir()
        (out / 'frames').symlink_to(self.root / 'victim')
        args = ['render.py', 'spec.json', 'scene.json', str(out), '--figures', str(self.log)]
        with patch('sys.argv', args), patch.object(render, 'run') as run, patch('sys.stderr'):
            with self.assertRaises(SystemExit) as caught: render.main()
        self.assertEqual(caught.exception.code, 2)
        run.assert_not_called()
        self.assertFalse((self.root / 'victim').exists())

    def test_engine_cleanup_preserves_unrelated_files(self):
        out = self.root / 'render'
        frames = out / 'frames'
        frames.mkdir(parents=True)
        for name in ('notes.svg', 'reference.png', '0003.svg'):
            (frames / name).write_text('keep')
        def fake_engine(command):
            fresh = Path(command[-1])
            (fresh / 'frames').mkdir()
            (fresh / 'manifest.json').write_text('{}')
            (fresh / 'frames/0000.svg').write_text('new')
        with patch.object(render, 'run', side_effect=fake_engine):
            render.render_engine('figures', 'spec', 'scene', out)
        self.assertEqual((frames / 'notes.svg').read_text(), 'keep')
        self.assertEqual((frames / 'reference.png').read_text(), 'keep')
        self.assertFalse((frames / '0003.svg').exists())
        self.assertEqual((frames / '0000.svg').read_text(), 'new')

    def test_reply_cost_and_scratch_symlinks_are_refused_before_writes(self):
        from factory.taste import paths
        run = self.root / 'run'
        run.mkdir()
        outside = self.root / 'outside'
        outside.mkdir()
        for kind in ('replies', 'costs', 'scratch'):
            (run / ('001' if kind == 'scratch' else kind)).symlink_to(outside, target_is_directory=True)
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                paths.job_path(run, self.job, kind)
        self.assertEqual(list(outside.iterdir()), [])
        (run / 'replies').unlink()
        (run / 'replies/001').mkdir(parents=True)
        target = run / 'replies/001/proposer-moon.json'
        target.symlink_to(outside / 'missing.json')
        with self.assertRaises(ValueError):
            runners.destination(run, self.job)

    def test_linked_ancestors_are_allowed_like_macos_tmp(self):
        # macOS reaches /tmp and $TMPDIR through links; only what lies below the output counts.
        from factory.taste import paths
        import output_paths
        real = self.root / 'private'
        (real / 'out').mkdir(parents=True)
        (self.root / 'tmp').symlink_to(real, target_is_directory=True)
        linked = self.root / 'tmp/out'
        self.assertEqual(output_paths.outside_repo(linked), (real / 'out').resolve())
        self.assertEqual(paths.job_path(linked, self.job, 'replies'),
                         (real / 'out/replies/001/proposer-moon.json').resolve())
        (real / 'out/frames').symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(ValueError):
            output_paths.outside_repo(linked)

    def test_legacy_extractors_reject_escaping_ids_and_symlinks(self):
        with patch.object(color_names, 'RUN', str(self.root)):
            for name in ('../escape', '/absolute', ''):
                with self.assertRaises(ValueError):
                    color_names.extract('proposals', name, str(self.log))
            (self.root / 'proposals').symlink_to(self.root / 'elsewhere', target_is_directory=True)
            with self.assertRaises(ValueError):
                color_names.extract('proposals', 'moon', str(self.log))
        with patch.object(panel_name, 'RUN', str(self.root)):
            for n, name in [('1', '../escape'), ('0', 'moon'), ('1', '/absolute')]:
                with patch('sys.argv', ['taste.py', 'extract', n, 'proposals', name, str(self.log)]):
                    with self.assertRaises(ValueError):
                        panel_name.main()

    def test_engine_missing_manifest_cannot_reuse_old_artifacts(self):
        out = self.root / 'render'
        (out / 'frames').mkdir(parents=True)
        old = out / 'frames/0000.svg'
        old.write_text('old')
        with patch.object(render, 'run'), self.assertRaisesRegex(RuntimeError, 'manifest.json'):
            render.render_engine('figures', 'spec', 'scene', out)
        self.assertEqual(old.read_text(), 'old')

    def test_empty_names_fail_craft(self):
        for name in ('', ' ', '\t\n'):
            self.assertTrue(color_names.craft(name, {'incumbent': 'Honey'}, set()))
            self.assertTrue(panel_name.craft(name, {})[0])

    def test_schema_json_equality_distinguishes_booleans_recursively(self):
        for first, second in [(True, 1), (False, 0), ([True], [1]), ({'x': False}, {'x': 0})]:
            with self.subTest(first=first, second=second):
                self.assertTrue(schema.validate(first, {'enum': [second]}))
                self.assertEqual(schema.validate([first, second], {'uniqueItems': True}), [])
        self.assertEqual(schema.validate(1.0, {'enum': [1]}), [])
        self.assertTrue(schema.validate([{'x': 1}, {'x': 1.0}], {'uniqueItems': True}))

    def test_translucent_material_contrast_ignores_edge_antialiasing(self):
        paper = Image.new('RGB', (3, 1), '#F6F1E7')
        mask = Image.new('RGBA', (3, 1), (85, 85, 85, 128))
        self.assertLess(render.ink_contrast(paper, [mask], '#55555580'), 3)
        mask.putalpha(64)
        self.assertLess(render.ink_contrast(paper, [mask], '#55555580'), 3)
        mask.putalpha(255)
        self.assertGreater(render.ink_contrast(paper, [mask], '#555555'), 3)
        self.assertEqual(render.ink_contrast(paper, [Image.new('RGBA', (3, 1))], '#55555580'), 1)

    def test_generic_case_variants_cannot_win_two_slots(self):
        results = [dict(slot=str(i), owner='g', winner=name, winner_source='g',
                        standings=[dict(name=name, source='g', score=1, vetoes=[])])
                   for i, name in enumerate(('Lamp', 'lamp'))]
        with self.assertRaisesRegex(ValueError, 'no legal name set'):
            loop.select(results, {}, {'0': '0', '1': '1'}, lambda table: [])

    def test_identity_applies_to_repairs_guarantee_and_assignment_search(self):
        def standing(name, source, score):
            return dict(name=name, source=source, score=score, vetoes=[])
        results = [dict(slot='1', owner='g1', winner='The Café', winner_source='g1', standings=[
            standing('The Café', 'g1', 10), standing('Garden', 'incumbent', 0)]),
            dict(slot='2', owner='g2', winner='Cafe', winner_source='g2', standings=[
            standing('Cafe', 'g2', 9), standing('Moon', 'g2', 8)])]
        class Caps:
            def __call__(self, table): return []
            def contributes(self, *args): return False
        # The piece's own normalization is authoritative at every selection stage.
        loop.select(results, {}, {'1': '1', '2': '2'}, Caps(), owners=['g1', 'g2'],
                    guarantee=True, identity=panel_name.identity)
        self.assertEqual([r['winner'] for r in results], ['The Café', 'Moon'])
        assignment = loop.legal_assignment(results, {}, {'1': '1', '2': '2'}, Caps(),
                                           ['g1', 'g2'], identity=panel_name.identity)
        self.assertEqual(assignment['2']['name'], 'Moon')
        self.assertIsNone(loop.legal_assignment([], {'a': 'The Café', 'b': 'Cafe'}, {}, Caps(), [],
                                               identity=panel_name.identity))

    def test_repository_and_symlinked_outputs_are_refused(self):
        from output_paths import outside_repo
        for path in (ROOT, ROOT / 'factory/unsafe.html'):
            with self.assertRaises(ValueError): outside_repo(path)
            with self.assertRaises(ValueError): reveal_sheet.make_sheet(self.root, self.root, path)
        out = self.root / 'out'
        out.mkdir()
        victim = self.root / 'victim'
        victim.write_text('keep')
        for child in ('frames', 'sheets', 'checks.json', 'clip.mp4'):
            link = out / child
            link.symlink_to(victim)
            with self.assertRaises(ValueError): outside_repo(out)
            link.unlink()
        link = self.root / 'sheet.png'
        link.symlink_to(victim)
        with self.assertRaises(ValueError): reveal_sheet.make_sheet(self.root, self.root, link)
        self.assertEqual(victim.read_text(), 'keep')

    def test_collection_refuses_its_input_repository_and_output_symlinks(self):
        repo = self.root / 'input'
        repo.mkdir()
        for output in (repo / 'page.html', self.root / 'link.html'):
            if output.name == 'link.html': output.symlink_to(repo / 'victim.html')
            result = subprocess.run([sys.executable, str(ROOT / 'tools/factory/collection.py'), str(repo),
                                     str(output), str(ROOT / 'tools/factory/collection_template.html')],
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('output', result.stderr)
            self.assertFalse((repo / 'victim.html').exists())

    def test_only_numbered_frame_files_are_removed(self):
        folder = self.root / 'frames'
        folder.mkdir()
        for name in ('0000.png', '0001.svg', 'notes.svg', 'reference.png', '123.png'):
            (folder / name).write_text('keep')
        render.clean_frames(folder)
        self.assertEqual(sorted(p.name for p in folder.iterdir()), ['123.png', 'notes.svg', 'reference.png'])

    def test_build_configuration_and_missing_build_messages(self):
        with patch.dict(os.environ, {'FIGURES_BIN': str(self.log), 'SWIFT_SCRATCH_PATH': str(self.root / 'build')}):
            self.assertEqual(verify.figures_binary(), self.log)
            self.assertEqual(verify.swift_test_command(), ['swift', 'test', '--scratch-path', str(self.root / 'build')])
        with patch.dict(os.environ, {'FIGURES_BIN': str(self.root / 'missing')}):
            with self.assertRaisesRegex(RuntimeError, 'build figures first'):
                verify.figures_binary()

    def test_public_help_has_no_side_effects(self):
        scripts = sorted((ROOT / 'tools/factory').glob('*.py'))
        scripts = [s for s in scripts if not s.name.startswith('test_') and s.name != 'output_paths.py']
        scripts += [ROOT / 'factory/taste/loop', ROOT / 'factory/taste/taste.py', ROOT / 'factory/taste/colors.py',
                    ROOT / 'factory/pieces/marginarium/poll.py']
        commands = [[sys.executable, str(s), '--help'] for s in scripts]
        commands += [[sys.executable, '-m', name, '--help'] for name in ('factory.taste', 'factory.taste.runners')]
        def snapshot():
            return {p: hashlib.sha256(p.read_bytes()).hexdigest() for base in
                    (ROOT / 'Sources', ROOT / 'factory', ROOT / 'tools/factory', self.root)
                    for p in base.rglob('*') if p.is_file() and '__pycache__' not in p.parts}
        before = snapshot()
        for command in commands:
            with self.subTest(command=command):
                result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True,
                                        env={**os.environ, 'PYTHONDONTWRITEBYTECODE': '1'})
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('usage:', result.stdout.lower())
        self.assertEqual(snapshot(), before)

    def test_help_does_not_require_optional_dependencies(self):
        blocker = self.root / 'sitecustomize.py'
        blocker.write_text("import sys\nclass Block:\n def find_spec(self, fullname, *args):\n  if fullname.split('.')[0] in ('PIL', 'fontTools'): raise ImportError('optional dependency imported')\nsys.meta_path.insert(0, Block())\n")
        scripts = ('render.py', 'reveal_sheet.py', 'collection.py', 'verify.py', 'card_font.py',
                   'make_scene.py', 'nickname_traffic.py', 'palette_gallery.py')
        commands = [[sys.executable, str(ROOT / 'tools/factory' / s), '--help'] for s in scripts]
        commands += [[sys.executable, '-m', m, '--help'] for m in ('factory.taste', 'factory.taste.runners')]
        for command in commands:
            with self.subTest(command=command):
                result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, env={**os.environ,
                    'PYTHONPATH': str(self.root) + os.pathsep + str(ROOT), 'PYTHONDONTWRITEBYTECODE': '1'})
                self.assertEqual(result.returncode, 0, result.stderr)
