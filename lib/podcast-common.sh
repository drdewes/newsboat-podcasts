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
POD_RESUME="${PODCAST_RESUME:-1}"                 # remember the position, 0 = off
POD_SAVE_EVERY="${PODCAST_SAVE_EVERY:-60}"        # save it every N seconds, 0 = off

POD_RUN="${XDG_RUNTIME_DIR:-/tmp}"
POD_PIDF="$POD_RUN/mpv-podcast.pid"
POD_TPID="$POD_RUN/mpv-podcast.timer.pid"
POD_TEND="$POD_RUN/mpv-podcast.timer.end"
POD_SOCK="$POD_RUN/mpv-podcast.sock"
POD_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"
[ -d "$POD_CACHE" ] || mkdir -p "$POD_CACHE" 2>/dev/null   # XDG_CACHE_HOME may not exist
POD_LOG="$POD_CACHE/mpvpod.log"
POD_MPVLOG="$POD_CACHE/mpvpod-mpv.log"
POD_MARK="--script-opts=podcast=yes"              # marks "our" mpv process
POD_WATCH="${PODCAST_WATCH_DIR:-$POD_CACHE/newsboat-podcasts/watch_later}"

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

# ── Talking to the running mpv ──────────────────────────────────────────────
# Anyone can create a socket FILE; only a running mpv answers on it. The
# mpvSockets.lua script (LARBS and others) redirects the socket after mpv has
# already created ours, so testing for the file is not enough — we ask.

pod_answers() {
	[ -S "$1" ] || return 1
	printf '%s\n' '{"command":["get_property","pause"]}' |
		timeout 1 socat - "$1" >/dev/null 2>&1
}

# pod_sock_for <pid> -> prints the socket that mpv actually listens on
pod_sock_for() {
	pod_answers "$POD_SOCK"            && { printf '%s' "$POD_SOCK";            return 0; }
	pod_answers "/tmp/mpvSockets/$1"   && { printf '%s' "/tmp/mpvSockets/$1";   return 0; }
	return 1
}

# pod_ipc <socket> <json command>
pod_ipc() {
	printf '%s\n' "$2" | timeout 2 socat - "$1" >/dev/null 2>&1
}

# ── Resume / Weiterhören ────────────────────────────────────────────────────
# mpv writes one file per episode into $POD_WATCH, named after a hash we do not
# want to compute ourselves. --write-filename-in-watch-later-config puts the
# file name or URL into the file as a "# …" line, so we can simply look for it.
#
# Two things are worth knowing:
#   * SIGTERM does NOT write that file. Only a proper quit does, or the
#     write-watch-later-config command. That is why mpvpod asks mpv to quit.
#   * When an episode is heard to the end, mpv deletes its entry. No entry
#     therefore means "finished", not "never played".

# pod_saved_pos <file-or-url> -> seconds, or nothing
pod_saved_pos() {
	[ "$POD_RESUME" = 1 ] || return 1
	[ -d "$POD_WATCH" ] || return 1
	_f="$(grep -rlxF "# $1" "$POD_WATCH" 2>/dev/null | head -1)"
	[ -n "$_f" ] || return 1
	_s="$(sed -n 's/^start=//p' "$_f" | head -1)"
	[ -n "$_s" ] || return 1
	printf '%s' "${_s%%.*}"
}

# pod_forget <file-or-url> | --all  -> prints how many entries were dropped
pod_forget() {
	[ -d "$POD_WATCH" ] || { printf '0'; return 0; }
	if [ "$1" = "--all" ]; then
		# Count real entries only. mpv also drops a "# redirect entry" file for
		# every parent directory of a local file; those are not positions.
		_n=0
		for _e in "$POD_WATCH"/*; do
			[ -f "$_e" ] || continue
			grep -q '^start=' "$_e" 2>/dev/null && _n=$((_n + 1))
			rm -f "$_e"
		done
		printf '%s' "$_n"
		return 0
	fi
	_f="$(grep -rlxF "# $1" "$POD_WATCH" 2>/dev/null | head -1)"
	[ -n "$_f" ] && { rm -f "$_f"; printf '1'; return 0; }
	printf '0'
}
