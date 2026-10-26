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
import re
import socket
import subprocess
import sys
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from typing import Callable, Dict, List, Optional, Set, Tuple

DEFAULT_URL = os.environ.get("DLNA_URL", "http://127.0.0.1:8200").rstrip("/")
KNOWN_HOSTS = {
    "localhost": "http://127.0.0.1:8200",
    "zits": "http://127.0.0.1:8200",
    "bufflehead": "http://192.168.12.93:8200",
}
FALLBACK_DIRS = [
    "/mnt/mybook",
    "/mnt/elements",
    "/mnt/toshiba",
    "/mnt/sdb1",
    "/mnt/sdc1",
    "/mnt/sdd1",
    "/mnt/wdblack",
]

ITEM_FILTER = (
    "dc:title,dc:date,upnp:class,res,res@size,res@duration,"
    "res@resolution,res@nrAudioChannels,res@sampleFrequency,"
    "res@bitrate,res@protocolInfo"
)

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


def normalize_dlna_url(raw: str) -> str:
    val = raw.strip().rstrip("/")
    if not val:
        return DEFAULT_URL
    low = val.lower()
    if low in KNOWN_HOSTS:
        return KNOWN_HOSTS[low]
    if "://" not in val:
        val = f"http://{val}"
    parsed = urllib.parse.urlsplit(val)
    host = parsed.hostname or ""
    port = parsed.port or 8200
    scheme = parsed.scheme or "http"
    if host.lower() in KNOWN_HOSTS:
        target = urllib.parse.urlsplit(KNOWN_HOSTS[host.lower()])
        host = target.hostname or host
        if not parsed.port and target.port:
            port = target.port
    return f"{scheme}://{host}:{port}"


def discover_dlna_servers(timeout: float = 0.8) -> List[Tuple[str, str]]:
    """Discover MiniDLNA / UPnP ContentDirectory servers via SSDP + known hosts."""
    locations: Set[str] = set()
    msg = (
        "M-SEARCH * HTTP/1.1\r\n"
        "HOST: 239.255.255.250:1900\r\n"
        'MAN: "ssdp:discover"\r\n'
        "MX: 1\r\n"
        "ST: urn:schemas-upnp-org:service:ContentDirectory:1\r\n\r\n"
    ).encode("utf-8")
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
        sock.settimeout(timeout)
        sock.sendto(msg, ("239.255.255.250", 1900))
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                data, _ = sock.recvfrom(4096)
            except socket.timeout:
                break
            text = data.decode("utf-8", errors="ignore")
            if "minidlna" not in text.lower() and ":8200" not in text:
                continue
            m = re.search(r"(?im)^LOCATION:\s*(http://[^\s\r\n]+)", text)
            if m:
                u = urllib.parse.urlsplit(m.group(1))
                if u.scheme and u.netloc:
                    locations.add(f"{u.scheme}://{u.netloc}")
        sock.close()
    except OSError:
        pass

    for known_url in KNOWN_HOSTS.values():
        locations.add(known_url)

    def probe(base: str) -> Optional[Tuple[str, str]]:
        try:
            req = urllib.request.Request(f"{base}/rootDesc.xml", method="GET")
            with urllib.request.urlopen(req, timeout=0.8) as resp:
                xml_bytes = resp.read()
            root = ET.fromstring(xml_bytes)
            fname_el = root.find(".//{urn:schemas-upnp-org:device-1-0}friendlyName")
            fname = fname_el.text.strip() if fname_el is not None and fname_el.text else base
            return (base, fname)
        except Exception:
            return None

    servers: List[Tuple[str, str]] = []
    seen_names: Dict[str, str] = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        for res in pool.map(probe, sorted(locations)):
            if res is not None:
                base, fname = res
                # Prefer 127.0.0.1 for local server if duplicate friendlyName
                if fname in seen_names:
                    if "127.0.0.1" in base:
                        servers = [(b, n) if n != fname else (base, fname) for b, n in servers]
                        seen_names[fname] = base
                else:
                    seen_names[fname] = base
                    servers.append((base, fname))
    servers.sort(key=lambda x: (0 if "127.0.0.1" in x[0] else 1, x[1].lower()))
    return servers


