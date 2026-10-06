<#
  build-lorebook-pages.ps1
  ---------------------------------------------------------------------------
  Splits Mushoku_Tensei/mushoku_tensei_lorebook.md into fetch-sized HTML pages:

    Mushoku_Tensei/entries_index.html       -> .../Mushoku_Tensei/entries_index
    Mushoku_Tensei/entries_sec_NN.html      -> .../Mushoku_Tensei/entries_sec_01
    Mushoku_Tensei/entries_NNN.html         -> .../Mushoku_Tensei/entries_001

  Batching rule (agreed with the owner):
    - at most 5 entries per page
    - if a 5-entry batch would exceed $charCap source chars, it is cut at 3
    - entry contents are copied VERBATIM - never edited, compressed or reworded

  URL rules (from session findings B3/B4/B5):
    - every advertised URL is extensionless and has NO trailing slash
    - flat files only, no directory URLs
    - the root is linked as https://danxdunzi.github.io/session-lorebook

  Usage:
    powershell -ExecutionPolicy Bypass -File build-lorebook-pages.ps1          # dry run: report only
    powershell -ExecutionPolicy Bypass -File build-lorebook-pages.ps1 -Emit    # write pages + manifest
#>
param([switch]$Emit)

$ErrorActionPreference = 'Stop'
$root   = 'C:\RegSYS\session-lorebook'
$utf8   = [System.Text.UTF8Encoding]::new($false)
$base   = 'https://danxdunzi.github.io/session-lorebook'
$mdRel  = 'Mushoku_Tensei/mushoku_tensei_lorebook.md'
$mdPath = Join-Path $root ($mdRel -replace '/', '\')
$outDir = Join-Path $root 'Mushoku_Tensei'
$rootUrl    = $base                                                   # B3: never a trailing slash
$dumpUrl    = "$base/Mushoku_Tensei/mushoku_tensei_lorebook"
$indexUrl   = "$base/Mushoku_Tensei/entries_index"
$secPrefix  = "$base/Mushoku_Tensei/"
$mdUrl      = "$base/$mdRel"                                          # head-only alternate link

$maxA     = 5        # preferred entries per page
$maxB     = 3        # fallback when 5 would be too big
$charCap  = 17000    # source chars per page (~1/3 of the observed ~50k browse-tool limit)
$htmlWarn = 20480    # 20 KB rendered - warn
$htmlFail = 30720    # 30 KB rendered - fail

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
function Enc([string]$s) {
  if ($null -eq $s) { return '' }
  [System.Net.WebUtility]::HtmlEncode($s)
}
function Norm([string]$s) {
  if ($null -eq $s) { return '' }
  $s = $s -replace '\[([^\]]*)\]\([^)]*\)', '$1'   # markdown link -> text
  $s = $s -replace '^[-*]\s+', ''                  # list marker
  $s = $s -replace '[*_`~]', ''                    # emphasis / code markers
  $s = $s -replace '\s+', ' '
  return $s.Trim()
}
function Get-PlainText([string]$html) {
  $t = [regex]::Replace($html, '<[^>]+>', ' ')
  $t = [System.Net.WebUtility]::HtmlDecode($t)
  return (Norm $t)
}
function Invoke-Marked([string]$markdown) {
  $in  = [System.IO.Path]::GetTempFileName()
  $out = [System.IO.Path]::GetTempFileName()
  try {
    [System.IO.File]::WriteAllText($in, $markdown, $utf8)
    & npx.cmd -y marked -i $in -o $out | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "marked failed with exit code $LASTEXITCODE" }
    return [System.IO.File]::ReadAllText($out, [System.Text.UTF8Encoding]::new($true))
  } finally {
    Remove-Item $in, $out -Force -ErrorAction SilentlyContinue
  }
}
function Write-IfChanged([string]$path, [string]$content) {
  if (Test-Path $path) {
    $old = [System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false))
    if ($old -ceq $content) { return 'unchanged' }
    [System.IO.File]::WriteAllText($path, $content, $utf8)
    return 'updated'
  }
  [System.IO.File]::WriteAllText($path, $content, $utf8)
  return 'created'
}
function Add-Check([System.Collections.ArrayList]$list, [string]$name, [bool]$ok, [string]$detail) {
  [void]$list.Add([pscustomobject]@{ name = $name; ok = $ok; detail = $detail })
}

