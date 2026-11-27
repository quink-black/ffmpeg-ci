import argparse
import os
import re
import subprocess
import sys
from pathlib import Path, PureWindowsPath

if os.name != 'posix':
    sys.exit('Use the MSYS2 Python interpreter for native Windows builds.')

from common import DEFAULT_SOURCE, LEGACY_PREFIX, ROOT, WINDOWS, BuildError, build_environment
from dependencies import resolve, select, supported
from libraries import DEPENDENCIES
from ffmpeg import PROFILES, ASanUnavailable, asan_settings, build_dir, build_ffmpeg


def positive_int(value):
    number = int(value)
    if number < 1:
        raise argparse.ArgumentTypeError('must be a positive integer')
    return number


def selection_options(parser):
    parser.add_argument('--deps', default='default',
                        help='default, none, or comma-separated library names (default: %(default)s)')
    parser.add_argument('-j', '--jobs', type=positive_int,
                        default=os.environ.get('FFMPEG_CI_JOBS', str(os.cpu_count() or 1)),
                        help='parallel build jobs (overrides FFMPEG_CI_JOBS)')


def ffmpeg_options(parser):
    selection_options(parser)
    parser.add_argument('--path', default=DEFAULT_SOURCE, metavar='DIR',
                        help='FFmpeg source directory (relative to this repository)')
    parser.add_argument('--profile', choices=PROFILES,
                        help='select a build profile (default: release)')
    parser.add_argument('--variant', default='default', metavar='NAME',
                        help='store an additional configuration for this worktree and profile')
    parser.add_argument('--extra-prefix', type=Path, action='append', default=[],
                        metavar='DIR', help='add an external dependency prefix (repeatable)')
    parser.add_argument('--no-optional-libs', action='store_true',
                        help='skip the optional library probes outside the selected managed dependencies')
    parser.add_argument('--configure-arg', action='append', default=[], metavar='ARG',
                        help='pass an FFmpeg configure option (repeatable, use --configure-arg=ARG)')
    parser.add_argument('--samples', default=os.environ.get('FATE_SAMPLES', ROOT / 'ffmpeg-fate-sample'),
                        metavar='DIR', help='FATE sample directory (overrides FATE_SAMPLES)')
    parser.add_argument('--skip-test', '--skip_test', dest='test', action='store_false',
                        help='build without running FATE')
    parser.add_argument('--test', action='store_true', help='run FATE (default for cibuild.sh)')
    parser.add_argument('--skip-test-case', '--skip_test_case', metavar='LIST',
                        help='comma-separated FFmpeg FATE cases to ignore')
    parser.add_argument('--fate-target', action='append', default=[], metavar='TARGET',
                        help='run a specific fate-* target (repeatable)')
    parser.add_argument('--no-rsync', action='store_true', help='use existing FATE samples')
    parser.add_argument('--install', action='store_true',
                        help='install FFmpeg under the build directory')
    parser.add_argument('--reconfigure', action='store_true', help='rerun FFmpeg configure')
    parser.add_argument('--reuse-deps', action='store_true',
                        help='use cached managed dependencies and skip building missing ones')
    parser.add_argument('--skip-unsupported-asan', action='store_true',
                        help='skip an ASan profile when automatic toolchain selection finds no ASan support')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--print-build-dir', action='store_true', help='print the build directory and exit')
    mode.add_argument('--clean', action='store_true', help='run make clean in the selected FFmpeg build')
    for name in ('--enable_asan', '--enable_opt'):
        parser.add_argument(name, type=int, choices=(0, 1), help=argparse.SUPPRESS)


def absolute_path(value):
    path = Path(value).expanduser()
    if WINDOWS and PureWindowsPath(path).is_absolute():
        path = Path(subprocess.check_output(['cygpath', '-u', str(path)], text=True).rstrip('\n'))
    return (ROOT / path).resolve()


def dependency_command(command, argv, env):
    parser = argparse.ArgumentParser(prog=f'cibuild.sh {command}')
    if command == 'deps':
        selection_options(parser)
        args = parser.parse_args(argv)
        prefixes = resolve(select(args.deps), env, args.jobs)
        for name, prefix in prefixes.items():
            print(f'{name} {prefix}')
    else:
        parser.parse_args(argv)
        for name, dep in DEPENDENCIES.items():
            status = ('default' if dep.default else 'optional') if supported(name) else 'unavailable'
            print(f'{name:<15} {status:<12} third_party/{dep.source}')


def main(argv):
    env = build_environment()
    if argv and argv[0] in ('deps', 'list-deps'):
        dependency_command(argv[0], argv[1:], env)
        return

    parser = argparse.ArgumentParser(
        prog='cibuild.sh',
        epilog='Use cibuild.sh deps to build only dependencies, or cibuild.sh list-deps to list them.')
    ffmpeg_options(parser)
    parser.set_defaults(test=True)
    args = parser.parse_args(argv)
    if args.profile and any(value is not None for value in (args.enable_asan, args.enable_opt)):
        parser.error('--profile cannot be combined with --enable_asan or --enable_opt')
    if not args.profile:
        optimize = args.enable_opt != 0
        args.profile = {
            (False, False): 'debug', (False, True): 'release',
            (True, False): 'asan', (True, True): 'asan-release',
        }[bool(args.enable_asan), optimize]
    if not re.fullmatch(r'[a-z0-9][a-z0-9_.-]{0,63}', args.variant):
        parser.error('--variant must use up to 64 lowercase letters, digits, dots, underscores or hyphens')
    for target in args.fate_target:
        if not re.fullmatch(r'fate-[A-Za-z0-9][A-Za-z0-9_.+-]*', target) or target == 'fate-rsync':
            parser.error(f'invalid FATE target {target!r}')
    source = absolute_path(args.path)
    directory = build_dir(source, args.profile, args.variant)
    if args.print_build_dir:
        print(directory)
        return
    if not args.clean and not (source / 'configure').is_file():
        raise BuildError(f'FFmpeg configure script not found in {source}')
    if source == directory or source in directory.parents:
        raise BuildError(f'The build directory must be outside the FFmpeg source directory: {source}')
    extra = [absolute_path(prefix) for prefix in args.extra_prefix]
    for prefix in extra:
        if not prefix.is_dir():
            raise BuildError(f'External prefix does not exist: {prefix}')
    if not args.no_optional_libs and LEGACY_PREFIX.is_dir():
        extra.append(LEGACY_PREFIX.resolve())
    names = select(args.deps)
    sanitizer = None
    if not args.clean and args.profile.startswith('asan'):
        try:
            sanitizer = asan_settings(env, args.configure_arg)
        except ASanUnavailable as error:
            if not args.skip_unsupported_asan:
                raise
            print(f'Skipping {args.profile}: {error}', flush=True)
            return

    managed = {} if args.clean else resolve(names, env, args.jobs, build=not args.reuse_deps)
    prefixes = list(dict.fromkeys([*reversed(managed.values()), *extra]))
    build_ffmpeg(args, source, directory, env, managed, prefixes, absolute_path(args.samples),
                 sanitizer=sanitizer)


if __name__ == '__main__':
    try:
        main(sys.argv[1:])
    except BuildError as error:
        sys.exit(f'error: {error}')
    except subprocess.CalledProcessError as error:
        print(f'error: {error}', file=sys.stderr)
        sys.exit(error.returncode if error.returncode > 0 else 128 - error.returncode)
    except OSError as error:
        sys.exit(f'error: {error}')
