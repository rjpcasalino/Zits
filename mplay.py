#!/usr/bin/env python3
"""
mplay --- full-screen TUI media browser and streamer for MiniDLNA + mpv.

Queries MiniDLNA's UPnP ContentDirectory SOAP service on port 8200 using a
single bulk UPnP Search request (with automatic fallback to recursive Browse
and local filesystem mounts) and streams selected media into mpv with native
HTTP byte-range seeking.
"""

import concurrent.futures
import curses
import dataclasses
import locale
import os
import subprocess
import sys
import time
import urllib.request
import xml.etree.ElementTree as ET
from typing import Dict, List, Optional, Set, Tuple

DEFAULT_URL = os.environ.get("DLNA_URL", "http://127.0.0.1:8200").rstrip("/")
FALLBACK_DIRS = ["/mnt/mybook", "/mnt/elements", "/mnt/toshiba"]

NS = {
    "s": "http://schemas.xmlsoap.org/soap/envelope/",
    "u": "urn:schemas-upnp-org:service:ContentDirectory:1",
    "didl": "urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/",
    "dc": "http://purl.org/dc/elements/1.1/",
    "upnp": "urn:schemas-upnp-org:metadata-1-0/upnp/",
}

VIDEO_EXTS = {
    ".mkv", ".mp4", ".avi", ".mov", ".m4v", ".webm", ".wmv",
    ".flv", ".mpg", ".mpeg", ".ts", ".iso", ".vob", ".m2ts",
}
AUDIO_EXTS = {
    ".mp3", ".flac", ".ogg", ".wav", ".m4a", ".aac", ".opus", ".wma",
}

SORT_MODES = ("path", "size", "duration", "date", "title")


@dataclasses.dataclass(slots=True)
class MediaItem:
    title: str
    folder: str
    drive: str
    rel_path: str
    search_key: str
    url: str
    size: int
    kind: str  # "video" or "audio"
    duration_str: str = ""
    duration_secs: float = 0.0
    resolution: str = ""
    channels: str = ""
    sample_rate: str = ""
    bitrate: int = 0
    mime: str = ""
    date: str = ""


def human_size(n: int) -> str:
    try:
        val = float(n)
    except (TypeError, ValueError):
        return "    ? B"
    for unit in ("B", "K", "M", "G", "T"):
        if val < 1024.0 or unit == "T":
            if unit == "B":
                return f"{int(val):5d}B"
            return f"{val:5.1f}{unit}"
        val /= 1024.0
    return f"{val:5.1f}T"


def parse_duration(raw: str) -> Tuple[str, float]:
    """Parse UPnP duration 'H:MM:SS.mmm' into compact 'HH:MM:SS' or 'MM:SS' and seconds."""
    if not raw:
        return "", 0.0
    main = raw.split(".")[0].strip()
    parts = main.split(":")
    try:
        if len(parts) == 3:
            h, m, s = int(parts[0]), int(parts[1]), int(parts[2])
        elif len(parts) == 2:
            h, m, s = 0, int(parts[0]), int(parts[1])
        else:
            h, m, s = 0, 0, int(parts[0])
        total = float(h * 3600 + m * 60 + s)
        if h > 0:
            return f"{h:d}:{m:02d}:{s:02d}", total
        return f"{m:02d}:{s:02d}", total
    except ValueError:
        return main[:8], 0.0


def build_media_item(
    title: str,
    prefix: str,
    url: str,
    size: int,
    uclass: str,
    duration_raw: str = "",
    resolution: str = "",
    channels: str = "",
    sample_rate: str = "",
    bitrate: int = 0,
    protocol_info: str = "",
    date_raw: str = "",
) -> Optional[MediaItem]:
    ext = os.path.splitext(url)[1]
    ext_low = ext.lower()
    is_audio = "audioItem" in uclass or ext_low in AUDIO_EXTS
    is_video = "videoItem" in uclass or ext_low in VIDEO_EXTS
    if not is_video and not is_audio:
        return None
    kind = "video" if is_video else "audio"

    display_title = title if title.lower().endswith(ext_low) else f"{title}{ext}"
    rel_path = f"{prefix}/{display_title}" if prefix else display_title
    drive = prefix.split("/", 1)[0] if prefix else "root"
    dur_str, dur_secs = parse_duration(duration_raw)

    mime = ""
    if protocol_info:
        proto_parts = protocol_info.split(":")
        if len(proto_parts) >= 3:
            mime = proto_parts[2]

    date_short = date_raw.split("T")[0] if date_raw else ""

    return MediaItem(
        title=display_title,
        folder=prefix,
        drive=drive,
        rel_path=rel_path,
        search_key=f"{rel_path} {resolution} {date_short}".lower(),
        url=url,
        size=size,
        kind=kind,
        duration_str=dur_str,
        duration_secs=dur_secs,
        resolution=resolution,
        channels=channels,
        sample_rate=sample_rate,
        bitrate=bitrate,
        mime=mime,
        date=date_short,
    )


