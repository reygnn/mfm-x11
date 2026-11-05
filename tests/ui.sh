#!/bin/bash
# Black-box test of mfm under its own Xvfb, without a window manager (see common.sh):
# simulated mouse and keyboard, checked through the file system (a command that worked
# leaves files behind) and through pixels in screenshots.
. "$(dirname "$0")/common.sh"

require_tools Xvfb xdotool import od
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mfmu.XXXXXX") || exit 1
x_start
export MFM_OPEN="sh -c 'printf %s \"\$1\" > \"\$0\"' $WORK/opened"
export MFM_TERMINAL="touch $WORK/term-ran"

SCREEN_W=1024
SCREEN_H=768
BG=aeb2c3
SEL=7387ad
TROUGH=999dac
LIST=c6c9d5
SHOT=$WORK/shot.rgb
# Where the window is on the screen: without a window manager it stays where it is put.
CX=0
CY=0

# ---- helpers ---------------------------------------------------------------

file_appears() { wait_for "$1" test -e "$2"; }

move() { timeout 10 xdotool mousemove "$1" "$2" || fail "xdotool mousemove"; sleep 0.05; }

button() { case $1 in left) echo 1 ;; right) echo 3 ;; esac; }
click() { timeout 10 xdotool click "$(button "$1")" || fail "xdotool click"; sleep 0.1; }
down() { timeout 10 xdotool mousedown "$(button "$1")" || fail "xdotool mousedown"; sleep 0.05; }
up() { timeout 10 xdotool mouseup "$(button "$1")" || fail "xdotool mouseup"; sleep 0.05; }

# hold_key <key> <seconds>: long enough for the server's auto-repeat to start.
hold_key() {
	timeout 10 xdotool keydown "$1" || fail "xdotool keydown"
	sleep "$2"
	timeout 10 xdotool keyup "$1" || fail "xdotool keyup"
	sleep 0.2
}

# The screen as bare RGB bytes, of which od reads single pixels quickly.
shoot() {
	rm -f "$SHOT"
	import -silent -window root -depth 8 "rgb:$SHOT" 2>/dev/null || fail "no screenshot"
	[ "$(stat -c %s "$SHOT")" = $((3 * SCREEN_W * SCREEN_H)) ] || fail "odd screenshot"
}

pixel() { od -An -tx1 -j $((3 * ($2 * SCREEN_W + $1))) -N3 "$SHOT" | tr -d ' \n'; }

# wait_shot_pixel <description> <x> <y> <rrggbb>: screen coordinates.
wait_shot_pixel() {
	local got i
	for ((i = 0; i < 50; i++)); do
		shoot
		got=$(pixel "$2" "$3")
		[ "$got" = "$4" ] && { echo "ok: $1"; return; }
		sleep 0.1
	done
	fail "$1: pixel $2,$3 is $got, expected $4"
}

# Find the selected row, which starts as the first one: ROW0 is its top on the
# screen, ROWH its height, LISTX a column inside the list.
find_rows() {
	local y end
	LISTX=$((CX + 80))
	shoot
	for ((y = CY; y < CY + 200; y++)); do
		[ "$(pixel "$LISTX" "$y")" = "$SEL" ] && break
	done
	[ "$y" -lt $((CY + 200)) ] || fail "no selected row found"
	ROW0=$y
	for ((end = y; end < y + 60; end++)); do
		[ "$(pixel "$LISTX" "$end")" = "$SEL" ] || break
	done
	ROWH=$((end - y))
	[ "$ROWH" -ge 10 ] && [ "$ROWH" -lt 50 ] || fail "odd row height $ROWH"
	echo "ok: rows start at $ROW0, $ROWH high"
}

row_y() { echo $((ROW0 + $1 * ROWH + ROWH / 2)); }

# ui_start <directory>: mfm_start, and wait until it has drawn what shows the rows.
ui_start() {
	mfm_start "$1"
	wait_shot_pixel "the window is drawn" $((CX + 1)) $((CY + 1)) "$BG"
	find_rows
}

