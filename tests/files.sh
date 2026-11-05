#!/bin/bash
# What file operations do around mounts, full disks and read-only directories, with
# real mounts in a private namespace, driven through mfm under its own Xvfb with
# xdotool (see common.sh). Skipped where unprivileged user namespaces are not
# available; tests/docker/run.sh brings all it needs.
#
# It runs in three stages: this script, again as root of a user namespace to set up
# the mounts, and again as the normal user in a namespace inside that one.
SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
. "$(dirname "$SELF")/common.sh"

if [ -z "${MFMT_STAGE:-}" ]; then
	require_tools Xvfb xdotool pgrep unshare
	unshare -Urm true 2>/dev/null ||
		{ echo "SKIP: no user namespaces here (use tests/docker/run.sh)"; exit 0; }
	MFMT_ROOT=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/mfmt.XXXXXX") || exit 1
	MFM=$MFM MFMT_STAGE=mounts MFMT_ROOT=$MFMT_ROOT MFMT_UID=$(id -u) MFMT_GID=$(id -g) \
		unshare -Urm bash "$SELF"
	status=$?
	rmdir "$MFMT_ROOT"
	exit $status
fi

if [ "$MFMT_STAGE" = mounts ]; then
	R=$MFMT_ROOT
	mount -t tmpfs -o size=64m none "$R" || exit 1
	mkdir -p "$R/del/outer/inner" "$R/del/precious" "$R/del/plain" "$R/del2/box/m" \
		"$R/del2/plain" "$R/src/mnt" "$R/dst" "$R/wide" "$R/vanish/sub"
	echo thesis >"$R/del/precious/thesis.txt"
	mount --bind "$R/del/precious" "$R/del/outer/inner" || exit 1
	mount -t tmpfs none "$R/del2/box/m" || exit 1
	echo keep >"$R/del2/box/m/keep"
	mount -t tmpfs none "$R/src/mnt" || exit 1
	echo keep >"$R/src/mnt/keep"
	mount -t tmpfs -o size=1m none "$R/dst" || exit 1
	mount -t tmpfs -o size=32m none "$R/wide" || exit 1
	head -c 4194304 /dev/urandom >"$R/src/big"
	echo slow >"$R/src/slow"
	mkdir -p "$R/src/rofull" "$R/src/roempty" "$R/src/tree/sub"
	echo f >"$R/src/rofull/f"
	echo f >"$R/src/tree/sub/f"
	echo f >"$R/src/tree/secret"
	chmod 555 "$R/src/rofull" "$R/src/roempty" "$R/src/tree/sub"
	chmod 000 "$R/src/tree/secret"
	# Inside a namespace of its own the mounts cannot be undone, as for a user.
	MFMT_STAGE=test exec unshare -U --map-user="$MFMT_UID" --map-group="$MFMT_GID" \
		bash "$SELF"
fi

R=$MFMT_ROOT
# Hidden, so that mfm does not list it, and gone with the namespace.
WORK=$R/.work
x_start

# ---- helpers ---------------------------------------------------------------

