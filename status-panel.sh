#!/usr/bin/env bash
#
# wm-panel - click-on-a-bar-segment dropdown for sway and hyprland.
#
# A bar segment can only be so wide, so each one shows a summary and
# defers the detail to a click. Where that detail appears matters: a
# terminal window is a separate surface that has to be closed again,
# and a TUI that exits on its own (cal, and anything that reads stdin
# until EOF) flickers away before it can be read.
#
# So the detail is shown in a wofi dropdown instead: it opens already
# positioned under the bar, and Escape closes it. Each segment gets its
# own content, so CPU and memory no longer open the same program.
#
#   --section net|disk|cpu|mem|time   which panel to show (default net)
#   --list                           print the entries instead of showing
#                                   them; used by the build-time check
#   --dry-run                        print the wofi command line instead
#                                   of running it
#
# As with status-line.sh, probe failures are normal and must not abort
# anything, so -e is deliberately not set.
set -uo pipefail

: "${WM_C_BG:=#1c1c1c}"
: "${WM_C_FG:=#9e9e9e}"
: "${WM_C_DIM:=#767676}"
: "${WM_C_BLUE:=#5f87af}"
: "${WM_C_CYAN:=#5f8787}"
: "${WM_C_GREEN:=#5faf5f}"
: "${WM_C_YELLOW:=#af875f}"
: "${WM_C_RED:=#af5f5f}"

STATE_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/wm-status"
# Deliberately NOT status-line.sh's net_counters file. That one stores
# "rx tx"; this one stores "timestamp rx tx" so a rate can be computed on
# a click without waiting for a second sample. Sharing the file made the
# two scripts alternate formats and the bar's own speed calculation then
# read the timestamp as a byte count.
NET_FILE="$STATE_DIR/net_counters_panel"
NET_WINDOW=2

# Escape anything interpolated into pango markup. An interface name or
# mount point containing & or < would otherwise blank the panel.
esc() {
  case "$1" in
    *'&'* | *'<'* | *'>'*)
      printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
      ;;
    *) printf '%s' "$1" ;;
  esac
}

repeat() {
  local char="$1" count="$2" out=""
  [ "${count:-0}" -gt 0 ] 2>/dev/null || { printf ''; return; }
  while [ "$count" -gt 0 ]; do
    out="$out$char"
    count=$((count - 1))
  done
  printf '%s' "$out"
}

# "  ██████░░░░  42%" - a bar of the given width, coloured by level.
bar() {
  local pct="${1:-0}" width="${2:-20}" filled empty colour
  pct="${pct%%%}"
  case "$pct" in
    '' | *[!0-9.]*) pct=0 ;;
  esac
  pct="${pct%%.*}"

  if [ "$pct" -ge 90 ]; then colour="$WM_C_RED"
  elif [ "$pct" -ge 75 ]; then colour="$WM_C_YELLOW"
  else colour="$WM_C_GREEN"
  fi

  filled=$((pct * width / 100))
  [ "$filled" -gt "$width" ] && filled=$width
  empty=$((width - filled))

  printf '<span foreground="%s">%s</span><span foreground="%s">%s</span> <span foreground="%s">%s%%</span>' \
    "$colour" "$(repeat '█' "$filled")" \
    "$WM_C_DIM" "$(repeat '░' "$empty")" \
    "$colour" "$pct"
}

# Thresholds in one place: green below warn, yellow to crit, red above.
level() {
  local value="$1" warn="$2" crit="$3" dim="$4" text="$5" colour
  case "$value" in
    '' | *[!0-9.]*) colour="$dim" ;;
    *)
      if [ "$value" -ge "$crit" ] 2>/dev/null; then colour="$WM_C_RED"
      elif [ "$value" -ge "$warn" ] 2>/dev/null; then colour="$WM_C_YELLOW"
      else colour="$WM_C_GREEN"
      fi
      ;;
  esac
  printf '<span foreground="%s">%s</span>' "$colour" "$(esc "$text")"
}

# Bold label, used for the small headings inside a panel.
span() {
  printf '<span foreground="%s">%s</span>' "$1" "$(esc "${2:-}")"
}

