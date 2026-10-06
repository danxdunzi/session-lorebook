# Session Lorebook Index

Plain-text lorebooks, one flat Markdown file per franchise. No login, no JavaScript, no CSS. Every file can be fetched directly as raw text with a single HTTP GET request.

Live index page (HTML): https://danxdunzi.github.io/session-lorebook/

## Lorebooks

### 1. Mushoku Tensei: Jobless Reincarnation Lorebook

Characters, in-world K-calendar chronologies, magic systems, world geography, organizations, artifacts, and historical events, compiled from the light novels, canon side stories, and author Q&As.

- Format: plain Markdown, UTF-8, approximately 407 KB
- Path: `Mushoku_Tensei/mushoku_tensei_lorebook.md`
- Live HTML page (for browse/view tools): https://danxdunzi.github.io/session-lorebook/Mushoku_Tensei/mushoku_tensei_lorebook.html
- Direct raw URL: https://raw.githubusercontent.com/danxdunzi/session-lorebook/main/Mushoku_Tensei/mushoku_tensei_lorebook.md
- Human-readable page: https://github.com/danxdunzi/session-lorebook/blob/main/Mushoku_Tensei/mushoku_tensei_lorebook.md

### 2. Blue Archive Lorebook

Characters, locations, world lore, and items, compiled from the Blue Archive wikis and in-game main story text, with timeline markers per volume.

- Format: plain Markdown, UTF-8, approximately 414 KB
- Path: `Blue_Archive/blue_archive_lorebook.md`
- Live HTML page (for browse/view tools): https://danxdunzi.github.io/session-lorebook/Blue_Archive/blue_archive_lorebook.html
- Direct raw URL: https://raw.githubusercontent.com/danxdunzi/session-lorebook/main/Blue_Archive/blue_archive_lorebook.md
- Human-readable page: https://github.com/danxdunzi/session-lorebook/blob/main/Blue_Archive/blue_archive_lorebook.md

## Sessions (roleplay logs, grouped by lorebook)

### Mushoku Tensei sessions

- `Mushoku_Tensei/sessions/session_log1.md`
  - HTML: https://danxdunzi.github.io/session-lorebook/Mushoku_Tensei/sessions/session_log1.html
  - Raw URL: https://raw.githubusercontent.com/danxdunzi/session-lorebook/main/Mushoku_Tensei/sessions/session_log1.md
- `Mushoku_Tensei/sessions/quiet_breakfast_in_sharia.md`
  - HTML: https://danxdunzi.github.io/session-lorebook/Mushoku_Tensei/sessions/quiet_breakfast_in_sharia.html
  - Raw URL: https://raw.githubusercontent.com/danxdunzi/session-lorebook/main/Mushoku_Tensei/sessions/quiet_breakfast_in_sharia.md

## For AI agents and scrapers

1. Fetch this README or the HTML index to discover the catalog.
2. Pick a file.
3. If your tool needs a live, viewable web page (HTML only), fetch the **Live HTML page** URL — it contains the complete text as a normal HTML document.
4. Otherwise send an HTTP GET request to the raw URL. The response body is the complete plain-text Markdown of that lorebook.

Bulk discovery of every file in the repository:

    https://api.github.com/repos/danxdunzi/session-lorebook/git/trees/main?recursive=1

## Repository layout

    session-lorebook/
    |-- index.html                                   plain HTML index (this page, rendered)
    |-- README.md                                     plain Markdown index (this file)
    |-- robots.txt                                    crawler directives
    |-- sitemap.xml                                   sitemap
    |-- Mushoku_Tensei/
    |   |-- mushoku_tensei_lorebook.md                the lorebook
    |   |-- mushoku_tensei_lorebook.html              generated HTML twin of the lorebook
    |   |-- sessions/
    |       |-- session_log1.md
    |       |-- quiet_breakfast_in_sharia.md
    |-- Blue_Archive/
        |-- blue_archive_lorebook.md                  the lorebook
        |-- blue_archive_lorebook.html                generated HTML twin

Each `.html` file is generated from its `.md` sibling and must be regenerated whenever the `.md` changes.
