#!/usr/bin/env python3
"""A stand-in RTMP ingest server for the live-streaming test (tests/live).

Accepts publishers like Twitch / YouTube / Kick do (handshake, connect, createStream, publish),
records what they send, and checks it: metadata, an H.264 sequence header with SPS/PPS, a first
keyframe that is an IDR picture, well-formed length-prefixed NAL units, an AAC sequence header,
steady timestamps and the reply to a ping. Stream key "bad-key" is refused the way a real
service refuses a wrong key. Writes each good stream to an .flv file (checked with ffprobe /
ffmpeg when they're installed).

Usage: fake_rtmp_server.py --port 19350 --out DIR [--streams 2] [--min-seconds 4]
Exit code 0 when every expected stream arrived and passed.
"""
import argparse
import asyncio
import json
import os
import shutil
import struct
import subprocess
import sys

# ---------- AMF0 ----------

def amf_encode(value):
    if value is None:
        return b"\x05"
    if isinstance(value, bool):
        return b"\x01" + (b"\x01" if value else b"\x00")
    if isinstance(value, (int, float)):
        return b"\x00" + struct.pack(">d", float(value))
    if isinstance(value, str):
        raw = value.encode()
        return b"\x02" + struct.pack(">H", len(raw)) + raw
    if isinstance(value, dict):
        out = b"\x03"
        for key, item in value.items():
            raw = key.encode()
            out += struct.pack(">H", len(raw)) + raw + amf_encode(item)
        return out + b"\x00\x00\x09"
    raise TypeError(value)


def amf_decode_all(data):
    values, i = [], 0
    while i < len(data):
        value, i = amf_decode(data, i)
        values.append(value)
    return values


def amf_decode(data, i):
    marker = data[i]
    i += 1
    if marker == 0x00:
        return struct.unpack(">d", data[i:i + 8])[0], i + 8
    if marker == 0x01:
        return data[i] != 0, i + 1
    if marker == 0x02:
        (n,) = struct.unpack(">H", data[i:i + 2])
        return data[i + 2:i + 2 + n].decode(), i + 2 + n
    if marker in (0x03, 0x08):
        if marker == 0x08:
            i += 4
        obj = {}
        while True:
            (n,) = struct.unpack(">H", data[i:i + 2])
            i += 2
            if n == 0:
                assert data[i] == 0x09, "object end marker"
                return obj, i + 1
            key = data[i:i + n].decode()
            i += n
            obj[key], i = amf_decode(data, i)
    if marker in (0x05, 0x06):
        return None, i
    raise ValueError("AMF0 marker %#x" % marker)

# ---------- chunks ----------