def extract_item_fields(it: ET.Element, prefix: str) -> Optional[MediaItem]:
    title_el = it.find("dc:title", NS)
    title = title_el.text if title_el is not None and title_el.text else "Untitled"
    uclass_el = it.find("upnp:class", NS)
    uclass = uclass_el.text if uclass_el is not None and uclass_el.text else ""
    date_el = it.find("dc:date", NS)
    date_raw = date_el.text.strip() if date_el is not None and date_el.text else ""

    res_el = it.find("didl:res", NS)
    if res_el is None or not res_el.text:
        return None
    url = res_el.text.strip()
    attrib = res_el.attrib
    size = int(attrib.get("size", "0") or 0)
    duration_raw = attrib.get("duration", "")
    resolution = attrib.get("resolution", "")
    channels = attrib.get("nrAudioChannels", "")
    sample_rate = attrib.get("sampleFrequency", "")
    bitrate = int(attrib.get("bitrate", "0") or 0)
    protocol_info = attrib.get("protocolInfo", "")

    return build_media_item(
        title=title,
        prefix=prefix,
        url=url,
        size=size,
        uclass=uclass,
        duration_raw=duration_raw,
        resolution=resolution,
        channels=channels,
        sample_rate=sample_rate,
        bitrate=bitrate,
        protocol_info=protocol_info,
        date_raw=date_raw,
    )


