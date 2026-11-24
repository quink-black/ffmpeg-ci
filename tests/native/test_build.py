import contextlib
import io
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'native_build'))
import common
import dependencies
import ffmpeg


class BuildStateTests(unittest.TestCase):
    def test_cli_profile_selection(self):
        cibuild = common.ROOT / 'cibuild.sh'
        for arguments, profile in (
            ([], 'release'),
            (['--profile', 'debug'], 'debug'),
            (['--enable_opt', '0'], 'debug'),
            (['--enable_opt', '1'], 'release'),
            (['--profile', 'asan'], 'asan'),
            (['--enable_asan', '1'], 'asan-release'),
            (['--enable_asan', '1', '--enable_opt', '0'], 'asan'),
        ):
            with self.subTest(arguments=arguments):
                directory = subprocess.check_output(
                    [cibuild, '--print-build-dir', *arguments], text=True).strip()
                self.assertEqual(Path(directory).parent.name, profile)

    def test_dependency_order(self):
        names = dependencies.select('libplacebo,cms,vulkan_loader')
        self.assertEqual(names, ['cms', 'vulkan_header', 'vulkan_loader', 'libplacebo'])

    def test_git_source_identity_includes_revision_and_tracked_changes(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp).resolve()
            source = root / 'source'
            source.mkdir()
            tracked = source / 'configure'
            tracked.write_text('initial source\n')
            subprocess.run(['git', 'init', '-q'], cwd=root, check=True)
            subprocess.run(['git', 'add', 'source/configure'], cwd=root, check=True)
            subprocess.run(['git', '-c', 'user.name=Test', '-c', 'user.email=test@example.com',
                            'commit', '-qm', 'Initial source'], cwd=root, check=True)

            revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
            initial = dependencies.source_identity(source)
            self.assertEqual(initial[0], revision)
            (source / 'untracked').touch()
            self.assertEqual(dependencies.source_identity(source), initial)
            tracked.write_text('updated source\n')
            self.assertNotEqual(dependencies.source_identity(source), initial)

    def test_failed_dependency_is_retried_and_source_changes_get_new_prefix(self):
        def install(name, dep, source, directory, prefix, env, jobs, options, requirements):
            prefix.mkdir()
            (prefix / 'artifact').write_text((source / 'configure').read_text())
            if attempts[-1] == 'fail':
                raise RuntimeError('interrupted install')

        env = common.build_environment()
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / 'third_party' / 'x264'
            source.mkdir(parents=True)
            (source / 'configure').write_text('initial source')
            attempts = ['fail']
            with (
                contextlib.redirect_stdout(io.StringIO()),
                patch.object(dependencies, 'ROOT', root),
                patch.object(dependencies, 'BUILD', root / 'build'),
                patch.object(dependencies, 'STATE', root / 'locks'),
                patch.object(dependencies, 'environment_identity', return_value={}),
                patch.object(dependencies, 'build_recipe', side_effect=install) as recipe,
            ):
                with self.assertRaisesRegex(RuntimeError, 'interrupted install'):
                    dependencies.resolve(['x264'], env, 1)
                self.assertEqual(dependencies.resolve(['x264'], env, 1, build=False), {})
                attempts.append('pass')
                initial = dependencies.resolve(['x264'], env, 1)['x264']
                self.assertEqual(dependencies.resolve(['x264'], env, 1)['x264'], initial)
                self.assertEqual(recipe.call_count, 2)
                (source / 'configure').write_text('updated source')
                updated = dependencies.resolve(['x264'], env, 1)['x264']
                self.assertNotEqual(updated, initial)
                self.assertEqual((initial / 'artifact').read_text(), 'initial source')
                self.assertEqual((updated / 'artifact').read_text(), 'updated source')

    def test_worktree_paths_and_configuration_reuse(self):
        def configure(command, *, cwd, env):
            (cwd / 'config.h').touch()
            (cwd / 'ffbuild').mkdir(exist_ok=True)
            (cwd / 'ffbuild' / 'config.mak').touch()

        args = SimpleNamespace(clean=False, profile='debug', no_optional_libs=True,
                               skip_test_case='', configure_arg=[], reconfigure=False,
                               jobs=1, test=False, install=False)
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / 'a' / 'ffmpeg'
            source.mkdir(parents=True)
            (source / 'configure').write_text('#!/bin/sh\n')
            env = common.build_environment()
            with (
                contextlib.redirect_stdout(io.StringIO()),
                patch.object(ffmpeg, 'BUILD', root / 'build'),
                patch.object(ffmpeg, 'STATE', root / 'locks'),
                patch.object(ffmpeg, 'environment_identity', return_value={}),
                patch.object(ffmpeg, 'run', side_effect=configure) as config,
                patch.object(ffmpeg, 'make') as make,
            ):
                directory = ffmpeg.build_dir(source, 'debug', 'default')
                self.assertNotEqual(directory, ffmpeg.build_dir(root / 'b' / 'ffmpeg', 'debug', 'default'))
                self.assertNotEqual(directory, ffmpeg.build_dir(source, 'release', 'default'))
                self.assertNotEqual(directory, ffmpeg.build_dir(source, 'debug', 'shared'))
                for _ in range(2):
                    ffmpeg.build_ffmpeg(args, source, directory, env, {}, [], root / 'samples')
                self.assertEqual(config.call_count, 1)
                self.assertEqual(make.call_count, 2)
                args.configure_arg = ['--enable-shared']
                ffmpeg.build_ffmpeg(args, source, directory, env, {}, [], root / 'samples')
                self.assertEqual(config.call_count, 2)
                self.assertEqual(make.call_args_list[-2].args[-1], 'clean')

                (source / 'configure').write_text('#!/bin/sh\n# Changed\n')
                ffmpeg.build_ffmpeg(args, source, directory, env, {}, [], root / 'samples')
                self.assertEqual(config.call_count, 3)


if __name__ == '__main__':
    unittest.main()