class Connection:
    def __init__(self, reader, writer, server):
        self.reader, self.writer, self.server = reader, writer, server
        self.in_chunk = 128
        self.out_chunk = 128
        self.streams = {}
        self.key = None
        self.messages = []          # (type, timestamp, payload) of media and data
        self.commands = []
        self.pong = False
        self.publishing = False

    async def read_exact(self, n):
        return await self.reader.readexactly(n)

    async def handshake(self):
        c0c1 = await self.read_exact(1537)
        assert c0c1[0] == 3, "RTMP version 3"
        s1 = struct.pack(">II", 0, 0) + os.urandom(1528)
        self.writer.write(b"\x03" + s1 + c0c1[1:])
        await self.writer.drain()
        c2 = await self.read_exact(1536)
        assert c2[8:] == s1[8:], "C2 echoes S1"

    def send(self, csid, msg_type, payload, stream_id=0, timestamp=0):
        out = bytes([csid]) + timestamp.to_bytes(3, "big") + len(payload).to_bytes(3, "big")
        out += bytes([msg_type]) + struct.pack("<I", stream_id)
        for i in range(0, max(len(payload), 1), self.out_chunk):
            if i:
                out += bytes([0xC0 | csid])
            out += payload[i:i + self.out_chunk]
        self.writer.write(out)

    def send_command(self, values, stream_id=0):
        self.send(3, 20, b"".join(amf_encode(v) for v in values), stream_id)

    async def read_message(self):
        while True:
            first = (await self.read_exact(1))[0]
            fmt, csid = first >> 6, first & 0x3F
            if csid == 0:
                csid = 64 + (await self.read_exact(1))[0]
            elif csid == 1:
                b = await self.read_exact(2)
                csid = 64 + b[0] + b[1] * 256
            st = self.streams.setdefault(csid, {"ts": 0, "delta": 0, "len": 0, "type": 0, "sid": 0, "ext": False, "buf": b""})
            header = await self.read_exact([11, 7, 3, 0][fmt])
            field = None
            if fmt <= 2:
                field = int.from_bytes(header[0:3], "big")
                st["ext"] = field == 0xFFFFFF
            if fmt <= 1:
                st["len"] = int.from_bytes(header[3:6], "big")
                st["type"] = header[6]
            if fmt == 0:
                st["sid"] = struct.unpack("<I", header[7:11])[0]
            if st["ext"]:
                field = int.from_bytes(await self.read_exact(4), "big")
            if not st["buf"]:
                if fmt == 0:
                    st["ts"] = field
                elif fmt in (1, 2):
                    st["delta"] = field
                    st["ts"] += field
                else:
                    st["ts"] += st["delta"]
            want = min(self.in_chunk, st["len"] - len(st["buf"]))
            st["buf"] += await self.read_exact(want)
            if len(st["buf"]) >= st["len"]:
                payload, st["buf"] = st["buf"], b""
                return st["type"], st["sid"], st["ts"], payload

    async def run(self):
        await self.handshake()
        while True:
            try:
                msg_type, sid, ts, payload = await self.read_message()
            except asyncio.IncompleteReadError:
                return
            if msg_type == 1:
                self.in_chunk = struct.unpack(">I", payload)[0] & 0x7FFFFFFF
            elif msg_type == 4:
                event = struct.unpack(">H", payload[:2])[0]
                if event == 7:
                    self.pong = True
            elif msg_type == 20:
                values = amf_decode_all(payload)
                self.commands.append(values[0])
                await self.command(values)
                if values[0] == "deleteStream":
                    return
            elif msg_type in (8, 9, 18):
                assert self.publishing, "media only after NetStream.Publish.Start"
                self.messages.append((msg_type, ts, payload))

    async def command(self, values):
        name, txn = values[0], values[1]
        if name == "connect":
            app = values[2].get("app")
            assert app == "app", "app name from the URL path (got %r)" % app
            assert values[2].get("tcUrl", "").startswith("rtmp://"), "tcUrl"
            self.send(2, 5, struct.pack(">I", 2500000))
            self.send(2, 6, struct.pack(">IB", 2500000, 2))
            self.send(2, 1, struct.pack(">I", 4096))
            self.out_chunk = 4096
            # A ping the client must answer.
            self.send(2, 4, struct.pack(">HI", 6, 12345))
            self.send_command(["_result", txn, {"fmsVer": "FMS/3,0,1,123", "capabilities": 31},
                               {"level": "status", "code": "NetConnection.Connect.Success",
                                "description": "Connection succeeded.", "padding": "x" * 5000}])
        elif name == "createStream":
            self.send_command(["_result", txn, None, 1])
        elif name == "publish":
            self.key = values[3]
            if self.key == "bad-key":
                self.send_command(["onStatus", 0, None, {"level": "error", "code": "NetStream.Publish.BadName",
                                                         "description": "Invalid stream key"}], 1)
            else:
                self.publishing = True
                self.send_command(["onStatus", 0, None, {"level": "status", "code": "NetStream.Publish.Start",
                                                         "description": "Publishing"}], 1)
        await self.writer.drain()

# ---------- checks ----------

