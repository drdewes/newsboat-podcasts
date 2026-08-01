# Shared helpers for the newsboat-podcasts scripts.
# Sourced, never executed. POSIX sh.
#
# Gemeinsame Funktionen für die newsboat-podcasts-Skripte.
# Wird eingebunden, nicht ausgeführt.

# ── Settings / Einstellungen ────────────────────────────────────────────────
# Override any of these in ~/.config/newsboat-podcasts.conf
POD_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/newsboat-podcasts.conf"
[ -r "$POD_CONF" ] && . "$POD_CONF"

POD_DIR="${PODCAST_DIR:-$HOME/Podcasts}"          # download folder
POD_TIMER_MIN="${PODCAST_TIMER:-30}"              # sleep timer, 0 = off
POD_SEEK="${PODCAST_SEEK:-30}"                    # seek step in seconds
POD_SIGNAL="${PODCAST_I3BLOCKS_SIGNAL:-27}"       # i3blocks refresh signal
POD_PLAYER_OPTS="${PODCAST_MPV_OPTS:-}"           # extra mpv options

POD_RUN="${XDG_RUNTIME_DIR:-/tmp}"
POD_PIDF="$POD_RUN/mpv-podcast.pid"
POD_TPID="$POD_RUN/mpv-podcast.timer.pid"
POD_TEND="$POD_RUN/mpv-podcast.timer.end"
POD_SOCK="$POD_RUN/mpv-podcast.sock"
POD_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"
POD_LOG="$POD_CACHE/mpvpod.log"
POD_MPVLOG="$POD_CACHE/mpvpod-mpv.log"
POD_MARK="--script-opts=podcast=yes"              # marks "our" mpv process

# ── Language / Sprache ──────────────────────────────────────────────────────
# German when the session is German, English otherwise.
# Force with PODCAST_LANG=en or PODCAST_LANG=de.
case "${PODCAST_LANG:-$LANG}" in
	[dD][eE]*) POD_DE=1 ;;
	*)         POD_DE=0 ;;
esac

# say <english> <german>
say() { [ "$POD_DE" = 1 ] && printf '%s' "$2" || printf '%s' "$1"; }

# ── Helpers ─────────────────────────────────────────────────────────────────

# Refresh the i3blocks status bar (harmless if i3blocks is not running).
pod_refresh() { pkill "-RTMIN+$POD_SIGNAL" i3blocks 2>/dev/null; return 0; }

# Seconds -> h:mm:ss or m:ss
pod_time() {
	s="${1%%.*}"
	case "$s" in ''|*[!0-9]*) return ;; esac
	if [ "$s" -ge 3600 ]; then
		printf '%d:%02d:%02d' $((s / 3600)) $((s % 3600 / 60)) $((s % 60))
	else
		printf '%d:%02d' $((s / 60)) $((s % 60))
	fi
}

# Extract the enclosure URL from an article newsboat piped to us.
#
# newsboat writes    Podcast Download URL: https://…/ep.mp3 (type: audio/mpeg)
# and in German      Podcast-Download-URL: https://…/ep.mp3 (Typ: audio/mpeg)
# The trailing type is only present when the feed declares one — which is why
# half of all podcasts appear to work and the other half do not. Everything
# after the first blank must go.
pod_url_from_article() {
	_txt="$1"
	_url="$(printf '%s\n' "$_txt" |
		sed -n 's/^[Pp]odcast[- ][Dd]ownload[- ]URL: *//p' | head -1)"
	[ -z "$_url" ] && _url="$(printf '%s\n' "$_txt" |
		grep -oE 'https?://[^ ]+\.(mp3|m4a|mp4|ogg|opus|aac|flac|wav)([?][^ ]*)?' | head -1)"
	printf '%s' "${_url%% *}"
}

# Field out of the article header ("Title:" / "Titel:", "Feed:")
pod_field() {
	printf '%s\n' "$2" | sed -n "s/^$1: *//p" | head -1
}

# Is this pid our podcast mpv?
pod_is_ours() {
	[ "$(cat "/proc/$1/comm" 2>/dev/null)" = "mpv" ] || return 1
	tr '\0' ' ' < "/proc/$1/cmdline" 2>/dev/null | grep -q "podcast=yes"
}
