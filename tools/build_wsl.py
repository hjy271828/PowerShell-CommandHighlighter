"""WSL build helper. Windows users can use tools/build.ps1 without Python."""
from pathlib import Path
import os
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
stage = root / '.build/upstream'
from prepare_upstream import prepare
candidate = root / '.build/upstream.pending'
if candidate.exists():
    shutil.rmtree(candidate)
prepare(root / 'vendor/PSReadLine', candidate)
if stage.exists():
    shutil.rmtree(stage)
candidate.rename(stage)
dotnet = sys.argv[1] if len(sys.argv) > 1 else 'dotnet'
env = dict(os.environ, DOTNET_CLI_HOME=str(root / '.build/dotnet-home'),
           NUGET_PACKAGES=str(root / '.build/packages'), DOTNET_NOLOGO='1',
           DOTNET_CLI_TELEMETRY_OPTOUT='1')
for framework in ('netstandard2.0', 'net6.0'):
    subprocess.run([dotnet, 'publish', str(stage / 'Polyfill/Polyfill.csproj'), '-c', 'Release', '-f', framework, '-p:DebugType=None', '-p:DebugSymbols=false', '-p:UseSharedCompilation=false', '-m:1'], check=True, env=env)
subprocess.run([dotnet, 'publish', str(stage / 'PSReadLine/PSReadLine.csproj'), '-c', 'Release', '-p:DebugType=None', '-p:DebugSymbols=false', '-p:UseSharedCompilation=false', '-m:1'], check=True, env=env)
import json
version = json.loads((root / 'release.json').read_text())['moduleVersion']
final = root / 'artifacts/PSReadLine' / version
output = final.with_name(version + '.pending')
if output.exists():
    shutil.rmtree(output)
output.mkdir(parents=True)
for file in ('Microsoft.PowerShell.PSReadLine.dll', 'Microsoft.PowerShell.Pager.dll', 'PSReadLine.psd1', 'PSReadLine.psm1', 'PSReadLine.format.ps1xml'):
    shutil.copy2(stage / 'PSReadLine/bin/Release/netstandard2.0/publish' / file, output)
for framework, directory in (('netstandard2.0', 'netstd'), ('net6.0', 'net6plus')):
    (output / directory).mkdir()
    shutil.copy2(stage / f'Polyfill/bin/Release/{framework}/publish/Microsoft.PowerShell.PSReadLine.Polyfiller.dll', output / directory)
shutil.copy2(stage / 'License.txt', output)
shutil.copytree(root / 'third-party', output / 'third-party')
shutil.copy2(root / 'LICENSE', output / 'CommandHighlighter-LICENSE.txt')
shutil.copy2(root / 'THIRD-PARTY-NOTICES.md', output)
shutil.copy2(root / 'vendor/PSReadLine.provenance.json', output / 'UPSTREAM.json')
backup = final.with_name(version + '.previous')
if backup.exists():
    raise RuntimeError('Previous build backup exists; review before rebuilding.')
try:
    if final.exists():
        final.rename(backup)
    output.rename(final)
except Exception:
    if backup.exists() and not final.exists():
        backup.rename(final)
    raise
if backup.exists():
    shutil.rmtree(backup)
print(f'Built: {final}')