def soap_search_page(
    base_url: str,
    container_id: str,
    criteria: str,
    filter_str: str = "*",
    start: int = 0,
    count: int = 100000,
) -> Tuple[Optional[ET.Element], int, int]:
    """Execute one UPnP ContentDirectory#Search request and return (DIDL element, NumberReturned, TotalMatches)."""
    body = f"""<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:Search xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">
      <ContainerID>{container_id}</ContainerID>
      <SearchCriteria>{criteria}</SearchCriteria>
      <Filter>{filter_str}</Filter>
      <StartingIndex>{start}</StartingIndex>
      <RequestedCount>{count}</RequestedCount>
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
    with urllib.request.urlopen(req, timeout=8) as resp:
        xml_bytes = resp.read()

    env = ET.fromstring(xml_bytes)
    result_el = env.find(".//Result")
    num_ret = int(env.findtext(".//NumberReturned") or "0")
    tot_mat = int(env.findtext(".//TotalMatches") or "0")
    # MiniDLNA truncates responses exceeding 2MB (MAX_RESPONSE_SIZE = 2097152).
    # Even if a response occurs mid-scan where NumberReturned >= TotalMatches,
    # any response > 1.95MB was likely truncated by upnpsoap.c.
    truncated = len(xml_bytes) > 1_950_000 or (0 < num_ret < tot_mat)
    if result_el is None or not result_el.text or num_ret <= 0:
        return None, 0, tot_mat

    didl = ET.fromstring(result_el.text.encode("utf-8"))
    return didl, num_ret, (tot_mat if not truncated else max(tot_mat, start + num_ret + 1))


def soap_search_paginated(
    base_url: str,
    container_id: str,
    criteria: str,
    filter_str: str = "*",
    progress_cb: Optional[Callable[[str], None]] = None,
    label: str = "items",
) -> List[ET.Element]:
    """Fetch all pages for a UPnP Search query, automatically handling MiniDLNA's 2MB response truncation."""
    didl, num_ret, tot_mat = soap_search_page(base_url, container_id, criteria, filter_str, 0, 100000)
    if didl is None:
        return []
    pages = [didl]
    cur = num_ret
    while cur < tot_mat and num_ret > 0:
        if progress_cb:
            progress_cb(f"Loading {label} from {base_url} ({cur}/{tot_mat}) ...")
        didl_next, num_ret, _ = soap_search_page(
            base_url, container_id, criteria, filter_str, cur, 100000
        )
        if didl_next is None or num_ret <= 0:
            break
        pages.append(didl_next)
        cur += num_ret
    return pages


def soap_search_all(
    base_url: str,
    container_id: str = "64",
    category: str = "all",
    progress_cb: Optional[Callable[[str], None]] = None,
) -> List[MediaItem]:
    """Fetch containers and media items via UPnP Search with automatic 2MB truncation pagination."""
    if category == "all":
        didl, num_ret, tot_mat = soap_search_page(
            base_url,
            container_id,
            'upnp:class derivedfrom "object.container" or upnp:class derivedfrom "object.item"',
            "*",
            0,
            100000,
        )
        if didl is not None and num_ret >= tot_mat and tot_mat > 0:
            c_pages = [didl]
            item_pages = [didl]
        else:
            c_pages = []
            item_pages = []
    else:
        c_pages = []
        item_pages = []

    if not c_pages:
        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
            fut_c = pool.submit(
                soap_search_paginated,
                base_url,
                container_id,
                'upnp:class derivedfrom "object.container"',
                "dc:title",
                None,
                "folders",
            )
            fut_v = (
                pool.submit(
                    soap_search_paginated,
                    base_url,
                    container_id,
                    'upnp:class derivedfrom "object.item.videoItem"',
                    ITEM_FILTER,
                    progress_cb,
                    "videos",
                )
                if category in ("all", "video")
                else None
            )
            fut_a = (
                pool.submit(
                    soap_search_paginated,
                    base_url,
                    container_id,
                    'upnp:class derivedfrom "object.item.audioItem"',
                    ITEM_FILTER,
                    progress_cb,
                    "audio",
                )
                if category in ("all", "audio")
                else None
            )
            c_pages = fut_c.result()
            item_pages = []
            if fut_v is not None:
                item_pages.extend(fut_v.result())
            if fut_a is not None:
                item_pages.extend(fut_a.result())

    containers: Dict[str, Tuple[str, str]] = {}
    for page in c_pages:
        for c in page.findall("didl:container", NS):
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
    for page in item_pages:
        for it in page.findall("didl:item", NS):
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