human_kib() {
  local kib="${1:-0}"
  if [ "${kib:-0}" -gt 1048576 ] 2>/dev/null; then
    printf '%d.%dG' $((kib / 1048576)) $(((kib % 1048576) * 10 / 1048576))
  elif [ "${kib:-0}" -gt 1024 ] 2>/dev/null; then
    printf '%d.%dM' $((kib / 1024)) $(((kib % 1024) * 10 / 1024))
  else
    printf '%dK' "$kib"
  fi
}

# ---------------------------------------------------------------------
# Panels
# ---------------------------------------------------------------------

panel_net() {
  printf '<span foreground="%s" size="large">Network</span>\n' "$WM_C_BLUE"

  local route
  route=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $5; exit}')
  if [ -z "$route" ]; then
    printf '<span foreground="%s">  no route to the internet</span>\n' "$WM_C_DIM"
  else
    printf '  via <span foreground="%s">%s</span>\n' "$WM_C_CYAN" "$(esc "$route")"
  fi

  printf '\n'
  printf '  %s\n' "$(span "$WM_C_DIM" 'interfaces')"
  ip -o addr show 2>/dev/null |
    grep -v ' state DOWN' | awk '$2 != "lo" {print $2}' | sort -u |
    while read -r dev; do
      [ -n "$dev" ] || continue
      local ipv4 state mtu
      ipv4=$(ip -4 -o addr show dev "$dev" 2>/dev/null |
        awk '{split($4, a, "/"); print a[1]; exit}')
      state=$(cat "/sys/class/net/$dev/operstate" 2>/dev/null)
      mtu=$(cat "/sys/class/net/$dev/mtu" 2>/dev/null)
      local colour="$WM_C_GREEN"
      [ "$state" = "up" ] || colour="$WM_C_DIM"
      printf '    %s %s %s\n' \
        "$(span "$colour" "$(printf '%-10s' "$(esc "$dev")")")" \
        "$(esc "${ipv4:-no IPv4}")" \
        "$(span "$WM_C_DIM" "${state:-?}${mtu:+, mtu $mtu}")"
    done

  printf '\n'
  printf '  %s\n' "$(span "$WM_C_DIM" 'throughput')"
  local total=0
  if [ -n "$route" ] && [ -r "/sys/class/net/$route/statistics/rx_bytes" ]; then
    local now prev
    now=$(date +%s)
    local rx tx
    rx=$(cat "/sys/class/net/$route/statistics/rx_bytes" 2>/dev/null)
    tx=$(cat "/sys/class/net/$route/statistics/tx_bytes" 2>/dev/null)
    if [ -r "$NET_FILE" ]; then
      local pnow prx ptx
      read -r pnow prx ptx <"$NET_FILE" 2>/dev/null || :
      if [ -n "${pnow:-}" ] && [ "${now}" -gt "${pnow}" ] 2>/dev/null; then
        local dt=$((now - pnow))
        [ "$dt" -gt 0 ] || dt=1
        # rx_bytes/tx_bytes are bytes, so the delta over dt is bytes per
        # second. human_kib formats KiB, and is shared with the memory
        # panel where the input really is KiB, so convert here: divide by
        # dt * 1024 to get KiB/s. Same arithmetic as status-line.sh, which
        # divides by POLL_INTERVAL * 1024.
        printf '    %s  %s\n' \
          "$(span "$WM_C_DIM" 'recv')" \
          "$(span "$WM_C_GREEN" "$(human_kib $(((rx - prx) / (dt * 1024))))/s")"
        printf '    %s  %s\n' \
          "$(span "$WM_C_DIM" 'send')" \
          "$(span "$WM_C_BLUE" "$(human_kib $(((tx - ptx) / (dt * 1024))))/s")"
        total=1
      fi
    fi
    mkdir -p "$STATE_DIR" 2>/dev/null
    printf '%s %s %s' "$now" "$rx" "$tx" >"$NET_FILE" 2>/dev/null
  fi
  [ "$total" = "1" ] ||
    printf '    <span foreground="%s">sampling, click again for a rate</span>\n' "$WM_C_DIM"

  printf '\n'
  printf '  %s %s\n' "$(span "$WM_C_DIM" 'established:')" \
    "$(span "$WM_C_FG" "$(ss -tua state established 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')")"
  printf '  %s %s\n' "$(span "$WM_C_DIM" 'listening:')" \
    "$(span "$WM_C_FG" "$(ss -tul state listening 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')")"
}

panel_disk() {
  printf '<span foreground="%s" size="large">Storage</span>\n' "$WM_C_YELLOW"
  printf '\n'

  df -h --output=target,pcent,size,used,avail \
    -x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs 2>/dev/null |
    tail -n +2 | while read -r target pcent size used avail; do
      [ -n "$target" ] || continue
      printf '  %s\n' "$(span "$WM_C_FG" "$target")"
      printf '    %s  %s\n' "$(bar "$pcent")" \
        "$(span "$WM_C_DIM" "$used of $size used, $avail free")"
      printf '\n'
    done

  # Largest subdirectories, so the panel answers "what is filling this
  # up" rather than restating the df line the bar already shows.
  local top_home="${HOME:-/tmp}"
  if command -v dust >/dev/null 2>&1; then
    printf '  %s\n' "$(span "$WM_C_DIM" 'largest in home:')"
    dust -d 1 -n 6 -b -r "$top_home" 2>/dev/null |
      head -n 8 | while read -r line; do
        [ -n "$line" ] && printf '    <span foreground="%s">%s</span>\n' "$WM_C_FG" "$(esc "$line")"
      done
  fi
}

panel_cpu() {
  printf '<span foreground="%s" size="large">CPU</span>\n' "$WM_C_GREEN"

  local usage cores
  usage=$(top -bn1 2>/dev/null | grep -E 'Cpu\(s\)|%Cpu' | head -n1 |
    awk '{
      for (i = 2; i <= NF; i++) {
        v = ""
        if ($i ~ /^id,$/) v = $(i - 1)
        else if ($i == "id" || $i == "%id") v = $(i + 1)
        if (v != "") { g = v; gsub(/[^0-9.]/, "", g)
          if (g != "") { print int(100 - g); exit } }
      }
    }')
  usage="${usage:-0}"
  cores=$(grep -c ^processor /proc/cpuinfo 2>/dev/null)
  cores="${cores:-?}"

  printf '  %s\n' "$(span "$WM_C_FG" "$usage% of $cores cores")"
  printf '  %s\n\n' "$(bar "$usage")"

  local load
  load=$(awk '{print $1" "$2" "$3}' /proc/loadavg 2>/dev/null)
  printf '  %s %s\n' "$(span "$WM_C_DIM" 'load:')" "$(span "$WM_C_FG" "$load")"

  local temp
  for zone in /sys/class/thermal/thermal_zone*/temp; do
    [ -r "$zone" ] || continue
    temp=$(( $(cat "$zone") / 1000 ))
    break
  done
  [ -n "${temp:-}" ] && printf '  %s %s\n' "$(span "$WM_C_DIM" 'temp:')" \
    "$(level "$temp" 65 80 "$WM_C_DIM" "${temp}°C")"

  printf '\n  %s\n' "$(span "$WM_C_DIM" 'busiest processes')"
  ps -eo pcpu,rss,comm --sort=-pcpu 2>/dev/null | head -n 8 |
    tail -n +2 | while read -r pcpu rss comm; do
      [ -n "${comm:-}" ] || continue
      printf '    <span foreground="%s">%5s%%</span>  %s  %s\n' \
        "$WM_C_GREEN" "$pcpu" \
        "$(span "$WM_C_FG" "$comm")" \
        "$(span "$WM_C_DIM" "$(human_kib "$rss")")"
    done
}

panel_mem() {
  printf '<span foreground="%s" size="large">Memory</span>\n' "$WM_C_BLUE"

  local total used avail pct
  read -r total used avail pct <<<"$(free -h | awk '/^Mem:/ {
    t = $2; u = $3; a = $7; sub(/G$/, "", t); sub(/G$/, "", u); sub(/G$/, "", a)
    p = $2 + 0 ? (u / t) * 100 : 0
    printf "%d %d %d %d", t, u, a, p
  }')"
  total="${total:-0}"; used="${used:-0}"; avail="${avail:-0}"; pct="${pct:-0}"

  printf '  %s\n' "$(span "$WM_C_FG" "${used}G of ${total}G used")"
  printf '  %s\n\n' "$(bar "$pct")"

  printf '  %s %s\n' "$(span "$WM_C_DIM" 'free:')" \
    "$(span "$WM_C_FG" "${avail}G available")"

  local swap
  read -r swap <<<"$(free -h | awk '/^Swap:/ {s = $2; sub(/G$/, "", s); print s + 0}')"
  printf '  %s %s\n' "$(span "$WM_C_DIM" 'swap:')" \
    "$(span "$WM_C_FG" "${swap:-0}G swap")"

  local bat
  for d in /sys/class/power_supply/BAT*; do
    [ -d "$d" ] || continue
    bat="$(cat "$d/capacity" 2>/dev/null)% $(cat "$d/status" 2>/dev/null)"
    break
  done
  [ -n "${bat:-}" ] && printf '  %s %s\n' \
    "$(span "$WM_C_DIM" 'battery:')" "$(span "$WM_C_YELLOW" "$bat")"

  printf '\n  %s\n' "$(span "$WM_C_DIM" 'largest processes')"
  ps -eo pcpu,rss,comm --sort=-rss 2>/dev/null | head -n 8 |
    tail -n +2 | while read -r pcpu rss comm; do
      [ -n "${comm:-}" ] || continue
      printf '    %s  %s\n' \
        "$(span "$WM_C_FG" "$comm")" \
        "$(span "$WM_C_YELLOW" "$(human_kib "$rss")")"
    done
}

