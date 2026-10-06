# Session Lorebook Index

Plain-text lorebooks, one flat Markdown file per franchise. No login, no JavaScript, no CSS. Every file can be fetched directly as raw text with a single HTTP GET request.

Live index page (HTML): https://danxdunzi.github.io/session-lorebook

## Lorebooks

### 1. Mushoku Tensei: Jobless Reincarnation Lorebook

Characters, in-world K-calendar chronologies, magic systems, world geography, organizations, artifacts, and historical events, compiled from the light novels, canon side stories, and author Q&As.

- Format: plain Markdown, UTF-8, approximately 407 KB
- Path: `Mushoku_Tensei/mushoku_tensei_lorebook.md`
- Live page URL (extensionless, for browse/view tools): https://danxdunzi.github.io/session-lorebook/Mushoku_Tensei/mushoku_tensei_lorebook
- Direct raw URL: https://raw.githubusercontent.com/danxdunzi/session-lorebook/main/Mushoku_Tensei/mushoku_tensei_lorebook.md
- Human-readable page: https://github.com/danxdunzi/session-lorebook/blob/main/Mushoku_Tensei/mushoku_tensei_lorebook.md

#### Browse the Mushoku Tensei lorebook entry by entry

The full page is about 416 KB and fetch tools usually truncate it around the first dozen
entries. The same 200 entries are also published as pages holding at most 5 entries each,
wired together by an entry index. Every URL has no file extension and no trailing slash.

- Entry index (start here): https://danxdunzi.github.io/session-lorebook/Mushoku_Tensei/entries_index
- Characters — 51 entries in 15 pages: https://danxdunzi.github.io/session-lorebook/Mushoku_Tensei/entries_sec_01
- Locations — 45 entries in 9 pages: https://danxdunzi.github.io/session-lorebook/Mushoku_Tensei/entries_sec_02
- World Lore — 63 entries in 13 pages: https://danxdunzi.github.io/session-lorebook/Mushoku_Tensei/entries_sec_03
- Items — 12 entries in 3 pages: https://danxdunzi.github.io/session-lorebook/Mushoku_Tensei/entries_sec_04
- Guide — 1 entry in 1 page: https://danxdunzi.github.io/session-lorebook/Mushoku_Tensei/entries_sec_05
- Characters (secondary) — 16 entries in 4 pages: https://danxdunzi.github.io/session-lorebook/Mushoku_Tensei/entries_sec_06
- Items (Dragon King Sword) — 1 entry in 1 page: https://danxdunzi.github.io/session-lorebook/Mushoku_Tensei/entries_sec_07
- Locations (Teleport Labyrinth) — 1 entry in 1 page: https://danxdunzi.github.io/session-lorebook/Mushoku_Tensei/entries_sec_08
- Items (The Diary) — 1 entry in 1 page: https://danxdunzi.github.io/session-lorebook/Mushoku_Tensei/entries_sec_09
- The Diary (Entry 1-9) — 9 entries in 2 pages: https://danxdunzi.github.io/session-lorebook/Mushoku_Tensei/entries_sec_10

Each section index lists every entry name with its alias keys (Fitz, Quagmire, Mad Dog, ...)
as plain text, and each name links to the page holding that entry. Pages are numbered
`entries_001` .. `entries_050` under `Mushoku_Tensei/`.

### 2. Blue Archive Lorebook

Characters, locations, world lore, and items, compiled from the Blue Archive wikis and in-game main story text, with timeline markers per volume.

- Format: plain Markdown, UTF-8, approximately 414 KB
- Path: `Blue_Archive/blue_archive_lorebook.md`
- Live page URL (extensionless, for browse/view tools): https://danxdunzi.github.io/session-lorebook/Blue_Archive/blue_archive_lorebook
- Direct raw URL: https://raw.githubusercontent.com/danxdunzi/session-lorebook/main/Blue_Archive/blue_archive_lorebook.md
- Human-readable page: https://github.com/danxdunzi/session-lorebook/blob/main/Blue_Archive/blue_archive_lorebook.md

## Sessions (roleplay logs, grouped by lorebook)

### Mushoku Tensei sessions

- `Mushoku_Tensei/sessions/session_log1.md`
  - Page (extensionless): https://danxdunzi.github.io/session-lorebook/Mushoku_Tensei/sessions/session_log1
  - Raw URL: https://raw.githubusercontent.com/danxdunzi/session-lorebook/main/Mushoku_Tensei/sessions/session_log1.md
- `Mushoku_Tensei/sessions/quiet_breakfast_in_sharia.md`
  - Page (extensionless): https://danxdunzi.github.io/session-lorebook/Mushoku_Tensei/sessions/quiet_breakfast_in_sharia
  - Raw URL: https://raw.githubusercontent.com/danxdunzi/session-lorebook/main/Mushoku_Tensei/sessions/quiet_breakfast_in_sharia.md

## For AI agents and scrapers

1. Fetch this README or the HTML index to discover the catalog.
2. Pick a file.
3. If your tool needs a live, viewable web page, fetch the **Live page URL** (extensionless — some browse tools treat URLs ending in a file extension as files rather than pages). It contains the complete text as a normal HTML document.
4. Otherwise send an HTTP GET request to the raw URL. The response body is the complete plain-text Markdown of that lorebook.
5. For one specific Mushoku Tensei entry, do not fetch the full page — it gets truncated. Fetch the entry index, open the section index, then open the page holding that entry (max 5 whole entries per page, alias keys listed on the section index).

Bulk discovery of every file in the repository:

    https://api.github.com/repos/danxdunzi/session-lorebook/git/trees/main?recursive=1

## Repository layout

    session-lorebook/
    |-- index.html                                   plain HTML index (this page, rendered)
    |-- README.md                                     plain Markdown index (this file)
    |-- robots.txt                                    crawler directives
    |-- sitemap.xml                                   sitemap
    |-- Mushoku_Tensei/
    |   |-- mushoku_tensei_lorebook.md                the lorebook (source of truth)
    |   |-- mushoku_tensei_lorebook.html              generated HTML twin of the lorebook
    |   |-- entries_index.html                        entry index / browse hub
    |   |-- entries_sec_01.html .. entries_sec_10.html  section indexes (entry names + alias keys)
    |   |-- entries_001.html .. entries_050.html      chunk pages, at most 5 entries each
    |   |-- sessions/
    |       |-- session_log1.md
    |       |-- quiet_breakfast_in_sharia.md
    |-- Blue_Archive/
        |-- blue_archive_lorebook.md                  the lorebook
        |-- blue_archive_lorebook.html                generated HTML twin

Each `.html` file is generated from its `.md` sibling and must be regenerated whenever the `.md` changes:

    powershell -ExecutionPolicy Bypass -File build-html.ps1             # full-page HTML twins
    powershell -ExecutionPolicy Bypass -File build-lorebook-pages.ps1   # chunked entry pages (dry run)
    powershell -ExecutionPolicy Bypass -File build-lorebook-pages.ps1 -Emit   # chunked entry pages (write)
