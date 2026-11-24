import os
import re
import shlex
import shutil
import subprocess
from pathlib import Path
from tempfile import TemporaryDirectory

from common import (BUILD, DARWIN, STATE, WINDOWS, digest,
                    environment_identity, file_digest, lock, make, output, pkg_config,
                    pkg_metadata, run, with_prefixes, write_state)
from libraries import DEPENDENCIES

OPTIONAL_LIBS = (
    ('libxml-2.0', 'libxml2', True),
    ('openssl', 'openssl', True),
    ('libwebp', 'libwebp', True),
    ('OpenCL', 'opencl', True),
    ('SvtAv1Enc', 'libsvtav1', False),
    ('libmfx', 'libmfx', False),
    ('libass', 'libass', False),
    ('fribidi', 'libfribidi', False),
    ('harfbuzz', 'libharfbuzz', False),
    ('whisper', 'whisper', True),
    ('caca', 'libcaca', False),
    ('opencv4', 'libopencv', False),
    ('libdrm', 'libdrm', False),
)

PROFILES = ('debug', 'release', 'asan', 'asan-release')


def build_dir(source, profile, variant):
    name = re.sub(r'[^a-zA-Z0-9_.-]', '_', source.name)[:48]
    return BUILD / 'ffmpeg' / f'{name}-{digest(str(source))[:16]}' / profile / variant


def probe_link(env, directory, *, cflags=(), libraries=(), header=None, symbol=None):
    source = directory / 'probe.c'
    code = 'int main(void) { return 0; }\n'
    if header:
        code = (f'#include <{header}>\n'
                f'int main(void) {{ void (*volatile fn)(void) = (void (*)(void)){symbol}; '
                'return fn == 0; }\n')
    source.write_text(code, encoding='ascii')
    cc_flags = shlex.split(env.get('CPPFLAGS', '')) + shlex.split(env.get('CFLAGS', ''))
    ld_flags = shlex.split(env.get('LDFLAGS', ''))
    result = output([*shlex.split(env['CC']), *cc_flags, *cflags, source,
                     '-o', directory / 'probe', *ld_flags, *libraries], env=env)
    return result.returncode == 0


def probe_pkg(env, directory, module, static, header=None, symbol=None):
    if pkg_config(env, '--exists', module).returncode:
        return False
    if not static and not header:
        return True
    cflags = pkg_config(env, '--cflags', module)
    flags = ('--static', '--libs') if static else ('--libs',)
    libraries = pkg_config(env, *flags, module)
    return cflags.returncode == libraries.returncode == 0 and probe_link(
        env, directory, cflags=shlex.split(cflags.stdout), libraries=shlex.split(libraries.stdout),
        header=header, symbol=symbol)


def nvidia_vulkan_icd(env):
    data_home = Path(env.get('XDG_DATA_HOME', Path.home() / '.local' / 'share'))
    config_home = Path(env.get('XDG_CONFIG_HOME', Path.home() / '.config'))
    roots = [data_home, config_home]
    roots.extend(Path(path) for path in env.get('XDG_DATA_DIRS', '/usr/local/share:/usr/share').split(':') if path)
    roots.extend(Path(path) for path in env.get('XDG_CONFIG_DIRS', '/etc/xdg').split(':') if path)
    roots.append(Path('/etc'))
    override = env.get('VK_DRIVER_FILES') or env.get('VK_ICD_FILENAMES')
    if override:
        candidates = [Path(path) for path in override.split(';' if WINDOWS else ':') if path]
    else:
        candidates = [path for root in roots for path in (root / 'vulkan' / 'icd.d').glob('*.json')]
    for candidate in candidates:
        files = candidate.glob('*.json') if candidate.is_dir() else [candidate]
        for path in files:
            try:
                if re.search(r'lib(?:GLX|EGL)_nvidia|nvoglv', path.read_text(errors='replace'), re.I):
                    return True
            except OSError:
                pass
    return False


