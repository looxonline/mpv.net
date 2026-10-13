$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = (Resolve-Path "$PSScriptRoot/..").Path
$out = Join-Path $root 'artifacts'
$results = Join-Path $out 'test-results'
New-Item -ItemType Directory -Force $results | Out-Null
& dotnet publish "$PSScriptRoot/SdrSmoke/SdrSmoke.csproj" -c Release -r win-x64 --self-contained true -o "$out/smoke"
if ($LASTEXITCODE -ne 0) { throw 'Smoke test compilation failed' }
foreach ($mode in @('defaults', 'override', 'render')) {
    & "$out/smoke/SdrSmoke.exe" $mode "$out/publish" $results
    if ($LASTEXITCODE -ne 0) { throw "Smoke test failed: $mode" }
}
$setup = @(Get-ChildItem "$out/installer" -Filter '*.exe')
if ($setup.Count -ne 1) { throw 'Expected exactly one installer' }
$installed = Join-Path $out 'installed'
$process = Start-Process $setup[0].FullName -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/DIR=`"$installed`"", "/LOG=`"$results/install.log`"") -Wait -PassThru
if ($process.ExitCode -ne 0) { throw "Installer failed: $($process.ExitCode)" }
foreach ($name in @('mpvnet.exe', 'libmpv-2.dll', 'MediaInfo.dll', 'mpvnet.com')) {
    if ((Get-FileHash "$installed/$name").Hash -ne (Get-FileHash "$out/publish/$name").Hash) {
        throw "Installed file differs: $name"
    }
}
$process = Start-Process "$installed/unins000.exe" -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') -Wait -PassThru
if ($process.ExitCode -ne 0) { throw 'Uninstall failed' }
'PASS: defaults, overrides, native ICC rendering, installation and uninstall' | Set-Content "$results/summary.txt"