# Make a directory with entries for one scenario.
fresh_dir() {
	D=$WORK/tree/$1
	mkdir -p "$D"
}

window_size() { xdotool getwindowgeometry --shell "$MFM_WIN" | sed -n "s/^$1=//p"; }

# ---- window ----------------------------------------------------------------

fresh_dir basics
touch "$D/alpha.txt" "$D/beta.txt" "$D/run.sh"
mkdir "$D/folder"
ui_start "$D"
[ "$(window_size WIDTH)" = 680 ] && [ "$(window_size HEIGHT)" = 480 ] ||
	fail "not the default size: $(window_size WIDTH)x$(window_size HEIGHT)"
[ "$(xdotool getwindowname "$MFM_WIN")" = "mfm: $D" ] ||
	fail "title is $(xdotool getwindowname "$MFM_WIN")"
echo "ok: default size and title"

# A new size means a new back buffer. The list shows only what mfm draws itself: the
# server fills new areas with the window's background.
for _ in 1 2 3; do
	timeout 10 xdotool windowsize --sync "$MFM_WIN" 900 600 || fail "xdotool windowsize"
	wait_shot_pixel "drawn at the new size" 100 540 "$LIST"
	timeout 10 xdotool windowsize --sync "$MFM_WIN" 680 480 || fail "xdotool windowsize"
	wait_shot_pixel "drawn at the old size" 100 420 "$LIST"
done

# ---- keyboard --------------------------------------------------------------

press F7
for k in n e u; do press "$k"; done
press Return
file_appears "F7 and typing make a folder" "$D/neu"
[ -d "$D/neu" ] || fail "neu is not a directory"
[ "$(xdotool getwindowname "$MFM_WIN")" = "mfm: $D" ] || fail "the title changed"

press b
press e
press F2
press x
press Return
file_appears "type-ahead and F2 rename, keeping the extension" "$D/x.txt"
[ ! -e "$D/beta.txt" ] || fail "beta.txt still there"

press ctrl+c
press ctrl+v
file_appears "Ctrl+C, Ctrl+V duplicates in a child process" "$D/x (copy).txt"

press ctrl+t
file_appears "Ctrl+T runs the terminal" "$WORK/term-ran"

# Shift and a letter: type-ahead folds case, the keys must still reach it.
sleep 1.1
press shift+a
press Return
file_appears "Shift+a and Enter open something" "$WORK/opened"
[ "$(cat "$WORK/opened")" = "$D/alpha.txt" ] || fail "opened $(cat "$WORK/opened")"
echo "ok: and that is alpha.txt"
rm -f "$WORK/opened"

mfm_quit

# ---- held keys -------------------------------------------------------------

# Told apart through detectable auto-repeat, so this is X11's own. Down shows that the
# server does repeat here; Delete must act once all the same.
fresh_dir held
for i in 1 2 3 4 5 6 7 8; do touch "$D/held$i"; done
ui_start "$D"
hold_key Down 1.5
shoot
# The press alone gets to row 1, so past that only a repeat can have gone.
[ "$(pixel "$LISTX" "$(row_y 1)")" != "$SEL" ] && [ "$(pixel "$LISTX" "$(row_y 2)")" != "$SEL" ] ||
	fail "a held Down does not repeat"
echo "ok: a held Down repeats"
press Home
press Down
hold_key Delete 1.5
[ "$(find "$XDG_DATA_HOME/Trash/files" -mindepth 1 -maxdepth 1 | wc -l)" = 1 ] ||
	fail "a held Delete moved more than one file to the trash"
echo "ok: a held Delete acts once"
press Delete
[ "$(find "$XDG_DATA_HOME/Trash/files" -mindepth 1 -maxdepth 1 | wc -l)" = 2 ] ||
	fail "pressing Delete again did not count as a new press"
echo "ok: pressing it again is a new press"
mfm_quit
rm -rf "$XDG_DATA_HOME/Trash"

# ---- context menu ----------------------------------------------------------

fresh_dir menu
touch "$D/one.txt"
ui_start "$D"
Y=$(row_y 1)
X=$((LISTX + 40))