# ---------------------------------------------------------------------------
# 1. parse source
# ---------------------------------------------------------------------------
if (-not (Test-Path $mdPath)) { throw "source not found: $mdPath" }
$raw   = [System.IO.File]::ReadAllText($mdPath)
$nl    = if ($raw.Contains("`r`n")) { "`r`n" } else { "`n" }
$lines = $raw.Split([string[]]@($nl), [System.StringSplitOptions]::None)

$h1 = @()
for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^# ') { $h1 += $i } }
if ($h1.Count -eq 0 -or $h1[0] -ne 0) { throw "unexpected document shape: first h1 is not at line 1" }

$sections    = New-Object System.Collections.ArrayList
$entriesAll  = New-Object System.Collections.ArrayList
$introSlice  = $null
$curSec      = $null
$secNum      = 0

for ($k = 0; $k -lt $h1.Count; $k++) {
  $s = $h1[$k]
  $nextH1 = if ($k -lt $h1.Count - 1) { $h1[$k + 1] } else { $lines.Count }
  $isEntry = ($s + 1 -lt $lines.Count) -and ($lines[$s + 1] -match '^<!-- Keys: (.*) -->')

  if ($k -eq 0) {
    $introSlice = $lines[0..($h1[1] - 1)] -join $nl
    continue
  }

  if (-not $isEntry) {
    $secNum++
    $curSec = [pscustomobject]@{
      num    = $secNum
      title  = $lines[$s].Substring(2)
      label  = ''
      line   = $s + 1
      slug   = 'entries_sec_{0:d2}' -f $secNum
      count  = 0
      placed = 0
      chunks = New-Object System.Collections.ArrayList
      entries = New-Object System.Collections.ArrayList
    }
    [void]$sections.Add($curSec)
    continue
  }

  $e = $nextH1 - 1
  while ($e -gt $s -and ($lines[$e] -eq '' -or $lines[$e] -eq '---')) { $e-- }   # drop trailing separator only
  if ($null -eq $curSec) { throw "entry found before any section header at line $($s + 1)" }
  $body = ($lines[$s..$e] -join $nl)
  $m    = [regex]::Match($lines[$s + 1], '^<!-- Keys: (.*) -->')

  $curSec.count++
  $en = [pscustomobject]@{
    title    = $lines[$s].Substring(2)
    keys     = $m.Groups[1].Value
    body     = $body
    srcChars = $body.Length
    seq      = $curSec.count
    section  = $curSec
    placed   = $false
    pageUrl  = ''
  }
  [void]$entriesAll.Add($en)
  [void]$curSec.entries.Add($en)
}

# disambiguate duplicate section titles: Characters, Characters (2), Items, Items (2) ...
$seenTitle = @{}
foreach ($sec in $sections) {
  if ($seenTitle.ContainsKey($sec.title)) {
    $seenTitle[$sec.title]++
    $sec.label = '{0} ({1})' -f $sec.title, $seenTitle[$sec.title]
  } else {
    $seenTitle[$sec.title] = 1
    $sec.label = $sec.title
  }
}

# ---------------------------------------------------------------------------
# 2. chunk: <=5 entries, cut at 3 if a 5-pack would exceed $charCap
# ---------------------------------------------------------------------------
$chunks    = New-Object System.Collections.ArrayList
$chunkUrl  = @{}
$chunkId   = 0

foreach ($sec in $sections) {
  $buf   = New-Object System.Collections.ArrayList
  $acc   = 0

  $flush = {
    if ($buf.Count -eq 0) { return }
    $script:chunkId++
    $c = [pscustomobject]@{
      id       = $chunkId
      slug     = 'entries_{0:d3}' -f $chunkId
      section  = $sec
      firstSeq = $buf[0].seq
      lastSeq  = $buf[$buf.Count - 1].seq
      srcChars = $acc
      entries  = @($buf.ToArray())
      bodyMd   = (@($buf.ToArray() | ForEach-Object { $_.body }) -join ($nl + $nl))
      htmlBody = ''
    }
    foreach ($en in $c.entries) { $en.placed = $true }
    [void]$chunks.Add($c)
    [void]$sec.chunks.Add($c)
    $buf.Clear(); $script:acc = 0
  }

  foreach ($en in $sec.entries) {
    if ($buf.Count -eq 0) {                      # always accept the first entry
      [void]$buf.Add($en); $acc = $en.srcChars; continue
    }
    if ($buf.Count -ge $maxA) {                  # full: flush then start new
      & $flush
      [void]$buf.Add($en); $acc = $en.srcChars; continue
    }
    if (($acc + $en.srcChars) -le $charCap) {    # fits: keep packing
      [void]$buf.Add($en); $acc += $en.srcChars; continue
    }
    if ($buf.Count -ge $maxB) {                  # too big at 3+: cut here
      & $flush
      [void]$buf.Add($en); $acc = $en.srcChars; continue
    }
    [void]$buf.Add($en); $acc += $en.srcChars    # 3-entry path
  }
  & $flush
}

