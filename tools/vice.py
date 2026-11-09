#!/usr/bin/env python3
"""Closed-loop debugging of the game in VICE via its binary monitor protocol.

Usage (each call connects, does its thing, resumes the emulator, disconnects).
Chain commands with a lone "," to keep the CPU halted between them, e.g.
  tools/vice.py until sprite_from_tile 60 , step 30 , sprites


  tools/vice.py start [--watch] [image]
                                     launch x64sc with the binary monitor on :6502;
                                     background-only (no focus steal), minimized,
                                     emulator sound off, warp speed
                                     (--watch: normal window, sound, real time)
  tools/vice.py play [image]         a window just for playing (no monitor port)
  tools/vice.py stop                 quit VICE
  tools/vice.py shot [file.png]      screenshot (visible area, 2x scaled)
  tools/vice.py peek ADDR [LEN]      hex dump; ADDR may be a label from mygame.vs
  tools/vice.py poke ADDR BYTE...    write bytes
  tools/vice.py regs                 show CPU registers
  tools/vice.py keys [KEY...]        hold keys (e.g. `keys W J`); no args releases
  tools/vice.py tap FRAMES KEY...    hold keys for FRAMES video frames then release
  tools/vice.py frames N             run exactly N video frames (50 = 1s on PAL)
  tools/vice.py wait SECONDS         let the emulator run (wall clock)
  tools/vice.py until ADDR [TIMEOUT] run until PC hits ADDR, print registers
  tools/vice.py watch ADDR [TIMEOUT] run until something stores to ADDR
  tools/vice.py step [N]            single-step N instructions, tracing PC/regs
  tools/vice.py reset                hard reset
  tools/vice.py sym NAME             look up a label

Keys are injected through the game's `debug_keys` table (see myvic2.s), so they
work even though the game scans the CIA keyboard matrix directly.
"""
import os
import socket
import struct
import subprocess
import sys
import time
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
# our own monitor port (not VICE's default 6502), so a VICE the user runs
# never gets touched by these tools
HOST, PORT = "127.0.0.1", 6510

# C64 keyboard matrix: key -> (row selected via $dc00 bit, column bit read on $dc01)
MATRIX = [
    ["DEL", "RETURN", "RIGHT", "F7", "F1", "F3", "F5", "DOWN"],
    ["3", "W", "A", "4", "Z", "S", "E", "LSHIFT"],
    ["5", "R", "D", "6", "C", "F", "T", "X"],
    ["7", "Y", "G", "8", "B", "H", "U", "V"],
    ["9", "I", "J", "0", "M", "K", "O", "N"],
    ["+", "P", "L", "-", ".", ":", "@", ","],
    ["POUND", "*", ";", "HOME", "RSHIFT", "=", "UP", "/"],
    ["1", "LEFT", "CTRL", "2", "SPACE", "C=", "Q", "STOP"],
]
KEYPOS = {k: (r, c) for r, row in enumerate(MATRIX) for c, k in enumerate(row)}


def symbols():
    """Parse KickAssembler's VICE label file (mygame.vs)."""
    syms = {}
    path = os.environ.get("VICE_SYMS", os.path.join(ROOT, "mygame.vs"))
    if os.path.exists(path):
        for line in open(path):
            parts = line.split()
            if len(parts) == 3 and parts[0] == "al":
                syms[parts[2].lstrip(".")] = int(parts[1].split(":")[1], 16)
    return syms


def addr(s):
    try:
        return int(s.replace("$", "0x"), 0)
    except ValueError:
        syms = symbols()
        if s in syms:
            return syms[s]
        if "+" in s:
            a, b = s.split("+", 1)
            return addr(a) + addr(b)
        sys.exit(f"unknown address/label: {s}")