panel_time() {
  printf '<span foreground="%s" size="large">%s</span>\n' "$WM_C_FG" "$(date +'%A, %d %B %Y %I:%M:%S %p')"

  if command -v cal >/dev/null 2>&1; then
    cal 2>/dev/null | while read -r line; do
      [ -n "$line" ] && printf '  <span foreground="%s">%s</span>\n' "$WM_C_CYAN" "$(esc "$line")"
    done
  fi

  printf '\n'
  printf '  %s %s\n' "$(span "$WM_C_DIM" 'uptime:')" \
    "$(span "$WM_C_FG" "$(awk '{m = int($1/60); h = int(m/60); d = int(h/24)
       printf "%dd %dh %dm", d, h%24, m%60}' /proc/uptime 2>/dev/null)")"
  printf '  %s %s\n' "$(span "$WM_C_DIM" 'kernel:')" \
    "$(span "$WM_C_FG" "$(uname -r 2>/dev/null)")"
  printf '  %s %s\n' "$(span "$WM_C_DIM" 'shell: ')" \
    "$(span "$WM_C_FG" "${SHELL##*/}")"
}

# ---------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------
SECTION=net
LIST_ONLY=0
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --section)
      [ $# -ge 2 ] || { printf 'wm-panel: --section requires an argument\n' >&2; exit 2; }
      shift
      SECTION="$1"
      ;;
    --list) LIST_ONLY=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h | --help)
      printf 'usage: %s [--section net|disk|cpu|mem|time] [--list] [--dry-run]\n' \
        "$(basename "$0")"
      exit 0
      ;;
    *)
      printf 'wm-panel: unknown option %s\n' "$1" >&2
      exit 2
      ;;
  esac
  shift
