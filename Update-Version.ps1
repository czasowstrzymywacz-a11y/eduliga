param(
    [ValidatePattern('^\d+\.\d+$')]
    [string]$Version
)

$ErrorActionPreference = 'Stop'
$versionPath = Join-Path $PSScriptRoot 'version.json'
$htmlPath = Join-Path $PSScriptRoot 'index.html'
$current = (Get-Content -LiteralPath $versionPath -Raw | ConvertFrom-Json).version
if (-not $Version) {
    if ($current -notmatch '^\d+\.\d+$') { throw 'Nieprawidlowy numer w version.json.' }
    $parts = $current.Split('.')
    $Version = '{0}.{1}' -f $parts[0], ([int]$parts[1] + 1)
}
$html = [System.IO.File]::ReadAllText($htmlPath)
$metaPattern = '<meta name="application-version" content="[^"]+">'
$badgePattern = '<button type="button" id="app-version" class="app-version" title="Pokaż historię wersji" onclick="openVersionHistory\(\)">v[^<]+</button>'
foreach ($pattern in @($metaPattern, $badgePattern)) {
    if ([regex]::Matches($html, $pattern).Count -ne 1) {
        throw 'Nie znaleziono pojedynczego oznaczenia wersji w index.html.'
    }
}
$html = [regex]::Replace($html, $metaPattern, ('<meta name="application-version" content="{0}">' -f $Version))
$html = [regex]::Replace($html, $badgePattern, ('<button type="button" id="app-version" class="app-version" title="Pokaż historię wersji" onclick="openVersionHistory()">v{0}</button>' -f $Version))
foreach ($asset in @('ortoliga.css','ortoliga-core.js','ortoliga.js','liga-angielska.css','liga-angielska.js')) {
    $pattern = [regex]::Escape($asset) + '\?v=\d+\.\d+'
    $html = [regex]::Replace($html, $pattern, ($asset + '?v=' + $Version))
}
$utf8 = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($htmlPath, $html, $utf8)
[System.IO.File]::WriteAllText($versionPath, ((@{version=$Version} | ConvertTo-Json) + [Environment]::NewLine), $utf8)
Write-Output ('Wersja aplikacji: {0}' -f $Version)