class Vice:
    def __init__(self, timeout=10):
        self.sock = socket.create_connection((HOST, PORT), timeout=timeout)
        self.reqid = 0
        self.buf = b""
        self.events = []
        self.hits = {}          # checkpoint number -> hits seen

    def _recv(self, n):
        while len(self.buf) < n:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise ConnectionError("VICE closed the connection")
            self.buf += chunk
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def read_response(self):
        hdr = self._recv(12)
        stx, api, blen, rtype, err, rid = struct.unpack("<BBIBBI", hdr)
        assert stx == 2, "protocol desync"
        data = self._recv(blen)
        if rtype == 0x11 and rid == 0xFFFFFFFF and data[4]:   # checkpoint hit
            n = struct.unpack_from("<I", data)[0]
            self.hits[n] = self.hits.get(n, 0) + 1
        return rtype, err, rid, data

    def cmd(self, command, body=b""):
        self.reqid += 1
        rid = self.reqid
        self.sock.sendall(struct.pack("<BBIIB", 2, 2, len(body), rid, command) + body)
        while True:
            rtype, err, r, data = self.read_response()
            if r == rid:
                if err:
                    raise RuntimeError(f"VICE error {err:#x} for command {command:#x}")
                return rtype, data
            self.events.append((rtype, data))

    # --- commands -------------------------------------------------------
    def mem_get(self, start, length):
        end = start + length - 1
        _, d = self.cmd(0x01, struct.pack("<BHHBH", 0, start, end, 0, 0))
        (n,) = struct.unpack_from("<H", d)
        return d[2 : 2 + n]

    def mem_set(self, start, data):
        end = start + len(data) - 1
        self.cmd(0x02, struct.pack("<BHHBH", 0, start, end, 0, 0) + bytes(data))

    def regs(self):
        _, d = self.cmd(0x83, b"\x00")
        names = {}
        (n,) = struct.unpack_from("<H", d)
        off = 2
        for _ in range(n):
            size = d[off]
            rid, bits, nlen = d[off + 1], d[off + 2], d[off + 3]
            names[rid] = d[off + 4 : off + 4 + nlen].decode()
            off += size + 1
        _, d = self.cmd(0x31, b"\x00")
        (n,) = struct.unpack_from("<H", d)
        out, off = {}, 2
        for _ in range(n):
            size = d[off]
            rid, val = struct.unpack_from("<BH", d, off + 1)
            out[names.get(rid, rid)] = val
            off += size + 1
        return out

    def set_reg(self, name, value):
        """set a CPU register by name (as regs() reports them)"""
        _, d = self.cmd(0x83, b"\x00")
        (n,) = struct.unpack_from("<H", d)
        off, ids = 2, {}
        for _ in range(n):
            size = d[off]
            rid, nlen = d[off + 1], d[off + 3]
            ids[d[off + 4: off + 4 + nlen].decode()] = rid
            off += size + 1
        self.cmd(0x32, struct.pack("<BHBBH", 0, 1, 3, ids[name], value))

    def checkpoint(self, a, op=4):
        """op: 1=load, 2=store, 4=exec. Temporary, stops the CPU when hit.
        Returns the checkpoint number."""
        _, d = self.cmd(0x12, struct.pack("<HHBBBB", a, a, 1, 1, op, 1))
        return struct.unpack_from("<I", d)[0]

    def delete_checkpoint(self, num):
        try:
            self.cmd(0x13, struct.pack("<I", num))
        except RuntimeError:
            pass  # already gone (temporary checkpoints vanish when hit)

    # VICE semantics (measured, 3.10): any command stops a running emulator
    # and it stays stopped; *creating a checkpoint resumes it*. An "exit"
    # sent while running is queued and executed at the next stop, which
    # would immediately resume after a checkpoint hit. So we always ping
    # first (guaranteed stopped) before sending exit.
    def run_until_hit(self, num, timeout):
        """Resume and wait for checkpoint `num` to fire. True if it did.
        On return the CPU is halted at the checkpoint."""
        self.hits.pop(num, None)
        self.cmd(0x81)                    # stop (catches a hit that already happened)
        if self.hits.get(num):
            return True
        self.cmd(0xAA)
        deadline = time.time() + timeout
        self.sock.settimeout(1)
        try:
            while time.time() < deadline:
                try:
                    rtype, err, rid, data = self.read_response()
                except socket.timeout:
                    continue
                if self.hits.get(num):
                    return True
            return False
        finally:
            self.sock.settimeout(10)

    def frames(self, n):
        """Run exactly n video frames (counted on the game's raster IRQ).
        Deterministic and independent of warp/real-time speed."""
        syms = symbols()
        # ag_bot_body: reached once per frame both via the bottom IRQ and via
        # the swap IRQ chaining into the bottom work
        irq = next(syms[n] for n in ("ag_bot_body", "ag_irq_bot", "irq_bot", "irq") if n in syms)
        num = struct.unpack_from("<I", self.cmd(0x12, struct.pack(
            "<HHBBBB", irq, irq, 1, 1, 4, 0))[1])[0]
        try:
            for _ in range(n):
                if not self.run_until_hit(num, 10):
                    raise RuntimeError("IRQ handler not reached (game not running?)")
        finally:
            self.delete_checkpoint(num)

    def screenshot(self):
        _, d = self.cmd(0x84, b"\x01\x00")
        flen = struct.unpack_from("<I", d)[0]
        dw, dh, xo, yo, iw, ih, bpp = struct.unpack_from("<HHHHHHB", d, 4)
        blen = struct.unpack_from("<I", d, 4 + flen)[0]
        pix = d[8 + flen : 8 + flen + blen]
        _, p = self.cmd(0x91, b"\x01")
        (n,) = struct.unpack_from("<H", p)
        pal, off = [], 2
        for _ in range(n):
            size = p[off]
            pal.append(tuple(p[off + 1 : off + 4]))
            off += size + 1
        return dw, dh, xo, yo, iw, ih, pix, pal

    def resume(self):
        self.cmd(0x81)
        self.cmd(0xAA)

    def close(self, resume=True):
        if resume:
            self.resume()
        self.sock.close()


