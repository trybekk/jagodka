# Refreshes the WoW Forever API reference used by doc/index.html.
# Easiest: double-click doc\update.bat.  Or:  powershell -ExecutionPolicy Bypass -File doc\update.ps1
# Needs only git (no Python/Node).
#
# 1. Fetches (or updates) into doc\.cache (git-ignored):
#    - Blizzard's own API documentation for the Forever client, from the Gethe/wow-ui-source mirror,
#      branch "forever" (only Interface/AddOns/Blizzard_APIDocumentationGenerated)
#    - ForeverAPI by zmarotrix (MIT docs): globals the game has that Blizzard's docs do not list,
#      and the blocked / secret lists captured in game
#    - community notes (whole documents of addon authors, all MIT), list below
# 2. Writes doc\data\api.js + api.tsv (the API index, with full signatures) and doc\data\community.js.
# Hand-written notes are in doc\data\notes.js and doc\data\sources.js; this script never touches them.

$ErrorActionPreference = 'Stop'
$docDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$cacheDir = Join-Path $docDir '.cache'
$dataDir  = Join-Path $docDir 'data'
New-Item -ItemType Directory -Force $cacheDir, $dataDir | Out-Null
$utf8 = New-Object Text.UTF8Encoding($false)

function Sync-Repo($url, $branch, $dir, $sparse) {
    if (Test-Path (Join-Path $dir '.git')) {
        Write-Host "Updating $url ($branch)"
        git -C $dir fetch -q --depth 1 origin $branch
        git -C $dir reset -q --hard FETCH_HEAD
    } else {
        Write-Host "Cloning $url ($branch)"
        git clone -q --depth 1 --filter=blob:none --sparse -b $branch $url $dir
        if ($LASTEXITCODE -ne 0) { throw "git clone failed: $url" }
    }
    git -C $dir sparse-checkout set --no-cone @sparse
    if ($LASTEXITCODE -ne 0) { throw "sparse-checkout failed: $url" }
}

$wui  = Join-Path $cacheDir 'wow-ui-source'
$fapi = Join-Path $cacheDir 'ForeverAPI'
Sync-Repo 'https://github.com/Gethe/wow-ui-source' 'forever' $wui @('/Interface/AddOns/Blizzard_APIDocumentationGenerated/')
Sync-Repo 'https://github.com/zmarotrix/ForeverAPI' 'master' $fapi @('/docs/globals-undocumented.md', '/docs/restrictions.md', '/docs/LICENSE')

$wuiCommit  = (git -C $wui log -1 --format='%cs %s')
$fapiCommit = (git -C $fapi log -1 --format='%cs %s')

# ---------------------------------------------------------------------------------------------
# Blizzard's generated docs. Layout (tabs): 1 = system (Namespace), 3 = an entry (function, event,
# enum, structure) and its flags, 3 = "Arguments =" / "Returns =" / "Payload =" / "Fields =",
# 4 = one field: { Name = "x", Type = "y", InnerType = "z", Nilable = false, Documentation = {...} }
# Each entry keeps its fields as [name, type, nilable(0/1), extra] in a (arguments), r (returns),
# p (event payload), fl (structure fields / enum values).
# ---------------------------------------------------------------------------------------------
$items = New-Object System.Collections.Generic.List[object]
$flagPattern = 'Secret|Restrict|Protected|Hardware|Lockdown|Combat|MayReturnNothing'
$sectionKey = @{ Arguments = 'a'; Returns = 'r'; Payload = 'p'; Fields = 'fl'; Values = 'fl' }

function Get-Attr($line, $attr) {
    if ($line -match ('\b' + $attr + ' = "([^"]*)"')) { return $Matches[1] }
    if ($line -match ('\b' + $attr + ' = ([^,}\s]+)')) { return $Matches[1] }
    return $null
}