# Press, drag, release. Open is the first item, whatever the font's size.
move "$X" "$Y"
down right
sleep 0.2       # a quicker release is a click
move $((X + 30)) $((Y + 12))
sleep 0.2
up right
file_appears "press, drag and release runs Open" "$WORK/opened"
rm -f "$WORK/opened"

# A menu that is still up would take this key: the menu must be closed now.
press F7
press Escape

# A quick click leaves it open for a second click.
move "$X" "$Y"
click right
sleep 0.4
[ ! -e "$WORK/opened" ] || fail "the opening click ran an item"
move $((X + 30)) $((Y + 12))
click left
file_appears "click, then click on an item runs it" "$WORK/opened"
rm -f "$WORK/opened"

# Slow press and release without moving: the menu stays and nothing runs.
move "$X" "$Y"
down right
sleep 0.5
up right
sleep 0.2
[ ! -e "$WORK/opened" ] || fail "a release on the corner ran an item"
press Down
press Return
file_appears "a slow click leaves it open, Down and Return run Open" "$WORK/opened"
rm -f "$WORK/opened"

# Esc closes it: afterwards the key goes to the list again.
move "$X" "$Y"
click right
sleep 0.4
press Escape
press F7
for k in a b; do press "$k"; done
press Return
file_appears "Esc closes the menu" "$D/ab"

# A click on our own window closes it and does nothing else there: the row above
# the menu does not get selected.
move "$X" "$Y"
click right
sleep 0.4
move "$LISTX" "$(row_y 0)"
click left
sleep 0.3
shoot
[ "$(pixel "$LISTX" "$ROW0")" != "$SEL" ] || fail "the click selected a row"
press F7
for k in c d; do press "$k"; done
press Return
file_appears "a click beside the menu closes it" "$D/cd"

# The whole way through the keys: Down to Move to trash (Open Cut Copy Rename
# Trash; Paste is off with nothing to paste).
press F5
move "$X" "$(row_y 3)"
click right
sleep 0.4
for _ in 1 2 3 4 5; do press Down; done
press Return
file_appears "the menu moves a file to the trash" "$XDG_DATA_HOME/Trash/files/one.txt"
[ ! -e "$D/one.txt" ] || fail "one.txt still there"

mfm_quit

# Near the bottom of the screen the menu opens above the pointer.
fresh_dir flip
touch "$D/f.txt"
ui_start "$D"
CY=$((SCREEN_H - 480))
timeout 10 xdotool windowmove --sync "$MFM_WIN" 0 "$CY" || fail "xdotool windowmove"
sleep 0.2
X=$((LISTX + 40))
Y=$((CY + 420))    # the list ends a bit below, then comes the status line
move "$X" "$Y"
click right
sleep 0.4
shoot
for ((y = Y - 100; y < Y - 80; y++)); do
	[ "$(pixel $((X + 6)) "$y")" = "$BG" ] && break
done
[ "$y" -lt $((Y - 80)) ] || fail "no menu above the pointer"
[ "$(pixel $((X + 6)) $((Y + 10)))" != "$BG" ] || fail "the menu is below the pointer"
echo "ok: the menu opens upwards at the bottom of the screen"
press Escape
mfm_quit
CY=0

# ---- scrollbar -------------------------------------------------------------

fresh_dir many
for i in $(seq 100 299); do touch "$D/file$i"; done
ui_start "$D"
W=680
H=480
SBX=$((CX + W - 6 - 15 / 2))    # PAD, SBW
SBY=$((ROW0 + 6))               # inside the thumb at the top
shoot
[ "$(pixel "$SBX" $((CY + H - 80)))" = "$TROUGH" ] || fail "no trough at the bottom"

# Drag the thumb down: where it was, there is trough now.
move "$SBX" "$SBY"
down left
move "$SBX" $((SBY + 150))
wait_shot_pixel "dragging moves the thumb" "$SBX" "$SBY" "$TROUGH"

