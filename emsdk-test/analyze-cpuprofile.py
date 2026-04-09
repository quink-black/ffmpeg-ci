#!/usr/bin/env python3
"""
Analyze V8 .cpuprofile files for WASM function-level profiling.

Requires: emscripten build with --profiling-funcs (adds WASM name section).

Usage:
    python3 analyze-cpuprofile.py <file.cpuprofile> [options]

Options:
    --top N          Show top N functions (default: 40)
    --exclude-idle   Exclude idle/wait/overhead from percentages
    --wasm-only      Show only WASM functions
    --json           Output JSON instead of text
"""

import json
import sys
import collections
import argparse


OVERHEAD_NAMES = frozenset([
    'emscripten_futex_wait',
    'emscripten_futex_wake',
    'emscripten_conditional_set_current_thread_status',
    '__emscripten_receive_on_main_thread_js',
    '_emscripten_get_now',
    '__wasm_init_memory',
    '__wasm_call_ctors',
    '__timedwait_cp',
    '__emscripten_environ_constructor',
])


def classify_function(callframe):
    """Classify a callframe into category and return (category, name)."""
    fname = callframe.get('functionName', '')
    url = callframe.get('url', '')

    if not fname and not url:
        return ('idle', '(idle)')
    if fname == '(idle)':
        return ('idle', '(idle)')
    if fname == '(program)':
        return ('overhead', '(program)')
    if fname == '(garbage collector)':
        return ('gc', '(garbage collector)')

    if 'wasm://wasm' in url:
        if fname in OVERHEAD_NAMES:
            return ('wasm-overhead', fname)
        if fname.startswith('wasm-to-js:'):
            return ('wasm-overhead', fname)
        if fname:
            return ('wasm', fname)
        return ('wasm', '(anonymous wasm)')

    if 'ffmpeg' in url or 'checkasm' in url:
        if fname in OVERHEAD_NAMES:
            return ('wasm-overhead', fname)
        return ('js-glue', fname or '(anonymous js)')

    if url.startswith('node:'):
        return ('node', fname)

    if not url:
        if fname in ('(idle)', '(program)', '(garbage collector)'):
            return ('overhead', fname)
        return ('other', fname)

    return ('other', fname or '(anonymous)')


def analyze(filepath, top_n=40, exclude_idle=False, wasm_only=False):
    with open(filepath) as f:
        data = json.load(f)

    nodes = data['nodes']
    samples = data.get('samples', [])
    time_deltas = data.get('timeDeltas', [])

    if not samples:
        print('Error: no samples in profile', file=sys.stderr)
        return None

    node_map = {n['id']: n for n in nodes}

    sample_counts = collections.Counter(samples)
    total_samples = len(samples)

    total_time_us = sum(time_deltas) if time_deltas else 0
    total_time_ms = total_time_us / 1000.0

    category_samples = collections.Counter()
    func_samples = collections.Counter()

    for sample_id, count in sample_counts.items():
        node = node_map.get(sample_id, {})
        cf = node.get('callFrame', {})
        cat, name = classify_function(cf)
        category_samples[cat] += count
        func_samples[(cat, name)] += count

    wasm_samples = category_samples.get('wasm', 0)
    active_samples = total_samples - category_samples.get('idle', 0)
    decode_samples = (wasm_samples +
                      category_samples.get('wasm-overhead', 0) +
                      category_samples.get('js-glue', 0))

    result = {
        'file': filepath,
        'total_samples': total_samples,
        'total_time_ms': total_time_ms,
        'categories': dict(category_samples),
        'functions': [],
    }

    denominator = total_samples
    label = 'total'
    if exclude_idle:
        denominator = active_samples
        label = 'active'

    print(f'Profile: {filepath}')
    print(f'Total samples: {total_samples}  ({total_time_ms:.0f}ms)')
    print()
    print('=== Category breakdown ===')
    for cat in ['wasm', 'wasm-overhead', 'js-glue', 'node', 'gc',
                'overhead', 'idle', 'other']:
        count = category_samples.get(cat, 0)
        pct = 100.0 * count / total_samples if total_samples else 0
        if count > 0:
            print(f'  {cat:16s}  {count:7d}  {pct:6.2f}%')

    print()
    if denominator > 0:
        print(f'=== Top functions by self time ({label}) ===')
    else:
        print('No active samples found.')
        return result

    sorted_funcs = sorted(func_samples.items(), key=lambda x: -x[1])

    shown = 0
    for (cat, name), count in sorted_funcs:
        if wasm_only and cat != 'wasm':
            continue
        if exclude_idle and cat == 'idle':
            continue

        pct = 100.0 * count / denominator
        result['functions'].append({
            'name': name,
            'category': cat,
            'samples': count,
            'percent': round(pct, 2),
        })
        print(f'  {pct:6.2f}%  {count:6d}  [{cat:14s}]  {name}')
        shown += 1
        if shown >= top_n:
            break

    if wasm_samples > 0:
        print()
        print(f'=== WASM decode functions (% of WASM time, '
              f'{wasm_samples} samples) ===')
        wasm_funcs = [(name, count)
                      for (cat, name), count in sorted_funcs
                      if cat == 'wasm']
        for name, count in wasm_funcs[:top_n]:
            pct = 100.0 * count / wasm_samples
            print(f'  {pct:6.2f}%  {count:6d}  {name}')

    return result


def main():
    parser = argparse.ArgumentParser(
        description='Analyze V8 .cpuprofile for WASM profiling')
    parser.add_argument('file', help='.cpuprofile file path')
    parser.add_argument('--top', type=int, default=40,
                        help='Show top N functions (default: 40)')
    parser.add_argument('--exclude-idle', action='store_true',
                        help='Exclude idle/wait from percentages')
    parser.add_argument('--wasm-only', action='store_true',
                        help='Show only WASM functions')
    parser.add_argument('--json', action='store_true',
                        help='Output JSON')
    args = parser.parse_args()

    result = analyze(args.file, args.top, args.exclude_idle, args.wasm_only)

    if args.json and result:
        print()
        print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
