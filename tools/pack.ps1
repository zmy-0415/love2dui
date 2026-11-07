# Package LumiUI into a distributable .love archive (zip with main.lua at its root).
#
# Usage (from the repo root):
#   powershell -ExecutionPolicy Bypass -File tools\pack.ps1
#   powershell -File tools\pack.ps1 -OutDir build
#
# Output: <OutDir>\lumiui-<version>.love
# Run:    love build\lumiui-0.2.0.love
#
# NOTE: keep this file ASCII-only. Windows PowerShell 5.1 decodes BOM-less
# scripts as ANSI, and CJK comments can swallow the following line.

param(
    [string]$OutDir = "build"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    if (-not (Test-Path "main.lua")) {
        throw "main.lua not found: the .love package must have it at the archive root"
    }

    # Version comes from lumi/init.lua so the two never drift apart.
    $init = Get-Content -Raw -Encoding UTF8 "lumi/init.lua"
    $version = "0.0.0"
    if ($init -match 'lumi\.version\s*=\s*"([^"]+)"') {
        $version = $Matches[1]
    }

    if (-not (Test-Path $OutDir)) {
        New-Item -ItemType Directory -Path $OutDir | Out-Null
    }

    $name = "lumiui-$version.love"
    $zip = Join-Path $OutDir ($name + ".zip")
    $out = Join-Path $OutDir $name

    if (Test-Path $zip) { Remove-Item $zip -Force }
    if (Test-Path $out) { Remove-Item $out -Force }

    $items = @()
    foreach ($i in @("main.lua", "conf.lua", "README.md", "lumi", "demo", "tests")) {
        if (Test-Path $i) { $items += $i }
    }

    Compress-Archive -Path $items -DestinationPath $zip -CompressionLevel Optimal
    Move-Item -Path $zip -Destination $out -Force

    $size = [math]::Round((Get-Item $out).Length / 1KB, 1)
    Write-Host "OK  $out  ($size KB, version $version)"
    Write-Host "Run: love `"$out`""
}
finally {
    Pop-Location
}
