$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'tools/node_modules/firebase-tools/lib/bin/firebase.js'
if (-not (Test-Path -LiteralPath $cli -PathType Leaf)) {
    throw 'Brak oficjalnego Firebase CLI w folderze tools.'
}
# Use the Windows certificate store as well as Node's bundled roots.
$env:NODE_USE_SYSTEM_CA = '1'
& (Join-Path (Split-Path -Parent $PSScriptRoot) 'Create-Backup.ps1')
& (Join-Path $PSScriptRoot 'Prepare-Hosting.ps1')
Push-Location $PSScriptRoot
try {
    & node $cli deploy --only hosting --project eduliga --non-interactive
    if ($LASTEXITCODE -ne 0) { throw 'Publikacja Firebase nie powiodła się. Nie zmieniaj przekierowań.' }
} finally {
    Pop-Location
}
