import os
import platform
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

from common import (ARCH, BUILD, DARWIN, ROOT, STATE, WINDOWS, BuildError,
                    digest, environment_identity, file_digest, lock, make, output,
                    pkg_config, pkg_metadata, run, with_prefixes, write_state)
from libraries import DEPENDENCIES


def supported(name):
    if name in ('davs2', 'xavs2'):
        return platform.system() in ('Darwin', 'Linux') and not WINDOWS and ARCH in ('x86_64', 'amd64')
    return True


def select(selection):
    if selection == 'none':
        return []
    order = []

    def add(name):
        if name not in DEPENDENCIES:
            raise BuildError(f'Unknown dependency {name!r}. See cibuild.sh list-deps.')
        if not supported(name):
            raise BuildError(f'{name} is unavailable on this platform.')
        if name not in order:
            for required in DEPENDENCIES[name].requires:
                add(required)
            order.append(name)

    for name in map(str.strip, selection.split(',')):
        if name == 'default':
            for default, dependency in DEPENDENCIES.items():
                if dependency.default and supported(default):
                    add(default)
        else:
            add(name)
    return order


def git_files(source):
    return subprocess.check_output(['git', '-C', source, 'ls-files', '-z', '--', '.']).split(b'\0')


def source_identity(source):
    repo = output(['git', 'rev-parse', '--show-toplevel'], cwd=source)
    if repo.returncode == 0:
        git_root = Path(repo.stdout.strip()).resolve()
        if git_root in (source, source.parent) and git_root != ROOT:
            head = output(['git', 'rev-parse', 'HEAD'], cwd=source)
            if head.returncode:
                raise BuildError(f'Cannot read Git HEAD for {source}')
            changes = subprocess.check_output(['git', 'diff', '--binary', '--no-ext-diff',
                                               '--submodule=diff', 'HEAD', '--', '.'], cwd=source)
            submodules = output(['git', 'submodule', 'status', '--recursive', '--', '.'], cwd=source)
            if submodules.returncode:
                raise BuildError(f'Cannot read submodule state for {source}')
            missing = [line for line in submodules.stdout.splitlines() if line.startswith('-')]
            if missing:
                raise BuildError(f'Initialize the nested submodules in {source}: '
                                 'git submodule update --init --recursive')
            revisions = [line.split()[:2] for line in submodules.stdout.splitlines()]
            return head.stdout.strip(), digest(changes.hex()), revisions
    return [(str(path.relative_to(source)), file_digest(path))
            for path in sorted(source.rglob('*')) if path.is_file()]


def copy_source(source, destination):
    if not (source / '.git').exists():
        shutil.copytree(source, destination, symlinks=True)
        return
    destination.mkdir()
    for name in filter(None, git_files(source)):
        path = source / os.fsdecode(name)
        if not path.is_file() and not path.is_symlink():
            continue
        target = destination / os.fsdecode(name)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target, follow_symlinks=False)
    git_dir = output(['git', 'rev-parse', '--absolute-git-dir'], cwd=source)
    if git_dir.returncode == 0:
        (destination / '.git').write_text(f'gitdir: {git_dir.stdout.strip()}\n', encoding='utf-8')


def cmake(source, build_dir, prefix, env, jobs, options):
    run(['cmake', '-S', source, '-B', build_dir, '-G', 'Ninja',
         '-DCMAKE_BUILD_TYPE=RelWithDebInfo', '-DCMAKE_POSITION_INDEPENDENT_CODE=ON',
         f'-DCMAKE_INSTALL_PREFIX={prefix}', '-DCMAKE_INSTALL_LIBDIR=lib',
         '-DCMAKE_POLICY_VERSION_MINIMUM=3.5', *options], env=env)
    run(['cmake', '--build', build_dir, '--parallel', jobs], env=env)


