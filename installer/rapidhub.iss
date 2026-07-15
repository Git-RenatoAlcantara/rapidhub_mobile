; Inno Setup script — gera um instalador .exe único do RapidHub (Windows).
; Empacota toda a pasta build\windows\x64\runner\Release (exe + DLLs + data).
;
; Uso:
;   1. flutter build windows --release
;   2. "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\rapidhub.iss
;   Saída: installer\Output\rapidhub-setup-<versao>.exe

#define AppName "RapidHub"
#define AppVersion "1.0.0"
#define AppExe "rapidhubmobile.exe"
#define Publisher "RapidHub"
; Caminho da pasta de build, relativo a este .iss (installer\ -> raiz do repo).
#define BuildDir "..\build\windows\x64\runner\Release"

[Setup]
AppId={{B7E4A9C2-3F1D-4E8A-9C6B-2A5D8F0E1234}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#Publisher}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
UninstallDisplayIcon={app}\{#AppExe}
OutputDir=Output
OutputBaseFilename=rapidhub-setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; Instala por máquina (Program Files) — exige elevação. Para instalar por
; usuário sem admin, troque para: PrivilegesRequired=lowest e {autopf}->{localappdata}
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Tasks]
Name: "desktopicon"; Description: "Criar atalho na área de trabalho"; GroupDescription: "Atalhos:"

[Files]
; Copia recursivamente TODA a pasta de build (exe, *.dll, pasta data\).
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\Desinstalar {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "Abrir {#AppName}"; Flags: nowait postinstall skipifsilent
