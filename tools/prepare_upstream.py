"""Shared context patch plan, with all-or-nothing source preparation."""
import json
from pathlib import Path
import re
import shutil
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def prepare(source, destination, experimental=False):
    source, destination = Path(source), Path(destination)
    version = json.loads((ROOT / 'release.json').read_text())['moduleVersion']
    texts = {}
    for entry in json.loads((ROOT / 'tools/patches.json').read_text()):
        file = entry['file']
        if file not in texts:
            texts[file] = (source / file).read_text(encoding='utf-8-sig')
            if '_commandHighlighter' in texts[file] or 'GetDefaultTokenColor' in texts[file]:
                raise ValueError(f'Source already patched: {file}')
        count = texts[file].count(entry['before'])
        if count != 1:
            raise ValueError(f'Patch anchor mismatch: {file}; expected 1, found {count}. Review upstream context.')
        texts[file] = texts[file].replace(entry['before'], entry['after'])
    metadata = [
        ('PSReadLine/PSReadLine.csproj', '<AssemblyVersion>', '</AssemblyVersion>', '2.4.5.0', version),
        ('PSReadLine/PSReadLine.csproj', '<FileVersion>', '</FileVersion>', '2.4.5', version),
        ('PSReadLine/PSReadLine.csproj', '<InformationalVersion>', '</InformationalVersion>', '2.4.5', '2.4.5-commandhighlighter.' + version.split('.')[-1]),
        ('PSReadLine/PSReadLine.psd1', "ModuleVersion = '", "'", '2.4.5', version),
    ]
    for file, prefix, suffix, expected, replacement in metadata:
        if file not in texts:
            texts[file] = (source / file).read_text(encoding='utf-8-sig')
        matches = list(re.finditer(re.escape(prefix) + "([^<\\r\\n']+)" + re.escape(suffix), texts[file]))
        if len(matches) != 1 or (not experimental and matches[0][1] != expected):
            raise ValueError(f'Version anchor mismatch: {file} / {prefix}. Review upstream metadata.')
        texts[file] = texts[file].replace(matches[0][0], prefix + replacement + suffix)
    if (source / 'PSReadLine/CommandExistenceHighlighter.cs').exists():
        raise ValueError('Injected source already exists.')
    if destination.exists():
        raise ValueError('Preparation destination must not exist; existing staged source was preserved.')
    destination.parent.mkdir(parents=True, exist_ok=True)
    pending = Path(tempfile.mkdtemp(prefix=destination.name + '.pending-', dir=destination.parent))
    try:
        shutil.copytree(source, pending, dirs_exist_ok=True)
        for file, text in texts.items():
            (pending / file).write_text(text, encoding='utf-8', newline='\n')
        shutil.copy2(ROOT / 'src/CommandExistenceHighlighter.cs', pending / 'PSReadLine')
        shutil.copy2(ROOT / 'nuget.config', pending)
        pending.rename(destination)
    finally:
        if pending.exists():
            shutil.rmtree(pending)


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('destination', type=Path)
    parser.add_argument('--experimental', action='store_true')
    args = parser.parse_args()
    prepare(args.source, args.destination, args.experimental)