foreach ($c in $chunks) {
  $chunkUrl[$c.slug] = "$base/Mushoku_Tensei/$($c.slug)"
  foreach ($en in $c.entries) { $en.pageUrl = $chunkUrl[$c.slug] }
}
$prevChunk = @{}; $nextChunk = @{}
for ($i = 0; $i -lt $chunks.Count; $i++) {
  if ($i -gt 0)             { $prevChunk[$chunks[$i].slug] = $chunks[$i - 1] }
  if ($i -lt $chunks.Count - 1) { $nextChunk[$chunks[$i].slug] = $chunks[$i + 1] }
}

# ---------------------------------------------------------------------------
# 3. render (one marked call for everything, split by sentinels)
# ---------------------------------------------------------------------------
$mdBatch = New-Object System.Text.StringBuilder
[void]$mdBatch.AppendLine('<!--SPLIT:__intro__-->'); [void]$mdBatch.AppendLine()
[void]$mdBatch.AppendLine($introSlice);             [void]$mdBatch.AppendLine()
foreach ($c in $chunks) {
  [void]$mdBatch.AppendLine("<!--SPLIT:$($c.slug)-->"); [void]$mdBatch.AppendLine()
  [void]$mdBatch.AppendLine($c.bodyMd);                [void]$mdBatch.AppendLine()
}
$rendered = Invoke-Marked $mdBatch.ToString()
$parts    = $rendered -split '<!--SPLIT:[^>]*-->'
$expectedParts = $chunks.Count + 2                   # '' + intro + each chunk
if ($parts.Count -ne $expectedParts) {
  throw "sentinel split mismatch: got $($parts.Count) parts, expected $expectedParts"
}
$introHtml = $parts[1].Trim()

# demote entry h1 -> h2, turn hidden <!-- Keys --> comments into visible text
$keyPattern = '<!-- Keys: (.*?) -->'
for ($i = 0; $i -lt $chunks.Count; $i++) {
  $b = $parts[$i + 2].Trim()
  $b = [regex]::Replace($b, '<h1(.*?)</h1>', { param($m) '<h2' + $m.Groups[1].Value + '</h2>' }, 'Singleline')
  $b = [regex]::Replace($b, $keyPattern, { param($m) '<p><strong>Keys:</strong> ' + (Enc $m.Groups[1].Value) + '</p>' })
  $chunks[$i].htmlBody = $b
}

function New-Page([string]$title, [string]$desc, [string]$canonical, [string]$bodyHtml) {
@"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$title</title>
<meta name="description" content="$desc">
<meta name="robots" content="index, follow, max-snippet:-1">
<link rel="canonical" href="$canonical">
<link rel="alternate" type="text/markdown" href="$mdUrl">
</head>
<body>
$bodyHtml
</body>
</html>
"@
}
function Get-Nav([object[]]$links) { return ('<p>' + (($links | Where-Object { $_ }) -join ' &middot; ') + '</p>') }

$pages = @{}   # slug or 'entries_index' -> html content

