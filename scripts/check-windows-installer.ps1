param(
    [Parameter(Mandatory)][string]$Installer,
    [Parameter(Mandatory)][string]$PublishDirectory,
    [Parameter(Mandatory)][string]$EvidenceDirectory
)

$ErrorActionPreference = 'Stop'
$installerPath = (Resolve-Path -LiteralPath $Installer).Path
$publish = (Resolve-Path -LiteralPath $PublishDirectory).Path
$evidence = (New-Item -ItemType Directory -Force -Path $EvidenceDirectory).FullName
$install = Join-Path $env:LOCALAPPDATA 'Programs\iPreview'
$catalog = Join-Path $env:LOCALAPPDATA 'iPreview\library.sqlite3'
$shortcutPath = Join-Path ([Environment]::GetFolderPath('Programs')) 'iPreview.lnk'
$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\io.github.amindflow.iPreview_is1'

# This check belongs on an isolated CI runner, never a user's installed library.
if ((Test-Path -LiteralPath $install) -or (Test-Path -LiteralPath $catalog) -or (Test-Path -LiteralPath $shortcutPath) -or (Test-Path -LiteralPath $uninstallKey)) {
    throw 'Installer acceptance requires a fresh runner without an existing iPreview installation or catalog'
}
New-Item -ItemType Directory -Force -Path (Split-Path $catalog) | Out-Null
Set-Content -LiteralPath $catalog -Value 'synthetic catalog preservation sentinel'
$catalogHash = (Get-FileHash -LiteralPath $catalog -Algorithm SHA256).Hash

function Run-Setup([string]$LogName) {
    $process = Start-Process -FilePath $installerPath -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/LOG=`"$(Join-Path $evidence $LogName)`"") -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "Installation failed with exit code $($process.ExitCode)" }
}

function Check-Payload {
    $files = Get-ChildItem -LiteralPath $publish -File -Recurse
    foreach ($file in $files) {
        $relative = [IO.Path]::GetRelativePath($publish, $file.FullName)
        $actual = Join-Path $install $relative
        if (!(Test-Path -LiteralPath $actual -PathType Leaf) -or
            (Get-FileHash -LiteralPath $actual -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash) {
            throw "Installed payload differs: $relative"
        }
    }
    Write-Output "Verified $($files.Count) installed files against the self-contained publish"
}

Run-Setup 'install.log'
Check-Payload
$shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcutPath)
if ($shortcut.TargetPath -ne (Join-Path $install 'iPreview.exe')) { throw 'Start Menu shortcut points to the wrong executable' }
if ((Get-ItemProperty -LiteralPath $uninstallKey).DisplayName -ne 'iPreview') { throw 'Uninstall registration is missing' }

$userFile = Join-Path $install 'user-created-sentinel.txt'
Set-Content -LiteralPath $userFile -Value 'not owned by the installer'
$userFileHash = (Get-FileHash -LiteralPath $userFile -Algorithm SHA256).Hash
Set-Content -LiteralPath (Join-Path $install 'Assets\AppIcon.ico') -Value 'synthetic damaged installed asset'
Run-Setup 'upgrade.log'
Check-Payload

$uninstaller = Join-Path $install 'unins000.exe'
$process = Start-Process -FilePath $uninstaller -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/LOG=`"$(Join-Path $evidence 'uninstall.log')`"") -Wait -PassThru
if ($process.ExitCode -ne 0) { throw "Uninstallation failed with exit code $($process.ExitCode)" }
if ((Test-Path -LiteralPath (Join-Path $install 'iPreview.exe')) -or (Test-Path -LiteralPath $shortcutPath) -or (Test-Path -LiteralPath $uninstallKey)) {
    throw 'Uninstallation left the application, shortcut or uninstall registration behind'
}
if ((Get-FileHash -LiteralPath $catalog -Algorithm SHA256).Hash -ne $catalogHash -or
    (Get-FileHash -LiteralPath $userFile -Algorithm SHA256).Hash -ne $userFileHash) {
    throw 'Install, upgrade or uninstall changed user-owned data'
}
Write-Output 'Fresh install, same-version repair and uninstall passed; catalog and unowned files are unchanged'
