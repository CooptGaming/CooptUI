#!/usr/bin/env python3
"""
Scrape Perky's Crew Server AA Browser (https://perkycrewserver.com/aa_browser.php)
and export the table to CSV for use as a project resource.
"""

import csv
import re
import sys
from pathlib import Path

try:
    import requests
    from bs4 import BeautifulSoup
    HAS_REQUESTS = True
except ImportError:
    HAS_REQUESTS = False

URL = "https://perkycrewserver.com/aa_browser.php"
HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
}


def parse_markdown_table_line(line: str):
    """Parse a markdown table row into 5 columns. Handles pipes inside description and empty Effects."""
    line = line.strip()
    if not line.startswith("|") or not line.endswith("|"):
        return None
    # Remove leading/trailing pipe and split by " | "
    inner = line[1:-1].strip()
    parts = [p.strip() for p in inner.split(" | ")]
    if len(parts) < 4:
        return None
    # Last two columns are always Max Rank and Cost (numeric). Effects is optional (last column).
    # So: [name, description..., max_rank, cost] or [name, description..., max_rank, cost, effects]
    def is_numeric(s):
        return s and s.isdigit()

    if len(parts) >= 5 and is_numeric(parts[-3]) and is_numeric(parts[-2]):
        # Has effects: ... max_rank, cost, effects
        max_rank, cost, effects = parts[-3], parts[-2], parts[-1]
        ability_name = parts[0]
        description = " | ".join(parts[1:-3]).strip() if len(parts) > 5 else parts[1]
    elif len(parts) >= 4 and is_numeric(parts[-2]) and is_numeric(parts[-1]):
        # No effects: ... max_rank, cost
        max_rank, cost, effects = parts[-2], parts[-1], ""
        ability_name = parts[0]
        description = " | ".join(parts[1:-2]).strip() if len(parts) > 4 else parts[1]
    else:
        return None
    return [ability_name, description, max_rank, cost, effects]


def scrape_from_html(html: str) -> list[list[str]]:
    """Extract AA table rows from HTML using BeautifulSoup."""
    soup = BeautifulSoup(html, "html.parser")
    rows = []
    table = soup.find("table")
    if not table:
        return rows
    thead = table.find("thead")
    if thead:
        header_cells = [th.get_text(strip=True) for th in thead.find_all("th")]
        if header_cells:
            rows.append(header_cells)
    for tr in table.find_all("tr"):
        cells = [td.get_text(strip=True) for td in tr.find_all("td")]
        if len(cells) >= 5:
            rows.append(cells[:5])
    return rows


def scrape_from_markdown_file(path: Path) -> list[list[str]]:
    """Extract AA table from a markdown-converted copy of the page (e.g. from web fetch)."""
    rows = [["Ability Name", "Description", "Max Rank", "Cost", "Effects"]]
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            parsed = parse_markdown_table_line(line)
            if parsed:
                rows.append(parsed)
    return rows


def fetch_live() -> str | None:
    """Fetch the AA browser page HTML. Returns None on failure (e.g. 403)."""
    if not HAS_REQUESTS:
        return None
    try:
        r = requests.get(URL, headers=HEADERS, timeout=30)
        r.raise_for_status()
        return r.text
    except Exception as e:
        print(f"Live fetch failed: {e}", file=sys.stderr)
        return None


def main() -> int:
    script_dir = Path(__file__).resolve().parent
    project_root = script_dir.parent
    out_path = project_root / "resources" / "perky_aa_browser.csv"

    # Prefer live fetch; fall back to markdown file if provided
    data = None
    if HAS_REQUESTS:
        html = fetch_live()
        if html:
            data = scrape_from_html(html)
    if not data and len(sys.argv) > 1:
        md_path = Path(sys.argv[1])
        if md_path.exists():
            print(f"Parsing markdown table from {md_path}", file=sys.stderr)
            data = scrape_from_markdown_file(md_path)
    if not data or len(data) <= 1:
        print(
            "No data. Run with a path to a saved markdown copy of the page, or ensure requests/beautifulsoup4 are installed for live fetch.",
            file=sys.stderr,
        )
        return 1

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerows(data)
    print(f"Wrote {len(data) - 1} AAs to {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