$docFolder = Join-Path $wui 'Interface\AddOns\Blizzard_APIDocumentationGenerated'
foreach ($file in Get-ChildItem $docFolder -Filter '*.lua') {
    $ns = ''; $cur = $null; $section = $null; $sysName = ''; $widget = $false
    foreach ($line in [IO.File]::ReadAllLines($file.FullName)) {
        if ($line -match '^\tNamespace = "([^"]+)"') { $ns = $Matches[1]; continue }
        if ($line -match '^\tName = "([^"]+)"') { $sysName = $Matches[1] -replace 'API$', ''; continue }
        # widget methods (Frame, FontString, ...) are written as Widget:Method
        if ($line -match '^\tType = "ScriptObject"') { $widget = $true; continue }
        if ($line -match '^\t\t\tName = "([^"]+)"') {
            if ($cur) { $items.Add($cur) }
            $cur = [ordered]@{ n = $Matches[1]; k = ''; f = ''; d = ''; s = $file.Name }
            $section = $null
            continue
        }
        if (-not $cur) { continue }
        if ($line -match '^\t\t\t(\w+) =\s*$') { $section = $sectionKey[$Matches[1]]; continue }
        if ($section -and $line -match '^\t\t\t\t\{ Name = "([^"]+)"') {
            $fname = $Matches[1]
            $type = Get-Attr $line 'Type'
            $inner = Get-Attr $line 'InnerType'
            if ($inner) { $type = "$type<$inner>" }
            $nil = if ((Get-Attr $line 'Nilable') -eq 'true') { 1 } else { 0 }
            $extra = @()
            $ev = Get-Attr $line 'EnumValue'; if ($ev) { $extra += "= $ev" }
            $def = Get-Attr $line 'Default'; if ($def) { $extra += "default $def" }
            if ($line -match 'NeverSecret = true') { $extra += 'never secret' }
            if ($line -match 'ConditionalSecret = true') { $extra += 'conditionally secret' }
            if ($line -match 'Documentation = \{ "(.*?)" \}') { $extra += ($Matches[1] -replace '", "', ' ') }
            if (-not $cur.Contains($section)) { $cur[$section] = New-Object System.Collections.ArrayList }
            [void]$cur[$section].Add(@($fname, $type, $nil, ($extra -join '; ')))
            continue
        }
        if ($line -match '^\t\t\tType = "([^"]+)"') {
            switch ($Matches[1]) {
                'Function'    { $cur.k = 'f'; if ($widget) { $cur.n = "$($sysName):$($cur.n)" } elseif ($ns) { $cur.n = "$ns.$($cur.n)" } }
                'Event'       { $cur.k = 'e' }
                'Enumeration' { $cur.k = 't'; $cur.n = "Enum.$($cur.n)" }
                'Structure'   { $cur.k = 's' }
                'Constants'   { $cur.k = 'c'; $cur.n = "Constants.$($cur.n)" }
                'CallbackType'{ $cur.k = 's' }
                default       { $cur.k = 'x' }
            }
            continue
        }
        if ($line -match '^\t\t\tLiteralName = "([^"]+)"') { $cur.n = $Matches[1]; continue }
        if ($line -match '^\t\t\tDocumentation = \{ "(.*)" \},?$') { $cur.d = ($Matches[1] -replace '", "', ' '); continue }
        if ($line -match '^\t\t\t(\w+) = (true|"[^"]*")') {
            $key = $Matches[1]; $val = $Matches[2].Trim('"')
            if ($key -notmatch $flagPattern) { continue }
            $flag = if ($val -eq 'true') { $key } else { "$key=$val" }
            $cur.f = (($cur.f, $flag) | Where-Object { $_ }) -join ' '
        }
    }
    if ($cur) { $items.Add($cur) }
}
$items = [System.Collections.Generic.List[object]]@($items | Where-Object { $_.k -in 'f', 'e', 't', 's', 'c' })
$blizzCount = $items.Count

