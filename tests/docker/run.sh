#!/bin/sh
# Build mfm in a container and run tests/files.sh there, for hosts without Xvfb and
# xdotool or that restrict user namespaces (Ubuntu's AppArmor does). The source is
# mounted read-only and built from a copy. Takes podman or docker.
set -e
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
engine=$(command -v podman || command -v docker) ||
	{ echo "FAIL: neither podman nor docker found"; exit 1; }
"$engine" build -q -t mfm-x11-test "$here" >/dev/null
# The nested user namespaces need the default seccomp and AppArmor profiles out of
# the way.
exec "$engine" run --rm --security-opt seccomp=unconfined \
	--security-opt apparmor=unconfined -v "$repo":/repo:ro mfm-x11-test sh -ec '
		cp -r /repo /tmp/b
		cd /tmp/b
		make -s clean
		make -s
		tests/files.sh'