def fetch_dlna_catalog(
    base_url: str,
    progress_cb: Optional[Callable[[str], None]] = None,
) -> List[MediaItem]:
    """Fetch complete DLNA catalog via UPnP Search (with pagination), falling back to recursive Browse."""
    for root_id in ("64", "0"):
        try:
            items = soap_search_all(base_url, root_id, category="all", progress_cb=progress_cb)
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


def load_catalog(
    base_url: str,
    progress_cb: Optional[Callable[[str], None]] = None,
) -> Tuple[List[MediaItem], str, float]:
    t0 = time.monotonic()
    norm_url = normalize_dlna_url(base_url)
    host_short = norm_url.replace("http://", "").replace("https://", "")
    parsed = urllib.parse.urlsplit(norm_url)
    is_local_target = (parsed.hostname or "") in ("127.0.0.1", "localhost", "::1")

    try:
        items = fetch_dlna_catalog(norm_url, progress_cb=progress_cb)
        if items:
            return items, f"MiniDLNA ({host_short})", (time.monotonic() - t0) * 1000.0
    except Exception:
        pass

    if is_local_target:
        items = fetch_local_catalog(FALLBACK_DIRS)
        return items, "Local Mounts", (time.monotonic() - t0) * 1000.0

    return [], f"Unreachable ({host_short})", (time.monotonic() - t0) * 1000.0


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
        self.base_url = normalize_dlna_url(base_url)
        self.category = initial_cat  # "video", "audio", "all"
        self.query = initial_query
        self.search_mode = False
        self.show_inspector = True
        self.drive_filter = "all"
        self.sort_idx = 0
        self.sort_reverse = False

        self.all_items: List[MediaItem] = []
        self.drives: List[str] = ["all"]
        self.servers: List[Tuple[str, str]] = []
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

    def _show_loading_progress(self, msg: str):
        try:
            _, cols = self.stdscr.getmaxyx()
            self.stdscr.erase()
            safe_addnstr(self.stdscr, 0, 0, f" {msg}", max(20, cols - 1), self.c_accent)
            self.stdscr.refresh()
        except curses.error:
            pass

    def reload_catalog(self):
        self._show_loading_progress(f"Loading media catalog from {self.base_url} ...")
        self.all_items, self.source_label, self.load_ms = load_catalog(
            self.base_url, progress_cb=self._show_loading_progress
        )
        drive_set = sorted({it.drive for it in self.all_items if it.drive})
        self.drives = ["all"] + drive_set
        if self.drive_filter not in self.drives:
            self.drive_filter = "all"
        if self.all_items:
            self.status_msg = f"Loaded {len(self.all_items)} items in {self.load_ms:.0f}ms"
        else:
            self.status_msg = f"No items loaded from {self.base_url} (press H to switch server)"

    def cycle_server(self):
        self._show_loading_progress("Discovering MiniDLNA servers on LAN ...")
        self.servers = discover_dlna_servers()
        if not self.servers:
            self.status_msg = "No MiniDLNA servers discovered on LAN"
            return
        urls = [u for u, _ in self.servers]
        if self.base_url in urls:
            idx = (urls.index(self.base_url) + 1) % len(urls)
        else:
            idx = 0
        self.base_url, fname = self.servers[idx]
        self.drive_filter = "all"
        self.reload_catalog()
        self.apply_filters(reset_cursor=True)
        self.status_msg = f"Server: {fname} ({self.base_url}) — {len(self.all_items)} items"

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
        drv = self.drive_filter
        drv_items = self.all_items if drv == "all" else [x for x in self.all_items if x.drive == drv]
        vid_cnt = sum(1 for x in drv_items if x.kind == "video")
        aud_cnt = sum(1 for x in drv_items if x.kind == "audio")
        all_cnt = len(drv_items)

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
        match_stats = f"{len(self.hits)}/{len(self.all_items)} items "
        stats_reserve = len(match_stats) + 2 if cols > len(match_stats) + 25 else 1
        max_q_width = max(5, cols - 4 - stats_reserve)
        if self.search_mode:
            prompt = " / "
            safe_addnstr(self.stdscr, 1, 0, prompt, cols, self.c_accent)
            q_disp = self.query[-max_q_width:] if len(self.query) > max_q_width else self.query
            safe_addnstr(self.stdscr, 1, len(prompt), q_disp, max_q_width, curses.A_BOLD)
        else:
            if self.query:
                safe_addnstr(self.stdscr, 1, 0, " Filter: ", cols, self.c_accent)
                safe_addnstr(self.stdscr, 1, 9, f'"{self.query}" (Esc to clear, / to edit)', max(1, cols - 10 - stats_reserve), curses.A_BOLD)
            else:
                safe_addnstr(self.stdscr, 1, 0, " Press / to search (multi-word fuzzy filter)...", cols, self.c_dim)

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

                prefix_cols = 46
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
                    try:
                        ch_info += f" {int(cur.sample_rate) // 1000}kHz"
                    except ValueError:
                        pass
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
            keys_help = " [/] Search  [Enter] Play  [Tab] Cat  [d] Drive  [H] Server  [s/S] Sort  [i] Info  [r] Reload  [q] Quit "
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
                q_vis_len = min(len(self.query), max_q_width)
                cx = min(cols - 1, 3 + q_vis_len)
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
            elif ch in ("H",):
                self.cycle_server()
            elif ch == curses.KEY_MOUSE:
                try:
                    _, mx, my, _, bstate = curses.getmouse()
                    if bstate & curses.BUTTON4_PRESSED:
                        self.cursor -= 3
                    elif bstate & getattr(curses, "BUTTON5_PRESSED", 0x200000):
                        self.cursor += 3
                    elif bstate & (curses.BUTTON1_CLICKED | curses.BUTTON1_PRESSED | curses.BUTTON1_DOUBLE_CLICKED):
                        if my == 0:
                            # Header bar click: switch tabs or cycle drive/sort
                            drv = self.drive_filter
                            drv_items = self.all_items if drv == "all" else [x for x in self.all_items if x.drive == drv]
                            vid_cnt = sum(1 for x in drv_items if x.kind == "video")
                            aud_cnt = sum(1 for x in drv_items if x.kind == "audio")
                            all_cnt = len(drv_items)

                            def _tab_str(name: str, label: str, count: int) -> str:
                                return f"[{label}:{count}]" if self.category == name else f" {label}:{count} "

                            t_vid = _tab_str("video", "Video", vid_cnt)
                            t_aud = _tab_str("audio", "Audio", aud_cnt)
                            t_all = _tab_str("all", "All", all_cnt)
                            x0 = len(" mplay │ ")
                            x1 = x0 + len(t_vid)
                            x2 = x1 + 1 + len(t_aud)
                            x3 = x2 + 1 + len(t_all)
                            if x0 <= mx < x1:
                                self.category = "video"
                                self.apply_filters(reset_cursor=True)
                            elif x1 + 1 <= mx < x2:
                                self.category = "audio"
                                self.apply_filters(reset_cursor=True)
                            elif x2 + 1 <= mx < x3:
                                self.category = "all"
                                self.apply_filters(reset_cursor=True)
                        elif my == 1:
                            self.search_mode = True
                        else:
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
        if args[i] in ("--url", "-u", "-H", "--host") and i + 1 < len(args):
            base_url = normalize_dlna_url(args[i + 1])
            i += 2
        elif args[i].startswith("--url="):
            base_url = normalize_dlna_url(args[i].split("=", 1)[1])
            i += 1
        elif args[i] in ("-b", "--bufflehead"):
            base_url = KNOWN_HOSTS["bufflehead"]
            i += 1
        elif args[i] in ("-z", "--zits", "--local"):
            base_url = KNOWN_HOSTS["zits"]
            i += 1
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
            print(
                "Usage: mplay [-v|--video] [-a|--audio] [-A|--all] "
                "[-b|--bufflehead] [-z|--zits] [--url|-H HOST_OR_URL] [search query]"
            )
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
