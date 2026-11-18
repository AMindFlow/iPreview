#ifndef PublishDir
  #error PublishDir is required
#endif
#ifndef AppVersion
  #error AppVersion is required
#endif

[Setup]
AppId=io.github.amindflow.iPreview
AppName=iPreview
AppVersion={#AppVersion}
AppPublisher=AMindFlow
AppPublisherURL=https://github.com/AMindFlow/iPreview
DefaultDirName={localappdata}\Programs\iPreview
DisableDirPage=no
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64os
ArchitecturesInstallIn64BitMode=x64os
MinVersion=10.0.22000
OutputBaseFilename=iPreview-{#AppVersion}-windows-x64-setup
SetupIconFile={#PublishDir}\Assets\AppIcon.ico
UninstallDisplayIcon={app}\iPreview.exe
WizardStyle=modern dynamic windows11
Compression=lzma2
SolidCompression=yes
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "{#PublishDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{userprograms}\iPreview"; Filename: "{app}\iPreview.exe"

[Run]
Filename: "{app}\iPreview.exe"; Description: "{cm:LaunchProgram,iPreview}"; Flags: nowait postinstall skipifsilent