# The server keeps the pointer on the window while the button is down, so the drag
# goes on outside it, and the release out there still ends it.
move $((CX + W + 60)) $((SBY + 300))
wait_shot_pixel "the drag goes on outside the window" "$SBX" $((SBY + 150)) "$TROUGH"
up left

# A drag that had not ended would take this one for itself, and bring the thumb back.
move "$LISTX" "$(row_y 2)"
down left
move "$LISTX" "$(row_y 0)"
sleep 0.3
up left
sleep 0.2
shoot
[ "$(pixel "$SBX" "$SBY")" = "$TROUGH" ] || fail "still dragging after a release outside"
echo "ok: a release outside the window ends the drag"
mfm_quit

# ---- names Xft could trip over ---------------------------------------------

# Xft reports widths as 16-bit values, which a whole long path would overflow, and
# Latin-1 doubles in length for display.
fresh_dir long
P=$D
comp=$(printf '\xe9%.0s' $(seq 1 200))
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18; do P=$P/$comp; done
mkdir -p "$P" || fail "cannot make the long path"
touch "$P/inside"
ui_start "$P"
press F5
sleep 0.3
kill -0 "$MFM_PID" 2>/dev/null || fail "mfm died on a long path"
echo "ok: a path of ${#P} bytes as a title"
mfm_quit

# A newline in a name must not make a second line, which would show on the empty
# rows below it.
fresh_dir odd
touch "$D/$(printf 'first\nsecond\nthird')"
ui_start "$D"
press F5
sleep 0.3
kill -0 "$MFM_PID" 2>/dev/null || fail "mfm died on odd names"
shoot
for ((x = LISTX - 60; x < LISTX + 100; x += 3)); do
	[ "$(pixel "$x" "$(row_y 2)")" = "$LIST" ] || fail "text on the empty row at x=$x"
done
echo "ok: a newline stays on its line"
mfm_quit

fresh_dir odd2
touch "$D/$(printf 'latin\xe9')" "$D/ütf ☃ 日本語.txt" "$D/$(printf 'zz\xe2\x80\xaefdp.exe')"
ui_start "$D"
press F5
sleep 0.3
kill -0 "$MFM_PID" 2>/dev/null || fail "mfm died on odd names"
echo "ok: odd names"
mfm_quit

# The cursor does not stop between a letter and its accent: F2 puts it behind the
# stem, Left in front of the e with its accent, so Backspace takes the f.
fresh_dir comb
touch "$D/$(printf 'cafe\xcc\x81.txt')"
ui_start "$D"
press Down
press F2
press Left
press BackSpace
press Return
file_appears "Left steps over a combining accent" "$D/$(printf 'cae\xcc\x81.txt')"
mfm_quit

# ---- settings --------------------------------------------------------------

# A font name without a size: find_rows checks the height.
fresh_dir font
MFM_FONT=Monospace ui_start "$D"
mfm_quit
echo "ok: a font without a size"

# mfm has to read mwmrc as mwm does.
fresh_dir rc
mkdir -p "$XDG_CONFIG_HOME/mwm"
printf 'mwm.Background : #336699\n' >"$XDG_CONFIG_HOME/mwm/mwmrc"
BG=336699
ui_start "$D"
BG=aeb2c3
rm "$XDG_CONFIG_HOME/mwm/mwmrc"
echo "ok: mwmrc in another spelling"
mfm_quit

# ---- the end ---------------------------------------------------------------

# X server gone: an error message and status 1, not a hang.
fresh_dir gone
ui_start "$D"
kill "$XVFB_PID"
wait "$XVFB_PID" 2>/dev/null
XVFB_PID=
for ((i = 0; i < 50; i++)); do
	kill -0 "$MFM_PID" 2>/dev/null || break
	sleep 0.1
done
kill -0 "$MFM_PID" 2>/dev/null && fail "mfm still runs without an X server"
wait "$MFM_PID"
status=$?
MFM_PID=
[ "$status" = 1 ] || fail "mfm exited with status $status, not 1"
grep -qE 'X connection|fatal IO error' "$MFM_LOG" || fail "no message about the lost connection"
echo "ok: exits when the X server goes away"

echo "PASS"
