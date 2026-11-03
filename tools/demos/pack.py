"""Turn a `script` recording into a replay file for assets/term.js.

usage: python3 -I pack.py RAW TIMING OUT --cmd "curl … | bash" [options]

The output is the script's own terminal stream (ANSI SGR colours, \\r
spinner frames, cursor moves …) with a typed prompt in front and two
private OSC sequences that real terminals ignore, so `cat OUT` still looks
right in a terminal:

  ESC ] 999 ; t BEL  …text…  ESC ] 999 ; /t BEL   type …text… like a keyboard
  ESC ] 999 ; w=<ms> BEL                          pause <ms> milliseconds

Real pauses from the recording are compressed (SPEED, MAX_PAUSE) and long
spinner runs are thinned to --max-frames redraws so a replay stays short.
"""
import argparse
import re

ap = argparse.ArgumentParser()
ap.add_argument("raw")
ap.add_argument("timing")
ap.add_argument("out")
ap.add_argument("--cmd", required=True, help="command shown as typed at the prompt")
ap.add_argument("--host", default="catlab-01")
ap.add_argument("--max-frames", type=int, default=14, help="max redraws kept per spinner run")
ap.add_argument("--speed", type=float, default=0.5, help="pause scale factor")
ap.add_argument("--max-pause", type=int, default=900, help="longest pause kept (ms)")
ap.add_argument("--sub", action="append", default=[], help="OLD=NEW byte substitution (paths)")
ap.add_argument("--drop", action="append", default=[], help="drop output lines containing this text")
a = ap.parse_args()

MERGE_S = 0.008      # writes closer than this belong to the same burst
MIN_PAUSE = 40       # shorter pauses are dropped (the player paces lines itself)
FRAME_MS = (55, 110)  # clamp for a kept spinner redraw

raw = open(a.raw, "rb").read()
if raw.startswith(b"Script started"):
    raw = raw[raw.index(b"\n") + 1:]

chunks = []  # [delay_seconds, bytes]
pos = 0
for line in open(a.timing):
    parts = line.split()
    if len(parts) != 2:
        continue
    d, n = float(parts[0]), int(parts[1])
    chunks.append([d, raw[pos:pos + n]])
    pos += n

# Merge bursts; never start a chunk with a UTF-8 continuation byte.
merged = []
for d, b in chunks:
    if merged and (d < MERGE_S or (b and 0x80 <= b[0] <= 0xBF)):
        merged[-1][1] += b
    else:
        merged.append([d, b])

subs = []
for s in a.sub:
    old, new = s.split("=", 1)
    subs.append((old.encode(), new.encode()))
drops = [re.compile(rb"[^\n]*" + re.escape(d.encode()) + rb"[^\n]*\n") for d in a.drop]
for c in merged:
    for old, new in subs:
        c[1] = c[1].replace(old, new)
    for rx in drops:
        c[1] = rx.sub(b"", c[1])

FRAME_RE = re.compile(rb"^(?:\x1b\[[0-9;?]*[A-Za-z])*\r(?!\n)")


def is_frame(b):
    return bool(FRAME_RE.match(b)) and b"\n" not in b


# Thin long runs of redraws: keep max_frames evenly spaced, always the last.
out_chunks = []
i = 0
while i < len(merged):
    if not is_frame(merged[i][1]):
        out_chunks.append((merged[i][0], merged[i][1], False))
        i += 1
        continue
    j = i
    while j < len(merged) and is_frame(merged[j][1]):
        j += 1
    run = merged[i:j]
    keep = len(run)
    if keep > a.max_frames:
        step = (len(run) - 1) / (a.max_frames - 1)
        idx = sorted({round(k * step) for k in range(a.max_frames)})
        run = [run[k] for k in idx]
    for d, b in run:
        out_chunks.append((d, b, True))
    i = j


def wait(ms):
    return b"\x1b]999;w=%d\x07" % ms


body = bytearray()
for d, b, frame in out_chunks:
    ms = int(d * 1000 * a.speed)
    if frame:
        ms = max(FRAME_MS[0], min(ms, FRAME_MS[1]))
    else:
        ms = min(ms, a.max_pause)
    if ms >= MIN_PAUSE and body:
        body += wait(ms)
    body += b

# One blank line between the output and the closing prompt.
body = re.sub(rb"[\r\n]+\Z", b"", bytes(body)) + b"\r\n\r\n"

prompt = ("\x1b[1;38;5;114mroot@%s\x1b[0m:\x1b[1;38;5;81m~\x1b[0m# " % a.host).encode()
typed = b"\x1b]999;t\x07" + a.cmd.encode() + b"\x1b]999;/t\x07\r\n"
data = prompt + typed + body + prompt

with open(a.out, "wb") as fh:
    fh.write(data)
print("%s: %d bytes, %d chunks" % (a.out, len(data), len(out_chunks)))