# --- chunk pages ---
foreach ($c in $chunks) {
  $sec  = $c.section
  $url  = $chunkUrl[$c.slug]
  $prev = $prevChunk[$c.slug]
  $next = $nextChunk[$c.slug]

  $navLinks = @(
    '<a href="' + $rootUrl + '">Session Lorebook Index</a>'
    '<a href="' + $indexUrl + '">Lorebook index</a>'
    '<a href="' + $secPrefix + $sec.slug + '">Section: ' + (Enc $sec.label) + '</a>'
    $(if ($prev) { '<a href="' + $chunkUrl[$prev.slug] + '">&larr; ' + $prev.slug + '</a>' } else { '<span>&larr; previous</span>' })
    $(if ($next) { '<a href="' + $chunkUrl[$next.slug] + '">' + $next.slug + ' &rarr;</a>' } else { '<span>next &rarr;</span>' })
  )
  $foot = ''
  if ($next) {
    $foot = '<p>Continue: <a href="' + $chunkUrl[$next.slug] + '">' + $next.slug + ' - ' + (Enc $next.entries[0].title) + '</a></p>'
  } else {
    $foot = '<p>End of section. <a href="' + $indexUrl + '">Back to the lorebook index</a>.</p>'
  }
  $title    = 'Mushoku Tensei Lorebook - {0} (entries {1}-{2} of {3})' -f $sec.label, $c.firstSeq, $c.lastSeq, $sec.count
  $names    = (@($c.entries | ForEach-Object { $_.title }) -join ', ')
  $desc     = Enc ($title + ': ' + $names)
  $bodyHtml = ('<h1>' + (Enc $title) + '</h1>') + (Get-Nav $navLinks) + $c.htmlBody + $foot
  $pages[$c.slug] = New-Page (Enc $title) $desc $url $bodyHtml
}

# --- section index pages ---
foreach ($sec in $sections) {
  $secUrl = $secPrefix + $sec.slug
  $secPrev = if ($sec.num -gt 1) { $sections[$sec.num - 2] } else { $null }
  $secNext = if ($sec.num -lt $sections.Count) { $sections[$sec.num] } else { $null }

  $navLinks = @(
    '<a href="' + $rootUrl + '">Session Lorebook Index</a>'
    '<a href="' + $indexUrl + '">Lorebook index</a>'
    $(if ($secPrev) { '<a href="' + $secPrefix + $secPrev.slug + '">&larr; ' + (Enc $secPrev.label) + '</a>' } else { '<span>&larr; previous</span>' })
    $(if ($secNext) { '<a href="' + $secPrefix + $secNext.slug + '">' + (Enc $secNext.label) + ' &rarr;</a>' } else { '<span>next &rarr;</span>' })
  )

  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine('<h1>' + (Enc $sec.label) + ' - Mushoku Tensei Lorebook</h1>')
  [void]$sb.AppendLine((Get-Nav $navLinks))
  [void]$sb.AppendLine('<p>' + $sec.entries.Count + ' entries in ' + $sec.chunks.Count + ' pages. Every entry name and alias key links to the page that holds it; each page carries at most 5 entries so fetches are not truncated.</p>')
  [void]$sb.AppendLine('<ul>')
  foreach ($en in $sec.entries) {
    [void]$sb.AppendLine('<li><a href="' + $en.pageUrl + '">' + (Enc $en.title) + '</a> &mdash; Keys: ' + (Enc $en.keys) + '</li>')
  }
  [void]$sb.AppendLine('</ul>')
  [void]$sb.AppendLine('<p><a href="' + $rootUrl + '">Session Lorebook Index</a></p>')

  $title = '{0} - Mushoku Tensei Lorebook ({1} entries)' -f $sec.label, $sec.entries.Count
  $desc  = Enc ($title + '. Entries: ' + (@($sec.entries | Select-Object -First 8 | ForEach-Object { $_.title }) -join ', '))
  $pages[$sec.slug] = New-Page (Enc $title) $desc $secUrl $sb.ToString()
}

# --- main index page ---
$idxSb = New-Object System.Text.StringBuilder
[void]$idxSb.AppendLine($introHtml)
[void]$idxSb.AppendLine('<h2>Browse by section</h2>')
[void]$idxSb.AppendLine('<p>Each section index links every entry name and alias key to the page that contains it. Pages hold at most 5 entries, so a single fetch always returns whole entries.</p>')
[void]$idxSb.AppendLine('<ul>')
foreach ($sec in $sections) {
  $range = $sec.chunks[0].slug + ' .. ' + $sec.chunks[$sec.chunks.Count - 1].slug
  [void]$idxSb.AppendLine('<li><a href="' + $secPrefix + $sec.slug + '">' + (Enc $sec.label) + '</a> &mdash; ' + $sec.entries.Count + ' entries in ' + $sec.chunks.Count + ' pages (' + $range + ')</li>')
}
[void]$idxSb.AppendLine('</ul>')
[void]$idxSb.AppendLine('<h2>Full document</h2>')
[void]$idxSb.AppendLine('<ul><li><a href="' + $dumpUrl + '">Complete lorebook as one page (large - may be truncated by fetch tools)</a></li></ul>')
[void]$idxSb.AppendLine('<p><a href="' + $rootUrl + '">Session Lorebook Index</a></p>')

