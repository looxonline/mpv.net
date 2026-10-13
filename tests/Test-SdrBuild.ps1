$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = (Resolve-Path "$PSScriptRoot/..").Path
$out = Join-Path $root 'artifacts'
$results = Join-Path $out 'test-results'
New-Item -ItemType Directory -Force $results | Out-Null
& dotnet publish "$PSScriptRoot/SdrSmoke/SdrSmoke.csproj" -c Release -r win-x64 --self-contained true -o "$out/smoke"
if ($LASTEXITCODE -ne 0) { throw 'Smoke test compilation failed' }
foreach ($mode in @('defaults', 'override', 'regressions', 'render')) {
    & "$out/smoke/SdrSmoke.exe" $mode "$out/publish" $results
    if ($LASTEXITCODE -ne 0) { throw "Smoke test failed: $mode" }
}
$setup = @(Get-ChildItem "$out/installer" -Filter '*.exe')
if ($setup.Count -ne 1) { throw 'Expected exactly one installer' }
$appVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo("$out/publish/mpvnet.exe").FileVersion
$setupVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($setup[0].FullName)
if ($setupVersion.FileVersion -ne $appVersion -or $setupVersion.ProductVersion -ne $appVersion) {
    throw "Installer version does not match application version $appVersion"
}
$installed = Join-Path $out 'installed'
$process = Start-Process $setup[0].FullName -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/DIR=`"$installed`"", "/LOG=`"$results/install.log`"") -Wait -PassThru
if ($process.ExitCode -ne 0) { throw "Installer failed: $($process.ExitCode)" }
foreach ($name in @('mpvnet.exe', 'libmpv-2.dll', 'MediaInfo.dll', 'mpvnet.com')) {
    if ((Get-FileHash "$installed/$name").Hash -ne (Get-FileHash "$out/publish/$name").Hash) {
        throw "Installed file differs: $name"
    }
}
$uiConfig = Join-Path $results 'installed-app-config'
New-Item -ItemType Directory -Force $uiConfig | Out-Null
$previousConfig = $env:MPVNET_HOME
$env:MPVNET_HOME = $uiConfig
$app = $null
try {
    $app = Start-Process "$installed/mpvnet.exe" -ArgumentList @('--idle=yes', '--load-scripts=no', '--d3d11-warp=yes', "--log-file=`"$results/installed-app.log`"", "`"$results/gradient.ppm`"") -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    do {
        Start-Sleep -Milliseconds 250
        $app.Refresh()
        if ($app.HasExited) { throw "Installed application exited during startup: $($app.ExitCode)" }
    } while ($app.MainWindowHandle -eq 0 -and [DateTime]::UtcNow -lt $deadline)
    if ($app.MainWindowHandle -eq 0) { throw 'Installed application did not create its window' }
    Start-Sleep -Seconds 2
    if (!$app.CloseMainWindow() -or !$app.WaitForExit(20000)) { throw 'Installed application did not close normally' }
    if ($app.ExitCode -ne 0) { throw "Installed application failed: $($app.ExitCode)" }
} finally {
    if ($null -ne $app -and !$app.HasExited) { $app.Kill() }
    $env:MPVNET_HOME = $previousConfig
}
$process = Start-Process "$installed/unins000.exe" -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') -Wait -PassThru
if ($process.ExitCode -ne 0) { throw 'Uninstall failed' }
'PASS: defaults, overrides, upstream regressions, native ICC rendering, installed GUI startup/exit, installation and uninstall' | Set-Content "$results/summary.txt"