def onnx_paths(env, directory, prefixes):
    paths = list(prefixes)
    if env.get('ONNXRUNTIME_ROOT'):
        paths.insert(0, Path(env['ONNXRUNTIME_ROOT']).expanduser().resolve())
    for variable in ('prefix', 'exec_prefix'):
        value = pkg_config(env, f'--variable={variable}', 'libonnxruntime').stdout.strip()
        if value:
            paths.append(Path(value))
    paths.append(Path('/usr/local'))
    if DARWIN and shutil.which('brew', path=env['PATH']):
        brew = output(['brew', '--prefix', 'onnxruntime'], env=env)
        if brew.returncode == 0:
            paths.append(Path(brew.stdout.strip()))
    for prefix in dict.fromkeys(paths):
        for subdir in ('include', 'include/onnxruntime', 'include/onnxruntime/core/session'):
            header_dir = prefix / subdir
            if not (header_dir / 'onnxruntime_c_api.h').is_file():
                continue
            for lib_dir in (prefix / 'lib', prefix / 'lib64', prefix / 'lib' / 'x86_64-linux-gnu',
                            prefix / 'lib' / 'aarch64-linux-gnu'):
                if probe_link(env, directory, cflags=[f'-I{header_dir}'],
                              libraries=[f'-L{lib_dir}', '-lonnxruntime'],
                              header='onnxruntime_c_api.h', symbol='OrtGetApiBase'):
                    return [f'-I{header_dir}'], [f'-L{lib_dir}'], [lib_dir]
    if probe_link(env, directory, libraries=['-lonnxruntime'],
                  header='onnxruntime_c_api.h', symbol='OrtGetApiBase'):
        return [], [], []
    return None


def external_options(configure, env, directory, managed, prefixes, asan, optional):
    features = set(re.findall(r'^\s*--enable-([\w-]+)\s', configure, re.MULTILINE))
    config = []
    cflags = []
    ldflags = []
    libraries = []
    runtime_dirs = []
    modules = []

    def enable(module, feature, static):
        if feature in features and probe_pkg(env, directory, module, static):
            config.append(f'--enable-{feature}')
            modules.append(module)
            return True
        return False

    for name, dep in DEPENDENCIES.items():
        if dep.feature and (name in managed or optional):
            enable(dep.module, dep.feature, True)

    if optional:
        for module, feature, static in OPTIONAL_LIBS:
            if (feature != 'libopencv' or not asan) and enable(module, feature, static):
                if feature == 'openssl':
                    config.append('--enable-nonfree')
        if DARWIN and '--enable-libopencv' in config:
            # Unused OpenCV modules can load a second copy of FFmpeg via videoio.
            ldflags.append('-Wl,-dead_strip_dylibs')

    if asan and nvidia_vulkan_icd(env):
        config.append('--disable-vulkan')
        print('ASan build: Vulkan disabled because an NVIDIA ICD is active.', flush=True)
    elif optional or 'vulkan_loader' in managed:
        if pkg_config(env, '--exists', 'vulkan').returncode == 0:
            config.append('--enable-vulkan')
            modules.append('vulkan')
            if shutil.which('glslangValidator', path=env['PATH']):
                config.append('--glslc=glslangValidator')
            if optional:
                enable('shaderc', 'libshaderc', False)

    if '--enable-libplacebo' in config:
        # FFmpeg keeps -l flags after the objects but may move absolute archives ahead of them.
        libraries.extend(flag for flag in shlex.split(pkg_config(env, '--static', '--libs', 'libplacebo').stdout)
                         if os.path.isabs(flag))

    if optional and not asan and 'libopenvino' in features and probe_pkg(
            env, directory, 'openvino', False, 'openvino/c/openvino.h', 'ov_core_create'):
        config.append('--enable-libopenvino')
        modules.append('openvino')
        cflags.extend(shlex.split(pkg_config(env, '--cflags-only-I', 'openvino').stdout))
        ldflags.extend(shlex.split(pkg_config(env, '--libs-only-L', 'openvino').stdout))
        runtime_dirs.extend(Path(flag[2:]) for flag in ldflags if flag.startswith('-L'))

    if optional and 'libonnxruntime' in features:
        onnx = onnx_paths(env, directory, prefixes)
        if onnx:
            include_flags, library_flags, onnx_runtime_dirs = onnx
            config.append('--enable-libonnxruntime')
            cflags.extend(include_flags)
            ldflags.extend(library_flags)
            runtime_dirs.extend(onnx_runtime_dirs)
            modules.append('libonnxruntime')

    return config, cflags, ldflags, libraries, runtime_dirs, pkg_metadata(env, modules)