$idxTitle = 'Mushoku Tensei Lorebook Index ({0} entries)' -f $entriesAll.Count
$pages['entries_index'] = New-Page (Enc $idxTitle) (Enc $idxTitle) $indexUrl $idxSb.ToString()

# ---------------------------------------------------------------------------
# 4. self-checks
# ---------------------------------------------------------------------------
$checks  = New-Object System.Collections.ArrayList
$warns   = New-Object System.Collections.ArrayList
$failMsg = @()

$placedCount = 0
foreach ($c in $chunks) { $placedCount += $c.entries.Count }
$notPlaced = @($entriesAll | Where-Object { -not $_.placed }).Count

Add-Check $checks 'source parsed' ($sections.Count -eq 10 -and $entriesAll.Count -eq 200) ("sections={0} entries={1} (expected 10 / 200)" -f $sections.Count, $entriesAll.Count)
Add-Check $checks 'every entry has alias keys' ((@($entriesAll | Where-Object { -not $_.keys }).Count -eq 0)) ("{0}/{1} entries carry Keys" -f (@($entriesAll | Where-Object { $_.keys }).Count), $entriesAll.Count)
Add-Check $checks 'every entry placed exactly once' (($notPlaced -eq 0) -and ($placedCount -eq $entriesAll.Count)) ("placed {0}/{1}, unplaced={2}" -f $placedCount, $entriesAll.Count, $notPlaced)
Add-Check $checks 'no section empty' ((@($sections | Where-Object { $_.entries.Count -eq 0 }).Count -eq 0)) ''

$overCap = @($chunks | Where-Object { $_.srcChars -gt $charCap })
$badSize = @($overCap | Where-Object { $_.entries.Count -gt $maxB })
Add-Check $checks 'chunk entry count <= 5' ((@($chunks | Where-Object { $_.entries.Count -gt $maxA }).Count -eq 0)) ("max entries on one page = {0}" -f (@($chunks | ForEach-Object { $_.entries.Count } | Measure-Object -Maximum).Maximum))
Add-Check $checks "chunk source chars <= $charCap (over-cap allowed only as a 3-pack)" ($badSize.Count -eq 0) ("{0} pages over cap, all <= {1} entries" -f $overCap.Count, $maxB)

$allHtml = ''
$perPage = @()
foreach ($p in $pages.GetEnumerator()) {
  $bytes  = $utf8.GetByteCount($p.Value)
  $perPage += [pscustomobject]@{ slug = $p.Key; bytes = $bytes }
  $allHtml += $p.Value + "`n"
}
$big = @($perPage | Where-Object { $_.bytes -gt $htmlFail })
Add-Check $checks "rendered page <= $htmlFail bytes" ($big.Count -eq 0) ("largest = {0} ({1} bytes)" -f (($perPage | Sort-Object bytes -Descending)[0].slug), (($perPage | Sort-Object bytes -Descending)[0].bytes))
foreach ($p in ($perPage | Where-Object { $_.bytes -gt $htmlWarn -and $_.bytes -le $htmlFail })) {
  [void]$warns.Add(('{0} is {1} bytes (> 20 KB)' -f $p.slug, $p.bytes))
}

Add-Check $checks 'no liquid markers in output' (($allHtml -notmatch '\{\{') -and ($allHtml -notmatch '\{%')) ''

