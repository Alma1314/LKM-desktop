; ==================================================
#define AppVersion "3.3.0"
#define BuildNumber "144"
; ==================================================

#define FullVersion AppVersion + "." + BuildNumber

[Setup]
AppName=理科迷
AppVersion={#AppVersion}
AppPublisher=LKM-AHZ
AppUpdatesURL=https://github.com/LKM-AHZ/LKM-desktop/releases
AppCopyright=Copyright © 2026 LKM-AHZ
VersionInfoVersion={#FullVersion}
UninstallDisplayName=理科迷
UninstallDisplayIcon={app}\Phientist.exe

DefaultDirName={commonpf}\Phientist
; Reuse the directory of an existing installation so an unattended update
; (/SILENT) replaces the same files the running build came from.
UsePreviousAppDir=yes

OutputDir=.\Installer
OutputBaseFilename=windows-x86_64-setup
SetupIconFile=.\assets\icons\icon.ico  

Compression=lzma2/ultra64
SolidCompression=yes
LZMAUseSeparateProcess=yes
LZMANumBlockThreads=4

ArchitecturesAllowed=x64compatible
PrivilegesRequired=admin

[Files]
Source: ".\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\理科迷"; Filename: "{app}\Phientist.exe";IconFilename: "{app}\Phientist.exe"
Name: "{group}\{cm:UninstallProgram,理科迷}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\理科迷"; Filename: "{app}\Phientist.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Run]
Filename: "{app}\Phientist.exe"; Description: "Launch 理科迷"; Flags: nowait postinstall skipifsilent
; The updater runs this installer with /SILENT, and Setup closes the running
; Phientist through the Restart Manager before replacing its files. Nothing is
; left on screen afterwards and RestartApplications cannot bring it back
; (Flutter's Windows runner never calls RegisterApplicationRestart), so relaunch
; the installed build with the original, non-elevated user token.
Filename: "{app}\Phientist.exe"; Flags: nowait runasoriginaluser skipifnotsilent

[UninstallDelete]
Type: filesandordirs; Name: "{userappdata}\LKM-AHZ\Phientist"
Type: files; Name: "{group}\理科迷.lnk" ;
Type: files; Name: "{autodesktop}\理科迷.lnk" ;