def configure_flags(args, source, directory, env, managed, prefixes, samples):
    configure_path = source / 'configure'
    configure = configure_path.read_text(encoding='utf-8')
    asan = args.profile.startswith('asan')
    with TemporaryDirectory(dir=directory) as tmp:
        probe_dir = Path(tmp)
        config, cflags, ldflags, libraries, runtime_dirs, metadata = external_options(
            configure, env, probe_dir, managed, prefixes, asan, not args.no_optional_libs)
        if asan:
            version = output([*shlex.split(env['CC']), '--version'], env=env).stdout
            if 'clang' in version.lower():
                config.append('--toolchain=clang-asan')
            else:
                config.append('--toolchain=gcc-asan')
                ldflags.append('-static-libasan')
                # GCC's stack-use-after-return instrumentation can dominate short DSP calls.
                param = '--param=asan-use-after-return=0'
                if probe_link(env, probe_dir, cflags=['-fsanitize=address', param]):
                    cflags.append(param)

    if args.profile in ('debug', 'asan'):
        config.extend(['--enable-debug', '--disable-optimizations'])
    if args.skip_test_case:
        config.append(f'--ignore-tests={args.skip_test_case}')
    cflags.extend(f'-I{prefix / "include"}' for prefix in prefixes if (prefix / 'include').is_dir())
    library_dirs = [prefix / name for prefix in prefixes for name in ('lib', 'lib64')
                    if (prefix / name).is_dir()]
    ldflags.extend(f'-L{path}' for path in library_dirs)
    cflags.extend(shlex.split(env.get('CPPFLAGS', '')))
    cflags.extend(shlex.split(env.get('CFLAGS', '')))
    ldflags.extend(shlex.split(env.get('LDFLAGS', '')))
    if not WINDOWS:
        runtime_dirs.extend(library_dirs)
        ldflags.extend(f'-Wl,-rpath,{path}' for path in dict.fromkeys(runtime_dirs) if path.is_dir())
    libraries.extend(['-pthread', '-lm'])
    libraries.extend(shlex.split(env.get('LIBS', '')))

    ccache = shutil.which('ccache', path=env['PATH'])
    cc, cxx = (f'ccache {env[name]}' if ccache and Path(shlex.split(env[name])[0]).stem != 'ccache'
               else env[name] for name in ('CC', 'CXX'))
    sample_arg = os.path.relpath(samples, directory) if WINDOWS else samples
    flags = [
        f'--prefix={directory / "install"}', f'--cc={cc}',
        f'--cxx={cxx}', f'--ld={env["CXX"]}',
        f'--pkg-config={env["PKG_CONFIG"]}', '--pkg-config-flags=--static',
        '--assert-level=2', '--enable-gpl', '--enable-version3', '--enable-rpath',
        '--disable-doc', '--disable-stripping', f'--samples={sample_arg}',
        f'--extra-cflags={shlex.join(cflags)}',
        f'--extra-cxxflags={shlex.join(shlex.split(env.get("CXXFLAGS", "")))}',
        f'--extra-ldflags={shlex.join(ldflags)}',
        f'--extra-libs={shlex.join(libraries)}', *config, *args.configure_arg,
    ]
    return flags, metadata


