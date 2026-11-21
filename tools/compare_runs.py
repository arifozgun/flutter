#!/usr/bin/env python3
"""Compare the summary.txt of two runs of the Flutter menu harness.

Usage: compare_runs.py RUN_A RUN_B [--all]

RUN_A and RUN_B are output folders (each holding a summary.txt) or the
summary.txt files themselves. For every scenario, the fields that differ are
printed as `name: A=<value> | B=<value>`. Timestamps (`start=`, `at <time>`)
and coordinates (`frame=`) are ignored. Scenarios that only one run has are
listed. With --all, scenarios without a difference are listed too.

Reads files and prints; standard library only.
"""

import argparse
import os
import re
import sys

KEY = re.compile(r'(?:(?<=\s)|^)([A-Za-z][\w#]*)=')
# What ends a value that is not quoted or a [list]: a space before the next
# `key=` or before a `label: ` such as `status: `.
VALUE_END = re.compile(r'\s+(?:[A-Za-z][\w#]*=|[A-Za-z]+:\s)')
# Segments whose key is not written as `key=` or `key:`.
SPECIAL = [
    (re.compile(r'^(.+?) found at (step\d+) among (\[.*\])$'), 'found'),
    (re.compile(r'^tap (.*)$'), 'tap'),
]
# Keys that were renamed between versions of the harness.
ALIASES = {'after 2 s': 'after tap'}
MAX_VALUE = 300


def normalise(text):
    text = re.sub(r'frame=-?\d+,-?\d+,\d+x\d+', 'frame=*', text)
    text = re.sub(r'\bat \d{9,}\.\d+', 'at *', text)
    text = re.sub(r'\bstart=\S+', 'start=*', text)
    return text


def scan_pairs(text, prefix):
    """The `key=value` pairs of `text`; values may be quoted or a [list]."""
    pairs = []
    position = 0
    while True:
        match = KEY.search(text, position)
        if match is None:
            return pairs
        start = match.end()
        if text.startswith('"', start):
            end = start + 1
            while end < len(text) and text[end] != '"':
                end += 2 if text[end] == '\\' else 1
            end += 1
        elif text.startswith('[', start):
            close = text.find(']', start)
            end = len(text) if close < 0 else close + 1
        else:
            stop = VALUE_END.search(text, start)
            end = len(text) if stop is None else stop.start()
        key = match.group(1)
        pairs.append((f'{prefix}.{key}' if prefix else key, text[start:end]))
        position = end


def label_of(text):
    """The words in front of the first pair, as a short label."""
    text = text.strip().rstrip(':').strip()
    text = text.split(':')[0].split(';')[0].strip()
    words = text.split()
    return ' '.join(words[:4])


def fields_of(segment):
    """The (key, value) pairs of one ` | ` separated part of a result line."""
    segment = normalise(segment.strip())
    for pattern, key in SPECIAL:
        match = pattern.match(segment)
        if match:
            return [(key, ' '.join(match.groups()) if key == 'found' else match.group(1))]
    status = None
    marker = segment.find(' status: ')
    if marker >= 0:
        status = segment[marker + len(' status: '):]
        segment = segment[:marker]
    first = KEY.search(segment)
    prefix = ''
    if first is None:
        pairs = [(segment[:24], segment)]
    else:
        prefix = ALIASES.get(label_of(segment[: first.start()]), label_of(segment[: first.start()]))
        pairs = scan_pairs(segment, prefix)
    if status is not None:
        pairs += scan_pairs(status, f'{prefix}.status' if prefix else 'status')
    return pairs


def parse_line(line):
    parts = [part for part in line.rstrip('\n').split(' | ')]
    scenario = parts[0].strip()
    fields = {}
    for part in parts[1:]:
        if part.startswith('start='):
            continue
        for key, value in fields_of(part):
            name, number = key, 2
            while name in fields:
                name = f'{key}#{number}'
                number += 1
            fields[name] = value
    return scenario, fields


def load(path):
    if os.path.isdir(path):
        path = os.path.join(path, 'summary.txt')
    scenarios = {}
    with open(path, encoding='utf-8') as handle:
        for line in handle:
            if not line.strip():
                continue
            scenario, fields = parse_line(line)
            scenarios[scenario] = fields
    return scenarios


def label(path):
    path = path.rstrip('/')
    if os.path.basename(path) == 'summary.txt':
        path = os.path.dirname(path)
    return os.path.basename(path) or path


def short(value):
    if value is None:
        return '(absent)'
    return value if len(value) <= MAX_VALUE else value[:MAX_VALUE] + '...'


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('run_a')
    parser.add_argument('run_b')
    parser.add_argument('--all', action='store_true', help='also list scenarios without a difference')
    args = parser.parse_args()

    try:
        a, b = load(args.run_a), load(args.run_b)
    except OSError as error:
        print(f'cannot read: {error}', file=sys.stderr)
        return 2

    print(f'A = {label(args.run_a)}')
    print(f'B = {label(args.run_b)}')
    differing = 0
    for scenario in sorted(set(a) | set(b)):
        if scenario not in a or scenario not in b:
            only = 'A' if scenario in a else 'B'
            print(f'\n== {scenario}\n  only in {only}')
            differing += 1
            continue
        keys = list(a[scenario]) + [key for key in b[scenario] if key not in a[scenario]]
        diffs = [key for key in keys if a[scenario].get(key) != b[scenario].get(key)]
        if not diffs:
            if args.all:
                print(f'\n== {scenario}\n  no difference')
            continue
        differing += 1
        print(f'\n== {scenario}')
        for key in diffs:
            print(f'  {key}:')
            print(f'    A={short(a[scenario].get(key))}')
            print(f'    B={short(b[scenario].get(key))}')
    print(f'\n{differing} of {len(set(a) | set(b))} scenarios differ')
    return 0


if __name__ == '__main__':
    sys.exit(main())