# B4/B5: body links must be extensionless and must not end in '/'
$badHref = @(); $lostHref = @()
$allowed = @($rootUrl, $dumpUrl, $indexUrl)
foreach ($sec in $sections) { $allowed += $secPrefix + $sec.slug }
foreach ($c in $chunks)     { $allowed += $secPrefix + $c.slug }
foreach ($p in $pages.GetEnumerator()) {
  $m = [regex]::Match($p.Value, '<body>(.*)</body>', 'Singleline')
  foreach ($h in [regex]::Matches($m.Groups[1].Value, 'href="([^"]*)"')) {
    $u = $h.Groups[1].Value
    if ($u -match '\.(html|md|xml|txt)$' -or $u.EndsWith('/')) { $badHref += ($p.Key + ' -> ' + $u) }
    if ($allowed -notcontains $u) { $lostHref += ($p.Key + ' -> ' + $u) }
  }
}
Add-Check $checks 'body links extensionless, no trailing slash (B4/B5)' ($badHref.Count -eq 0) ($badHref -join '; ')
Add-Check $checks 'every body link points at a real page' ($lostHref.Count -eq 0) (($lostHref | Select-Object -First 5) -join '; ')

# verbatim + fidelity: each entry's first content line must survive rendering
$missing = @()
foreach ($c in $chunks) {
  $plain = Get-PlainText $c.htmlBody
  foreach ($en in $c.entries) {
    $needle = $null
    foreach ($ln in ($en.body -split "`r?`n")) {
      if ($ln -match '^\s*$' -or $ln -match '^#' -or $ln -match '^<!--' -or $ln -eq '---') { continue }
      $needle = $ln; break
    }
    if ($needle) {
      $n = Norm $needle
      if ($n.Length -gt 60) { $n = $n.Substring(0, 60) }
      if ($n -and -not $plain.Contains($n)) { $missing += $en.title }
    }
    $t = Norm $en.title
    if (-not $plain.Contains($t)) { $missing += ($en.title + ' [title]') }
    $k = Norm $en.keys
    if ($k -and -not $plain.Contains($k)) { $missing += ($en.title + ' [keys]') }
  }
}
Add-Check $checks 'entry content rendered verbatim (title, keys, first line all present)' ($missing.Count -eq 0) (($missing | Select-Object -First 5) -join '; ')

$structureBad = @()
foreach ($c in $chunks) {
  $heads = @()
  foreach ($mm in [regex]::Matches($c.htmlBody, '<h2[^>]*>(.*?)</h2>', 'Singleline')) {
    $heads += (Norm ([System.Net.WebUtility]::HtmlDecode($mm.Groups[1].Value)))
  }
  foreach ($en in $c.entries) {                 # every entry title must own an h2 (alignment)
    if ($heads -notcontains (Norm $en.title)) { $structureBad += ($c.slug + ' missing h2 for "' + $en.title + '"') }
  }
  if ($heads.Count -lt $c.entries.Count) { $structureBad += ($c.slug + ' has only ' + $heads.Count + ' h2 for ' + $c.entries.Count + ' entries') }
  if ($c.htmlBody -match '<h1') { $structureBad += ($c.slug + ' still has an h1') }
}
Add-Check $checks 'every entry title owns an h2, no leftover h1 on chunk pages' ($structureBad.Count -eq 0) (($structureBad | Select-Object -First 3) -join '; ')

$secPlain = ''
foreach ($sec in $sections) { $secPlain += Get-PlainText $pages[$sec.slug] }
$aliasMiss = @($entriesAll | Where-Object { (Norm $_.keys) -and -not $secPlain.Contains((Norm $_.keys)) } | ForEach-Object { $_.title })
Add-Check $checks 'alias keys visible on section index pages' ($aliasMiss.Count -eq 0) (($aliasMiss | Select-Object -First 5) -join '; ')

$idxPlain = Get-PlainText $pages['entries_index']
$idxMiss = @($sections | Where-Object { -not $idxPlain.Contains((Norm $_.label)) } | ForEach-Object { $_.label })
Add-Check $checks 'all sections linked from main index' ($idxMiss.Count -eq 0) (($idxMiss -join ', '))

