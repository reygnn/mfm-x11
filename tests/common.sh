# What the black-box tests of mfm share: its own Xvfb, simulated input through
# xdotool, and helpers on top. Source this, set WORK to an empty directory of the
# test's, and call x_start. It never uses the $DISPLAY of a running session.
MFM=${MFM:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/mfm}
MFM_PID=
XVFB_PID=

fail() { echo "FAIL: $*"; exit 1; }

# require_tools <tool>...: all that the test needs, or where to get it.
require_tools() {
	local tool
	[ -x "$MFM" ] || fail "$MFM not built"
	for tool in "$@"; do
		command -v "$tool" >/dev/null || fail "$tool is missing (or use tests/docker/run.sh)"
	done
}

cleanup() {
	local status=$?
	[ -z "$MFM_PID" ] || kill "$MFM_PID" 2>/dev/null
	[ -z "$XVFB_PID" ] || kill "$XVFB_PID" 2>/dev/null
	[ "$status" = 0 ] || [ ! -s "$MFM_LOG" ] || { echo "--- mfm said:"; cat "$MFM_LOG"; }
	# On a tmpfs of its namespace, files.sh has nothing to remove and may not be able to.
	rm -rf "$WORK" 2>/dev/null
	exit "$status"
}

x_start() {
	local i
	mkdir -p "$WORK/home"
	MFM_LOG=$WORK/mfm.log
	: >"$MFM_LOG"
	trap cleanup EXIT
	# The next free display, so never one in use, and no way back to the session's.
	unset XAUTHORITY WAYLAND_DISPLAY
	exec 3>"$WORK/display"
	Xvfb -displayfd 3 -screen 0 1024x768x24 -nolisten tcp >"$WORK/xvfb.log" 2>&1 &
	XVFB_PID=$!
	exec 3>&-
	for ((i = 0; i < 100; i++)); do
		[ -s "$WORK/display" ] && break
		sleep 0.1
	done
	[ -s "$WORK/display" ] || fail "Xvfb did not start: $(cat "$WORK/xvfb.log")"
	export DISPLAY=:$(cat "$WORK/display")
	# Nothing of the session's settings, and opening a file by mistake does nothing.
	export HOME=$WORK/home XDG_CONFIG_HOME=$WORK/home/.config
	export XDG_DATA_HOME=$WORK/home/.local/share LC_ALL=C.UTF-8
	export MFM_OPEN=true MFM_TERMINAL=true
	unset MFM_FONT MWM_INACTIVE MWM_ACTIVE MWM_TERMINAL XMODIFIERS
}

# press <key>...: the pause lets mfm act on them before anything looks at the result.
press() {
	timeout 10 xdotool key "$@" || fail "xdotool key $*"
	sleep 0.15
}

# wait_for <description> <command>...
wait_for() {
	local what=$1 i
	shift
	for ((i = 0; i < 100; i++)); do
		if "$@"; then
			echo "ok: $what"
			return
		fi
		sleep 0.1
	done
	fail "$what"
}

# mfm_start <directory>: run mfm there and wait until its window is up, as MFM_WIN.
# There is no window manager, and mfm's window is the only one.
mfm_start() {
	"$MFM" "$1" >>"$MFM_LOG" 2>&1 &
	MFM_PID=$!
	MFM_WIN=$(timeout 10 xdotool search --sync --onlyvisible --pid "$MFM_PID" | head -1)
	[ -n "$MFM_WIN" ] || fail "mfm shows no window"
	timeout 10 xdotool mousemove 300 300 || fail "xdotool mousemove"
	timeout 10 xdotool windowfocus --sync "$MFM_WIN" || fail "xdotool windowfocus"
	sleep 0.2
}

# mfm_quit: Ctrl+Q must end it with status 0.
mfm_quit() {
	local i status
	press ctrl+q
	for ((i = 0; i < 50; i++)); do
		kill -0 "$MFM_PID" 2>/dev/null || break
		sleep 0.1
	done
	kill -0 "$MFM_PID" 2>/dev/null && fail "mfm does not quit"
	wait "$MFM_PID"
	status=$?
	[ "$status" = 0 ] || fail "mfm exited with status $status"
	MFM_PID=
}
