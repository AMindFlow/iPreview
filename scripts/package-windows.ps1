param(
    [Parameter(Mandatory)][string]$PublishDirectory,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$Compiler = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
)

$ErrorActionPreference = 'Stop'
$publish = (Resolve-Path -LiteralPath $PublishDirectory).Path
$output = (New-Item -ItemType Directory -Force -Path $OutputDirectory).FullName
foreach ($file in 'iPreview.exe', 'iPreview.pri', 'App.xbf', 'MainWindow.xbf', 'AlbumMediaPicker.xbf', 'Assets\AppIcon.ico', 'coreclr.dll', 'Microsoft.UI.Xaml.dll') {
    if (!(Test-Path -LiteralPath (Join-Path $publish $file) -PathType Leaf)) {
        throw "Self-contained Windows publish is missing $file"
    }
}
[xml]$project = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\apps\windows\iPreview\iPreview.csproj') -Raw
$version = [string]$project.Project.PropertyGroup.Version
$installerScript = Join-Path $PSScriptRoot '..\packaging\windows\iPreview.iss'
& $Compiler "/DPublishDir=$publish" "/DAppVersion=$version" "/O$output" $installerScript
if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed with exit code $LASTEXITCODE" }
Get-FileHash -Algorithm SHA256 (Join-Path $output "iPreview-$version-windows-x64-setup.exe")
