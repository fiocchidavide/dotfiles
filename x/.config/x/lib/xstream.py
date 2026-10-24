"""Progress drawing for x: `x gdrive`'s transfers and `x rveil`'s log.

Standard library only, run through `uv run --no-project`. Subcommands:

  rclonebar [--label L]                  progress bar from rclone's JSON log
                                         (--use-json-log --stats) on stdin
  rveillog --role R ICON SGR…            rveil's JSON log (-vv --use-json-log)
                                         on stdin, drawn the way x looks
"""

import argparse
import json
import sys


def human(n: float) -> str:
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if n < 1024 or unit == "TiB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024
    return ""


def clock(seconds) -> str:
    if seconds is None:
        return "--:--"
    s = int(seconds)
    return f"{s // 3600}:{s // 60 % 60:02}:{s % 60:02}" if s >= 3600 else f"{s // 60}:{s % 60:02}"


def draw_bar(out, label, done, total, speed, eta) -> None:
    """One frame: label, sizes, a line filled in cyan over a dim track (with a
    half cell, ╸, for precision), percentage, speed and ETA."""
    import shutil
    frac = min(done / total, 1.0) if total else 0.0
    left = f"{label}  {human(done)} / {human(total) if total else '?'}  "
    rate = f"{human(speed or 0)}/s"
    right = f"  {frac * 100:3.0f}%  {rate:>11}  ETA {clock(eta):>7}"
    width = max(10, shutil.get_terminal_size((80, 24)).columns - len(left) - len(right) - 1)
    halves = int(frac * width * 2)
    filled = "━" * (halves // 2) + ("╸" if halves % 2 else "")
    track = "━" * (width - len(filled))
    out.write(f"\r\033[K{left}\033[36m{filled}\033[2;37m{track}\033[0m"
              f"\033[1m{right[:6]}\033[0m\033[2m{right[6:]}\033[0m")
    out.flush()


def cmd_rclonebar(args) -> int:
    """Draw a progress bar from rclone's --use-json-log stats lines (stdin);
    other log lines (errors, notices) are passed through as plain text."""
    out = sys.stderr
    tty = out.isatty()
    drawn = False
    for line in sys.stdin:
        try:
            record = json.loads(line)
        except ValueError:
            record = {"msg": line.rstrip("\n")}
        stats = record.get("stats")
        if stats is None:
            if record.get("msg", "").strip():
                if drawn:
                    out.write("\r\033[K")
                level = record.get("level", "")
                out.write(f"{level + ': ' if level else ''}{record['msg'].strip()}\n")
            continue
        if tty:
            draw_bar(out, args.label, stats.get("bytes", 0), stats.get("totalBytes", 0),
                     stats.get("speed"), stats.get("eta"))
            drawn = True
    if drawn:
        out.write("\r\033[K")
        out.flush()
    return 0


def elapsed(seconds: float) -> str:
    """As _x_elapsed: 4.2s, 3:07, 1:02:03."""
    return f"{seconds:.1f}s" if seconds < 59.95 else clock(seconds)


# What rveil's log events become in x: an outcome line (ok), a heading for
# each archive it works on (step), a detail (info). Notices and errors are
# warn and err lines whatever their event. Anything else (step start/end,
# progress, commands run) only feeds the live line.
RVEIL_ROLES = {
    "ok": {"sealed", "pushed", "restored", "rekeyed", "deleted", "key_created",
           "repaired", "agree", "readded", "verified", "opened"},
    "step": {"archive"},
    "info": {"sizes", "older_keys", "passphrase",
             "index_passphrases", "symlink", "already_pushed", "counts",
             "shared", "deleted_total", "dropped", "foreign"},
}


def cmd_rveillog(args) -> int:
    """Draw rveil's JSON log (stdin) on stderr as x commands look: while a step
    runs, a spinner with its description and elapsed time (as _x_spin), or a
    progress bar for a transfer (as x gdrive); a line with the role's icon
    for each outcome, notice and error. Icons and colours come from x.zsh
    (--role name icon sgr), so X_ICONS and X_COLORS stay the one place to
    restyle x. X_QUIET=1 keeps only warnings and errors."""
    import os
    import select
    import time
    out = sys.stderr
    tty = out.isatty()
    fancy = tty and not os.environ.get("NO_COLOR")
    quiet = os.environ.get("X_QUIET", "0") not in ("", "0")
    roles = {name: (icon, sgr) for name, icon, sgr in args.role}

    def paint(sgr, text):
        return f"\033[{sgr}m{text}\033[0m" if fancy and sgr else text

    def style(name):
        return roles.get(name, ("", ""))[1]

    steps = []          # running steps, innermost last: [name, msg, start]
    bar = None          # the innermost step's last progress event
    shown, frame = False, 0

    def clear():
        nonlocal shown
        if shown:
            out.write("\r\033[K")
            shown = False

    def draw():
        nonlocal shown, frame
        if not tty or quiet or not steps:
            return
        name, msg, start = steps[-1]
        if bar is not None and bar.get("step") == name:
            draw_bar(out, msg, bar.get("bytes", 0), bar.get("total", 0),
                     bar.get("bytes_per_second"), bar.get("eta_seconds"))
        else:
            spin = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"[frame % 10]
            out.write(f"\r\033[K{paint(style('spin'), spin)} {msg} "
                      f"{paint(style('dim'), elapsed(time.monotonic() - start))}")
        frame += 1
        shown = True
        out.flush()

    def say(role, text):
        if quiet and role not in ("warn", "err"):
            return
        icon, sgr = roles.get(role, ("", ""))
        if role == "step":
            text = paint(style("bold"), text)
        elif role == "info":
            text = paint(style("dim"), text)
        clear()
        out.write(f"{paint(sgr, icon)} {text}\n")
        draw()

    def handle(line):
        nonlocal bar
        try:
            ev = json.loads(line)
        except ValueError:
            if line.strip():
                say("err", line.strip())
            return
        level, event, msg = ev.get("level"), ev.get("event"), ev.get("msg", "")
        if event == "start":
            steps.append([ev.get("step"), msg, time.monotonic()])
            bar = None
        elif event == "end":
            for i in range(len(steps) - 1, -1, -1):
                if steps[i][0] == ev.get("step"):
                    del steps[i]
                    break
            bar = None
            clear()
        elif event == "progress":
            bar = ev
        if level == "error":
            say("err", msg)
        elif level == "notice":
            say("warn", msg)
        elif level == "info":
            for role, events in RVEIL_ROLES.items():
                if event in events:
                    say(role, msg)
                    break
        draw()

    fd = sys.stdin.fileno()
    pending = b""
    while True:
        ready, _, _ = select.select([fd], [], [], 0.1)
        if not ready:
            draw()
            continue
        chunk = os.read(fd, 1 << 16)
        if not chunk:
            break
        pending += chunk
        *lines, pending = pending.split(b"\n")
        for line in lines:
            handle(line.decode("utf-8", "replace"))
    if pending.strip():
        handle(pending.decode("utf-8", "replace"))
    clear()
    out.flush()
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(prog="xstream")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("rclonebar")
    p.add_argument("--label", default="")
    p.set_defaults(fn=cmd_rclonebar)

    p = sub.add_parser("rveillog")
    p.add_argument("--role", nargs=3, action="append", default=[], metavar=("NAME", "ICON", "SGR"))
    p.set_defaults(fn=cmd_rveillog)

    args = parser.parse_args()
    try:
        return args.fn(args)
    except BrokenPipeError:
        return 1
    except KeyboardInterrupt:  # Ctrl-C: the calling command reports it
        return 130


if __name__ == "__main__":
    sys.exit(main())
