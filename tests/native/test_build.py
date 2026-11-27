import contextlib
import io
import shlex
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
import main as native_cli


class BuildStateTests(unittest.TestCase):
    def test_asan_probe_uses_the_configured_linker(self):
        success = SimpleNamespace(returncode=0, stdout='')
        with (
            patch.object(ffmpeg, 'WINDOWS', True),
            patch.object(ffmpeg, 'output', return_value=SimpleNamespace(stdout='clang version')),
            patch.object(ffmpeg.subprocess, 'run', return_value=success) as run,
        ):
            settings = ffmpeg.asan_settings(
                {'CC': 'cc', 'CXX': 'c++', 'LDFLAGS': '-Lenv'},
                ['--cc=clang', '--ld=clang++', '--extra-ldflags=-Lfirst',
                 '--extra-ldflags=-Lsecond', '--extra-ldexeflags=-Lexe'])

        self.assertEqual(settings, ('--toolchain=clang-asan', [], []))
        compile_args, link_args = [call.args[0] for call in run.call_args_list]
        self.assertEqual(compile_args[0], 'clang')
        self.assertIn('-c', compile_args)
        self.assertEqual(link_args[0], 'clang++')
        self.assertEqual(link_args[1:5], ['-Lenv', '-Lfirst', '-Lsecond', '-Lexe'])
        self.assertIn('-fsanitize=address', link_args)

    def test_windows_gcc_missing_asan_runtime(self):
        def check(command, **kwargs):
            if command[0] == 'c++' and '-fsanitize=address' in command:
                self.assertNotIn('-static-libasan', command)
                return SimpleNamespace(returncode=1, stdout='cannot find -lasan')
            return SimpleNamespace(returncode=0, stdout='')

        with (
            patch.object(ffmpeg, 'WINDOWS', True),
            patch.object(ffmpeg, 'output', return_value=SimpleNamespace(stdout='GCC')),
            patch.object(ffmpeg.subprocess, 'run', side_effect=check),
        ):
            with self.assertRaisesRegex(ffmpeg.ASanUnavailable, 'cannot find -lasan'):
                ffmpeg.asan_settings({'CC': 'cc', 'CXX': 'c++'}, [])

    def test_unsupported_asan_skips_only_on_request(self):
        with tempfile.TemporaryDirectory() as temp:
            source = Path(temp).resolve()
            (source / 'configure').touch()
            args = ['--path', str(source), '--profile', 'asan-release']
            unavailable = ffmpeg.ASanUnavailable('missing ASan runtime')
            with (
                contextlib.redirect_stdout(io.StringIO()) as stdout,
                patch.object(native_cli, 'asan_settings', side_effect=unavailable) as probe,
                patch.object(native_cli, 'resolve') as resolve,
                patch.object(native_cli, 'build_ffmpeg') as build,
            ):
                with self.assertRaisesRegex(ffmpeg.ASanUnavailable, 'missing ASan runtime'):
                    native_cli.main(args)
                native_cli.main([*args, '--skip-unsupported-asan'])
                self.assertIn('Skipping asan-release: missing ASan runtime', stdout.getvalue())

                probe.side_effect = common.BuildError('ordinary toolchain failure')
                with self.assertRaisesRegex(common.BuildError, 'ordinary toolchain failure'):
                    native_cli.main([*args, '--skip-unsupported-asan'])
                resolve.assert_not_called()
                build.assert_not_called()

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

    def test_managed_libraries_precede_optional_probe_paths(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'configure').touch()
            managed_lib = root / 'managed' / 'lib'
            optional_lib = root / 'onnxruntime' / 'lib'
            legacy_lib = root / 'install' / 'lib'
            library_dirs = [managed_lib, optional_lib, legacy_lib]
            for path in library_dirs:
                path.mkdir(parents=True)

            args = SimpleNamespace(profile='debug', no_optional_libs=False,
                                   skip_test_case='', configure_arg=[])
            options = ([], [], [f'-L{optional_lib}'], [], [optional_lib], [])
            managed = {'libplacebo': managed_lib.parent}
            prefixes = [managed_lib.parent, legacy_lib.parent]
            with patch.object(ffmpeg, 'external_options', return_value=options):
                flags, _ = ffmpeg.configure_flags(args, root, root, common.build_environment(),
                                                  managed, prefixes, root / 'samples')

            ldflags = shlex.split(next(flag.split('=', 1)[1] for flag in flags
                                      if flag.startswith('--extra-ldflags=')))
            self.assertEqual(ldflags[:3], [f'-L{path}' for path in library_dirs])
            if not ffmpeg.WINDOWS:
                self.assertEqual([flag for flag in ldflags if flag.startswith('-Wl,-rpath,')][-3:],
                                 [f'-Wl,-rpath,{path}' for path in library_dirs])

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
