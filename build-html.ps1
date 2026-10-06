$ErrorActionPreference = 'Stop'
$root = 'C:\RegSYS\session-lorebook'
$utf8 = [System.Text.UTF8Encoding]::new($false)

$items = @(
  @{ md = 'Mushoku_Tensei\mushoku_tensei_lorebook.md'
     title = 'Mushoku Tensei: Jobless Reincarnation Lorebook'
     desc  = 'Plain-text lorebook: characters, K-calendar chronology, magic systems, geography, organizations, artifacts and history for Mushoku Tensei (Jobless Reincarnation).' },
  @{ md = 'Blue_Archive\blue_archive_lorebook.md'
     title = 'Blue Archive Lorebook'
     desc  = 'Plain-text lorebook: characters, locations, world lore and items for Blue Archive, with timeline markers per story volume.' },
  @{ md = 'Mushoku_Tensei\sessions\session_log1.md'
     title = 'Mushoku Tensei Session Log 1'
     desc  = 'Roleplay session log set in the Mushoku Tensei world: campfire reunion, spars, pacts and travel beats, day by day.' },
  @{ md = 'Mushoku_Tensei\sessions\quiet_breakfast_in_sharia.md'
     title = 'Quiet Breakfast In Sharia - Session Transcript'
     desc  = 'Full roleplay session transcript set in Sharia (Mushoku Tensei): quiet breakfast scene and household interactions.' }
)

foreach ($i in $items) {
  $mdPath   = Join-Path $root $i.md
  $htmlPath = [System.IO.Path]::ChangeExtension($mdPath, '.html')
  $bodyFile = [System.IO.Path]::GetTempFileName()

  & npx.cmd -y marked -i $mdPath -o $bodyFile | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "marked failed for $($i.md)" }

  $body = [System.IO.File]::ReadAllText($bodyFile, [System.Text.UTF8Encoding]::new($true))
  Remove-Item $bodyFile -Force

  $heading = if ($body -notmatch '<h1') { "<h1>$($i.title)</h1>`r`n" } else { '' }

  $relPath = ($i.md -replace '\\', '/')
  $mdUrl   = "https://danxdunzi.github.io/session-lorebook/" + $relPath
  $pageUrl = $mdUrl -replace '\.md$', ''

  $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$($i.title)</title>
<meta name="description" content="$($i.desc)">
<meta name="robots" content="index, follow, max-snippet:-1">
<link rel="canonical" href="$pageUrl">
<link rel="alternate" type="text/markdown" href="$mdUrl">
</head>
<body>
$heading<p><a href="https://danxdunzi.github.io/session-lorebook/">Session Lorebook Index</a></p>
$body
</body>
</html>
"@

  [System.IO.File]::WriteAllText($htmlPath, $html, $utf8)
  $size = (Get-Item $htmlPath).Length
  Write-Output "OK  $($i.md)  ->  $(Split-Path $htmlPath -Leaf)  ($size bytes)"
}