def soap_search_all(base_url: str, container_id: str = "64") -> List[MediaItem]:
    """Fetch all containers and items in a single UPnP ContentDirectory#Search call."""
    body = f"""<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:Search xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">
      <ContainerID>{container_id}</ContainerID>
      <SearchCriteria>upnp:class derivedfrom "object.container" or upnp:class derivedfrom "object.item"</SearchCriteria>
      <Filter>*</Filter>
      <StartingIndex>0</StartingIndex>
      <RequestedCount>100000</RequestedCount>
      <SortCriteria></SortCriteria>
    </u:Search>
  </s:Body>
</s:Envelope>""".encode("utf-8")

    req = urllib.request.Request(
        f"{base_url}/ctl/ContentDir",
        data=body,
        headers={
            "Content-Type": 'text/xml; charset="utf-8"',
            "SOAPAction": '"urn:schemas-upnp-org:service:ContentDirectory:1#Search"',
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=5) as resp:
        xml_bytes = resp.read()

    env = ET.fromstring(xml_bytes)
    result_el = env.find(".//Result")
    if result_el is None or not result_el.text:
        return []

    didl = ET.fromstring(result_el.text.encode("utf-8"))
    containers: Dict[str, Tuple[str, str]] = {}
    for c in didl.findall("didl:container", NS):
        cid = c.attrib.get("id", "")
        pid = c.attrib.get("parentID", "")
        title_el = c.find("dc:title", NS)
        title = title_el.text if title_el is not None and title_el.text else cid
        containers[cid] = (pid, title)

    path_cache: Dict[str, str] = {}

    def resolve_prefix(cid: str) -> str:
        if cid in path_cache:
            return path_cache[cid]
        if cid not in containers or cid in ("0", "64"):
            return ""
        pid, title = containers[cid]
        parent = resolve_prefix(pid)
        full = f"{parent}/{title}" if parent else title
        path_cache[cid] = full
        return full

    results: List[MediaItem] = []
    for it in didl.findall("didl:item", NS):
        pid = it.attrib.get("parentID", "")
        prefix = resolve_prefix(pid)
        item = extract_item_fields(it, prefix)
        if item is not None:
            results.append(item)

    return results


def soap_browse(base_url: str, object_id: str, start: int = 0, count: int = 5000):
    body = f"""<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:Browse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">
      <ObjectID>{object_id}</ObjectID>
      <BrowseFlag>BrowseDirectChildren</BrowseFlag>
      <Filter>*</Filter>
      <StartingIndex>{start}</StartingIndex>
      <RequestedCount>{count}</RequestedCount>
      <SortCriteria></SortCriteria>
    </u:Browse>
  </s:Body>
</s:Envelope>""".encode("utf-8")

    req = urllib.request.Request(
        f"{base_url}/ctl/ContentDir",
        data=body,
        headers={
            "Content-Type": 'text/xml; charset="utf-8"',
            "SOAPAction": '"urn:schemas-upnp-org:service:ContentDirectory:1#Browse"',
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=5) as resp:
        xml_bytes = resp.read()

    env = ET.fromstring(xml_bytes)
    result_el = env.find(".//Result")
    if result_el is None or not result_el.text:
        return [], []

    didl = ET.fromstring(result_el.text.encode("utf-8"))
    containers = []
    for c in didl.findall("didl:container", NS):
        cid = c.attrib.get("id", "")
        title_el = c.find("dc:title", NS)
        title = title_el.text if title_el is not None and title_el.text else cid
        containers.append((cid, title))

    raw_items = didl.findall("didl:item", NS)
    return containers, raw_items


def fetch_dlna_catalog(base_url: str) -> List[MediaItem]:
    """Fetch complete DLNA catalog via single Search request, falling back to recursive Browse."""
    for root_id in ("64", "0"):
        try:
            items = soap_search_all(base_url, root_id)
            if items:
                items.sort(key=lambda x: x.rel_path.lower())
                return items
        except Exception:
            pass

    results: List[MediaItem] = []
    visited: Set[str] = set()
    queue: List[Tuple[str, str]] = [("0", "")]
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        while queue:
            batch = []
            for cid, prefix in queue:
                if cid not in visited:
                    visited.add(cid)
                    batch.append((cid, prefix))
            queue = []
            if not batch:
                break

            future_map = {
                pool.submit(soap_browse, base_url, cid): (cid, prefix)
                for cid, prefix in batch
            }
            for fut in concurrent.futures.as_completed(future_map):
                cid, prefix = future_map[fut]
                try:
                    containers, raw_items = fut.result()
                except Exception:
                    continue
                for sub_id, sub_title in containers:
                    new_prefix = f"{prefix}/{sub_title}" if prefix else sub_title
                    queue.append((sub_id, new_prefix))
                for it in raw_items:
                    item = extract_item_fields(it, prefix)
                    if item is not None:
                        results.append(item)

    results.sort(key=lambda x: x.rel_path.lower())
    return results


def fetch_local_catalog(dirs: List[str]) -> List[MediaItem]:
    results: List[MediaItem] = []
    for base in dirs:
        if not os.path.isdir(base):
            continue
        drive_name = os.path.basename(base.rstrip("/")) or base
        for root, _, files in os.walk(base):
            rel_root = os.path.relpath(root, base)
            prefix = drive_name if rel_root == "." else f"{drive_name}/{rel_root}"
            for fname in files:
                ext_low = os.path.splitext(fname)[1].lower()
                if ext_low not in VIDEO_EXTS and ext_low not in AUDIO_EXTS:
                    continue
                full = os.path.join(root, fname)
                try:
                    st = os.stat(full)
                    sz = st.st_size
                    mtime_str = time.strftime("%Y-%m-%d", time.localtime(st.st_mtime))
                except OSError:
                    sz = 0
                    mtime_str = ""
                uclass = "object.item.videoItem" if ext_low in VIDEO_EXTS else "object.item.audioItem"
                item = build_media_item(
                    title=fname,
                    prefix=prefix,
                    url=full,
                    size=sz,
                    uclass=uclass,
                    date_raw=mtime_str,
                )
                if item is not None:
                    results.append(item)
    results.sort(key=lambda x: x.rel_path.lower())
    return results


def load_catalog(base_url: str) -> Tuple[List[MediaItem], str, float]:
    t0 = time.monotonic()
    host_short = base_url.replace("http://", "").replace("https://", "")
    try:
        items = fetch_dlna_catalog(base_url)
        if items:
            return items, f"MiniDLNA ({host_short})", (time.monotonic() - t0) * 1000.0
    except Exception:
        pass
    items = fetch_local_catalog(FALLBACK_DIRS)
    return items, "Local Mounts", (time.monotonic() - t0) * 1000.0


def safe_addnstr(win, y: int, x: int, text: str, max_cols: int, attr: int = 0):
    if max_cols <= 0:
        return
    try:
        win.addnstr(y, x, text, max_cols, attr)
    except curses.error:
        pass


def truncate_middle(text: str, width: int) -> str:
    if len(text) <= width:
        return text
    if width <= 3:
        return text[:width]
    left = (width - 1) // 2
    right = width - 1 - left
    return f"{text[:left]}…{text[-right:]}"


class MplayTUI:
    def __init__(self, stdscr, base_url: str, initial_cat: str, initial_query: str):
        self.stdscr = stdscr
        self.base_url = base_url
        self.category = initial_cat  # "video", "audio", "all"
        self.query = initial_query
        self.search_mode = False
        self.show_inspector = True
        self.drive_filter = "all"
        self.sort_idx = 0
        self.sort_reverse = False

        self.all_items: List[MediaItem] = []
        self.drives: List[str] = ["all"]
        self.hits: List[MediaItem] = []
        self.played_urls: Set[str] = set()

        self.cursor = 0
        self.top = 0
        self.source_label = ""
        self.load_ms = 0.0
        self.status_msg = ""

        self._init_colors()
        self.reload_catalog()
        self.apply_filters(reset_cursor=True)

    def _init_colors(self):
        curses.use_default_colors()
        try:
            curses.curs_set(0)
        except curses.error:
            pass

        # Color pairs matching a clean terminal palette
        curses.init_pair(1, curses.COLOR_BLACK, curses.COLOR_CYAN)     # Header bar / active pill
        curses.init_pair(2, curses.COLOR_CYAN, -1)                     # Accent / drive / prompt
        curses.init_pair(3, curses.COLOR_YELLOW, -1)                   # Size / metadata labels
        curses.init_pair(4, curses.COLOR_GREEN, -1)                    # Duration / played mark
        curses.init_pair(5, curses.COLOR_MAGENTA, -1)                  # Resolution / format
        curses.init_pair(6, curses.COLOR_WHITE, curses.COLOR_BLUE)     # Selected row
        curses.init_pair(7, curses.COLOR_BLACK, curses.COLOR_WHITE)    # Status / keybind bar

        self.c_header = curses.color_pair(1) | curses.A_BOLD
        self.c_accent = curses.color_pair(2) | curses.A_BOLD
        self.c_dim = curses.A_DIM
        self.c_size = curses.color_pair(3)
        self.c_dur = curses.color_pair(4)
        self.c_res = curses.color_pair(5)
        self.c_sel = curses.color_pair(6) | curses.A_BOLD
        self.c_bar = curses.color_pair(7)

    def reload_catalog(self):
        self.stdscr.erase()
        safe_addnstr(self.stdscr, 0, 0, f" Loading media catalog from {self.base_url} ...", 80, self.c_accent)
        self.stdscr.refresh()
        self.all_items, self.source_label, self.load_ms = load_catalog(self.base_url)
        drive_set = sorted({it.drive for it in self.all_items if it.drive})
        self.drives = ["all"] + drive_set
        if self.drive_filter not in self.drives:
            self.drive_filter = "all"
        self.status_msg = f"Loaded {len(self.all_items)} items in {self.load_ms:.0f}ms"

    def apply_filters(self, reset_cursor: bool = False):
        tokens = [t for t in self.query.lower().split() if t]
        cat = self.category
        drv = self.drive_filter

        filtered = []
        for it in self.all_items:
            if cat != "all" and it.kind != cat:
                continue
            if drv != "all" and it.drive != drv:
                continue
            if tokens and not all(tok in it.search_key for tok in tokens):
                continue
            filtered.append(it)

        sort_mode = SORT_MODES[self.sort_idx]
        if sort_mode == "path":
            filtered.sort(key=lambda x: x.rel_path.lower(), reverse=self.sort_reverse)
        elif sort_mode == "size":
            filtered.sort(key=lambda x: x.size, reverse=not self.sort_reverse)
        elif sort_mode == "duration":
            filtered.sort(key=lambda x: x.duration_secs, reverse=not self.sort_reverse)
        elif sort_mode == "date":
            filtered.sort(key=lambda x: x.date, reverse=not self.sort_reverse)
        elif sort_mode == "title":
            filtered.sort(key=lambda x: x.title.lower(), reverse=self.sort_reverse)

        self.hits = filtered
        if reset_cursor:
            self.cursor = 0
            self.top = 0
        else:
            self.clamp_cursor(max(1, self.get_list_height()))

    def get_list_height(self) -> int:
        rows, _ = self.stdscr.getmaxyx()
        reserved = 4 + (3 if self.show_inspector else 0)
        return max(1, rows - reserved)

    def clamp_cursor(self, list_h: int):
        if not self.hits:
            self.cursor = 0
            self.top = 0
            return
        self.cursor = max(0, min(self.cursor, len(self.hits) - 1))
        if self.cursor < self.top:
            self.top = self.cursor
        elif self.cursor >= self.top + list_h:
            self.top = max(0, self.cursor - list_h + 1)

    def draw(self):
        self.stdscr.erase()
        rows, cols = self.stdscr.getmaxyx()
        if rows < 6 or cols < 30:
            safe_addnstr(self.stdscr, 0, 0, "Terminal too small", cols)
            self.stdscr.refresh()
            return

        # 1. Top Header Bar (Row 0)
        vid_cnt = sum(1 for x in self.all_items if x.kind == "video")
        aud_cnt = sum(1 for x in self.all_items if x.kind == "audio")
        all_cnt = len(self.all_items)

        def fmt_tab(name: str, label: str, count: int) -> str:
            active = self.category == name
            return f"[{label}:{count}]" if active else f" {label}:{count} "

        tabs = f"{fmt_tab('video', 'Video', vid_cnt)} {fmt_tab('audio', 'Audio', aud_cnt)} {fmt_tab('all', 'All', all_cnt)}"
        sort_name = SORT_MODES[self.sort_idx].capitalize()
        sort_dir = "↓" if (SORT_MODES[self.sort_idx] in ("size", "duration", "date") and not self.sort_reverse) or (SORT_MODES[self.sort_idx] in ("path", "title") and self.sort_reverse) else "↑"
        header_left = f" mplay │ {tabs} │ Drive:{self.drive_filter} │ Sort:{sort_name}{sort_dir}"
        header_right = f"{self.source_label} ({self.load_ms:.0f}ms) "
        pad = max(1, cols - len(header_left) - len(header_right))
        header_line = (header_left + (" " * pad) + header_right)[:cols].ljust(cols)
        safe_addnstr(self.stdscr, 0, 0, header_line, cols, self.c_header)

        # 2. Search / Filter Bar (Row 1)
        if self.search_mode:
            prompt = " / "
            safe_addnstr(self.stdscr, 1, 0, prompt, cols, self.c_accent)
            q_disp = self.query
            safe_addnstr(self.stdscr, 1, len(prompt), q_disp, cols - len(prompt) - 1, curses.A_BOLD)
        else:
            if self.query:
                safe_addnstr(self.stdscr, 1, 0, " Filter: ", cols, self.c_accent)
                safe_addnstr(self.stdscr, 1, 9, f'"{self.query}" (Esc to clear, / to edit)', cols - 10, curses.A_BOLD)
            else:
                safe_addnstr(self.stdscr, 1, 0, " Press / to search (multi-word fuzzy filter)...", cols, self.c_dim)

        match_stats = f"{len(self.hits)}/{len(self.all_items)} items "
        if cols > len(match_stats) + 25:
            safe_addnstr(self.stdscr, 1, cols - len(match_stats), match_stats, len(match_stats), self.c_accent)

        # 3. Table Column Header (Row 2)
        col_hdr = f" {'#':>4}  {'SIZE':>6}  {'DURATION':>8}  {'RES':>9}  {'DRIVE':<8}  {'MEDIA PATH'}"
        safe_addnstr(self.stdscr, 2, 0, col_hdr.ljust(cols), cols, curses.A_UNDERLINE | curses.A_BOLD)

        # 4. Media List Viewport
        list_h = self.get_list_height()
        self.clamp_cursor(list_h)

        if not self.hits:
            safe_addnstr(self.stdscr, 4, 3, "No matching media items found.", cols - 4, self.c_dim)
        else:
            last = min(self.top + list_h, len(self.hits))
            for idx in range(self.top, last):
                row_y = 3 + (idx - self.top)
                it = self.hits[idx]
                selected = idx == self.cursor
                played = "✓" if it.url in self.played_urls else " "
                sz_s = human_size(it.size)
                dur_s = f"{it.duration_str:>8}" if it.duration_str else "       -"
                res_s = f"{it.resolution:>9}" if it.resolution else ("    audio" if it.kind == "audio" else "        -")
                drv_s = f"{it.drive[:8]:<8}"

                prefix_cols = 42
                avail_path = max(8, cols - prefix_cols - 1)
                # Strip leading drive from path since DRIVE has its own column
                sub_path = it.rel_path[len(it.drive) + 1:] if it.rel_path.startswith(it.drive + "/") else it.rel_path
                path_s = truncate_middle(sub_path, avail_path)

                if selected:
                    line = f"{played}{idx + 1:4d}  {sz_s}  {dur_s}  {res_s}  {drv_s}  {path_s}"
                    safe_addnstr(self.stdscr, row_y, 0, line.ljust(cols), cols, self.c_sel)
                else:
                    safe_addnstr(self.stdscr, row_y, 0, f"{played}{idx + 1:4d}  ", 7, self.c_dur if played == "✓" else self.c_dim)
                    safe_addnstr(self.stdscr, row_y, 7, f"{sz_s}  ", 8, self.c_size)
                    safe_addnstr(self.stdscr, row_y, 15, f"{dur_s}  ", 10, self.c_dur)
                    safe_addnstr(self.stdscr, row_y, 25, f"{res_s}  ", 11, self.c_res)
                    safe_addnstr(self.stdscr, row_y, 36, f"{drv_s}  ", 10, self.c_accent)

                    # Dim folder prefix, bold filename
                    if "/" in path_s:
                        folder_part, file_part = path_s.rsplit("/", 1)
                        folder_part += "/"
                        safe_addnstr(self.stdscr, row_y, 46, folder_part, avail_path, self.c_dim)
                        rem = avail_path - len(folder_part)
                        if rem > 0:
                            safe_addnstr(self.stdscr, row_y, 46 + len(folder_part), file_part, rem, curses.A_NORMAL)
                    else:
                        safe_addnstr(self.stdscr, row_y, 46, path_s, avail_path, curses.A_NORMAL)

        # 5. Inspector / Details Footer (Rows H-4 .. H-2)
        if self.show_inspector:
            sep_y = rows - 4
            safe_addnstr(self.stdscr, sep_y, 0, "─" * cols, cols, self.c_dim)
            if self.hits and 0 <= self.cursor < len(self.hits):
                cur = self.hits[self.cursor]
                br_mbps = f"{(cur.bitrate * 8) / 1_000_000:.1f} Mbps" if cur.bitrate else "-"
                ch_info = f"{cur.channels}ch" if cur.channels else "-"
                if cur.sample_rate:
                    ch_info += f" {int(cur.sample_rate) // 1000}kHz"
                meta1 = f" Path: {cur.rel_path}"
                meta2 = (
                    f" Size: {human_size(cur.size).strip()}  │  "
                    f"Duration: {cur.duration_str or '-'}  │  "
                    f"Res: {cur.resolution or '-'}  │  "
                    f"Audio: {ch_info}  │  "
                    f"Bitrate: {br_mbps}  │  "
                    f"Format: {cur.mime or '-'}  │  "
                    f"Date: {cur.date or '-'}  │  "
                    f"URL: {cur.url}"
                )
                safe_addnstr(self.stdscr, sep_y + 1, 0, truncate_middle(meta1, cols - 1), cols, curses.A_BOLD)
                safe_addnstr(self.stdscr, sep_y + 2, 0, meta2[:cols - 1], cols, self.c_size)
            else:
                safe_addnstr(self.stdscr, sep_y + 1, 0, " No item selected", cols, self.c_dim)

        # 6. Bottom Keybind Bar (Row H-1)
        if self.search_mode:
            keys_help = " [Type] Filter live  [Up/Down/PgDn] Navigate  [Enter] Done/Play  [Esc] Exit search "
        else:
            keys_help = " [/] Search  [Enter] Play  [Tab] Cat  [d] Drive  [s/S] Sort  [i] Info  [r] Reload  [q] Quit "
        if self.status_msg and cols > len(keys_help) + len(self.status_msg) + 4:
            pad_k = cols - len(keys_help) - len(self.status_msg) - 1
            bar_text = f"{keys_help}{' ' * pad_k}{self.status_msg} "
        else:
            bar_text = keys_help.ljust(cols)
        safe_addnstr(self.stdscr, rows - 1, 0, bar_text[:cols].ljust(cols), cols, self.c_bar)

        # Position cursor in search bar when actively editing
        if self.search_mode:
            try:
                curses.curs_set(1)
                cx = min(cols - 1, 3 + len(self.query))
                self.stdscr.move(1, cx)
            except curses.error:
                pass
        else:
            try:
                curses.curs_set(0)
            except curses.error:
                pass

        self.stdscr.refresh()

    def play_selected(self):
        if not self.hits or not (0 <= self.cursor < len(self.hits)):
            return
        item = self.hits[self.cursor]
        self.played_urls.add(item.url)

        curses.def_prog_mode()
        curses.endwin()
        try:
            sys.stdout.write(f"\nPlaying: {item.rel_path}\nStream:  {item.url}\n\n")
            sys.stdout.flush()
            subprocess.run(["mpv", "--force-window=immediate", item.url])
        except FileNotFoundError:
            self.status_msg = "Error: mpv not found on PATH"
        except KeyboardInterrupt:
            pass
        finally:
            curses.reset_prog_mode()
            try:
                curses.curs_set(0)
            except curses.error:
                pass
            self.stdscr.clear()
            self.stdscr.refresh()
        self.status_msg = f"Last played: {item.title}"

    def handle_search_key(self, ch) -> bool:
        list_h = self.get_list_height()
        if ch in ("\x1b", 27):
            self.search_mode = False
            return True
        if ch in (curses.KEY_ENTER, "\n", "\r", 10, 13):
            self.search_mode = False
            return True
        if ch in (curses.KEY_UP,):
            self.cursor -= 1
            self.clamp_cursor(list_h)
            return True
        if ch in (curses.KEY_DOWN,):
            self.cursor += 1
            self.clamp_cursor(list_h)
            return True
        if ch == curses.KEY_NPAGE:
            self.cursor += list_h
            self.clamp_cursor(list_h)
            return True
        if ch == curses.KEY_PPAGE:
            self.cursor -= list_h
            self.clamp_cursor(list_h)
            return True
        if ch in (curses.KEY_BACKSPACE, "\x7f", "\b", 127, 8):
            if self.query:
                self.query = self.query[:-1]
                self.apply_filters(reset_cursor=True)
            return True
        if ch in ("\x15", 21):  # Ctrl-U clears search
            self.query = ""
            self.apply_filters(reset_cursor=True)
            return True
        if ch in ("\t", 9):  # Tab cycles category even while searching
            cats = ("video", "audio", "all")
            self.category = cats[(cats.index(self.category) + 1) % len(cats)]
            self.apply_filters(reset_cursor=True)
            return True
        if isinstance(ch, str) and ch.isprintable():
            self.query += ch
            self.apply_filters(reset_cursor=True)
            return True
        if isinstance(ch, int) and 32 <= ch <= 126:
            self.query += chr(ch)
            self.apply_filters(reset_cursor=True)
            return True
        return True

    def run(self) -> int:
        curses.mousemask(curses.ALL_MOUSE_EVENTS | curses.REPORT_MOUSE_POSITION)
        while True:
            self.draw()
            try:
                ch = self.stdscr.get_wch()
            except curses.error:
                continue
            except KeyboardInterrupt:
                return 130

            if ch == curses.KEY_RESIZE:
                curses.update_lines_cols()
                continue

            if self.search_mode:
                self.handle_search_key(ch)
                continue

            list_h = self.get_list_height()

            # Navigation & Commands
            if ch in ("q", "Q"):
                return 0
            elif ch in ("\x1b", 27):
                if self.query:
                    self.query = ""
                    self.apply_filters(reset_cursor=True)
                    self.status_msg = "Cleared filter"
                else:
                    return 0
            elif ch == "/":
                self.search_mode = True
            elif ch in (curses.KEY_DOWN, "j"):
                self.cursor += 1
            elif ch in (curses.KEY_UP, "k"):
                self.cursor -= 1
            elif ch in (curses.KEY_NPAGE, " ", "\x04", 4):  # PgDn, Space, Ctrl-D
                self.cursor += list_h
            elif ch in (curses.KEY_PPAGE, "\x15", 21):  # PgUp, Ctrl-U
                self.cursor -= list_h
            elif ch in (curses.KEY_HOME, "g"):
                self.cursor = 0
            elif ch in (curses.KEY_END, "G"):
                self.cursor = max(0, len(self.hits) - 1)
            elif ch in (curses.KEY_ENTER, "\n", "\r", 10, 13, "l", curses.KEY_RIGHT):
                self.play_selected()
            elif ch == "\t" or ch == 9:
                cats = ("video", "audio", "all")
                self.category = cats[(cats.index(self.category) + 1) % len(cats)]
                self.apply_filters(reset_cursor=True)
                self.status_msg = f"Category: {self.category}"
            elif ch in ("v", "V"):
                self.category = "video"
                self.apply_filters(reset_cursor=True)
            elif ch in ("a", "A"):
                self.category = "audio"
                self.apply_filters(reset_cursor=True)
            elif ch == "d":
                idx = (self.drives.index(self.drive_filter) + 1) % len(self.drives)
                self.drive_filter = self.drives[idx]
                self.apply_filters(reset_cursor=True)
                self.status_msg = f"Drive filter: {self.drive_filter}"
            elif ch == "s":
                self.sort_idx = (self.sort_idx + 1) % len(SORT_MODES)
                self.sort_reverse = False
                self.apply_filters(reset_cursor=True)
                self.status_msg = f"Sorted by {SORT_MODES[self.sort_idx]}"
            elif ch == "S":
                self.sort_reverse = not self.sort_reverse
                self.apply_filters(reset_cursor=True)
                self.status_msg = f"Reversed {SORT_MODES[self.sort_idx]} sort"
            elif ch == "i":
                self.show_inspector = not self.show_inspector
            elif ch == "r":
                self.reload_catalog()
                self.apply_filters(reset_cursor=False)
            elif ch == curses.KEY_MOUSE:
                try:
                    _, _, my, _, bstate = curses.getmouse()
                    if bstate & curses.BUTTON4_PRESSED:
                        self.cursor -= 3
                    elif bstate & getattr(curses, "BUTTON5_PRESSED", 0x200000):
                        self.cursor += 3
                    elif bstate & (curses.BUTTON1_CLICKED | curses.BUTTON1_PRESSED | curses.BUTTON1_DOUBLE_CLICKED):
                        clicked_idx = self.top + (my - 3)
                        if 3 <= my < 3 + list_h and 0 <= clicked_idx < len(self.hits):
                            if self.cursor == clicked_idx and (bstate & curses.BUTTON1_DOUBLE_CLICKED):
                                self.play_selected()
                            else:
                                self.cursor = clicked_idx
                except curses.error:
                    pass

            self.clamp_cursor(list_h)


def main() -> int:
    locale.setlocale(locale.LC_ALL, "")
    os.environ.setdefault("ESCDELAY", "25")

    args = sys.argv[1:]
    base_url = DEFAULT_URL
    cat = "video"
    query_parts: List[str] = []

    i = 0
    while i < len(args):
        if args[i] == "--url" and i + 1 < len(args):
            base_url = args[i + 1].rstrip("/")
            i += 2
        elif args[i] in ("-a", "--audio"):
            cat = "audio"
            i += 1
        elif args[i] in ("-v", "--video"):
            cat = "video"
            i += 1
        elif args[i] in ("-A", "--all"):
            cat = "all"
            i += 1
        elif args[i] in ("-h", "--help"):
            print("Usage: mplay [-v|--video] [-a|--audio] [-A|--all] [--url http://host:8200] [search query]")
            return 0
        else:
            query_parts.append(args[i])
            i += 1

    initial_query = " ".join(query_parts)

    def _run_curses(stdscr):
        app = MplayTUI(stdscr, base_url=base_url, initial_cat=cat, initial_query=initial_query)
        return app.run()

    try:
        return curses.wrapper(_run_curses)
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    sys.exit(main())
