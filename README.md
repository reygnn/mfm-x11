# mfm – a minimal file browser for X11 (to go with mwm)

One C file, only Xlib + Xft, no toolkit. Motif look with the same colors as
[mwm-x11](https://github.com/reygnn/mwm-x11): `MWM_INACTIVE` / `MWM_ACTIVE`
from the environment, otherwise `Mwm*background` / `Mwm*activeBackground`
from `~/.config/mwm/mwmrc`.

## Building

    sudo apt install build-essential pkg-config libx11-dev libxft-dev
    make
    sudo make install        # -> /usr/local/bin/mfm

To open files, optionally: `sudo apt install xdg-utils`.

## Running

    mfm [directory | file]

Given a file, mfm opens its folder and selects it. Without an argument it
starts in the current directory. If the start directory cannot be opened,
it shows `$HOME` and gives the reason in the status line.

To start it with mwm, e.g. in `~/.config/mwm/autostart`:

    #!/bin/sh
    mfm "$HOME" &

## Keys

| Key | Action |
|---|---|
| ↑ ↓ PgUp PgDn Home End (keypad too) | move |
| Enter / → | open a folder or a file |
| Backspace / ← / Alt+↑ | parent folder |
| Alt+Home | home directory |
| typing letters | jump to a name (case-insensitive, umlauts included; after 1 s the search starts over) |
| Ctrl+L | enter a path (`/…` or `~…` starts over, Ctrl+U clears) |
| F2 | rename (the name without its extension is selected: typing replaces it, ← → place the cursor) |
| F7 / Ctrl+Shift+N | new folder |
| Ctrl+H | show/hide hidden files |
| Ctrl+R / F5 | reload |
| Ctrl+T | terminal in the current folder |
| Ctrl+Q / Ctrl+W / Alt+F4 | quit (under mwm the window manager takes Alt+F4 and closes the window) |
| Space / Insert | mark or unmark, then move to the next row (during a name search, Space is part of the name) |
| Ctrl+A | mark all, or unmark all |
| Ctrl+C / Ctrl+X | remember the marked entries (else the selection) for copying or moving |
| Ctrl+V | paste into the current folder |
| Delete | move to the trash |
| Shift+Delete | delete permanently, after asking (`y`/`j` confirms, any other key cancels) |
| Esc | one at a time: clear the search, else clear the message, else unmark all |

In input fields (path, rename, new folder): ← → Home End move the cursor,
Backspace/Delete delete, Ctrl+U clears, Enter confirms, Esc cancels.

Mouse: click selects, double-click opens, the wheel scrolls, drag the
scrollbar or click into its trough, the arrow button or the mouse back
button (8) goes up, click into the path field to edit it, Ctrl+click marks,
Shift+click marks the range up to the selection, a plain click unmarks
everything.

A right-click into the list opens a context menu with the commands from
above (Open, Cut, Copy, Paste, Rename, Move to trash, Delete permanently,
New folder, Terminal, hidden files, Reload). A right-click on a marked
entry keeps the marks: Cut, Copy, Move to trash and Delete then act on all
marked entries, while Open and Rename are only offered with at most one
mark. A right-click on any other entry selects just that one. On empty
space the menu acts on the marks, else only on the folder. While a copy or
move is running, Paste, Rename, Move to trash, Delete and New folder are
disabled. Press and hold, drag onto a command and release to run it, or
click it; ↑ ↓ and Enter work too, Esc or a click elsewhere closes the menu.
If the listing changed while the menu was open (the entry disappeared, a
different folder), nothing happens.

## Managing files

Marks belong to the current folder and survive the automatic reload; they
are dropped on changing folders, after Ctrl+C/Ctrl+X and on a plain click.
Without marks, every action works on the selected row.

Copying, moving and permanent deletion run in a background process, so the
window stays usable; another action (F2/F7 included) waits until the
running one is done. If you quit mfm before that, it still runs to the
end. The result, or the first error, appears in the status line. After
Ctrl+X the clipboard stays until the move has fully succeeded. If the
background process dies, mfm says so and keeps the clipboard as well.

Nothing is ever overwritten. Within a file system, moving is a `rename`
that never replaces an existing name. Copies (`cp -a`) and moves across
file systems (`mv`) first land in a hidden folder `.mfm-XXXXXX` in the
target and are renamed from there: half a copy never shows up under the
real name, and the name is only chosen at that moment. If it is taken
(even just in different case on FAT drives), the copy is called
`name (copy).txt`, `name (copy 2).txt` and so on, a moved entry
`name (2).txt`, `name (3).txt`. That is also how Ctrl+C, Ctrl+V in the
same folder makes a duplicate. mfm refuses to copy or move a folder into
itself. Renaming does not overwrite either; if the new name is taken, mfm
says so. (The one gap: file systems without an atomic "rename without
replacing", e.g. NFS, for folders, and for files if they cannot do hard
links either.)

If a move across file systems fails, e.g. because the target is full, what
arrived stays in the hidden `.mfm-XXXXXX`, and the status line names that
folder. After such a failure the source is, as a rule, still complete. mfm
cleans up after a failed copy.

Permanent deletion is `rm -rf --one-file-system`. mfm does not delete a
mount point itself or a folder with something mounted in it, bind mounts
from the same file system included, whose contents `rm` would otherwise
empty. A mount point cannot be moved either, nor, across file systems, a
folder with something mounted in it; copying works.

The trash follows the freedesktop.org specification, so files can be
restored with any file manager that knows it (or by hand from `files/`; the
original path is in `info/*.trashinfo`). It lives in `$XDG_DATA_HOME/Trash`
(default `~/.local/share/Trash`); for files on other file systems, at their
root in `.Trash/$UID` (if the administrator has set up a shared `.Trash`),
else in `.Trash-$UID`. There the original path is relative to the root, so
it stays correct when the drive is mounted somewhere else. What is already
in the trash is not put there again. If trashing does not work (e.g.
read-only), Shift+Delete is left.

The folder is checked for changes every second and read again, keeping the
selection and the scroll position. If it disappears or becomes unreadable,
mfm moves to the nearest readable parent. A file's changed size or
permissions do not change the folder: Ctrl+R shows them.

Paths are logical, as with `cd` in the shell: after entering a linked
folder, `..` leads back to the folder the link is in, and a terminal opened
with Ctrl+T gets that path as `$PWD`. A parent folder you may traverse but
not list is skipped by Backspace.

Text input goes through the input method set in `XMODIFIERS` (ibus, fcitx,
…). If that is not running, mfm uses the one built into Xlib (with Compose
and dead keys) and switches over as soon as the real one starts.

File names that are not valid UTF-8 (e.g. Latin-1 from old disks or network
drives) are shown as Latin-1.

Only moving and typing repeat when held, not commands: Delete, Enter and
key combinations act once per press; Delete and Backspace in input fields
repeat.

## Environment

| Variable | Default | |
|---|---|---|
| `MFM_OPEN` | `xdg-open` | program to open files with, e.g. `feh` or `"mimeopen -n"`; the file is appended as the last argument |
| `MFM_TERMINAL` | `$MWM_TERMINAL`, else the first one found of xterm, uxterm, x-terminal-emulator, urxvt, alacritty, konsole, kitty, xfce4-terminal, gnome-terminal | for Ctrl+T |
| `MFM_FONT` | `Sans:size=10` | fontconfig pattern |
| `MWM_INACTIVE`, `MWM_ACTIVE` | `#aeb2c3`, `#7387ad` | background, selection |

`MFM_OPEN` and `MFM_TERMINAL` are split into words at spaces. Quotes group
words (`xterm -fa 'DejaVu Sans Mono'`); beyond that there is no shell syntax
(no `$VAR`, no `;`, no pipes) – for that, put in a small script. The
program is only looked up in the absolute entries of `$PATH`, never in the
folder being shown. If it is missing, the status line says so.

Anything beyond that (permissions, links, archives, …): Ctrl+T and the
shell.

## Tests

    make test

runs mfm under its own Xvfb with a simulated mouse and keyboard and checks
files and screenshots (`tests/ui.sh`), plus file operations with real mounts
in a private namespace (`tests/files.sh`; skipped without user namespaces).
It needs `xvfb`, `xdotool` and `imagemagick`. The tests leave a running
session alone.

Ubuntu's AppArmor blocks user namespaces. There, or without those packages,

    make test-docker

brings everything along in a container (podman or docker).

## License

MIT, see [LICENSE](LICENSE).