done

render_panel() {
  case "$SECTION" in
    net) panel_net ;;
    disk) panel_disk ;;
    cpu) panel_cpu ;;
    mem) panel_mem ;;
    time) panel_time ;;
    *)
      printf 'wm-panel: unknown section %s\n' "$SECTION" >&2
      exit 2
      ;;
  esac
}

# Rendered once, up front. The content is captured rather than streamed
# so it can be fed to wofi below: wofi in dmenu mode reads its list on
# stdin, so printing the panel and then exec'ing wofi would send the
# panel to the caller and leave wofi waiting on the wrong file
# descriptor.
PANEL_CONTENT=$(render_panel)

if [ "$LIST_ONLY" = "1" ]; then
  printf '%s\n' "$PANEL_CONTENT"
  exit 0
fi

# ---------------------------------------------------------------------
# Presentation
#
# wofi in dmenu mode is used purely as a surface: entries in, nothing
# submitted. --no-custom-entry and --hide-search keep it from looking
# like a launcher, and it stays open until Escape.
# ---------------------------------------------------------------------
PANEL_WIDTH=560
PANEL_MAX_LINES=22

# Waybar's on-click gives a handler no pointer position, so the panel
# cannot be pinned to the segment that was clicked. It is anchored to
# the top of the focused monitor and centred horizontally, which puts it
# directly under the bar rather than in the middle of the screen: with no
# --location wofi centres vertically, and --xoffset/--yoffset are then
# applied from that centre, so the y offset has to be a real anchor to be
# the 34px under the bar that is wanted here.
PANEL_X="${WM_PANEL_X:-0}"
PANEL_Y="${WM_PANEL_Y:-34}"

