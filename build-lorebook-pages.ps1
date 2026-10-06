<#
  build-lorebook-pages.ps1
  ---------------------------------------------------------------------------
  Splits Mushoku_Tensei/mushoku_tensei_lorebook.md into fetch-sized HTML pages:

    Mushoku_Tensei/entries_index.html       the lorebook catalogue (every entry -> its batch)
    Mushoku_Tensei/entries_NNN.html         batch pages, at most 5 entries each

  Navigation flow (agreed with the owner):
    index.html (branch catalogue) -> entries_index (lorebook catalogue) -> entries_NNN (batch)
  There is deliberately NO middle layer of section pages any more: they repeated the
  catalogue's entry lists, so entries_sec_*.html are no longer generated and any stale
  copy is deleted at emit time.

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
$indexUrl   = "$base/Mushoku_Tensei/entries_index"
$mdUrl      = "$base/$mdRel"                                          # head-only alternate link

$maxA     = 5        # preferred entries per page
$maxB     = 3        # fallback when 5 would be too big
$charCap  = 17000    # source chars per page (~1/3 of the observed ~50k browse-tool limit)
$htmlWarn  = 20480    # 20 KB rendered - warn (chunk pages)
$htmlFail  = 30720    # 30 KB rendered - fail (chunk pages)
$indexWarn = 40960    # 40 KB rendered - warn (index/catalog pages)
$indexFail = 46080    # 45 KB rendered - fail (browse-tool fetch limit measured at ~56 KB)

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
function Get-PlainTextRaw([string]$html) {
  # same extraction but WITHOUT markdown character stripping - Norm() removes '_' and would
  # turn entries_001 into entries001, so URLs must be compared against raw extracted text
  $t = [regex]::Replace($html, '<[^>]+>', ' ')
  $t = [System.Net.WebUtility]::HtmlDecode($t)
  $t = $t -replace '\s+', ' '
  return $t.Trim()
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

function New-CatalogHtml {
  # The catalogue page: every section, every entry name, every alias key - and each entry
  # links straight to the batch page that holds it. No URL is printed as text; the batch is
  # reached by clicking the entry, which is the whole point of the 3-level flow.
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine(('<h2>Mushoku Tensei entry catalogue - all {0} entries in {1} batch pages</h2>' -f $entriesAll.Count, $chunks.Count))
  [void]$sb.AppendLine(('<p>Every entry of this lorebook, grouped by section. Each name links to the batch page that holds it, and a batch page carries at most {0} whole entries so a fetch is never truncated. Every URL has no file extension and no trailing slash.</p>' -f $maxA))
  foreach ($sec in $sections) {
    [void]$sb.AppendLine('<h3>' + (Enc $sec.label) + ' &mdash; ' + $sec.entries.Count + ' entries</h3>')
    [void]$sb.AppendLine('<ul>')
    foreach ($en in $sec.entries) {
      [void]$sb.AppendLine('<li><a href="' + $en.pageUrl + '">' + (Enc $en.title) + '</a> &mdash; Keys: ' + (Enc $en.keys) + '</li>')
    }
    [void]$sb.AppendLine('</ul>')
  }
  return $sb.ToString()
}

function New-CatalogMarkdown {
  # same catalog as New-CatalogHtml, as Markdown for the README mirror
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine(('#### Entry catalog - all {0} entries in {1} batch pages' -f $entriesAll.Count, $chunks.Count))
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('Every entry of this lorebook, grouped by section. Each name links to the batch page that holds it (at most 5 whole entries per page, so a fetch is never truncated).')
  foreach ($sec in $sections) {
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine(('**{0} - {1} entries**' -f $sec.label, $sec.entries.Count))
    foreach ($en in $sec.entries) {
      [void]$sb.AppendLine(('- [{0}]({1}) - Keys: {2}' -f $en.title, $en.pageUrl, $en.keys))
    }
  }
  return $sb.ToString()
}

$pages = @{}   # slug or 'entries_index' -> html content

# --- chunk pages ---
foreach ($c in $chunks) {
  $sec  = $c.section
  $url  = $chunkUrl[$c.slug]
  $prev = $prevChunk[$c.slug]
  $next = $nextChunk[$c.slug]

  $navLinks = @(
    '<a href="' + $rootUrl + '">All lorebooks</a>'
    '<a href="' + $indexUrl + '">Mushoku Tensei catalogue</a>'
    $(if ($prev) { '<a href="' + $chunkUrl[$prev.slug] + '">&larr; ' + $prev.slug + '</a>' } else { '<span>&larr; previous</span>' })
    $(if ($next) { '<a href="' + $chunkUrl[$next.slug] + '">' + $next.slug + ' &rarr;</a>' } else { '<span>next &rarr;</span>' })
  )
  $names    = (@($c.entries | ForEach-Object { $_.title }) -join ', ')
  # method 3: username + character names in <title>/<h1> so google_search("danxdunzi Hilda")
  # returns this batch page directly (search results are whitelisted for the browse tool)
  $title    = 'danxdunzi - Mushoku Tensei Lorebook - {0}: {1}' -f $sec.label, $names
  $h1Text   = 'danxdunzi - Mushoku Tensei Lorebook - {0} (entries {1}-{2} of {3}): {4}' -f $sec.label, $c.firstSeq, $c.lastSeq, $sec.count, $names
  $desc     = Enc $h1Text
  $bodyHtml = ('<h1>' + (Enc $h1Text) + '</h1>') + (Get-Nav $navLinks) + $c.htmlBody
  $pages[$c.slug] = New-Page (Enc $title) $desc $url $bodyHtml
}

# --- section pages: deliberately NOT generated (they duplicated the catalogue) ---
# stale files from the old layout are deleted at emit time.

# --- main index page: the catalogue (every entry name and key, one click per batch) ---
$catalogHtml = New-CatalogHtml
$catalogMd   = New-CatalogMarkdown
$idxSb = New-Object System.Text.StringBuilder
[void]$idxSb.AppendLine($introHtml)
[void]$idxSb.AppendLine($catalogHtml)
[void]$idxSb.AppendLine('<p><a href="' + $rootUrl + '">All lorebooks</a></p>')

$idxTitle = 'danxdunzi - Mushoku Tensei Lorebook Catalogue ({0} entries)' -f $entriesAll.Count
$idxDesc  = Enc ('Mushoku Tensei lorebook catalogue: all {0} entries grouped by section, each linking to the batch page that holds it.' -f $entriesAll.Count)
$pages['entries_index'] = New-Page (Enc $idxTitle) $idxDesc $indexUrl $idxSb.ToString()

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
  $kind   = if ($p.Key -match '^entries_\d{3}$') { 'chunk' } else { 'index' }
  $perPage += [pscustomobject]@{ slug = $p.Key; bytes = $bytes; kind = $kind }
  $allHtml += $p.Value + "`n"
}
$big = @($perPage | Where-Object { ($_.kind -eq 'chunk' -and $_.bytes -gt $htmlFail) -or ($_.kind -eq 'index' -and $_.bytes -gt $indexFail) })
$largest = ($perPage | Sort-Object bytes -Descending)[0]
Add-Check $checks "page size within budget (chunk <= $htmlFail, index <= $indexFail bytes)" ($big.Count -eq 0) ("largest = {0} ({1} bytes)" -f $largest.slug, $largest.bytes)
foreach ($p in ($perPage | Where-Object { ($_.kind -eq 'chunk' -and $_.bytes -gt $htmlWarn -and $_.bytes -le $htmlFail) -or ($_.kind -eq 'index' -and $_.bytes -gt $indexWarn -and $_.bytes -le $indexFail) })) {
  [void]$warns.Add(('{0} is {1} bytes' -f $p.slug, $p.bytes))
}

