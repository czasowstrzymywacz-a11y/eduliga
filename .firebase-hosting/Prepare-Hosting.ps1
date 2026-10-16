$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path -Parent $PSScriptRoot
$publishRoot = Join-Path $PSScriptRoot 'public'
$assets = @(
 'index.html','version.json','ortoliga-core.js','ortoliga.js','ortoliga.css',
 'liga-angielska.js','liga-angielska.css','liga-social.js','liga-rankings.js',
 'liga-platform.js','liga-platform.css','liga-hiszpanska-data.js','liga-hiszpanska.js',
 'liga-zdania.js','liga-arena.js','liga-pomocnika.js','eduliga-ui.js',
 'eduliga-community.js','eduliga-experience.js','eduliga-topics.js','eduliga-ocr.js','eduliga-hosting.js',
 'eduliga-logo.svg','eduliga-flag-en.svg','eduliga-flag-es.svg','eduliga-flag-pl.svg'
)
foreach ($asset in $assets) {
 if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot $asset) -PathType Leaf)) { throw "Brak pliku: $asset" }
}
New-Item -ItemType Directory -Path $publishRoot -Force | Out-Null
foreach ($asset in $assets) { Copy-Item -LiteralPath (Join-Path $sourceRoot $asset) -Destination (Join-Path $publishRoot $asset) -Force }
Write-Output 'Przygotowano pliki strony. Nie wykonano publikacji ani zmiany wersji.'