# Resolved at build time by the Nix wrapper, so a missing wofi fails the
# build rather than making every click a no-op.
WOFI="${WM_PANEL_WOFI:-wofi}"

if ! [ -x "$WOFI" ] && ! command -v "$WOFI" >/dev/null 2>&1; then
  printf 'wm-panel: wofi not found at %s\n' "$WOFI" >&2
  exit 127
fi

# Height follows the content instead of being a fixed 22 rows, so the
# short panels (the calendar) do not open as a mostly-empty box.
PANEL_LINES=$(printf '%s\n' "$PANEL_CONTENT" | wc -l | tr -d ' ')
[ "$PANEL_LINES" -gt 0 ] 2>/dev/null || PANEL_LINES=8
[ "$PANEL_LINES" -gt "$PANEL_MAX_LINES" ] && PANEL_LINES=$PANEL_MAX_LINES

# wofi has no single-instance behaviour in dmenu mode. Clicking a second
# segment while a panel is open would stack a second window in exactly the
# same spot, and closing the top one would reveal a stale panel that is
# still holding keyboard focus and still showing old numbers. So before
# opening, any panel we opened earlier is closed first.
#
# The pid is validated against /proc before it is signalled: a pidfile left
# behind by a crashed panel can name a pid that the kernel has since handed
# to something unrelated, and this script is being run from a click handler.
PANEL_PID_FILE="$STATE_DIR/panel.pid"

close_open_panel() {
  local pid cmd waited=0
  [ -r "$PANEL_PID_FILE" ] || return 0
  pid=$(cat "$PANEL_PID_FILE" 2>/dev/null) || pid=""
  case "$pid" in
    '' | *[!0-9]*)
      rm -f "$PANEL_PID_FILE"
      return 0
      ;;
  esac
  if ! kill -0 "$pid" 2>/dev/null; then
    rm -f "$PANEL_PID_FILE"
    return 0
  fi
  cmd=$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null) || cmd=""
  case "$cmd" in
    # Not one of ours: the pid was recycled, so the file is simply stale.
    *wofi-panel-style*) kill "$pid" 2>/dev/null ;;
    *)
      rm -f "$PANEL_PID_FILE"
      return 0
      ;;
  esac
  # Wait for it to unmap its layer surface, so the old one is not still on
  # screen behind the new one.
  while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 20 ]; do
    sleep 0.05
    waited=$((waited + 1))
  done
  kill -9 "$pid" 2>/dev/null
  rm -f "$PANEL_PID_FILE"
}

if [ "$DRY_RUN" = "1" ]; then
  printf '%s \\\n' "$WOFI" \
    --dmenu --allow-markup --no-custom-entry --hide-search --hide-scroll \
    --location top --width "$PANEL_WIDTH" --lines "$PANEL_LINES" \
    --xoffset "$PANEL_X" --yoffset "$PANEL_Y" --gtk-dark
  exit 0
fi

# --allow-markup is what lets the panels above use colour; --dmenu makes
# wofi read the list on stdin instead of showing its own modes. The
# captured panel is piped in, and the script exits with wofi's status.
# No --normal-window: it is a layer-shell surface, so it behaves like a
# dropdown (anchored, above other windows, no taskbar entry) rather than
# a floating window that has to be given focus.
mkdir -p "$STATE_DIR" 2>/dev/null
close_open_panel
printf '%s\n' "$PANEL_CONTENT" | "$WOFI" \
  --dmenu \
  --allow-markup \
  --no-custom-entry \
  --hide-search \
  --hide-scroll \
  --location top \
  --width "$PANEL_WIDTH" \
  --lines "$PANEL_LINES" \
  --xoffset "$PANEL_X" \
  --yoffset "$PANEL_Y" \
  --gtk-dark &
WOFI_PID=$!
printf '%s\n' "$WOFI_PID" >"$PANEL_PID_FILE" 2>/dev/null
wait "$WOFI_PID"
STATUS=$?
# Only clear the file if it is still ours: a panel opened in the meantime
# will have overwritten it, and removing that would orphan it.
if [ "$(cat "$PANEL_PID_FILE" 2>/dev/null)" = "$WOFI_PID" ]; then
  rm -f "$PANEL_PID_FILE" 2>/dev/null
fi
exit "$STATUS"