# ForeverAPI: globals that exist in the game but are in no Blizzard doc file (no full signature known)
$undoc = Join-Path $fapi 'docs\globals-undocumented.md'
foreach ($line in [IO.File]::ReadAllLines($undoc)) {
    if ($line -match '^- `([^`]+)`: (.*)$') {
        $d = $Matches[2]
        if ($d.Length -gt 300) { $d = $d.Substring(0, 300) + '...' }
        $items.Add([ordered]@{ n = $Matches[1]; k = 'g'; f = ''; d = $d; s = 'ForeverAPI' })
    }
}

# Signatures of those older globals (GetGuildRosterInfo, CreateFrame, ...): Blizzard does not document
# them, Warcraft Wiki does. Ketho's vscode-wow-api (MIT) keeps the wiki's signatures as LuaLS annotations
# in Annotations/Core/Data/Wiki.lua. Only names the game really has (the ForeverAPI list) get them.
$kwa = Join-Path $cacheDir 'vscode-wow-api'
Sync-Repo 'https://github.com/Ketho/vscode-wow-api' 'master' $kwa @('/README.md')
$kwaCommit = (git -C $kwa log -1 --format='%cs %s')
$wikiLua = (git -C $kwa show HEAD:Annotations/Core/Data/Wiki.lua) -split "`r?`n"
$globals = @{}
foreach ($it in $items) { if ($it.k -eq 'g') { $globals[$it.n] = $it } }
$params = @(); $rets = @(); $notes = @(); $wikiFilled = 0
foreach ($line in $wikiLua) {
    if ($line -match '^---@param (\S+?)(\?)? (.+)$') { $params += ,@($Matches[1], $Matches[3].Trim(), [int]($Matches[2] -eq '?'), ''); continue }
    if ($line -match '^---@return (\S+)(?: (\S+))?') { $rets += ,@($(if ($Matches[2]) { $Matches[2] } else { '' }), $Matches[1], 0, ''); continue }
    if ($line -match '^---#') { continue }
    if ($line -match '^---\[Documentation\]') { continue }
    if ($line -match '^---(?!@)\s*(.+)$') { $notes += $Matches[1].Trim(); continue }
    if ($line -match '^function ([\w\.:]+)\(') {
        $it = $globals[$Matches[1]]
        if ($it) {
            if ($params.Count) { $it['a'] = $params }
            if ($rets.Count) { $it['r'] = $rets }
            $it.d = (@($notes) + "wiki signature (vscode-wow-api)" | Where-Object { $_ }) -join ' '
            $wikiFilled++
        }
    }
    if ($line -notmatch '^---') { $params = @(); $rets = @(); $notes = @() }
}
Write-Host "Wiki signatures added to $wikiFilled of $($globals.Count) undocumented globals"

# ForeverAPI restrictions.md: mark names the game blocked or kept secret in their tests
$restr = [IO.File]::ReadAllText((Join-Path $fapi 'docs\restrictions.md'))
$byName = @{}
foreach ($it in $items) { $short = ($it.n -split '\.')[-1]; if (-not $byName[$short]) { $byName[$short] = @() }; $byName[$short] += $it }
foreach ($m in [regex]::Matches($restr, '`([A-Za-z_][\w\.]*)(\(\))?`')) {
    $short = ($m.Groups[1].Value -split '\.')[-1]
    if ($byName[$short]) { foreach ($it in $byName[$short]) { if ($it.f -notmatch 'ForeverAPI-restrictions') { $it.f = (($it.f, 'ForeverAPI-restrictions') | Where-Object { $_ }) -join ' ' } } }
}

