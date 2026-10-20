"""Stream and key helpers for `x kdf`, `x seal`, `x unseal` and `x vault`.

Standard library only, run through `uv run --no-project`. Subcommands:

  hkdf --purpose P --id ID --name NAME   master key (base64url) on stdin
                                         -> per-archive passphrase on stdout
  selftest                               HKDF-SHA256 against RFC 5869 vectors
  hash [--meta F] [--expect HEX] [--sink]
                                         copy stdin to stdout (or swallow it
                                         with --sink), recording sha256 and
                                         length; --expect fails on mismatch
  pad [--meta F] [--no-pad]              copy stdin to stdout, then append
                                         Padmé padding as zstd skippable frames
  padme N                                print the Padmé bucket for N bytes

Design notes (see the x README for the whole scheme):
- Passphrase = base64url(HKDF-SHA256(ikm=master, salt=SALT,
  info=purpose || 0x00 || id || 0x00 || name)). Distinct purposes and names
  give independent keys; the master key never leaves this process.
- Padding is a run of zstd skippable frames (magic 0x184D2A50, LE32 length,
  zeros) so a stock `zstd -d` skips it: nothing has to strip it on the way
  back. The bucket is chosen on the whole inner stream (payload + frames).
"""

import argparse
import base64
import hashlib
import hmac
import json
import sys

SALT = b"x-vault/v1"
CHUNK = 1 << 20

SKIPPABLE_MAGIC = (0x184D2A50).to_bytes(4, "little")
FRAME_HEADER = 8
MAX_FRAME = FRAME_HEADER + 0xFFFFFFFF


def hkdf_sha256(ikm: bytes, salt: bytes, info: bytes, length: int) -> bytes:
    """RFC 5869 extract-then-expand."""
    prk = hmac.new(salt or bytes(32), ikm, hashlib.sha256).digest()
    okm, block, counter = b"", b"", 1
    while len(okm) < length:
        block = hmac.new(prk, block + info + bytes([counter]), hashlib.sha256).digest()
        okm += block
        counter += 1
    return okm[:length]


def b64url_decode(text: str) -> bytes:
    text = text.strip()
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))


def b64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def cmd_hkdf(args) -> int:
    master = b64url_decode(sys.stdin.readline())
    if len(master) != 32:
        print("master key must be 32 bytes (base64url)", file=sys.stderr)
        return 1
    info = b"\0".join(s.encode() for s in (args.purpose, args.id, args.name))
    print(b64url_encode(hkdf_sha256(master, SALT, info, 32)))
    return 0


def cmd_selftest(_args) -> int:
    # RFC 5869 appendix A, test cases 1-3 (SHA-256).
    vectors = [
        ("0b" * 22, "000102030405060708090a0b0c", "f0f1f2f3f4f5f6f7f8f9", 42,
         "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf"
         "34007208d5b887185865"),
        (bytes(range(0x00, 0x50)).hex(), bytes(range(0x60, 0xb0)).hex(),
         bytes(range(0xb0, 0x100)).hex(), 82,
         "b11e398dc80327a1c8e7f78c596a49344f012eda2d4efad8a050cc4c19afa97c"
         "59045a99cac7827271cb41c65e590e09da3275600c2f09b8367793a9aca3db71"
         "cc30c58179ec3e87c14c01d5c1f3434f1d87"),
        ("0b" * 22, "", "", 42,
         "8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d"
         "9d201395faa4b61a96c8"),
    ]
    for n, (ikm, salt, info, length, okm) in enumerate(vectors, 1):
        got = hkdf_sha256(bytes.fromhex(ikm), bytes.fromhex(salt), bytes.fromhex(info), length)
        if got.hex() != okm:
            print(f"RFC 5869 test case {n}: FAIL", file=sys.stderr)
            return 1
        print(f"RFC 5869 test case {n}: ok", file=sys.stderr)
    return 0


def write_meta(path, meta) -> None:
    if path:
        with open(path, "w") as f:
            json.dump(meta, f)
            f.write("\n")


def cmd_hash(args) -> int:
    digest, total = hashlib.sha256(), 0
    src, dst = sys.stdin.buffer, sys.stdout.buffer
    while chunk := src.read(CHUNK):
        digest.update(chunk)
        total += len(chunk)
        if not args.sink:
            dst.write(chunk)
    dst.flush()
    write_meta(args.meta, {"sha256": digest.hexdigest(), "bytes": total})
    if args.expect and not hmac.compare_digest(digest.hexdigest(), args.expect.lower()):
        print(f"sha256 mismatch: expected {args.expect}, got {digest.hexdigest()}",
              file=sys.stderr)
        return 1
    return 0


def padme(length: int) -> int:
    """Padmé (Nikitin et al., PETS 2019): leaks O(log log n) bits, <= 12% overhead."""
    if length < 2:
        return length
    e = length.bit_length() - 1
    s = e.bit_length()
    mask = (1 << (e - s)) - 1
    return (length + mask) & ~mask


def padding_frames(payload: int):
    """Yield skippable frames that bring `payload` up to its Padmé bucket."""
    target = padme(payload + FRAME_HEADER)
    rest = target - payload
    while rest:
        frame = min(rest, MAX_FRAME)
        if 0 < rest - frame < FRAME_HEADER:  # never leave a sliver too small for a header
            frame -= FRAME_HEADER
        body = frame - FRAME_HEADER
        yield SKIPPABLE_MAGIC + body.to_bytes(4, "little"), body
        rest -= frame


def cmd_pad(args) -> int:
    digest, payload = hashlib.sha256(), 0
    src, dst = sys.stdin.buffer, sys.stdout.buffer
    while chunk := src.read(CHUNK):
        digest.update(chunk)
        payload += len(chunk)
        dst.write(chunk)
    total = payload
    if not args.no_pad:
        zeros = bytes(CHUNK)
        for header, body in padding_frames(payload):
            digest.update(header)
            dst.write(header)
            while body:
                n = min(body, CHUNK)
                digest.update(zeros[:n])
                dst.write(zeros[:n])
                body -= n
            total += FRAME_HEADER + int.from_bytes(header[4:], "little")
    dst.flush()
    write_meta(args.meta, {"sha256": digest.hexdigest(), "bytes": total, "payload": payload})
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(prog="xstream")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("hkdf")
    p.add_argument("--purpose", required=True)
    p.add_argument("--id", required=True)
    p.add_argument("--name", required=True)
    p.set_defaults(fn=cmd_hkdf)

    sub.add_parser("selftest").set_defaults(fn=cmd_selftest)

    p = sub.add_parser("hash")
    p.add_argument("--meta")
    p.add_argument("--expect")
    p.add_argument("--sink", action="store_true")
    p.set_defaults(fn=cmd_hash)

    p = sub.add_parser("pad")
    p.add_argument("--meta")
    p.add_argument("--no-pad", action="store_true")
    p.set_defaults(fn=cmd_pad)

    p = sub.add_parser("padme")
    p.add_argument("n", type=int)
    p.set_defaults(fn=lambda a: print(padme(a.n)) or 0)

    args = parser.parse_args()
    try:
        return args.fn(args)
    except BrokenPipeError:
        return 1


if __name__ == "__main__":
    sys.exit(main())
