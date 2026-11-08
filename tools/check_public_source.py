"""Check publishable Git files for common private records and generated output.

This heuristic is a review aid, not a complete secret detector. It never prints
matching file contents, which might themselves contain sensitive information.
"""
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
GENERATED_PARTS = {'.build', 'artifacts', 'test-results', '__pycache__', 'bin', 'obj'}
GENERATED_SUFFIXES = {'.dll', '.exe', '.pdb', '.nupkg', '.zip', '.tar', '.tgz', '.log'}
PRIVATE_SUFFIXES = {'.pem', '.key', '.pfx', '.p12'}
TEXT_RULES = {
    'CJK text in English-only public source': re.compile(r'[\u3400-\u9fff]'),
    'absolute personal home path': re.compile(
        r'(?i)(?:[a-z]:\\+Users\\+(?!<|Public\b|Default\b)[\w.-]+'
        r'|/(?:home|Users)/[\w.-]+|/mnt/[a-z]/Users/[\w.-]+'
        r'|\\\\wsl(?:\.localhost|\$)\\|DESKTOP-[A-Z0-9]+)'
    ),
    'private key header': re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
    'credential-shaped value': re.compile(r'(?:gh[pousr]_[A-Za-z0-9]{20,}|AKIA[A-Z0-9]{16})'),
    'raw terminal escape': re.compile('\x1b'),
}


def candidate_files():
    result = subprocess.run(
        ['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'],
        cwd=ROOT, check=True, stdout=subprocess.PIPE,
    )
    return sorted(set(result.stdout.decode('utf-8').rstrip('\0').split('\0')) - {''})


def check_file(name):
    relative = Path(name)
    path = ROOT / relative
    if not path.exists():
        return []  # A tracked deletion is not part of the next source tree.
    issues = []
    if path.is_symlink():
        return ['symlink requires a manual publication review']
    if set(relative.parts) & GENERATED_PARTS or path.suffix.lower() in GENERATED_SUFFIXES:
        issues.append('generated output must not be committed')
    if (path.name == '.env' or path.name.startswith('.env.')
            or path.suffix.lower() in PRIVATE_SUFFIXES):
        issues.append('local credential/configuration file must not be committed')
    if 'transcript' in path.name.lower() or path.name.startswith('environment-'):
        issues.append('raw local diagnostic record must not be committed')
    try:
        text = path.read_text(encoding='utf-8-sig')
    except UnicodeError:
        issues.append('binary or non-UTF-8 file requires a manual publication review')
        return issues
    for label, pattern in TEXT_RULES.items():
        match = pattern.search(text)
        if match:
            line = text.count('\n', 0, match.start()) + 1
            issues.append(f'{label} at line {line}')
    return issues


def main():
    files = candidate_files()
    failures = [(name, issue) for name in files for issue in check_file(name)]
    if failures:
        for name, issue in failures:
            print(f'{name}: {issue}', file=sys.stderr)
        return 1
    print(f'PASS: {len(files)} publishable files checked; no configured privacy/language/output rules matched.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