Add-Check $checks 'no liquid markers in output' (($allHtml -notmatch '\{\{') -and ($allHtml -notmatch '\{%')) ''

# B4/B5: body links must be extensionless and must not end in '/'
$badHref = @(); $lostHref = @()
$allowed = @($rootUrl, $indexUrl) + @($chunks | ForEach-Object { $chunkUrl[$_.slug] })
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

$idxPlain = Get-PlainText $pages['entries_index']
$idxMiss = @($sections | Where-Object { -not $idxPlain.Contains((Norm $_.label)) } | ForEach-Object { $_.label })
Add-Check $checks 'all sections listed on the catalogue page' ($idxMiss.Count -eq 0) (($idxMiss -join ', '))

# the catalogue must BE the whole catalogue: every entry name, every key, and every entry
# name must be a link to the batch page that actually holds it (main -> catalogue -> batch)
$idxPlainRaw = Get-PlainTextRaw $pages['entries_index']
$idxMissT = @($entriesAll | Where-Object { -not $idxPlain.Contains((Norm $_.title)) })
$idxMissL = @($entriesAll | Where-Object { $pages['entries_index'] -notmatch ('<a href="' + [regex]::Escape($_.pageUrl) + '">' + [regex]::Escape((Enc $_.title)) + '</a>') })
Add-Check $checks 'index lists every entry name (complete catalog)' ($idxMissT.Count -eq 0) (('missing: ' + ((@($idxMissT | ForEach-Object { $_.title }) | Select-Object -First 5) -join '; ')))
Add-Check $checks 'every entry name on the index links its batch page' ($idxMissL.Count -eq 0) (('missing: ' + ((@($idxMissL | ForEach-Object { $_.title }) | Select-Object -First 5) -join '; ')))
Add-Check $checks 'index lists every alias key' (@($entriesAll | Where-Object { -not $idxPlain.Contains((Norm $_.keys)) }).Count -eq 0) ''
Add-Check $checks 'index carries no printed batch URLs (links only)' ($idxPlainRaw -notmatch 'https://danxdunzi\.github\.io/session-lorebook/Mushoku_Tensei/entries_\d{3}') ''

