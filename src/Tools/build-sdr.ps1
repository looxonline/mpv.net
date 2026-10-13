# Run on Windows with .NET 10 SDK, Inno Setup 6 and 7-Zip installed.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = (Resolve-Path "$PSScriptRoot/../..").Path
$out = Join-Path $root 'artifacts'
$publish = Join-Path $out 'publish'
$runtime = Join-Path $out 'upstream-runtime'
$libmpv = Join-Path $out 'libmpv-runtime'
$installer = Join-Path $out 'installer'
New-Item -ItemType Directory -Force $out, $installer | Out-Null
# Always package fresh output. Never copy a user's local config into the installer.
foreach ($dir in @($publish, $runtime, $libmpv)) {
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
# mpv.net 7.1.2.0 bundles an older libmpv with a BT.1886 ICC NaN bug.
# This baseline x86-64 build contains mpv fix 47f81c8 (not the AVX2/v3 build).
$libmpvUrl = 'https://github.com/shinchiro/mpv-winbuild-cmake/releases/download/20261013/mpv-dev-x86_64-20261013-git-9d144e57b6.7z'
$libmpvHash = '10860837bc04491862c1e66a95dc1af1d7886d69757ce447a09e1e49ae993b52'
$libmpvArchive = Join-Path $out 'libmpv-runtime.7z'
if (!(Test-Path $libmpvArchive) -or (Get-FileHash $libmpvArchive -Algorithm SHA256).Hash -ne $libmpvHash) {
    Invoke-WebRequest $libmpvUrl -OutFile $libmpvArchive
}
if ((Get-FileHash $libmpvArchive -Algorithm SHA256).Hash -ne $libmpvHash) {
    throw 'libmpv runtime checksum mismatch'
}
$sevenZipCommand = Get-Command 7z.exe -ErrorAction SilentlyContinue
$sevenZip = if ($null -ne $sevenZipCommand) { $sevenZipCommand.Source } else { "$env:ProgramFiles/7-Zip/7z.exe" }
if (!(Test-Path $sevenZip)) { throw 'Install 7-Zip before building the installer.' }
& $sevenZip x $libmpvArchive "-o$libmpv" 'libmpv-2.dll' -y
if ($LASTEXITCODE -ne 0 -or !(Test-Path "$libmpv/libmpv-2.dll")) { throw 'libmpv extraction failed' }
& dotnet publish "$root/src/MpvNet.Windows/MpvNet.Windows.csproj" -c Release -r win-x64 --self-contained true -o $publish -p:IncludeNativeLibrariesForSelfExtract=true
if ($LASTEXITCODE -ne 0) { throw 'dotnet publish failed' }
foreach ($name in @('MediaInfo.dll', 'mpvnet.com', 'Locale')) {
    $source = Join-Path $runtime $name
    if (!(Test-Path $source)) { throw "Required runtime asset missing: $name" }
    Copy-Item $source $publish -Recurse -Force
}
Copy-Item "$libmpv/libmpv-2.dll" $publish
Copy-Item "$root/docs/sdr-build.md" "$publish/SDR-README.md"
Copy-Item "$root/License.txt" $publish
$commit = & git -C $root rev-parse HEAD
@"
Source: https://github.com/looxonline/mpv.net
Commit: $commit
Runtime archive: $runtimeUrl
Runtime archive SHA256: $runtimeHash
libmpv archive: $libmpvUrl
libmpv archive SHA256: $libmpvHash
libmpv source: https://github.com/mpv-player/mpv/commit/9d144e57b6
Includes BT.1886 ICC fix: 47f81c8d7e5edbb20a5b23c76b33a098335e595a
The managed player is built from this checkout. MediaInfo, the console launcher
and existing translations are from the pinned mpv.net release. libmpv is from
the separately pinned shinchiro Windows build linked by mpv.io/installation.
.NET runtime: self-contained win-x64
"@ | Set-Content "$publish/BUILD-INFO.txt"
$compiler = "${env:ProgramFiles(x86)}/Inno Setup 6/ISCC.exe"
if (!(Test-Path $compiler)) { throw 'Install Inno Setup 6 before building the installer.' }
& $compiler "/DSourceDir=$publish" "/DOutputPath=$installer" "$root/src/Setup/Inno/sdr-setup.iss"
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup failed' }
Get-ChildItem $installer -Filter '*.exe' | ForEach-Object {
    "$((Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant())  $($_.Name)"
} | Set-Content "$installer/SHA256SUMS.txt"
