#!/usr/bin/env python3
# clean_dashes.py - Automated cleaner for prohibited em-dashes and double-hyphens.
# Converts prohibited em-dashes and double-hyphens into natural human punctuation.

import sys
import os
import re
import subprocess

TARGET_EXTENSIONS = {
    '.ahk', '.ps1', '.py', '.cs', '.java', '.kt', '.kts',
    '.c', '.cpp', '.h', '.hpp', '.js', '.jsx', '.ts', '.tsx',
    '.go', '.rs', '.swift', '.dart', '.md', '.txt'
}

EXCLUDED_DIRS = {
    '.git', 'vendor', 'third_party', 'external', 'node_modules',
    'bin', 'obj', '.venv', '__pycache__'
}

def is_path_excluded(path_str, repo_root=None):
    norm_path = path_str.replace('\\', '/').strip('/')
    parts = norm_path.split('/')
    for part in parts:
        if part in EXCLUDED_DIRS:
            return True
    if repo_root:
        lintignore = os.path.join(repo_root, '.lintignore')
        if os.path.isfile(lintignore):
            try:
                with open(lintignore, 'r', encoding='utf-8') as f:
                    for line in f:
                        pattern = line.strip().replace('\\', '/')
                        if pattern and not pattern.startswith('#'):
                            if pattern.strip('/') in norm_path:
                                return True
            except Exception:
                pass
    return False

def is_file_exempt(content):
    lines = content.splitlines()[:5]
    for line in lines:
        if any(marker in line for marker in ['@generated', '@vendored', '<!-- no-dash-lint -->']):
            return True
    return False

def clean_line(line):
    if 'no-dash-lint' in line:
        return line

    # 1. Unicode em-dash (: ) and en-dash (: )
    # Replace spaced em-dash with colon or comma
    cleaned = re.sub(r'[ 	]*[\u2014\u2013][ 	]*', ': ', line)
    # Replace unspaced em-dash between words: 'word: word' -> 'word, word'
    cleaned = re.sub(r'([a-zA-Z0-9])[\u2014\u2013]([a-zA-Z0-9])', r'\1, \2', cleaned)
    # Stray em-dash at end of line
    cleaned = re.sub(r'[ 	]*[\u2014\u2013](\r?)$', r':\1', cleaned)

    # 2. ASCII double-hyphen (--)
    # Replace ': ' with ': ' while protecting HTML comments (<!-- -->) and arrows (-->)
    def replace_double_hyphen(match):
        full = match.group(0)
        start = match.start()
        end = match.end()
        # If preceded by '<' or '!'
        if start > 0 and match.string[start - 1] in '<!':
            return full
        # If followed by '>'
        if end < len(match.string) and match.string[end] == '>':
            return full
        return ': '

    cleaned = re.sub(r'[ 	]+--[ 	]+', replace_double_hyphen, cleaned)

    # Trailing space +: at line end -> ':'
    cleaned = re.sub(r'[ 	]+--(\r?)$', r':\1', cleaned)

    # word: word -> 'word: word'
    cleaned = re.sub(r'([a-zA-Z0-9])--([a-zA-Z0-9])', r'\1: \2', cleaned)

    return cleaned

def process_file(filepath, dry_run=False):
    try:
        with open(filepath, 'rb') as f:
            raw_bytes = f.read()
    except Exception as e:
        print(f'Skipping {filepath}: {e}', file=sys.stderr)
        return False, 0

    try:
        content = raw_bytes.decode('utf-8')
        encoding = 'utf-8'
    except UnicodeDecodeError:
        try:
            content = raw_bytes.decode('latin-1')
            encoding = 'latin-1'
        except Exception:
            return False, 0

    if is_file_exempt(content):
        return False, 0

    lines = content.splitlines(keepends=True)
    new_lines = []
    change_count = 0

    for idx, line in enumerate(lines, start=1):
        cleaned = clean_line(line)
        if cleaned != line:
            change_count += 1
        new_lines.append(cleaned)

    if change_count > 0:
        if not dry_run:
            new_content = ''.join(new_lines)
            with open(filepath, 'w', encoding=encoding, newline='') as f:
                f.write(new_content)
        return True, change_count

    return False, 0

def get_git_repo_root():
    try:
        res = subprocess.run(['git', 'rev-parse', '--show-toplevel'],
                             capture_output=True, text=True, check=True)
        return res.stdout.strip()
    except Exception:
        return None

def get_staged_files():
    try:
        res = subprocess.run(['git', 'diff', '--cached', '--name-only', '--diff-filter=ACM'],
                             capture_output=True, text=True, check=True)
        return [f.strip() for f in res.stdout.splitlines() if f.strip()]
    except Exception:
        return []

def get_tracked_files():
    try:
        res = subprocess.run(['git', 'ls-files'],
                             capture_output=True, text=True, check=True)
        return [f.strip() for f in res.stdout.splitlines() if f.strip()]
    except Exception:
        return []

def main():
    args = sys.argv[1:]
    repo_root = get_git_repo_root() or os.getcwd()
    os.chdir(repo_root)

    mode_staged = '--staged' in args
    mode_all = '--all' in args
    mode_check = '--check' in args

    explicit_paths = [a for a in args if not a.startswith('--')]
    files_to_check = []

    if mode_staged:
        staged = get_staged_files()
        files_to_check.extend(staged)
    elif mode_all:
        tracked = get_tracked_files()
        files_to_check.extend(tracked)
    elif explicit_paths:
        for p in explicit_paths:
            if os.path.isfile(p):
                files_to_check.append(p)
            elif os.path.isdir(p):
                for root, _, files in os.walk(p):
                    for f in files:
                        files_to_check.append(os.path.join(root, f))
    else:
        staged = get_staged_files()
        if staged:
            files_to_check.extend(staged)
            mode_staged = True
        else:
            print('No staged files found. Pass --all, --staged, or file paths.')
            sys.exit(0)

    target_files = []
    for f in files_to_check:
        ext = os.path.splitext(f)[1].lower()
        if ext in TARGET_EXTENSIONS and not is_path_excluded(f, repo_root):
            target_files.append(f)

    if not target_files:
        print('No matching text or code files to process.')
        sys.exit(0)

    modified_files = []
    total_fixes = 0

    for fpath in target_files:
        if not os.path.isfile(fpath):
            continue
        changed, count = process_file(fpath, dry_run=mode_check)
        if changed:
            modified_files.append((fpath, count))
            total_fixes += count

    if modified_files:
        verb = 'Would fix' if mode_check else 'Cleaned'
        print(f'{verb} {total_fixes} dash violation(s) across {len(modified_files)} file(s):')
        for fpath, count in modified_files:
            print(f'  - {fpath} ({count} fixes)')

        if mode_staged and not mode_check:
            for fpath, _ in modified_files:
                subprocess.run(['git', 'add', fpath], check=False)
            print('Re-staged all cleaned files successfully.')

        if mode_check:
            sys.exit(1)
    else:
        print(f'Clean! Scanned {len(target_files)} file(s), zero violations found.')

    sys.exit(0)

if __name__ == '__main__':
    main()
