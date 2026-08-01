#!/bin/sh
# Installer for newsboat-podcasts.
#
#   ./install.sh              install into ~/.local (no root needed)
#   ./install.sh --uninstall  remove again
#
# Nothing outside the two target directories is touched, and your newsboat
# configuration is never edited automatically — the snippets to paste are
# printed at the end.

set -e

BIN="${BIN:-$HOME/.local/bin}"
LIB="${LIB:-$HOME/.local/lib/newsboat-podcasts}"
BAR="${BAR:-$HOME/.local/bin/statusbar}"
SRC="$(cd "$(dirname "$0")" && pwd)"

SCRIPTS="podplay podget podseek podtimer podsock mpvpod mpvpod-run"

if [ "$1" = "--uninstall" ]; then
	for s in $SCRIPTS; do rm -f "$BIN/$s"; done
	rm -f "$BAR/sb-podcast"
	rm -rf "$LIB"
	echo "Removed."
	exit 0
fi

# ── dependencies ───────────────────────────────────────────────────────────
missing=""
for c in newsboat mpv socat; do
	command -v "$c" >/dev/null 2>&1 || missing="$missing $c"
done
[ -n "$missing" ] && { echo "Missing required programs:$missing"; exit 1; }

for c in playerctl notify-send tsp; do
	command -v "$c" >/dev/null 2>&1 || echo "optional program not found: $c"
done
mpris_found=""
for p in /etc/mpv/scripts/mpris.so /usr/lib/mpv-mpris/mpris.so \
         /usr/lib/mpv/mpris.so /usr/local/lib/mpv/mpris.so \
         "$HOME/.config/mpv/scripts/mpris.so"; do
	[ -f "$p" ] && { mpris_found="$p"; break; }
done
[ -z "$mpris_found" ] &&
	echo "optional: install mpv-mpris for media-key / headset-button control"

# ── install ────────────────────────────────────────────────────────────────
mkdir -p "$BIN" "$LIB" "$BAR"
cp "$SRC/lib/podcast-common.sh" "$LIB/"

for s in $SCRIPTS; do
	sed "s|\${PODCAST_LIB:-/usr/local/lib/newsboat-podcasts}|\${PODCAST_LIB:-$LIB}|" \
		"$SRC/scripts/$s" > "$BIN/$s"
	chmod +x "$BIN/$s"
done

sed "s|\${PODCAST_LIB:-/usr/local/lib/newsboat-podcasts}|\${PODCAST_LIB:-$LIB}|" \
	"$SRC/scripts/sb-podcast" > "$BAR/sb-podcast"
chmod +x "$BAR/sb-podcast"

case ":$PATH:" in
	*":$BIN:"*) ;;
	*) echo; echo "NOTE: $BIN is not in your PATH." ;;
esac

cat <<EOF

Installed into $BIN (status bar block: $BAR).

Add these two lines to ~/.config/newsboat/config:

    macro m pipe-to "podplay"   -- "play this episode"
    macro l pipe-to "podget"    -- "download this episode"

Then select an episode in newsboat and press , m  (comma, then m).

Optional settings in ~/.config/newsboat-podcasts.conf:

    PODCAST_DIR="\$HOME/Podcasts"   # download folder
    PODCAST_TIMER=30                # sleep timer in minutes, 0 = off
    PODCAST_SEEK=30                 # seek step in seconds

The i3blocks block and key bindings are described in the README.
EOF
