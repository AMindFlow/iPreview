param(
    [Parameter(Mandatory)][string]$Application
)

$ErrorActionPreference = 'Stop'
$executable = (Resolve-Path -LiteralPath $Application).Path
$qa = Join-Path ([IO.Path]::GetTempPath()) ('ipreview-launch-' + [Guid]::NewGuid().ToString('N'))
$catalog = Join-Path $qa 'library.sqlite3'
$previousCatalog = $env:IPREVIEW_DATA_DIR
$process = $null

try {
    $env:IPREVIEW_DATA_DIR = $qa
    $process = Start-Process -FilePath $executable -WorkingDirectory (Split-Path $executable) -PassThru
    for ($attempt = 0; $attempt -lt 40; $attempt++) {
        if ($process.HasExited) {
            throw "The packaged application exited during launch with code $($process.ExitCode)"
        }
        if ((Test-Path -LiteralPath $catalog -PathType Leaf) -and (Get-Item -LiteralPath $catalog).Length -gt 0) {
            break
        }
        Start-Sleep -Milliseconds 500
    }
    if ($attempt -eq 40) {
        throw 'The packaged application did not initialize its isolated catalog'
    }
    if ($process.WaitForExit(3000)) {
        throw "The packaged application exited after opening its catalog with code $($process.ExitCode)"
    }
    Write-Output 'iPreview stayed running on Windows and opened its isolated catalog'
} finally {
    $env:IPREVIEW_DATA_DIR = $previousCatalog
    if ($process -and !$process.HasExited) {
        if (!$process.CloseMainWindow() -or !$process.WaitForExit(3000)) {
            Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
        }
    }
}
