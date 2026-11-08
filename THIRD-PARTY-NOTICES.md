# Third-party notices

## PSReadLine

The `vendor/PSReadLine/` build-source subset comes from
[PowerShell/PSReadLine v2.4.5](https://github.com/PowerShell/PSReadLine/tree/v2.4.5),
commit `98d5610f7210924b79f553d982e10a9bd64dd52f`.

PSReadLine is distributed under the BSD-2-Clause license. Its original license
credits **Copyright (c) 2013, Jason Shirk**; individual source files also retain
their original Microsoft and other copyright notices. The complete license is
preserved as `vendor/PSReadLine/License.txt` in source distributions and
`License.txt` beside the DLLs in binary distributions. The
[pinned original terms](https://github.com/PowerShell/PSReadLine/blob/98d5610f7210924b79f553d982e10a9bd64dd52f/License.txt)
are retained in full. The project's MIT license does not relicense these files.

The build adds command existence coloring and uses the local module version
`2.4.5.1`. It is not an official Microsoft release or signed distribution.
Published module output includes the upstream license alongside the modified
binary, the project's license, and these notices.

## Microsoft.PowerShell.Pager

Build output includes Microsoft.PowerShell.Pager 1.0.0, licensed under MIT.
The original license credits **Copyright (c) 2020 PowerShell Team** and is
copied unchanged from the upstream `v1.0.0` commit
`965675f549dfa074eb02a47ca6d6e07d0ee7771f`. Its original NuGet package metadata
separately lists Microsoft Corporation as the copyright holder; that metadata
is retained without replacing the license's original notice.

The full license (`Pager-LICENSE.txt`) and original package metadata
(`microsoft.powershell.pager.nuspec`) are retained under `third-party/` in both
source and binary distributions.
See the [original package](https://www.nuget.org/packages/Microsoft.PowerShell.Pager/1.0.0)
and [pinned license](https://github.com/PowerShell/PSPager/blob/965675f549dfa074eb02a47ca6d6e07d0ee7771f/LICENSE).

## Project additions

New project code uses the MIT license in `LICENSE` in source distributions and
`CommandHighlighter-LICENSE.txt` in binary distributions. This notice describes
the component license boundaries; it does not replace any full license text.

## Build-time dependencies

PowerShellStandard.Library 5.1.0, Microsoft.CSharp 4.7.0, NETStandard.Library,
System.Management.Automation 7.2.24, and transitive reference packages are
restored from NuGet during the build. They are not copied as runtime assemblies
into the installed module. Each package retains its own license and metadata
in the local package cache; consult that metadata for its terms.
