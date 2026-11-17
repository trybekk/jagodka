# Kopiuje logi Jagodki z WoW Forever do logs/ (git-ignored).
#   logs.bat          okienko: wybór folderu gry i postaci, zapamiętuje wybór w tools\logs.config.json
#   logs.bat -Quick   bez okienka, kopiuje to, co zapisane w configu
# Pliki: logi postaci -> logs\jagodka-RRRR.MM.DD_N.lua, plik konta (treść czatu) -> logs\chat-RRRR.MM.DD_N.lua.
# Data w nazwie = kiedy gra zapisała plik. Plik identyczny z już skopiowanym jest pomijany. Każda kopia trafia
# do logs\logs.txt (skąd i kiedy).
param([switch]$Quick)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$LogsDir = Join-Path $Root 'logs'
$ConfigPath = Join-Path $PSScriptRoot 'logs.config.json'

# ---------- config ----------
function Load-Config {
    if (Test-Path $ConfigPath) {
        try { return Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
    }
    return [pscustomobject]@{ forever = ''; selected = @() }
}
function Save-Config($forever, $selected) {
    [pscustomobject]@{ forever = $forever; selected = @($selected) } | ConvertTo-Json | Set-Content $ConfigPath -Encoding UTF8
}

# ---------- finding WoW Forever ----------
function Find-Forever {
    $bases = New-Object System.Collections.Generic.List[string]
    # Battle.net installs: the uninstall entries of any World of Warcraft flavour point to the shared folder
    $keys = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    foreach ($k in $keys) {
        Get-ItemProperty $k -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like 'World of Warcraft*' -and $_.InstallLocation } |
            ForEach-Object { $bases.Add($_.InstallLocation) }
    }
    $p = Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft' -ErrorAction SilentlyContinue
    if ($p -and $p.InstallPath) { $bases.Add((Split-Path -Parent ($p.InstallPath.TrimEnd('\')))) }
    # Usual places on every drive
    foreach ($d in (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root })) {
        foreach ($sub in 'World of Warcraft', 'Program Files (x86)\World of Warcraft', 'Program Files\World of Warcraft', 'Games\World of Warcraft',
                         'Gry\World of Warcraft', 'Blizzard\World of Warcraft', 'battle.net\World of Warcraft', 'Battle.net\Games\World of Warcraft') {
            $bases.Add((Join-Path $d.Root $sub))
        }
    }
    foreach ($b in $bases) {
        $f = Join-Path $b '_forever_'
        if (Test-Path (Join-Path $f 'WTF')) { return $f }
    }
    return ''
}

# ---------- what can be copied ----------
# Every SavedVariables\jagodka.lua under WTF\Account: per character (Monitoring log) and per account (chat text)
function Get-Sources($forever) {
    $acc = Join-Path $forever 'WTF\Account'
    if (-not (Test-Path $acc)) { return @() }
    Get-ChildItem $acc -Recurse -Filter 'jagodka.lua' -ErrorAction SilentlyContinue |
        Where-Object { $_.Directory.Name -eq 'SavedVariables' } | ForEach-Object {
            $rel = $_.Directory.Parent.FullName.Substring($acc.Length).TrimStart('\')
            $parts = $rel -split '\\'
            [pscustomobject]@{
                Key     = $rel
                Kind    = $(if ($parts.Count -ge 3) { 'postac' } else { 'konto' })
                Account = $parts[0]
                Server  = $(if ($parts.Count -ge 3) { $parts[1] } else { '' })
                Char    = $(if ($parts.Count -ge 3) { $parts[2] } else { '(plik konta: treść czatu)' })
                Path    = $_.FullName
                Size    = $_.Length
                Time    = $_.LastWriteTime
            }
        } | Sort-Object Kind, Account, Server, Char
}

function Copy-Sources($sources) {
    if (-not (Test-Path $LogsDir)) { New-Item -ItemType Directory $LogsDir | Out-Null }
    $known = @{}
    Get-ChildItem $LogsDir -File -Filter '*.lua' | ForEach-Object { $known[(Get-FileHash $_.FullName -Algorithm SHA1).Hash] = $_.Name }
    $out = @()
    foreach ($s in $sources) {
        $hash = (Get-FileHash $s.Path -Algorithm SHA1).Hash
        if ($known.ContainsKey($hash)) { $out += "bez zmian: $($s.Key) (już jest jako $($known[$hash]))"; continue }
        $prefix = $(if ($s.Kind -eq 'konto') { 'chat' } else { 'jagodka' })
        $date = $s.Time.ToString('yyyy.MM.dd')
        $n = 1
        while (Test-Path (Join-Path $LogsDir "$prefix-${date}_$n.lua")) { $n++ }
        $name = "$prefix-${date}_$n.lua"
        Copy-Item $s.Path (Join-Path $LogsDir $name)
        $known[$hash] = $name
        $line = '{0}  {1}  <-  {2}  ({3} KB, zapisany w grze {4})' -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), $name, $s.Key, [math]::Round($s.Size / 1KB), $s.Time.ToString('dd.MM HH:mm')
        Add-Content (Join-Path $LogsDir 'logs.txt') $line -Encoding UTF8
        $out += "skopiowano: $name  <-  $($s.Key)"
    }
    return $out
}

# ---------- quick mode ----------
if ($Quick) {
    $cfg = Load-Config
    if (-not $cfg.forever -or -not @($cfg.selected).Count) { Write-Host 'Brak zapisanego wyboru: uruchom logs.bat bez -Quick.'; exit 1 }
    $src = @(Get-Sources $cfg.forever | Where-Object { @($cfg.selected) -contains $_.Key })
    if (-not $src.Count) { Write-Host 'Nie znaleziono zapisanych postaci w tym folderze gry.'; exit 1 }
    Copy-Sources $src | ForEach-Object { Write-Host $_ }
    exit 0
}

# ---------- window ----------
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$cfg = Load-Config

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Jagodka – logi z WoW Forever'
$form.Size = New-Object System.Drawing.Size(820, 560)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

$lbl = New-Object System.Windows.Forms.Label
$lbl.Text = 'Folder WoW Forever (_forever_):'
$lbl.SetBounds(12, 14, 200, 20)
$form.Controls.Add($lbl)

$path = New-Object System.Windows.Forms.TextBox
$path.SetBounds(12, 36, 560, 24)
$path.Anchor = 'Top, Left, Right'
$form.Controls.Add($path)

$btnFind = New-Object System.Windows.Forms.Button
$btnFind.Text = 'Znajdź'
$btnFind.SetBounds(580, 35, 100, 26)
$btnFind.Anchor = 'Top, Right'
$form.Controls.Add($btnFind)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = 'Wybierz…'
$btnBrowse.SetBounds(688, 35, 100, 26)
$btnBrowse.Anchor = 'Top, Right'
$form.Controls.Add($btnBrowse)

$hint = New-Object System.Windows.Forms.Label
$hint.Text = 'Zaznacz postacie, z których brać log (Monitoring > Preserve logs). Plik konta zawiera treść czatu. Najpierw /reload w grze.'
$hint.SetBounds(12, 70, 780, 20)
$form.Controls.Add($hint)

$list = New-Object System.Windows.Forms.ListView
$list.View = 'Details'
$list.CheckBoxes = $true
$list.FullRowSelect = $true
$list.SetBounds(12, 94, 776, 330)
$list.Anchor = 'Top, Bottom, Left, Right'
foreach ($c in @(@('Konto', 110), @('Serwer', 70), @('Postać', 230), @('Rozmiar', 90), @('Zapisany w grze', 130), @('', 120))) {
    [void]$list.Columns.Add($c[0], $c[1])
}
$form.Controls.Add($list)

$status = New-Object System.Windows.Forms.TextBox
$status.Multiline = $true
$status.ReadOnly = $true
$status.ScrollBars = 'Vertical'
$status.SetBounds(12, 432, 560, 78)
$status.Anchor = 'Bottom, Left, Right'
$form.Controls.Add($status)

$btnCopy = New-Object System.Windows.Forms.Button
$btnCopy.Text = 'Kopiuj do logs'
$btnCopy.SetBounds(580, 432, 208, 36)
$btnCopy.Anchor = 'Bottom, Right'
$btnCopy.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($btnCopy)

$btnOpen = New-Object System.Windows.Forms.Button
$btnOpen.Text = 'Otwórz folder logs'
$btnOpen.SetBounds(580, 474, 208, 36)
$btnOpen.Anchor = 'Bottom, Right'
$form.Controls.Add($btnOpen)

function Fill-List {
    $list.Items.Clear()
    $p = $path.Text.Trim()
    if (-not $p -or -not (Test-Path (Join-Path $p 'WTF'))) { $status.Text = 'To nie jest folder _forever_ (brak w nim WTF). Kliknij Znajdź albo Wybierz….'; return }
    $src = @(Get-Sources $p)
    foreach ($s in $src) {
        $it = New-Object System.Windows.Forms.ListViewItem($s.Account)
        [void]$it.SubItems.Add($s.Server)
        [void]$it.SubItems.Add($s.Char)
        [void]$it.SubItems.Add(('{0:N0} KB' -f ($s.Size / 1KB)))
        [void]$it.SubItems.Add($s.Time.ToString('dd.MM.yyyy HH:mm'))
        [void]$it.SubItems.Add($(if ($s.Kind -eq 'konto') { 'czat' } else { 'log postaci' }))
        $it.Tag = $s
        $it.Checked = @($cfg.selected) -contains $s.Key
        [void]$list.Items.Add($it)
    }
    $status.Text = $(if ($src.Count) { "Znaleziono $($src.Count) plików Jagodki." } else { 'Brak plików Jagodki w WTF (addon nie był jeszcze uruchomiony?).' })
}

$btnFind.Add_Click({
    $f = Find-Forever
    if ($f) { $path.Text = $f; Fill-List } else { $status.Text = 'Nie znalazłem WoW Forever. Kliknij Wybierz… i wskaż folder _forever_.' }
})
$btnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Wskaż folder _forever_ (np. ...\World of Warcraft\_forever_)'
    if ($path.Text -and (Test-Path $path.Text)) { $dlg.SelectedPath = $path.Text }
    if ($dlg.ShowDialog() -eq 'OK') {
        $p = $dlg.SelectedPath
        # Pointing at "World of Warcraft" itself is fine too
        if (-not (Test-Path (Join-Path $p 'WTF')) -and (Test-Path (Join-Path $p '_forever_\WTF'))) { $p = Join-Path $p '_forever_' }
        $path.Text = $p; Fill-List
    }
})
$path.Add_Leave({ Fill-List })
$btnCopy.Add_Click({
    $sel = @($list.CheckedItems | ForEach-Object { $_.Tag })
    if (-not $sel.Count) { $status.Text = 'Zaznacz co najmniej jedną pozycję.'; return }
    $cfg = [pscustomobject]@{ forever = $path.Text.Trim(); selected = @($sel | ForEach-Object { $_.Key }) }
    Save-Config $cfg.forever $cfg.selected
    try { $status.Lines = @(Copy-Sources $sel) + 'Wybór zapisany: następnym razem wystarczy logs.bat -Quick.' }
    catch { $status.Text = "Błąd: $($_.Exception.Message)" }
})
$btnOpen.Add_Click({
    if (-not (Test-Path $LogsDir)) { New-Item -ItemType Directory $LogsDir | Out-Null }
    Start-Process explorer.exe $LogsDir
})

if ($cfg.forever) { $path.Text = $cfg.forever } else { $path.Text = Find-Forever }
$form.Add_Shown({ Fill-List })
[void]$form.ShowDialog()