# ---------------------------------------------------------------------------
# 5. report
# ---------------------------------------------------------------------------
$mode = if ($Emit) { 'EMIT' } else { 'DRY RUN (nothing written)' }
Write-Output ('=' * 78)
Write-Output "Mushoku Tensei chunked lorebook - $mode"
Write-Output ('=' * 78)
Write-Output ("source      : {0}" -f $mdRel)
Write-Output ("lines/bytes : {0} / {1}" -f $lines.Count, $utf8.GetByteCount($raw))
Write-Output ("parse       : {0} h1 = {1} section headers + {2} entries ({3} with Keys)" -f $h1.Count, $sections.Count, $entriesAll.Count, @($entriesAll | Where-Object { $_.keys }).Count)
Write-Output ("batching    : <= {0} entries/page, cut at {1} when > {2} src chars" -f $maxA, $maxB, $charCap)
Write-Output ''
Write-Output 'SECTIONS'
foreach ($sec in $sections) {
  $r = '{0} .. {1}' -f $sec.chunks[0].slug, $sec.chunks[$sec.chunks.Count - 1].slug
  Write-Output ('  {0,-18} {1,3} entries  {2,2} pages  {3}' -f $sec.label, $sec.entries.Count, $sec.chunks.Count, $r)
}
Write-Output ''
Write-Output 'CHUNK PAGES'
foreach ($c in $chunks) {
  $names = @($c.entries | ForEach-Object { $_.title })
  if ($names.Count -gt 3) { $shown = ($names[0..2] -join ', ') + ', ...' } else { $shown = ($names -join ', ') }
  $kb = [math]::Round($pages[$c.slug].Length / 1024, 1)
  $flag = if ($c.srcChars -gt $charCap) { '  [OVER CAP]' } else { '' }
  Write-Output ('  {0}  {1,-17} {2} entries  {3,6} src chars  {4,5} KB  {5}{6}' -f $c.slug, $c.section.label, $c.entries.Count, $c.srcChars, $kb, $shown, $flag)
}
$sorted = $perPage | Sort-Object bytes -Descending
Write-Output ''
Write-Output ('TOTALS  pages = 1 main + {0} section + {1} chunk = {2}' -f $sections.Count, $chunks.Count, $pages.Count)
Write-Output ('        largest page = {0} ({1} bytes / {2} KB)' -f $sorted[0].slug, $sorted[0].bytes, [math]::Round($sorted[0].bytes / 1024, 1))
Write-Output ('        pages over {0} src chars = {1}' -f $charCap, $overCap.Count)
Write-Output ('        total output = {0} bytes' -f (($perPage | Measure-Object bytes -Sum).Sum))
Write-Output ''
Write-Output 'SELF-CHECKS'
foreach ($c in $checks) {
  Write-Output ('  [{0}] {1}{2}' -f $(if ($c.ok) { 'PASS' } else { 'FAIL' }), $c.name, $(if ($c.detail) { ' - ' + $c.detail } else { '' }))
  if (-not $c.ok) { $failMsg += ($c.name + ' :: ' + $c.detail) }
}
foreach ($w in $warns) { Write-Output ('  [WARN] ' + $w) }

# ---------------------------------------------------------------------------
# 6. emit
# ---------------------------------------------------------------------------
if ($Emit) {
  Write-Output ''
  Write-Output 'WRITE'
  if ($failMsg.Count -gt 0) { throw ("self-checks failed - nothing written:`n  " + ($failMsg -join "`n  ")) }

  $order = @('entries_index') + @($sections | ForEach-Object { $_.slug }) + @($chunks | ForEach-Object { $_.slug })
  $stats = @()
  foreach ($slug in $order) {
    $file = Join-Path $outDir ($slug + '.html')
    $stats += (Write-IfChanged $file $pages[$slug])
    Write-Output ('  {0,-9} {1}.html' -f $stats[-1], $slug)
  }

  $manifestDir = Join-Path $root '.build'
  if (-not (Test-Path $manifestDir)) { New-Item -ItemType Directory -Path $manifestDir | Out-Null }
  $manifest = ($order | ForEach-Object { "$base/Mushoku_Tensei/$_" }) -join "`n"
  [System.IO.File]::WriteAllText((Join-Path $manifestDir 'urls.txt'), $manifest + "`n", $utf8)
  Write-Output ('  manifest   .build/urls.txt ({0} urls)' -f $order.Count)
  Write-Output ('  result     {0} created, {1} updated, {2} unchanged' -f @($stats | Where-Object { $_ -eq 'created' }).Count, @($stats | Where-Object { $_ -eq 'updated' }).Count, @($stats | Where-Object { $_ -eq 'unchanged' }).Count)
} else {
  Write-Output ''
  Write-Output 'DRY RUN - re-run with -Emit to write the pages.'
}