# ---------------------------------------------------------------------------------------------
# Where OUR addon uses each function / event (jagodka\*.lua): u = [[file, line, code], ...] (at most
# USES_KEPT per entry), uc = how many uses in total, and the flag "Jagodka". Exact names only:
# C_X.Func, a global (also as _G.Func or a local alias of it), an event name ("CHAT_MSG_ADDON").
# Widget methods (frame:SetPoint) are left out: the same method name is on every kind of frame.
# ---------------------------------------------------------------------------------------------
$USES_KEPT = 12
$addonDir = Join-Path (Split-Path -Parent $docDir) 'jagodka'
$byFull = @{}
foreach ($it in $items) { if ($it.k -in 'f', 'e', 'g' -and $it.n -notmatch ':') { $byFull[$it.n] = $it } }
$usedCount = 0
foreach ($file in Get-ChildItem $addonDir -Filter '*.lua') {
    $lines = [IO.File]::ReadAllLines($file.FullName)
    for ($i = 0; $i -lt $lines.Length; $i++) {
        $line = $lines[$i]
        $code = ($line -replace '^\s+', '')
        if ($code.StartsWith('--')) { continue }
        $seen = @{}
        foreach ($m in [regex]::Matches($line, '[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)?')) {
            $name = $m.Value -replace '^_G\.', ''
            if ($seen[$name]) { continue }
            $it = $byFull[$name]
            if (-not $it) { continue }
            $seen[$name] = $true
            if (-not $it.Contains('uc')) { $it['uc'] = 0; $it['u'] = New-Object System.Collections.ArrayList; $usedCount++ }
            $it['uc']++
            if ($it['u'].Count -lt $USES_KEPT) {
                $snippet = if ($code.Length -gt 160) { $code.Substring(0, 160) + '...' } else { $code }
                [void]$it['u'].Add(@($file.Name, ($i + 1), $snippet))
            }
        }
    }
}
foreach ($it in $byFull.Values) { if ($it.Contains('uc')) { $it.f = (($it.f, 'Jagodka') | Where-Object { $_ }) -join ' ' } }
Write-Host "Used in our addon: $usedCount functions / events"

$meta = [ordered]@{
    generated  = (Get-Date -Format 'yyyy-MM-dd HH:mm')
    blizzard   = "Gethe/wow-ui-source forever: $wuiCommit"
    foreverApi = "zmarotrix/ForeverAPI master: $fapiCommit"
    wiki       = "Ketho/vscode-wow-api master: $kwaCommit"
    counts     = [ordered]@{ blizzard = $blizzCount; undocumented = $items.Count - $blizzCount }
}
$json = ConvertTo-Json -InputObject @($items) -Compress -Depth 6
$metaJson = ConvertTo-Json -InputObject $meta -Compress -Depth 3
[IO.File]::WriteAllText((Join-Path $dataDir 'api.js'), "// Generated by doc/update.ps1 - do not edit by hand`nwindow.FOREVER_API_META = $metaJson;`nwindow.FOREVER_API = $json;`n", $utf8)

# The same as plain text for grep: one line per entry, then indented lines with its signature
$kinds = @{ f = 'function'; e = 'event'; t = 'enum'; s = 'struct'; c = 'constants'; g = 'global' }
$labels = [ordered]@{ a = 'arg'; r = 'ret'; p = 'payload'; fl = 'field' }
$sb = New-Object Text.StringBuilder
foreach ($it in $items) {
    [void]$sb.Append("$($it.n)`t$($kinds[$it.k])`t$($it.f)`t$($it.s)`t$($it.d)`n")
    foreach ($key in $labels.Keys) {
        if (-not $it.Contains($key)) { continue }
        foreach ($fld in $it[$key]) {
            $opt = if ($fld[2] -eq 1) { '?' } else { '' }
            [void]$sb.Append("    $($labels[$key]) $($fld[0])$opt : $($fld[1])$(if ($fld[3]) { "  -- $($fld[3])" })`n")
        }
    }
    if ($it.Contains('u')) {
        foreach ($use in $it['u']) { [void]$sb.Append("    used jagodka/$($use[0]):$($use[1])  $($use[2])`n") }
        if ($it['uc'] -gt $it['u'].Count) { [void]$sb.Append("    used ... $($it['uc']) uses in total`n") }
    }
}
[IO.File]::WriteAllText((Join-Path $dataDir 'api.tsv'), $sb.ToString(), $utf8)