def run_fate(args, directory, samples, env):
    sample_lock = STATE / f'fate-{digest(str(samples))}.lock'
    targets = args.fate_target or ['fate']
    try:
        if not args.no_rsync:
            with lock(sample_lock):
                samples.mkdir(parents=True, exist_ok=True)
                make(env, args.jobs, directory, 'fate-rsync')
        with lock(sample_lock, shared=True):
            make(dict(env, VERBOSE='1'), args.jobs, directory, *targets)
    except subprocess.CalledProcessError:
        print(f'=== FATE RESULT: FAIL ({directory}) ===', flush=True)
        raise
    print(f'=== FATE RESULT: PASS ({directory}) ===', flush=True)


def runtime_environment(directory, prefixes, shared):
    variables = with_prefixes({'PATH': ''}, [directory / 'install', *prefixes])
    library_var = 'PATH' if WINDOWS else 'DYLD_LIBRARY_PATH' if DARWIN else 'LD_LIBRARY_PATH'
    if shared:
        build_paths = [str(path) for path in sorted(directory.glob('lib*')) if path.is_dir()]
        if variables.get(library_var):
            build_paths.append(variables[library_var])
        variables[library_var] = os.pathsep.join(build_paths)
    return {name: value for name, value in variables.items()
            if name in ('PATH', 'LD_LIBRARY_PATH', 'DYLD_LIBRARY_PATH') and value}


def build_ffmpeg(args, source, directory, env, managed, prefixes, samples):
    with lock(STATE / f'ffmpeg-{digest(str(directory))}.lock'):
        if args.clean:
            if (directory / 'ffbuild' / 'config.mak').is_file():
                make(env, args.jobs, directory, 'clean')
            return
        directory.mkdir(parents=True, exist_ok=True)
        config_env = with_prefixes(env, prefixes)
        flags, metadata = configure_flags(args, source, directory, config_env, managed, prefixes, samples)
        tools = [env[key] for key in ('CC', 'CXX', 'MAKE', 'PKG_CONFIG')]
        tools.extend(['ccache', 'nasm', 'glslc', 'glslangValidator', env.get('AR', 'ar')])
        configure = source / 'configure'
        key = digest(file_digest(configure), flags, metadata, list(map(str, prefixes)),
                     environment_identity(config_env, tools))
        marker = directory / '.configured'
        config_mak = directory / 'ffbuild' / 'config.mak'
        previous = marker.read_text(encoding='utf-8').strip() if marker.exists() else None
        if args.reconfigure or previous != key or not config_mak.is_file() or not (directory / 'config.h').is_file():
            had_objects = config_mak.is_file() or (directory / 'Makefile').exists()
            marker.unlink(missing_ok=True)
            run([configure, *flags], env=config_env, cwd=directory)
            if had_objects:
                make(config_env, args.jobs, directory, 'clean')
            write_state(marker, key)
        else:
            print(f'Using FFmpeg configuration: {directory}', flush=True)
        make(config_env, args.jobs, directory)
        shared = 'CONFIG_SHARED=yes' in config_mak.read_text(encoding='utf-8').splitlines()
        runtime = runtime_environment(directory, prefixes, shared)
        runtime_env = config_env.copy()
        exports = []
        for name, value in runtime.items():
            exports.append(f'export {name}={shlex.quote(value)}${{{name}:+:${name}}}')
            runtime_env[name] = os.pathsep.join(filter(None, (value, env.get(name))))
        write_state(directory / 'runtime.env', '\n'.join(exports))
        if args.test:
            run_fate(args, directory, samples, runtime_env)
        if args.install:
            make(config_env, args.jobs, directory, 'install')
        suffix = '.exe' if WINDOWS else ''
        print(f'FFmpeg build: {directory}', flush=True)
        for program in ('ffmpeg', 'ffprobe'):
            binary = directory / f'{program}{suffix}'
            if binary.is_file():
                print(binary, flush=True)
