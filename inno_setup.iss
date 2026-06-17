; Inno Setup script for Snag Report Extractor
; Build the app first:  flutter build windows --release
; Then compile this script with the Inno Setup Compiler (ISCC.exe) or the IDE.
; All paths are relative to this .iss file, so it works on any machine / CI runner.

#define MyAppName "Snag Report Extractor"
#define MyAppExeName "snag_report_extractor_app.exe"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Desality Snagging"

; Flutter release output, relative to this script. {#SourcePath} already ends with a backslash.
#define BuildDir "build\windows\x64\runner\Release"

[Setup]
; AppId uniquely identifies this app so upgrades replace the previous version.
; Keep this GUID stable across releases.
AppId={{8F3A6E1C-2D4B-4F9A-B7C3-9E5D1A0F62B4}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
OutputDir={#SourcePath}{#BuildDir}\installer
OutputBaseFilename=SnagReportExtractor-Setup-{#MyAppVersion}
Compression=lzma
SolidCompression=yes
; This is a 64-bit application.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"

[Files]
Source: "{#SourcePath}{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{userdesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