# ---------------------------------------------------------------------------------------------
# Community notes: whole documents from addon authors (all MIT), shown in the page's "Społeczność"
# tab and kept as .md in doc\.cache\community for grep. To add one: a new entry here.
# ---------------------------------------------------------------------------------------------
$community = @(
    @{ id = 'fpp-api'; license = 'MIT, Cameron Weaver'
       title = 'ForeverPlusPlus: forever-api.md (notatki autorów; [in-game] / [dump] / [web] / Unverified)'
       raw = 'https://raw.githubusercontent.com/xIGBClutchIx/ForeverPlusPlus/main/docs/forever-api.md'
       page = 'https://github.com/xIGBClutchIx/ForeverPlusPlus/blob/main/docs/forever-api.md' },
    @{ id = 'fapi-restr'; license = 'MIT, Maro'
       title = 'ForeverAPI: restrictions.md (co gra zablokowała albo zwróciła jako sekret)'
       raw = 'https://raw.githubusercontent.com/zmarotrix/ForeverAPI/master/docs/restrictions.md'
       page = 'https://github.com/zmarotrix/ForeverAPI/blob/master/docs/restrictions.md' },
    @{ id = 'fapi-checks'; license = 'MIT, Maro'
       title = 'ForeverAPI: checks.md (pytania sprawdzone w grze)'
       raw = 'https://raw.githubusercontent.com/zmarotrix/ForeverAPI/master/docs/checks.md'
       page = 'https://github.com/zmarotrix/ForeverAPI/blob/master/docs/checks.md' },
    @{ id = 'kit-readme'; license = 'MIT, Thunderz'
       title = 'forever-addon-kit: README (ustalenia z bety, wrzesień 2026)'
       raw = 'https://raw.githubusercontent.com/Thunderz96/forever-addon-kit/main/README.md'
       page = 'https://github.com/Thunderz96/forever-addon-kit' },
    @{ id = 'kit-bugs'; license = 'MIT, Thunderz'
       title = 'forever-addon-kit: BUG_REPORTS.md (zgłoszone błędy klienta)'
       raw = 'https://raw.githubusercontent.com/Thunderz96/forever-addon-kit/main/docs/BUG_REPORTS.md'
       page = 'https://github.com/Thunderz96/forever-addon-kit/blob/main/docs/BUG_REPORTS.md' }
)
$commDir = Join-Path $cacheDir 'community'
New-Item -ItemType Directory -Force $commDir | Out-Null
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$docs = @()
foreach ($c in $community) {
    $file = Join-Path $commDir "$($c.id).md"
    try {
        $resp = Invoke-WebRequest -UseBasicParsing -Uri $c.raw
        $text = [Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray())
        [IO.File]::WriteAllText($file, $text, $utf8)
        Write-Host "Community: $($c.id) ($($text.Length) chars)"
    } catch {
        Write-Warning "Community: could not fetch $($c.raw), keeping the old copy"
        if (-not (Test-Path $file)) { continue }
        $text = [IO.File]::ReadAllText($file)
    }
    $docs += [ordered]@{ id = $c.id; title = $c.title; license = $c.license; page = $c.page
                         fetched = (Get-Item $file).LastWriteTime.ToString('yyyy-MM-dd'); text = $text }
}
$commJson = ConvertTo-Json -InputObject @($docs) -Compress -Depth 3
[IO.File]::WriteAllText((Join-Path $dataDir 'community.js'), "// Generated by doc/update.ps1 - do not edit by hand`nwindow.FOREVER_COMMUNITY = $commJson;`n", $utf8)

Write-Host ""
Write-Host "API: $blizzCount entries from Blizzard docs (with signatures), $($items.Count - $blizzCount) undocumented globals"
Write-Host "Blizzard: $wuiCommit"
Write-Host "ForeverAPI: $fapiCommit"
Write-Host "Community: $($docs.Count) documents"