# root index.html is hand-maintained (the generator never writes it): it must stay a branch
# catalogue - two links, no printed URL dump - so warn only if the catalogue link went missing
$rootIdxPath = Join-Path $root 'index.html'
if (Test-Path $rootIdxPath) {
  $rootRaw = [System.IO.File]::ReadAllText($rootIdxPath, $utf8)
  $rootLinks = @([regex]::Matches($rootRaw, 'href="([^"]*)"') | ForEach-Object { $_.Groups[1].Value })
  $expected  = @($indexUrl, "$base/Blue_Archive/blue_archive_lorebook")
  $missing   = @($expected | Where-Object { $rootLinks -notcontains $_ })
  if ($missing.Count -eq 0) {
    Add-Check $checks 'root index.html links the branch catalogues' $true ("{0} links" -f $rootLinks.Count)
  } else {
    [void]$warns.Add(('root index.html is missing branch links: ' + ($missing -join ', ')))
  }
}

# README.md mirrors the root index and is what Googlebot crawls on github.com -
# same rule: warn (never fail) if its pasted catalog has drifted
$readmePath = Join-Path $root 'README.md'
if (Test-Path $readmePath) {
  $rmText   = [System.IO.File]::ReadAllText($readmePath, $utf8)
  $rmMissT  = @($entriesAll | Where-Object { -not $rmText.Contains($_.title) })
  $rmMissC  = @($chunks | Where-Object { -not $rmText.Contains($chunkUrl[$_.slug]) })
  if ($rmMissT.Count -eq 0 -and $rmMissC.Count -eq 0) {
    Add-Check $checks 'README.md carries the full catalog' $true ("{0} entries, {1} batch URLs" -f $entriesAll.Count, $chunks.Count)
  } else {
    [void]$warns.Add(('README.md catalog out of sync: {0} entries and {1} batch URLs missing - re-paste .build/root-catalog.md into README.md' -f $rmMissT.Count, $rmMissC.Count))
  }
}

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
Write-Output ('TOTALS  pages = 1 catalogue + {0} chunk = {1}' -f $chunks.Count, $pages.Count)
Write-Output ('        largest page = {0} ({1} bytes / {2} KB)' -f $sorted[0].slug, $sorted[0].bytes, [math]::Round($sorted[0].bytes / 1024, 1))
Write-Output ('        pages over {0} src chars = {1}' -f $charCap, $overCap.Count)
Write-Output ('        total output = {0} bytes' -f (($perPage | Measure-Object bytes -Sum).Sum))
$idxBytes = ($perPage | Where-Object { $_.slug -eq 'entries_index' }).bytes
Write-Output ('        entries_index = {0} bytes / {1} KB (full catalog, fetch budget ~55 KB)' -f $idxBytes, [math]::Round($idxBytes / 1024, 1))
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

  $order = @('entries_index') + @($chunks | ForEach-Object { $_.slug })
  $stats = @()
  foreach ($slug in $order) {
    $file = Join-Path $outDir ($slug + '.html')
    $stats += (Write-IfChanged $file $pages[$slug])
    Write-Output ('  {0,-9} {1}.html' -f $stats[-1], $slug)
  }

  # the section layer is gone: drop any leftover entries_sec_*.html from the old layout
  $stale = @(Get-ChildItem -Path $outDir -Filter 'entries_sec_*.html' -File -ErrorAction SilentlyContinue)
  foreach ($f in $stale) {
    Remove-Item -Path $f.FullName -Force
    Write-Output ('  deleted   {0}' -f $f.Name)
  }

  $manifestDir = Join-Path $root '.build'
  if (-not (Test-Path $manifestDir)) { New-Item -ItemType Directory -Path $manifestDir | Out-Null }
  $manifest = ($order | ForEach-Object { "$base/Mushoku_Tensei/$_" }) -join "`n"
  [System.IO.File]::WriteAllText((Join-Path $manifestDir 'urls.txt'), $manifest + "`n", $utf8)
  Write-Output ('  manifest   .build/urls.txt ({0} urls)' -f $order.Count)
  $staleFrag = Join-Path $manifestDir 'root-catalog.html'
  if (Test-Path $staleFrag) { Remove-Item -Path $staleFrag -Force; Write-Output ('  deleted   .build/root-catalog.html (root index no longer carries the catalog)') }
  [System.IO.File]::WriteAllText((Join-Path $manifestDir 'root-catalog.md'), $catalogMd, $utf8)
  Write-Output ('  fragment   .build/root-catalog.md ({0} bytes - paste into README.md)' -f $utf8.GetByteCount($catalogMd))
  Write-Output ('  result     {0} created, {1} updated, {2} unchanged' -f @($stats | Where-Object { $_ -eq 'created' }).Count, @($stats | Where-Object { $_ -eq 'updated' }).Count, @($stats | Where-Object { $_ -eq 'unchanged' }).Count)
} else {
  Write-Output ''
  Write-Output 'DRY RUN - re-run with -Emit to write the pages.'
}
