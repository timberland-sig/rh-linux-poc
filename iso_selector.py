#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0+

import html.parser
import os
import re
import sys
import time
import urllib.error
import urllib.request

from blessed import Terminal


class _LinkParser(html.parser.HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []

    def handle_starttag(self, tag, attrs):
        if tag == "a":
            for attr, val in attrs:
                if attr == "href" and val:
                    self.links.append(val)


def _download(url, dest, update_interval=0.5):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        total = resp.headers.get("Content-Length")
        total = int(total) if total else None
        downloaded = 0
        chunk_size = 2**20
        last_update = 0.0
        with open(dest, "wb") as f:
            while True:
                chunk = resp.read(chunk_size)
                if len(chunk) == 0:
                    break
                f.write(chunk)
                downloaded += len(chunk)

                now = time.monotonic()
                if not (now - last_update >= update_interval or (total is not None and downloaded == total)):
                    continue
                last_update = now

                # Progress bar update
                if total is not None:
                    pct = downloaded * 100 // total
                    bar = "#" * (pct // 2) + "-" * (50 - pct // 2)
                    print(f"\r  [{bar}] {pct}% ({downloaded // chunk_size}/{total // chunk_size} MB)", end="", flush=True)
                else:
                    print(f"\r  {downloaded // chunk_size} MB downloaded", end="", flush=True)
    print()


def _fetch_links(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        body = resp.read().decode("utf-8", errors="replace")
    parser = _LinkParser()
    parser.feed(body)
    return parser.links


def _find_dvd_iso(base_url):
    links = _fetch_links(base_url)
    candidates = []
    for link in links:
        if not link.endswith(".iso"):
            continue
        low = link.lower()
        if "boot" in low or "netinst" in low:
            continue
        if "dvd" not in low:
            continue
        candidates.append(link)
    if len(candidates) == 0:
        return None
    candidates.sort()
    best = candidates[-1]
    if best.startswith("http"):
        return best
    return base_url.rstrip("/") + "/" + best


def _resolve_from_urls(urls):
    errors = []
    for url in urls:
        try:
            result = _find_dvd_iso(url)
            if result:
                return result
        except (urllib.error.HTTPError, urllib.error.URLError, OSError) as e:
            errors.append(f"  {url}: {e}")
    detail = "\n".join(errors)
    raise RuntimeError(f"No DVD ISO found. Tried:\n{detail}")


def _resolve_direct(env_var):
    urls = os.environ.get(env_var, "").split()
    if len(urls) == 0:
        raise RuntimeError(f"No mirror URLs configured (${env_var} is empty, check defaults.sh)")
    return _resolve_from_urls(urls)


def _fedora_iso_urls(base, version):
    return [
        f"{base}releases/{version}/Server/x86_64/iso/",
        f"{base}development/{version}/Server/x86_64/iso/",
    ]


def _fedora_latest_version(base):
    links = _fetch_links(f"{base}releases/")
    versions = []
    for link in links:
        m = re.match(r"^(\d+)/?$", link)
        if m:
            versions.append(int(m.group(1)))
    if len(versions) == 0:
        raise RuntimeError(f"No Fedora releases found at {base}releases/")
    return max(versions)


def _resolve_fedora(version=None):
    base = os.environ.get("MIRROR_FEDORA", "").strip()
    if len(base) == 0:
        raise RuntimeError("No mirror URL configured ($MIRROR_FEDORA is empty, check defaults.sh)")
    if not base.endswith("/"):
        base += "/"
    if version is None:
        version = _fedora_latest_version(base)
    return _resolve_from_urls(_fedora_iso_urls(base, version))


CHOICES = [
    ("CentOS Stream 10",          lambda: _resolve_direct("MIRROR_CENTOS")),
    ("Fedora (latest)",            lambda: _resolve_fedora()),
    ("Fedora 43",                  lambda: _resolve_fedora(43)),
    ("Fedora 42",                  lambda: _resolve_fedora(42)),
    ("Custom ISO download link",   None),
]


def _tui_select():
    term = Terminal()
    selected = 0
    total_lines = 1 + len(CHOICES) + 1

    def draw(first):
        if not first:
            print(f"\r{term.move_up(total_lines - 1)}", end="")
        print(f"  {term.cyan_bold}?{term.normal} {term.bold}Select an OS to use{term.normal}{term.clear_eol}")
        for i, (label, _) in enumerate(CHOICES):
            if i == selected:
                print(f"  {term.cyan_bold}> {label}{term.normal}{term.clear_eol}")
            else:
                print(f"    {label}{term.clear_eol}")
        print(f"  {term.dim}Arrow keys to navigate, Enter to select, q to quit{term.normal}{term.clear_eol}", end="", flush=True)

    print(term.hide_cursor, end="", flush=True)
    try:
        draw(first=True)
        with term.cbreak():
            while True:
                key = term.inkey()
                if key.code == term.KEY_UP or key == "k":
                    selected = (selected - 1) % len(CHOICES)
                elif key.code == term.KEY_DOWN or key == "j":
                    selected = (selected + 1) % len(CHOICES)
                elif key.code == term.KEY_ENTER or key in ("\r", "\n"):
                    print()
                    return selected
                elif key == "q" or key.code == term.KEY_ESCAPE:
                    print()
                    return None
                else:
                    continue
                draw(first=False)
    finally:
        print(term.normal_cursor, end="", flush=True)


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    state_dir = os.getcwd()
    iso_dir = os.path.join(script_dir, "ISO")

    selection = _tui_select()
    if selection is None:
        print("Cancelled.")
        sys.exit(1)

    label, resolver = CHOICES[selection]

    if resolver is None:
        prev_url = ""
        durl_path = os.path.join(state_dir, ".durl")
        if os.path.isfile(durl_path):
            with open(durl_path) as f:
                prev_url = f.read().strip()
        prompt = "Enter URL of the ISO"
        if prev_url:
            prompt += f" ({prev_url})"
        prompt += ": "
        url = input(prompt).strip() or prev_url
        if not url:
            print("No URL provided.")
            sys.exit(1)
    else:
        print(f"Finding latest {label} DVD ISO...")
        try:
            url = resolver()
        except Exception as e:
            print(f"Error: {e}", file=sys.stderr)
            sys.exit(1)
        print(f"Found: {url}")

    iso_name = url.rstrip("/").split("/")[-1].split("?")[0]
    if ".iso" in iso_name:
        iso_name = iso_name[: iso_name.index(".iso") + 4]

    os.makedirs(iso_dir, exist_ok=True)

    iso_path = os.path.join(iso_dir, iso_name)
    if os.path.isfile(iso_path):
        print(f"ISO {iso_name} already exists")
    else:
        print(f"Downloading {iso_name}...")
        try:
            _download(url, iso_path)
        except (OSError, urllib.error.URLError) as e:
            if os.path.isfile(iso_path):
                os.remove(iso_path)
            print(f"Download failed: {e}", file=sys.stderr)
            sys.exit(1)

    with open(os.path.join(state_dir, ".durl"), "w") as f:
        f.write(url + "\n")
    with open(os.path.join(state_dir, ".diso"), "w") as f:
        f.write(iso_name + "\n")

    print(f"ISO ready: ISO/{iso_name}")


if __name__ == "__main__":
    main()