def x265(source, build_dir, prefix, env, jobs, options):
    options = (*options, '-DENABLE_SHARED=OFF')
    for depth, flags in (
        ('12bit', ('-DHIGH_BIT_DEPTH=ON', '-DMAIN12=ON')),
        ('10bit', ('-DHIGH_BIT_DEPTH=ON',)),
    ):
        cmake(source, build_dir / depth, prefix, env, jobs,
              (*options, '-DENABLE_CLI=OFF', '-DEXPORT_C_API=OFF', *flags))
    libraries = [build_dir / depth / 'libx265.a' for depth in ('10bit', '12bit')]
    main = build_dir / '8bit'
    cmake(source, main, prefix, env, jobs,
          (*options, '-DLINKED_10BIT=ON', '-DLINKED_12BIT=ON',
           '-DEXTRA_LIB=' + ';'.join(map(str, libraries))))
    run(['cmake', '--install', main], env=env)
    # Keep CMake's 8-bit archive intact for the CLI and merge the installed archive.
    destination = prefix / 'lib' / 'libx265.a'
    merged = build_dir / 'libx265.a'
    if DARWIN:
        run(['libtool', '-static', '-o', merged, destination, *libraries], env=env)
    else:
        archive_root = prefix / 'lib'
        for depth, library in zip(('10', '12'), libraries):
            shutil.copyfile(library, archive_root / f'x265-{depth}.a')
        script = ('CREATE x265-all.a\nADDLIB libx265.a\nADDLIB x265-10.a\n'
                  'ADDLIB x265-12.a\nSAVE\nEND\n')
        subprocess.run([*shlex.split(env.get('AR', 'ar')), '-M'], input=script, text=True,
                       env=env, cwd=archive_root, check=True)
        (archive_root / 'x265-all.a').replace(merged)
        for depth in ('10', '12'):
            (archive_root / f'x265-{depth}.a').unlink()
    merged.replace(destination)


def recipe_options(name, dep, env):
    options = list(dep.options)
    if name == 'vvdec':
        version = output([*shlex.split(env['CXX']), '--version'], env=env).stdout
        if 'clang' in version.lower():
            # This release treats Clang's newer diagnostics as errors.
            options.append(f'-DCMAKE_CXX_FLAGS={env["CXXFLAGS"]} '
                           '-Wno-unknown-warning-option -Wno-error=nontrivial-memcall')
    if name == 'vulkan_loader' and not (WINDOWS or DARWIN):
        for option, modules in (
            ('XCB', ('xcb',)), ('XLIB', ('x11',)),
            ('XLIB_XRANDR', ('x11', 'xrandr')), ('WAYLAND', ('wayland-client',)),
        ):
            if pkg_config(env, '--exists', *modules).returncode:
                options.append(f'-DBUILD_WSI_{option}_SUPPORT=OFF')
    return options


def fix_aom_nasm_probe(source):
    path = source / 'cmake' / 'aom_optimization.cmake'
    if not path.is_file():
        path = source / 'build' / 'cmake' / 'aom_optimization.cmake'
        if not path.is_file():
            return
    text = path.read_text(encoding='utf-8')
    help_check = '  if(NOT "${nasm_helptext}" MATCHES "-Ox")'
    if help_check not in text:
        return
    # NASM 3 still accepts -Ox but omits that spelling from -hf.
    assemble_check = '''  set(probe "${CMAKE_CURRENT_BINARY_DIR}/nasm-optimization-probe")
  file(WRITE "${probe}.asm" "nop\\n")
  execute_process(COMMAND "${CMAKE_ASM_NASM_COMPILER}" -Ox -f bin
                          -o "${probe}.bin" "${probe}.asm"
                  RESULT_VARIABLE nasm_optimization_result)
  file(REMOVE "${probe}.asm" "${probe}.bin")
  if(NOT nasm_optimization_result STREQUAL "0")'''
    path.write_text(text.replace(help_check, assemble_check), encoding='utf-8')