def nal_units(data):
    units, i = [], 0
    while i < len(data):
        assert i + 4 <= len(data), "NAL length prefix"
        (n,) = struct.unpack(">I", data[i:i + 4])
        assert 0 < n <= len(data) - i - 4, "NAL length %d fits" % n
        units.append(data[i + 4:i + 4 + n])
        i += 4 + n
    return units


def check(connection, min_seconds, out_dir, index):
    report = {"key": connection.key, "pong": connection.pong}
    problems = []

    def need(condition, message):
        if not condition:
            problems.append(message)

    meta = [p for t, _, p in connection.messages if t == 18]
    need(meta, "metadata (@setDataFrame onMetaData)")
    if meta:
        values = amf_decode_all(meta[0])
        need(values[:2] == ["@setDataFrame", "onMetaData"], "metadata header")
        info = values[2] if len(values) > 2 else {}
        width, height = info.get("width") or 0, info.get("height") or 0
        report["size"] = [width, height]
        need(width >= 640 and width * 9 == height * 16, "metadata gives a 16:9 picture (%sx%s)" % (width, height))
        need(info.get("videocodecid") == 7 and info.get("audiocodecid") == 10, "metadata codecs H.264 + AAC")

    video = [(ts, p) for t, ts, p in connection.messages if t == 9]
    audio = [(ts, p) for t, ts, p in connection.messages if t == 8]
    report["video_messages"], report["audio_messages"] = len(video), len(audio)
    need(video and video[0][1][:2] == b"\x17\x00", "first video message is the AVC sequence header")
    if video and video[0][1][:2] == b"\x17\x00":
        record = video[0][1][5:]
        need(record[0] == 1 and record[4] == 0xFF and record[5] & 0x1F == 1, "AVCDecoderConfigurationRecord")
        sps_len = struct.unpack(">H", record[6:8])[0]
        sps = record[8:8 + sps_len]
        pps_len = struct.unpack(">H", record[9 + sps_len:11 + sps_len])[0]
        need(sps and sps[0] & 0x1F == 7, "SPS NAL")
        need(record[11 + sps_len] & 0x1F == 8 if pps_len else False, "PPS NAL")
        need(record[1:4] == sps[1:4], "profile/level match the SPS")
    frames = [(ts, p) for ts, p in video if p[1] == 1]
    need(frames and frames[0][1][0] == 0x17, "first frame is a keyframe")
    keyframes = 0
    try:
        for i, (ts, p) in enumerate(frames):
            units = nal_units(p[5:])
            types = {u[0] & 0x1F for u in units}
            if p[0] == 0x17:
                keyframes += 1
                need(5 in types, "keyframe %d holds an IDR picture (NAL types %s)" % (i, sorted(types)))
    except AssertionError as error:
        problems.append("video NAL units: %s" % error)
    report["keyframes"] = keyframes
    need(len(frames) >= min_seconds * 30 * 0.8, "about 30 frames a second (%d frames)" % len(frames))
    need(keyframes >= 2, "a keyframe every 2 seconds or so (%d)" % keyframes)
    stamps = [ts for ts, _ in frames]
    need(all(b >= a for a, b in zip(stamps, stamps[1:])), "video timestamps never go back")
    gaps = [b - a for a, b in zip(stamps, stamps[1:])]
    if gaps:
        report["video_gap_ms"] = [min(gaps), max(gaps)]
        need(min(gaps) >= 30 and max(gaps) <= 400, "frames ~33 ms apart (gaps %s..%s ms)" % (min(gaps), max(gaps)))

    need(audio and audio[0][1][:4] == b"\xaf\x00\x11\x90", "first audio message is the AAC LC 48 kHz stereo config")
    packets = [(ts, p) for ts, p in audio if p[:2] == b"\xaf\x01"]
    report["aac_packets"] = len(packets)
    need(len(packets) >= min_seconds * 46 * 0.7, "about 47 AAC packets a second (%d)" % len(packets))
    astamps = [ts for ts, _ in packets]
    need(all(b >= a for a, b in zip(astamps, astamps[1:])), "audio timestamps never go back")
    if stamps and astamps:
        report["last_video_ms"], report["last_audio_ms"] = stamps[-1], astamps[-1]
        need(abs(stamps[-1] - astamps[-1]) < 1000, "sound and picture stay within a second")
    need(connection.pong, "answers the server's ping")

    # Write an FLV for ffprobe / ffmpeg and for people to watch.
    path = os.path.join(out_dir, "stream%d.flv" % index)
    with open(path, "wb") as f:
        f.write(b"FLV\x01\x05\x00\x00\x00\x09\x00\x00\x00\x00")
        for t, ts, p in connection.messages:
            tag = bytes([t]) + len(p).to_bytes(3, "big") + (ts & 0xFFFFFF).to_bytes(3, "big") + bytes([ts >> 24 & 0xFF]) + b"\x00\x00\x00"
            f.write(tag + p + struct.pack(">I", len(tag) + len(p)))
    report["flv"] = path
    if shutil.which("ffprobe"):
        probe = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=codec_name,width,height,sample_rate,channels",
                                "-of", "json", path], capture_output=True, text=True)
        streams = json.loads(probe.stdout or "{}").get("streams", [])
        report["ffprobe"] = streams
        codecs = {s.get("codec_name") for s in streams}
        need({"h264", "aac"} <= codecs, "ffprobe sees H.264 and AAC (%s)" % sorted(c for c in codecs if c))
    if shutil.which("ffmpeg"):
        decode = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "null", "-"], capture_output=True, text=True)
        errors = [line for line in decode.stderr.splitlines() if line.strip()]
        report["ffmpeg_errors"] = errors[:5]
        need(decode.returncode == 0 and not errors, "ffmpeg decodes the whole stream cleanly")
    report["problems"] = problems
    return report


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=19350)
    parser.add_argument("--out", default=".")
    parser.add_argument("--streams", type=int, default=2, help="connections to wait for")
    parser.add_argument("--min-seconds", type=float, default=4)
    parser.add_argument("--timeout", type=float, default=120)
    args = parser.parse_args()
    os.makedirs(args.out, exist_ok=True)
    done = []
    finished = asyncio.Event()

    async def handle(reader, writer):
        connection = Connection(reader, writer, None)
        try:
            await connection.run()
        except Exception as error:  # report, don't crash the server
            connection.error = repr(error)
        finally:
            writer.close()
        done.append(connection)
        if len(done) >= args.streams:
            finished.set()

    server = await asyncio.start_server(handle, "127.0.0.1", args.port)
    print("fake RTMP server listening on %d" % args.port, flush=True)
    try:
        await asyncio.wait_for(finished.wait(), args.timeout)
    except asyncio.TimeoutError:
        print("FAIL only %d of %d streams arrived" % (len(done), args.streams))
    server.close()

    failures = 0 if len(done) >= args.streams else 1
    reports = []
    for index, connection in enumerate(done):
        if getattr(connection, "error", None) and connection.key != "bad-key":
            print("FAIL stream %d (key %r): %s" % (index, connection.key, connection.error))
            failures += 1
            continue
        if connection.key == "bad-key":
            ok = not connection.messages
            print(("ok  " if ok else "FAIL") + " a refused key sends no media")
            failures += 0 if ok else 1
            continue
        report = check(connection, args.min_seconds, args.out, index)
        reports.append(report)
        for problem in report["problems"]:
            print("FAIL %s" % problem)
        failures += len(report["problems"])
        print("stream %d: %s" % (index, json.dumps({k: v for k, v in report.items() if k != "problems"})))
    with open(os.path.join(args.out, "report.json"), "w") as f:
        json.dump(reports, f, indent=1)
    print("all live stream checks passed" if not failures else "%d live stream check(s) failed" % failures)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    asyncio.run(main())
