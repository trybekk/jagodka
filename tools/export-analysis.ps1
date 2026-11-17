# Eksport wszystkich analiz (analysis\) do jednego zipa dla oficerów:
#   analysis\exports\jagodka-analizy-RRRR.MM.DD_N.zip  z jednym plikiem  jagodka-analizy.html
# Strona i wszystkie pliki data\*.js są sklejone w jeden HTML, więc działa po dwukliku, także prosto z zipa
# (bez rozpakowywania) i bez internetu. Linki do dokumentacji projektu są usuwane, bo oficer jej nie ma.
# Uwaga: analizy zawierają nazwy graczy i cytaty z czatu – przesyłaj tylko oficerom.

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Dir = Join-Path $Root 'analysis'
$Out = Join-Path $Dir 'exports'
$utf8 = New-Object System.Text.UTF8Encoding $false

$index = Join-Path $Dir 'index.html'
$listJs = Join-Path $Dir 'data\list.js'
if (-not (Test-Path $index) -or -not (Test-Path $listJs)) { Write-Host 'Brak analysis\index.html albo analysis\data\list.js.'; exit 1 }

# Analizy w kolejności z list.js (tylko te wpisane na listę, jak na stronie)
$ids = [regex]::Matches([IO.File]::ReadAllText($listJs, $utf8), "'([^']+)'") | ForEach-Object { $_.Groups[1].Value }
$data = New-Object System.Text.StringBuilder
$count = 0
foreach ($id in $ids) {
    $f = Join-Path $Dir "data\$id.js"
    if (-not (Test-Path $f)) { Write-Host "Pomijam (brak pliku): data\$id.js"; continue }
    $js = [IO.File]::ReadAllText($f, $utf8) -replace '</script', '<\/script'
    [void]$data.AppendLine("// ---- $id ----").AppendLine($js)
    $count++
}
if (-not $count) { Write-Host 'Brak analiz do eksportu.'; exit 1 }

$html = [IO.File]::ReadAllText($index, $utf8)
$now = Get-Date
$stamp = $now.ToString('dd.MM.yyyy HH:mm')
# Dane w miejsce <script src="data/list.js">; pusta lista plików, więc loader strony niczego już nie dociąga
$inline = "<script>`nwindow.ANALYSIS_FILES = [];`nwindow.ANALYSES = [];`n" + $data.ToString() + "</script>"
$html = $html.Replace('<script src="data/list.js"></script>', $inline)
# Bez linków do dokumentacji projektu; w nagłówku data eksportu
$html = [regex]::Replace($html, '\s*<a href="\.\./doc/[^"]*">[^<]*</a>', '')
$html = $html.Replace('– analizy z logów</h1>', "– analizy z logów <small style=`"font-weight:400;color:var(--muted);font-size:13px`">eksport z $stamp, analiz: $count</small></h1>")
if ($html.Contains('<script src="data/list.js">')) { Write-Host 'Błąd: strona nadal odwołuje się do data/ - eksport przerwany.'; exit 1 }

if (-not (Test-Path $Out)) { New-Item -ItemType Directory $Out | Out-Null }
$date = $now.ToString('yyyy.MM.dd')
$n = 1
while (Test-Path (Join-Path $Out "jagodka-analizy-${date}_$n.zip")) { $n++ }
$zip = Join-Path $Out "jagodka-analizy-${date}_$n.zip"

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("jagodka-export-" + [guid]::NewGuid())
New-Item -ItemType Directory $tmp | Out-Null
try {
    [IO.File]::WriteAllText((Join-Path $tmp 'jagodka-analizy.html'), $html, $utf8)
    Compress-Archive -Path (Join-Path $tmp 'jagodka-analizy.html') -DestinationPath $zip
} finally { Remove-Item $tmp -Recurse -Force }

Write-Host "Gotowe: $zip"
Write-Host "Analiz: $count. W środku: jagodka-analizy.html (otwiera się dwuklikiem)."
Start-Process explorer.exe "/select,`"$zip`""
