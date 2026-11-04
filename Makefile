# mfm - minimal file manager for X11 (mwm look)

PREFIX ?= /usr/local
PKG_CONFIG ?= pkg-config
PKGS = x11 xft

# CFLAGS and LDLIBS stay the user's, also on the command line: `make CFLAGS=-O0`
# must not lose the include paths.
CFLAGS ?= -O2 -g
MFM_CFLAGS = -std=c11 -Wall -Wextra -Wno-unused-parameter \
	$(shell $(PKG_CONFIG) --cflags $(PKGS))
MFM_LIBS = $(shell $(PKG_CONFIG) --libs $(PKGS))

all: mfm

mfm: mfm.c
	$(CC) $(MFM_CFLAGS) $(CFLAGS) $(LDFLAGS) -o $@ mfm.c $(MFM_LIBS) $(LDLIBS)

install: mfm
	install -Dm755 mfm $(DESTDIR)$(PREFIX)/bin/mfm

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/mfm

clean:
	rm -f mfm

.PHONY: all install uninstall clean