# type_name <letters>: type-ahead to a name; a pause first ends an earlier search.
type_name() {
	local i
	sleep 1.1
	for ((i = 0; i < ${#1}; i++)); do press "${1:i:1}"; done
}

# to_dir <name>: from a directory into a sibling of it.
to_dir() {
	sleep 1.1       # during a search, BackSpace is part of it
	press BackSpace
	type_name "$1"
	press Return
	sleep 0.2
}

# job_settled: wait until no worker runs below mfm any more.
job_settled() {
	local i
	for ((i = 0; i < 100; i++)); do
		pgrep -P "$MFM_PID" >/dev/null || return 0
		sleep 0.1
	done
	fail "the job did not end"
}

no_hidden_left() {
	local left
	left=$(find "$1" -maxdepth 1 -name '.mfm-*' 2>/dev/null)
	[ -z "$left" ] || fail "$2: left behind: $left"
}

# delete_name <letters>: Delete permanently, and say yes.
delete_name() {
	type_name "$1"
	press shift+Delete
	press y
	job_settled
}

# ---- delete -----------------------------------------------------------------

# "plain" goes first: a mount that stays would prove nothing if the keys got nowhere.
mfm_start "$R/del"
delete_name plain
[ ! -e "$R/del/plain" ] || fail "delete does not work at all"
delete_name outer
[ -e "$R/del/precious/thesis.txt" ] || fail "a bind mount of the same file system was emptied"
[ -d "$R/del/outer/inner" ] || fail "outer was deleted around its mount"
echo "ok: delete keeps out of a folder with a bind mount in it"
mfm_quit

mfm_start "$R/del2"
delete_name plain
[ ! -e "$R/del2/plain" ] || fail "delete does not work at all"
delete_name box
[ -e "$R/del2/box/m/keep" ] || fail "a mounted file system was emptied"
echo "ok: delete keeps out of a folder with another file system mounted in it"
mfm_quit

# ---- move -------------------------------------------------------------------

mfm_start "$R/src"
type_name big
press ctrl+x
to_dir dst
press ctrl+v
job_settled
[ ! -e "$R/dst/big" ] || fail "half a file under its real name"
[ "$(stat -c %s "$R/src/big")" = 4194304 ] || fail "the source was damaged"
[ -n "$(find "$R/dst" -maxdepth 1 -name '.mfm-*')" ] || fail "what arrived is gone"
echo "ok: a move to a full disk shows nothing under the real name"
rm -rf "$R"/dst/.mfm-*
mfm_quit

mfm_start "$R/src"
type_name mnt
press ctrl+x
to_dir wide
press ctrl+v
job_settled
[ -e "$R/src/mnt/keep" ] || fail "the mounted file system was emptied"
[ ! -e "$R/wide/mnt" ] || fail "the mount point was moved"
no_hidden_left "$R/wide" "moving a mount point"
echo "ok: a mount point is not moved"
mfm_quit

mfm_start "$R/src"
type_name roe
press ctrl+x
to_dir wide
press ctrl+v
job_settled
[ "$(stat -c %a "$R/wide/roempty" 2>/dev/null)" = 555 ] || fail "read-only folder not moved"
[ ! -e "$R/src/roempty" ] || fail "read-only folder still in the source"
no_hidden_left "$R/wide" "moving a read-only folder"
echo "ok: a move of a read-only folder arrives under its name"
mfm_quit

# A worker that dies must not look like success: the clipboard stays for another try.
SHIM=$WORK/shim
mkdir -p "$SHIM"
REAL_MV=$(command -v mv)
cat >"$SHIM/mv" <<EOS
#!/bin/sh
[ -e "$SHIM/hang" ] && exec sleep 300
exec "$REAL_MV" "\$@"
EOS
chmod +x "$SHIM/mv"
touch "$SHIM/hang"
PATH=$SHIM:$PATH mfm_start "$R/src"
type_name slow
press ctrl+x
to_dir wide
press ctrl+v
sleep 0.5
W=$(pgrep -P "$MFM_PID" | head -1)
[ -n "$W" ] || fail "no worker"
kill -9 -- "-$W"
rm "$SHIM/hang"
sleep 0.5
press ctrl+v
job_settled
wait_for "the clipboard survives a worker that died" test -e "$R/wide/slow"
rm -rf "$R"/wide/.mfm-*
mfm_quit

# ---- copy -------------------------------------------------------------------

mfm_start "$R/src"
type_name rof
press ctrl+c
to_dir wide
press ctrl+v
job_settled
[ -e "$R/wide/rofull/f" ] || fail "read-only folder not copied"
[ "$(stat -c %a "$R/wide/rofull")" = 555 ] || fail "the copy lost its mode"
no_hidden_left "$R/wide" "copying a read-only folder"
echo "ok: a copy of a read-only folder arrives under its name, still read-only"
mfm_quit

mfm_start "$R/src"
type_name tree
press ctrl+c
to_dir wide
press ctrl+v
job_settled
[ ! -e "$R/wide/tree" ] || fail "a failed copy under its real name"
no_hidden_left "$R/wide" "a failed copy with a read-only folder in it"
echo "ok: a failed copy is cleaned up, read-only folders included"
mfm_quit

# ---- the directory on screen ------------------------------------------------

mfm_start "$R/vanish/sub"
chmod 000 "$R/vanish/sub"
sleep 1.5
press F7
press x
press Return
wait_for "chmod 000 on the folder sends mfm to its parent" test -e "$R/vanish/x"
chmod 755 "$R/vanish/sub"
mfm_quit

echo "PASS"
