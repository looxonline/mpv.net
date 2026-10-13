# mpv.net SDR for Windows 11

This x64 fork enables monitor ICC colour conversion by default. mpv decodes the
video, interprets its source colour metadata, and uses LittleCMS in its GPU
renderer to transform the resulting RGB into the display profile's colour space.
It does not rewrite decoded video files or change the system calibration curves.

## Installation and playback

Download `mpv.net-SDR-Windows-x64` from the successful **SDR Windows installer**
GitHub Actions run, extract it, and run the setup EXE. The installer includes .NET
and installs per user under `%LOCALAPPDATA%\Programs\mpv.net SDR` with a separate
uninstaller and Start menu entry. It is unsigned. The build targets x64 Windows 11.

Turn Windows **Use HDR** off for the playback display. Assign an ICC/ICM profile
that actually characterizes that display in Windows Colour Management (`colorcpl`).
WCS profiles are not supported. Profiling/calibration must be done separately;
loading an ICC profile cannot characterize an unmeasured display.

The defaults, applied before user configuration, are:

```ini
vo=gpu
gpu-api=d3d11
icc-profile-auto=yes
target-colorspace-hint=no
target-prim=bt.709
target-trc=bt.1886
target-peak=100
```

A valid ICC profile takes precedence over target primaries/transfer settings.
Without one, output falls back to the SDR target; it is not display-corrected.
HDR passthrough is disabled by default. HDR source material is not the validation
target of this build; this is an SDR playback build, not a codec-level HDR ban.
Windows HDR and automatic system colour management require separate validation.

Open **Settings > Show Config Editor** (or the configuration editor entry in your
menu), then **Video / Colour Management**:

- Automatic: `icc-profile-auto=yes`, with `icc-profile` empty.
- Manual: set `icc-profile` to the full path of an ICC/ICM file. This overrides
  automatic detection and stays fixed when the window moves.
- Off: clear `icc-profile` and set `icc-profile-auto=no`.

Restart playback after settings changes. Automatic mode follows the monitor
containing the greatest part of the playback window. The frontend notifies mpv
when the embedding window changes monitors or receives display/settings changes.
Restart the player after replacing the contents of an ICC file at the same path.
A window spanning two monitors has a single colour transform.

**View > Display Colour Information** reports the selected mode, Windows-assigned
or manually configured profile, and renderer information. The profile path alone
does not prove that the profile loaded successfully; use verbose logs to check.
For an existing custom input menu, add this command or invoke it via the console:

```text
script-message-to mpvnet show-display-colour-info
```

Existing `%APPDATA%\mpv.net` settings are shared with upstream mpv.net and can
override these defaults. The installer does not replace user configuration.
For isolated testing, create a writable folder and launch from PowerShell:

```powershell
$env:MPVNET_HOME = "$env:LOCALAPPDATA\mpv.net-SDR-test"
New-Item -ItemType Directory -Force $env:MPVNET_HOME | Out-Null
& "$env:LOCALAPPDATA\Programs\mpv.net SDR\mpvnet.exe" '--msg-level=all=v' "--log-file=$env:MPVNET_HOME\icc.log" 'C:\Videos\test.mp4'
```

Look for `color-profile:`, `Opening ICC profile`, ICC/LUT messages and loading
errors. Automatic profiles are passed to the renderer in memory, so they need
not produce the same file-opening message as manual profiles.

## Verification

CI tests actual defaults and config overrides against the bundled libmpv, renders
a synthetic gradient through a Windows ICC profile using D3D11 WARP, compares
ICC-on/off output, and installs/uninstalls the generated package. Diagnostics are
uploaded separately. A cloud runner does not establish physical colour accuracy.

On the Windows 11 playback machine:

1. Test known SDR video with HDR off and the correct display profile assigned.
2. Confirm the profile in Display Colour Information and the verbose log.
3. Move playback between monitors with distinct ICC profiles, including while
   paused and when entering/leaving fullscreen. Confirm profile changes in logs.
4. Verify manual mode stays fixed and off mode disables ICC conversion.
5. Check playback performance and compare against a trusted colour-managed
   reference. Use measurement equipment if numerical colour accuracy is required.

## Building

Run `./src/Tools/build-sdr.ps1` on Windows with the .NET 10 SDK and Inno Setup 6,
then `./tests/Test-SdrBuild.ps1`. The GitHub workflow does both. The installer is
under `artifacts/installer`, accompanied by its SHA-256 checksum.

Native libraries, the console launcher and existing translations are taken from
upstream mpv.net v7.1.2.0's x64 archive and verified by SHA-256. The managed player
is compiled from this repository; no upstream player executable is repackaged.
`BUILD-INFO.txt` records the source commit and dependency archive. New strings
fall back to English. Runtime updates should be pinned and retested explicitly.

Upstream sources and licences: https://github.com/mpvnet-player/mpv.net (GPL-2.0),
https://github.com/mpv-player/mpv and its bundled dependencies, and
https://mediaarea.net/MediaInfo. This repository retains the upstream licence.
