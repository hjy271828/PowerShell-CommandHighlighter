"""WSL build helper. Windows users can use build.ps1 without Python."""
from pathlib import Path
import os
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
stage = root / '.build/upstream'
if stage.exists():
    shutil.rmtree(stage)
shutil.copytree(root / 'vendor/PSReadLine', stage)
shutil.copy2(root / 'src/CommandExistenceHighlighter.cs', stage / 'PSReadLine')
shutil.copy2(root / 'nuget.config', stage)

def replace(file, before, after):
    path = stage / file
    text = path.read_text(encoding='utf-8-sig')
    assert text.count(before) == 1, f'Upstream patch anchor changed: {file}'
    path.write_text(text.replace(before, after), encoding='utf-8')

replace('PSReadLine/Render.cs', '            var text = ParseInput();',
        '            var text = ParseInput();\n            _commandHighlighter.Analyze(_ast, _engineIntrinsics);')
replace('PSReadLine/Render.cs', '        private string GetTokenColor(Token token)',
        '''        private string GetTokenColor(Token token)
        {
            var commandColor = _commandHighlighter.GetColor(token);
            return commandColor ?? GetDefaultTokenColor(token);
        }

        private string GetDefaultTokenColor(Token token)''')
replace('PSReadLine/ReadLine.cs', '            _engineIntrinsics = engineIntrinsics;',
        '            _engineIntrinsics = engineIntrinsics;\n            _commandHighlighter.Reset();')
replace('PSReadLine/PSReadLine.csproj', '<AssemblyVersion>2.4.5.0</AssemblyVersion>', '<AssemblyVersion>2.4.5.1</AssemblyVersion>')
replace('PSReadLine/PSReadLine.csproj', '<FileVersion>2.4.5</FileVersion>', '<FileVersion>2.4.5.1</FileVersion>')
replace('PSReadLine/PSReadLine.csproj', '<InformationalVersion>2.4.5</InformationalVersion>', '<InformationalVersion>2.4.5-commandhighlighter.1</InformationalVersion>')
replace('PSReadLine/PSReadLine.psd1', "ModuleVersion = '2.4.5'", "ModuleVersion = '2.4.5.1'")
dotnet = sys.argv[1] if len(sys.argv) > 1 else 'dotnet'
env = dict(os.environ, DOTNET_CLI_HOME=str(root / '.build/dotnet-home'),
           NUGET_PACKAGES=str(root / '.build/packages'), DOTNET_NOLOGO='1',
           DOTNET_CLI_TELEMETRY_OPTOUT='1')
for framework in ('netstandard2.0', 'net6.0'):
    subprocess.run([dotnet, 'publish', str(stage / 'Polyfill/Polyfill.csproj'), '-c', 'Release', '-f', framework, '-p:UseSharedCompilation=false', '-m:1'], check=True, env=env)
subprocess.run([dotnet, 'publish', str(stage / 'PSReadLine/PSReadLine.csproj'), '-c', 'Release', '-p:UseSharedCompilation=false', '-m:1'], check=True, env=env)
output = root / 'artifacts/PSReadLine/2.4.5.1'
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
print(f'Built: {output}')
