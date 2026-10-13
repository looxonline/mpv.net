# Run on Windows with .NET 10 SDK and Inno Setup 6 installed.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = (Resolve-Path "$PSScriptRoot/../..").Path
$out = Join-Path $root 'artifacts'
$publish = Join-Path $out 'publish'
$runtime = Join-Path $out 'upstream-runtime'
$installer = Join-Path $out 'installer'
New-Item -ItemType Directory -Force $out, $installer | Out-Null
# Always package fresh output. Never copy a user's local config into the installer.
foreach ($dir in @($publish, $runtime)) {
    if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
    New-Item -ItemType Directory $dir | Out-Null
}
$runtimeUrl = 'https://github.com/mpvnet-player/mpv.net/releases/download/v7.1.2.0/mpv.net-v7.1.2.0-portable-x64.zip'
$runtimeHash = '33cba35bc6a8ebbb441a68cb9f3d26c366a2457f6a969ce50b95b0e7dd163431'
$archive = Join-Path $out 'upstream-runtime.zip'
if (!(Test-Path $archive) -or (Get-FileHash $archive -Algorithm SHA256).Hash -ne $runtimeHash) {
    Invoke-WebRequest $runtimeUrl -OutFile $archive
}
if ((Get-FileHash $archive -Algorithm SHA256).Hash -ne $runtimeHash) {
    throw 'Upstream runtime checksum mismatch'
}
Expand-Archive $archive $runtime -Force
& dotnet publish "$root/src/MpvNet.Windows/MpvNet.Windows.csproj" -c Release -r win-x64 --self-contained true -o $publish -p:IncludeNativeLibrariesForSelfExtract=true
if ($LASTEXITCODE -ne 0) { throw 'dotnet publish failed' }
foreach ($name in @('libmpv-2.dll', 'MediaInfo.dll', 'mpvnet.com', 'Locale')) {
    $source = Join-Path $runtime $name
    if (!(Test-Path $source)) { throw "Required runtime asset missing: $name" }
    Copy-Item $source $publish -Recurse -Force
}
Copy-Item "$root/docs/sdr-build.md" "$publish/SDR-README.md"
Copy-Item "$root/License.txt" $publish
$commit = & git -C $root rev-parse HEAD
@"
Source: https://github.com/looxonline/mpv.net
Commit: $commit
Runtime archive: $runtimeUrl
Runtime archive SHA256: $runtimeHash
The managed player is built from this checkout. libmpv, MediaInfo, the console
launcher and existing translations are from the pinned upstream release.
.NET runtime: self-contained win-x64
"@ | Set-Content "$publish/BUILD-INFO.txt"
$compiler = "${env:ProgramFiles(x86)}/Inno Setup 6/ISCC.exe"
if (!(Test-Path $compiler)) { throw 'Install Inno Setup 6 before building the installer.' }
& $compiler "/DSourceDir=$publish" "/DOutputPath=$installer" "$root/src/Setup/Inno/sdr-setup.iss"
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup failed' }
Get-ChildItem $installer -Filter '*.exe' | ForEach-Object {
    "$((Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant())  $($_.Name)"
} | Set-Content "$installer/SHA256SUMS.txt"
