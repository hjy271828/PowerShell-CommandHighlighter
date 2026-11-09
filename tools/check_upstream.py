"""Fetch pinned experimental inputs; never changes the vendored baseline."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import tarfile
import time
import urllib.error
import urllib.request

API = 'https://api.github.com/repos/PowerShell/PSReadLine/'
ROOT = Path(__file__).resolve().parents[1]


class Unavailable(RuntimeError):
    pass


def download(url, token=None, opener=urllib.request.urlopen, sleep=time.sleep):
    headers = {'User-Agent': 'PowerShell-CommandHighlighter-upstream-probe', 'Accept': 'application/vnd.github+json'}
    # The read-only token goes only to GitHub's API, never to downloaded code.
    if token and url.startswith(API):
        headers['Authorization'] = 'Bearer ' + token
    for attempt in range(3):
        try:
            with opener(urllib.request.Request(url, headers=headers), timeout=30) as response:
                return response.read()
        except urllib.error.HTTPError as error:
            error.close()
            if error.code in (403, 429):
                raise Unavailable('GitHub denied or rate-limited the request; retry on the next scheduled/manual run.') from None
            if error.code not in (500, 502, 503, 504):
                raise Unavailable(f'GitHub HTTP {error.code}; upstream input unavailable.') from None
        except (urllib.error.URLError, TimeoutError, OSError):
            pass
        if attempt < 2:
            sleep(2 ** attempt)
    raise Unavailable('Network/upstream unavailable after three bounded attempts.')


def tag_key(tag):
    match = re.fullmatch(r'v?(\d+)\.(\d+)\.(\d+)(?:-([\w.-]+))?(?:\+[\w.-]+)?', tag)
    if not match:
        return (-1, -1, -1, False, '')
    suffix = tuple((0, int(part)) if part.isdigit() else (1, part.lower())
                   for part in re.findall(r'\d+|[^\d]+', match[4] or ''))
    return (*map(int, match.groups()[:3]), match[4] is None, suffix)


def extract(data, destination):
    import io
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as archive:
        members = archive.getmembers()
        # Reject links, devices and traversal before extracting any file.
        for member in members:
            parts = Path(member.name).parts
            if not parts or ':' in parts[0] or member.name.startswith('/') or '..' in parts or '\\' in member.name or not (member.isdir() or member.isfile()):
                raise ValueError('Unsafe upstream archive entry.')
        roots = {Path(member.name).parts[0] for member in members}
        if len(roots) != 1:
            raise ValueError('Unexpected upstream archive layout.')
        archive.extractall(destination)
        return destination / roots.pop()


def snapshot(source):
    provenance = json.loads((ROOT / 'vendor/PSReadLine.provenance.json').read_text())
    changed, missing = [], []
    for baseline in sorted((ROOT / 'vendor/PSReadLine').rglob('*')):
        if not baseline.is_file():
            continue
        name = baseline.relative_to(ROOT / 'vendor/PSReadLine').as_posix()
        target = source / name
        if not target.is_file():
            missing.append(name)
        elif baseline.read_bytes().replace(b'\r\n', b'\n') != target.read_bytes().replace(b'\r\n', b'\n'):
            changed.append(name)
    return {'baseline': provenance['commit'], 'changedBaselineFiles': changed, 'missingBaselineFiles': missing}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target', choices=('tag', 'master'), required=True)
    parser.add_argument('--directory', type=Path, required=True)
    args = parser.parse_args()
    args.directory.mkdir(parents=True, exist_ok=True)
    report = {'target': args.target, 'status': 'unavailable', 'experimental': True}
    try:
        token = os.environ.get('GH_TOKEN')
        if args.target == 'tag':
            tags = json.loads(download(API + 'tags?per_page=100', token))
            tags = [tag for tag in tags if tag_key(tag['name'])[0] >= 0]
            if not tags:
                raise Unavailable('No semantic version tag was found in the first 100 tags.')
            selected = max(tags, key=lambda tag: tag_key(tag['name']))
            ref, sha = selected['name'], selected['commit']['sha']
        else:
            ref = 'master'
            sha = json.loads(download(API + 'commits/master', token))['sha']
        if not re.fullmatch('[a-f0-9]{40}', sha):
            raise ValueError('Upstream did not return a full commit SHA.')
        data = download('https://codeload.github.com/PowerShell/PSReadLine/tar.gz/' + sha)
        source = extract(data, args.directory / 'source')
        report.update(snapshot(source))
        report.update(status='ready', ref=ref, commit=sha, archiveSha256=hashlib.sha256(data).hexdigest(), source=str(source.resolve()))
    except Unavailable as error:
        report['diagnostic'] = str(error)
        print('::notice::' + str(error))
    except (ValueError, KeyError, tarfile.TarError) as error:
        report.update(status='invalid-input', diagnostic=str(error))
    (args.directory / 'discovery.json').write_text(json.dumps(report, indent=2) + '\n')
    output = os.environ.get('GITHUB_OUTPUT')
    if output:
        with open(output, 'a', encoding='utf-8') as stream:
            stream.write('ready=' + str(report['status'] == 'ready').lower() + '\n')
            if report['status'] == 'ready':
                stream.write('commit=' + report['commit'] + '\nsource=' + report['source'] + '\n')
    print(json.dumps({k: v for k, v in report.items() if k != 'source'}, indent=2))
    return 0 if report['status'] != 'invalid-input' else 1


if __name__ == '__main__':
    raise SystemExit(main())
