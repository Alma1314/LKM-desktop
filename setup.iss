; ==================================================
#define AppVersion "3.3.0"
#define BuildNumber "144"
; ==================================================

#define FullVersion AppVersion + "." + BuildNumber

[Setup]
AppName=LKM
AppVersion={#AppVersion}
AppPublisher=LKM-AHZ
AppPublisherURL=https://lkm-ahz.ltd
AppSupportURL=https://lkm-ahz.ltd
AppUpdatesURL=https://github.com/LKM-AHZ/LKM-desktop/releases
AppCopyright=Copyright © 2026 LKM-AHZ
VersionInfoVersion={#FullVersion}
UninstallDisplayName=LKM
UninstallDisplayIcon={app}\LKM.exe

DefaultDirName={commonpf}\LKM
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
Name: "{group}\LKM"; Filename: "{app}\LKM.exe";IconFilename: "{app}\LKM.exe"
Name: "{group}\{cm:UninstallProgram,LKM}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\LKM"; Filename: "{app}\LKM.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Run]
Filename: "{app}\LKM.exe"; Description: "Launch LKM"; Flags: nowait postinstall skipifsilent
; The updater runs this installer with /SILENT, and Setup closes the running
; LKM through the Restart Manager before replacing its files. Nothing is
; left on screen afterwards and RestartApplications cannot bring it back
; (Flutter's Windows runner never calls RegisterApplicationRestart), so relaunch
; the installed build with the original, non-elevated user token.
Filename: "{app}\LKM.exe"; Flags: nowait runasoriginaluser skipifnotsilent

[UninstallDelete]
Type: filesandordirs; Name: "{userappdata}\LKM-AHZ\LKM"
Type: files; Name: "{group}\LKM.lnk" ;
Type: files; Name: "{autodesktop}\LKM.lnk" ;