def write_png(path, w, h, rows):
    raw = b"".join(b"\x00" + r for r in rows)

    def chunk(t, data):
        c = struct.pack(">I", len(data)) + t + data
        return c + struct.pack(">I", zlib.crc32(t + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b"")
    open(path, "wb").write(png)


def do_shot(v, path, scale=2, border=32):
    dw, dh, xo, yo, iw, ih, pix, pal = v.screenshot()
    # crop to the 320x200 inner area plus some border
    x0, y0 = max(0, xo - border), max(0, yo - border)
    x1, y1 = min(dw, xo + iw + border), min(dh, yo + ih + border)
    lut = [bytes(c) * scale for c in pal]
    rows = []
    for y in range(y0, y1):
        line = pix[y * dw + x0 : y * dw + x1]
        row = b"".join(lut[i] for i in line)
        rows.extend([row] * scale)
    write_png(path, (x1 - x0) * scale, (y1 - y0) * scale, rows)
    print(path)


def set_keys(v, keys):
    mask = [0xFF] * 8
    for k in keys:
        k = k.upper()
        if k not in KEYPOS:
            sys.exit(f"unknown key {k}; known: {' '.join(KEYPOS)}")
        r, c = KEYPOS[k]
        mask[r] &= ~(1 << c) & 0xFF
    v.mem_set(addr("debug_keys"), mask)


def background_app():
    """macOS: wrap x64sc in a background-only .app bundle (LSBackgroundOnly)
    so launching it never steals focus or shows a dock icon."""
    import shutil
    app = os.path.join(ROOT, "build", "x64sc-bg.app")
    exe = os.path.join(app, "Contents", "MacOS", "x64sc")
    real = os.path.realpath(shutil.which("x64sc"))
    if not os.path.exists(exe) or os.path.getmtime(exe) < os.path.getmtime(real):
        os.makedirs(os.path.dirname(exe), exist_ok=True)
        shutil.copy2(real, exe)
        with open(os.path.join(app, "Contents", "Info.plist"), "w") as f:
            f.write("""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>x64sc</string>
<key>CFBundleIdentifier</key><string>local.vice.x64sc-background</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSBackgroundOnly</key><true/>
<key>LSUIElement</key><true/>
</dict></plist>
""")
    return app


def kill_ours():
    """Quit every VICE launched through our background wrapper (never a VICE
    the user started themselves), so stale instances cannot pile up."""
    subprocess.run(["pkill", "-f", os.path.join(ROOT, "build", "x64sc-bg.app")],
                   capture_output=True)
    for _ in range(50):
        if subprocess.run(["pgrep", "-f", os.path.join(ROOT, "build", "x64sc-bg.app")],
                          capture_output=True).returncode:
            return
        time.sleep(0.1)


def main(argv):
    if not argv:
        print(__doc__)
        return
    op, args = argv[0], argv[1:]
    if op == "play":
        # a window for playing: sound, real speed, *no* monitor port, so none
        # of these tools can pause, inspect or close it
        image = os.path.abspath(args[0]) if args else os.path.join(ROOT, "mygame.d64")
        subprocess.Popen(["x64sc", "-autostart", image], stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
        print("VICE (play) started")
        return
    if op == "start":
        # default: background-only (never takes focus), minimized, emulator
        # audio output off, warp speed. `start --watch` gives a normal
        # window with sound at real speed.
        watch = bool(args) and args[0] == "--watch"
        if watch:
            args = args[1:]
        image = os.path.abspath(args[0]) if args else os.path.join(ROOT, "mygame.d64")
        try:                                # one emulator at a time
            Vice(timeout=1).cmd(0xBB)
        except OSError:
            pass
        kill_ours()
        vice_args = ["-binarymonitor", "-binarymonitoraddress", f"ip4://{HOST}:{PORT}",
                     "-autostart", image, "+confirmonexit"] + args[1:]
        if watch:
            subprocess.Popen(["x64sc"] + vice_args, stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL, start_new_session=True)
        elif sys.platform == "darwin":
            subprocess.run(["open", "-g", "-j", "-n", background_app(), "--args"]
                           + vice_args + ["-minimized", "+sound", "-warp"], check=True)
        else:
            subprocess.Popen(["x64sc"] + vice_args + ["-minimized", "+sound", "-warp"],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                             start_new_session=True)
        for _ in range(100):
            try:
                Vice(timeout=1).close()
                if sys.platform == "darwin" and not watch:
                    # -minimized does not always hold: hide the app (like
                    # Cmd-H); emulation and the monitor are unaffected
                    subprocess.run(["osascript", "-e", 'tell application "System Events" to set '
                                    'visible of (every process whose name contains "x64sc-bg") to false'],
                                   capture_output=True)
                print("VICE up")
                return
            except OSError:
                time.sleep(0.2)
        sys.exit("VICE did not come up")
    if op == "sym":
        print(f"${addr(args[0]):04x}")
        return
    # Everything else talks to the monitor. Commands separated by "," run in
    # one connection, so the CPU stays halted between them (VICE resumes the
    # CPU whenever a monitor client disconnects).
    chain, cur = [], []
    for tok in argv:
        if tok == ",":
            chain.append(cur)
            cur = []
        else:
            cur.append(tok)
    chain.append(cur)
    try:
        v = Vice()
    except ConnectionRefusedError:
        if op == "stop":
            kill_ours()                 # nothing listening: clear strays
            return
        sys.exit("VICE is not running (tools/vice.py start)")
    try:
        for op, *args in chain:
            if op == "stop":
                try:
                    v.cmd(0xBB)
                except (OSError, ConnectionError):
                    pass
                kill_ours()
                return
            run_op(v, op, args)
    finally:
        try:
            v.close()
        except OSError:
            pass


def run_op(v, op, args):
    if True:
        if op == "shot":
            do_shot(v, args[0] if args else os.path.join(ROOT, "screenshots", "shot.png"))
        elif op == "peek":
            a = addr(args[0])
            n = int(args[1], 0) if len(args) > 1 else 64
            data = v.mem_get(a, n)
            for i in range(0, len(data), 16):
                print(f"{a + i:04x}: " + " ".join(f"{b:02x}" for b in data[i : i + 16]))
        elif op == "poke":
            v.mem_set(addr(args[0]), [int(b.replace("$", "0x"), 0) for b in args[1:]])
        elif op == "sprites":
            fields = ["xlo", "xhi", "y", "color", "pointer", "controller", "anim", "frame",
                      "delay", "gxlo", "gxhi", "gylo", "gyhi", "dxlo", "dxhi", "dylo", "dyhi",
                      "yhi", "order"]
            n = v.mem_get(addr("sprite2_count"), 1)[0]
            base = addr("sprite_data_2")
            table = v.mem_get(base, 32 * len(fields))
            print(f"sprite2_count={n}")
            print("   " + " ".join(f"{f:>5}" for f in fields))
            for i in range(max(n, int(args[0]) if args else 0)):
                print(f"{i:2} " + " ".join(f"{table[32 * j + i]:5}" for j in range(len(fields))))
        elif op == "regs":
            print(" ".join(f"{k}={val:04x}" for k, val in v.regs().items()))
        elif op == "keys":
            set_keys(v, args)
        elif op == "frames":
            v.frames(int(args[0]))
        elif op == "tap":
            set_keys(v, args[1:])
            v.frames(int(args[0]))
            set_keys(v, [])
        elif op in ("until", "watch"):
            a = addr(args[0])
            timeout = float(args[1]) if len(args) > 1 else 10
            num = v.checkpoint(a, 4 if op == "until" else 2)
            if not v.run_until_hit(num, timeout):
                print(f"timeout: nothing hit ${a:04x}")
                v.delete_checkpoint(num)
            print(" ".join(f"{k}={val:04x}" for k, val in v.regs().items()))
        elif op == "step":
            syms = sorted((a, n) for n, a in symbols().items())
            for _ in range(int(args[0]) if args else 1):
                v.cmd(0x71, struct.pack("<BH", 0, 1))
                r = v.regs()
                pc = r["PC"]
                lab = max(((a, n) for a, n in syms if a <= pc), default=(0, "?"))
                print(f"{pc:04x} {lab[1]}+{pc - lab[0]:<3} A={r['A']:02x} X={r['X']:02x} Y={r['Y']:02x} FL={r['FL']:02x}")
        elif op == "reset":
            v.cmd(0xCC, b"\x01")
        elif op == "wait":
            v.resume()
            time.sleep(float(args[0]))
            v.regs()  # any command halts the CPU again
        else:
            sys.exit(f"unknown op {op}")

if __name__ == "__main__":
    os.makedirs(os.path.join(ROOT, "screenshots"), exist_ok=True)
    main(sys.argv[1:])
