#ifndef SourceDir
  #error SourceDir must point to the self-contained publish directory
#endif
#ifndef OutputPath
  #define OutputPath "."
#endif
#define AppVersion GetFileVersion(SourceDir + "\mpvnet.exe")

[Setup]
AppId={{AC7F2639-50CC-4CF2-A2FB-2B8385570342}
AppName=mpv.net SDR
AppVersion={#AppVersion}
VersionInfoVersion={#AppVersion}
VersionInfoTextVersion={#AppVersion}
VersionInfoProductVersion={#AppVersion}
VersionInfoProductTextVersion={#AppVersion}
AppPublisher=looxonline (mpv.net SDR fork)
AppPublisherURL=https://github.com/looxonline/mpv.net
DefaultDirName={localappdata}\Programs\mpv.net SDR
DefaultGroupName=mpv.net SDR
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.22000
OutputDir={#OutputPath}
OutputBaseFilename=mpv.net-SDR-v{#AppVersion}-setup-x64
Compression=lzma2
SolidCompression=yes
SetupIconFile=..\..\MpvNet.Windows\mpv-icon.ico
UninstallDisplayIcon={app}\mpvnet.exe
LicenseFile=..\..\..\License.txt

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\mpv.net SDR"; Filename: "{app}\mpvnet.exe"
Name: "{group}\SDR playback guide"; Filename: "{app}\SDR-README.md"
