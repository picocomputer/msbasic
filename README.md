# Microsoft BASIC for the Picocomputer 6502

 - `INSTALL basic.rp6502` then `HELP basic` for usage.
 - `INFO basic.rp6502` for usage without installing.

Original source: https://github.com/microsoft/BASIC-M6502
<br/>
Ported to cc65: https://github.com/mist64/msbasic

## Launch arguments

```
basic [-c0|-c1|-c2] [<filename>]
```

| Flag       | Effect                                                      |
| ---------- | ----------------------------------------------------------- |
| `-c0`      | Caps mode off — characters echo as typed                    |
| `-c1`      | Caps mode on (default) — letters always upper case          |
| `-c2`      | Caps mode invert — swap upper/lower case                    |
| `<name>`   | Auto-`LOAD` the file, then `RUN` it                         |

The same modes are reachable at runtime via `CAPS <expr>`.

## File I/O

Up to sixteen files may be open at once. Logical file numbers (lfn) are integers in the range `0..15`.

```basic
OPEN <lfn>, <name$> [, <mode$>]
CLOSE <lfn>
```

`<mode$>` is a Unix-style string. If omitted, the default is `"r"`.

| Mode      | Flags                          |
| --------- | ------------------------------ |
| `"r"`     | read-only (default)            |
| `"w"`     | write, create, truncate        |
| `"a"`     | write, create, append          |
| `"rw"` / `"r+"` | read/write                |
| `"w+"`    | read/write, create, truncate   |
| `"a+"`    | read/write, create, append     |

Once a file is open, the lfn drives I/O redirection on CBM-style statements:

```basic
PRINT# <lfn>, <expr-list>      : write to the file
INPUT# <lfn>, <var-list>       : read from the file (newline-delimited)
GET#   <lfn>, <var>            : read one byte from the file
CMD    <lfn> [, <expr-list>]   : redirect subsequent PRINT output
```

Reads return EOF when the OS returns fewer bytes than requested. `INPUT#` then bails cleanly to the caller; `GET#` simply returns an empty value, so polling a pipe in BASIC is a normal `GET#` loop.

`LOAD` and `SAVE` operate on plain ASCII — the same byte stream `LIST` emits — so program files are interchangeable with anything that produces text:

```basic
SAVE "prog.bas"
LOAD "prog.bas"
```

`SAVE` always overwrites; `LOAD` replaces the program in memory.

## Other statements

```basic
CAPS <expr>
```

Sets the readline editor's caps mode at runtime: `0` off, `1` on, `2` invert. Same modes as the `-c<n>` launch flag. Anything else raises `?ILLEGAL QUANTITY`.

## Editor and runtime conveniences

 - `CTRL-C` interrupts a running program or `LIST`.
 - Type a line number then press `TAB` to recall that line into the editor for in-place editing.
 - Keywords and variable names may be entered in lower case; they are normalized for tokenization and listing.
 - `RND()` is seeded with hardware entropy at cold start, so `RND` produces a different sequence on each boot without needing a manual seed.
 - `CTRL-ALT-DEL` (or `BREAK`) drops to the RP6502 monitor — useful for listing/changing directories or managing files. Type `RESET` at the monitor prompt to warm-start the interpreter while preserving program memory.
