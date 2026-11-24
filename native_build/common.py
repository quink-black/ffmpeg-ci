import fcntl
import hashlib
import json
import os
import platform
import shlex
import shutil
import subprocess
from contextlib import contextmanager
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / 'build' / 'native'
STATE = BUILD / 'locks'
DEFAULT_SOURCE = ROOT.parent / 'ffmpeg'
LEGACY_PREFIX = ROOT / 'install'
WINDOWS = bool(os.environ.get('MSYSTEM')) or platform.system().startswith(('CYGWIN', 'MSYS'))
DARWIN = platform.system() == 'Darwin'
ARCH = platform.machine().lower()

BUILD_ENV = (
    'PATH', 'CC', 'CXX', 'AR', 'AS', 'LD', 'NM', 'RANLIB', 'STRIP', 'NASM',
    'CPPFLAGS', 'CFLAGS', 'CXXFLAGS', 'LDFLAGS', 'LIBS', 'CPATH',
    'C_INCLUDE_PATH', 'CPLUS_INCLUDE_PATH', 'LIBRARY_PATH', 'LD_LIBRARY_PATH',
    'PKG_CONFIG', 'PKG_CONFIG_PATH', 'PKG_CONFIG_LIBDIR', 'PKG_CONFIG_SYSROOT_DIR',
    'CMAKE_PREFIX_PATH', 'CMAKE_ARGS', 'CMAKE_TOOLCHAIN_FILE', 'SDKROOT',
    'DEVELOPER_DIR', 'MACOSX_DEPLOYMENT_TARGET', 'MSYSTEM', 'MSYSTEM_PREFIX',
)


class BuildError(Exception):
    pass


def digest(*values):
    return hashlib.sha256(json.dumps(values, sort_keys=True).encode()).hexdigest()


def file_digest(path):
    checksum = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            checksum.update(chunk)
    return checksum.hexdigest()


def run(args, *, env=None, cwd=ROOT, quiet=False):
    args = [str(arg) for arg in args]
    if not quiet:
        print(f'+ {shlex.join(args)}', flush=True)
    return subprocess.run(args, cwd=cwd, env=env, check=True)


def output(args, *, env=None, cwd=ROOT):
    return subprocess.run(args, cwd=cwd, env=env, stdout=subprocess.PIPE,
                          stderr=subprocess.DEVNULL, text=True, check=False)


def write_state(path, value):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(value + '\n', encoding='utf-8')
    temporary.replace(path)


@contextmanager
def lock(path, *, shared=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('a') as stream:
        fcntl.flock(stream, fcntl.LOCK_SH if shared else fcntl.LOCK_EX)
        yield


def tool_identity(command, env):
    args = shlex.split(command)
    executable = shutil.which(args[0], path=env['PATH'])
    if not executable:
        return command, None
    path = Path(executable).resolve()
    stat = path.stat()
    version = output([*args, '--version'], env=env).stdout.splitlines()[:1]
    return command, str(path), stat.st_size, stat.st_mtime_ns, version


def environment_identity(env, tools):
    return {key: env.get(key) for key in BUILD_ENV}, [tool_identity(t, env) for t in tools]


def build_environment():
    env = os.environ.copy()
    env['PATH'] = env.get('PATH', os.defpath)
    for key, default in (('CC', 'cc'), ('CXX', 'c++'), ('MAKE', 'make'),
                         ('PKG_CONFIG', 'pkg-config')):
        env[key] = env.get(key) or default
    if DARWIN:
        env.setdefault('MACOSX_DEPLOYMENT_TARGET', '11.0')
    return env


def with_prefixes(env, prefixes):
    env = env.copy()
    for key, paths in (
        ('PKG_CONFIG_PATH', [prefix / lib / 'pkgconfig' for prefix in prefixes
                             for lib in ('lib', 'lib64')]),
        ('CMAKE_PREFIX_PATH', prefixes),
        ('LD_LIBRARY_PATH', [prefix / lib for prefix in prefixes for lib in ('lib', 'lib64')]),
        ('DYLD_LIBRARY_PATH', [prefix / 'lib' for prefix in prefixes] if DARWIN else []),
        ('PATH', [prefix / 'bin' for prefix in prefixes] if WINDOWS else []),
    ):
        if paths:
            values = [str(path) for path in paths]
            if env.get(key):
                values.append(env[key])
            env[key] = os.pathsep.join(values)
    return env


def pkg_config(env, *args):
    return output([*shlex.split(env['PKG_CONFIG']), *args], env=env)


def pkg_metadata(env, modules):
    return [pkg_config(env, *flags, module).stdout.strip()
            for module in modules
            for flags in (('--modversion',), ('--cflags',), ('--libs',), ('--static', '--libs'))]


def make(env, jobs, cwd, *args):
    return run([*shlex.split(env['MAKE']), '-j', jobs, *args], env=env, cwd=cwd)