def build_recipe(name, dep, source, directory, prefix, env, jobs, options, requirements):
    build_dir = directory / 'build'
    aom_x86 = name == 'aom' and ARCH in ('x86_64', 'amd64', 'i386', 'i686', 'x86')
    if aom_x86 or dep.backend in ('cmake-copy', 'davs2', 'autogen'):
        copied = directory / 'source'
        copy_source(source, copied)
        source = copied
    if aom_x86:
        fix_aom_nasm_probe(source)
    if dep.backend.startswith('cmake'):
        cmake(source, build_dir, prefix, env, jobs, options)
        run(['cmake', '--install', build_dir], env=env)
        if name == 'vulkan_loader':
            # The loader's pkg-config file assumes its headers share the loader prefix.
            pc = prefix / 'lib' / 'pkgconfig' / 'vulkan.pc'
            headers = requirements['vulkan_header'] / 'include'
            pc.write_text(pc.read_text().replace('includedir=${prefix}/include',
                                                 f'includedir={headers}'))
    elif dep.backend == 'x265':
        x265(source, build_dir, prefix, env, jobs, options)
    elif dep.backend == 'meson':
        meson = ROOT / 'third_party' / 'meson' / 'meson.py'
        run([sys.executable, meson, 'setup', build_dir, source, '--wrap-mode=nodownload',
             '--buildtype=release', '-Ddefault_library=static', f'--prefix={prefix}',
             '--libdir=lib', *options], env=env)
        run(['ninja', '-C', build_dir, '-j', jobs, 'install'], env=env)
    elif dep.backend == 'davs2':
        # The AVS2 configure scripts resolve their sources relative to the working directory.
        work = source / 'build' / 'linux'
        env = dict(env, CC=env['CXX'])
        run(['bash', './configure', f'--prefix={prefix}', '--enable-pic', *options], cwd=work, env=env)
        make(env, jobs, work, 'install')
    elif dep.backend in ('configure', 'autogen'):
        if dep.backend == 'autogen':
            run(['./autogen.sh'], cwd=source, env=env)
        build_dir.mkdir()
        run([source / 'configure', f'--prefix={prefix}', *options], cwd=build_dir, env=env)
        make(env, jobs, build_dir, 'install')
    else:
        raise BuildError(f'Unknown build backend {dep.backend!r} for {name}')


def resolve(names, env, jobs, *, build=True):
    prefixes = {}
    versions = {}
    for name in names:
        dep = DEPENDENCIES[name]
        source = (ROOT / 'third_party' / dep.source).resolve()
        check = {'cmake': 'CMakeLists.txt', 'cmake-copy': 'CMakeLists.txt', 'x265': 'CMakeLists.txt',
                 'meson': 'meson.build', 'davs2': 'build/linux/configure',
                 'autogen': 'autogen.sh', 'configure': 'configure'}
        if not (source / check[dep.backend]).is_file():
            if not build:
                continue
            raise BuildError(f'Source for {name} is missing at {source}. Initialize submodules '
                             'with git submodule update --init --recursive, or supply the source.')
        required_names = select(','.join(dep.requires)) if dep.requires else []
        if any(required not in prefixes for required in required_names):
            continue
        requirements = {required: prefixes[required] for required in reversed(required_names)}
        pkg_env = with_prefixes(env, requirements.values())
        pkg_env.update({key: (pkg_env.get(key, '') + ' -fPIC').strip() for key in ('CFLAGS', 'CXXFLAGS')})
        options = recipe_options(name, dep, pkg_env)
        tools = [pkg_env[key] for key in ('CC', 'CXX', 'MAKE', 'PKG_CONFIG')]
        tools.extend([pkg_env.get('AR', 'ar'), pkg_env.get('NASM', 'nasm')])
        if dep.backend.startswith('cmake') or dep.backend == 'x265':
            tools.extend(['cmake', 'ninja'])
        elif dep.backend == 'meson':
            tools.extend([sys.executable, 'ninja'])
        meson = None
        if dep.backend == 'meson':
            meson_source = (ROOT / 'third_party' / 'meson').resolve()
            if not (meson_source / 'meson.py').is_file():
                if not build:
                    continue
                raise BuildError('Initialize Meson with git submodule update --init third_party/meson')
            meson = source_identity(meson_source)
        revision = source_identity(source)
        key = digest(str(source), revision, repr(dep), options, platform.system(), ARCH,
                     file_digest(Path(__file__)), file_digest(Path(__file__).with_name('common.py')),
                     meson, environment_identity(pkg_env, tools), pkg_metadata(pkg_env, dep.probes),
                     [versions[required] for required in required_names])
        directory = BUILD / 'deps' / name / key[:24]
        prefix = directory / 'prefix'
        stamp = prefix / '.complete'
        with lock(STATE / f'{name}-{directory.name}.lock'):
            if stamp.is_file():
                if stamp.read_text(encoding='utf-8').strip() != key:
                    raise BuildError(f'Dependency cache key mismatch at {prefix}')
                print(f'Using {name}: {prefix}', flush=True)
            elif not build:
                continue
            else:
                print(f'Building {name}: {prefix}', flush=True)
                if directory.exists():
                    shutil.rmtree(directory)
                directory.mkdir(parents=True)
                build_recipe(name, dep, source, directory, prefix, pkg_env, jobs, options, requirements)
                if source_identity(source) != revision:
                    raise BuildError(f'{source} changed during the build. Run the command again.')
                write_state(stamp, key)
        prefixes[name], versions[name] = prefix, key
    return prefixes
