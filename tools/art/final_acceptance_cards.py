"""Narrow saved-native card corrections, preserving unrelated Aseprite chunks.

Orbit changes only layer order/cel indices. Anchor Exchange adds integer-spaced
incoming poses from the existing native machine components, keeping its contact
keys and every other layer untouched. Normal exporters remain authoritative.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys
import zlib
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
sys.path.insert(0, str(ROOT / 'tools/art'))
from build_power_art import read_ase
from build_defence003a import top

ORBIT = 'assets/source-art/power_identity_002c5/orbit_drive_cards.aseprite'
EXCHANGE = 'assets/source-art/defence003a/anchor_exchange_cards.aseprite'
EXPECTED_SOURCE_SHA256 = {'assets/source-art/power_identity_002c5/orbit_drive_cards.aseprite': '22a5e441af9c7a2be3cb82340e0e8001c8338b0c4504066b7bc4e48ac15e0e35', 'assets/source-art/defence003a/anchor_exchange_cards.aseprite': '516b63974a6992085364f8e1f96ffa6c5faf6c2907b9f933b21ac8e8486f73c8'}
ENTRY = {0: (82, 4), 1: (73, 7), 2: (65, 11), 3: (58, 16), 7: (63, 12), 8: (72, 6), 9: (82, 0)}

def sha(data): return hashlib.sha256(data).hexdigest()

def split(data):
    size, magic, count = struct.unpack_from('<IHH', data)
    assert size == len(data) and magic == 0xA5E0
    frames = []
    offset = 128
    for _ in range(count):
        header = data[offset:offset + 16]
        length, magic, old, duration, new = struct.unpack('<IHHH2xI', header)
        assert magic == 0xF1FA
        pos = offset + 16
        chunks = []
        for _ in range(new or old):
            length_chunk, kind = struct.unpack_from('<IH', data, pos)
            chunks.append((kind, data[pos + 6:pos + length_chunk]))
            pos += length_chunk
        assert pos == offset + length
        frames.append([header, chunks])
        offset += length
    assert offset == len(data)
    return data[:128], frames

def join(header, frames):
    output = bytearray(header)
    for saved_header, chunks in frames:
        payload = b''.join(struct.pack('<IH', len(data) + 6, kind) + data for kind, data in chunks)
        frame_header = bytearray(saved_header)
        struct.pack_into('<I', frame_header, 0, len(payload) + 16)
        output += frame_header + payload
    struct.pack_into('<I', output, 0, len(output))
    return bytes(output)

def change_orbit(data):
    header, frames = split(data)
    order = [0, 3, 1, 2, 4]
    chunks = frames[0][1]
    layer_positions = [i for i, (kind, _) in enumerate(chunks) if kind == 0x2004]
    assert len(layer_positions) == 5
    old_layers = [chunks[i] for i in layer_positions]
    for slot, index in zip(layer_positions, order): chunks[slot] = old_layers[index]
    mapping = {old: new for new, old in enumerate(order)}
    for _, chunks in frames:
        for i, (kind, payload) in enumerate(chunks):
            if kind != 0x2005: continue
            layer = struct.unpack_from('<H', payload)[0]
            chunks[i] = (kind, struct.pack('<H', mapping[layer]) + payload[2:])
    return join(header, frames)

def change_exchange(data):
    header, frames = split(data)
    for index, (_, chunks) in enumerate(frames):
        key = index % 12
        if key not in ENTRY: continue
        for i, (kind, payload) in enumerate(chunks):
            if kind != 0x2005 or struct.unpack_from('<H', payload)[0] != 2: continue
            layer, x, y, opacity, cel_type, z = struct.unpack_from('<HhhBHh', payload)
            width, height = struct.unpack_from('<HH', payload, 16)
            assert (x, y, opacity, cel_type, z, width, height) == (0, 0, 255, 2, 0, 64, 64)
            image = Image.frombytes('RGBA', (64, 64), zlib.decompress(payload[20:]))
            top(image, 'breaker', *ENTRY[key], key)
            chunks[i] = (kind, payload[:20] + zlib.compress(image.tobytes(), 9))
    return join(header, frames)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', required=True, type=Path)
    args = parser.parse_args()
    assert not args.out.exists(), 'Preserve prior correction proof'
    proof = {'scope': 'Only Orbit Drive card stacking and Anchor Exchange incoming poses. No redraw or interpolation; unrelated native chunks, tags, durations, pivots and layers preserved.', 'files': []}
    for relative, action in [(ORBIT, change_orbit), (EXCHANGE, change_exchange)]:
        path = ROOT / relative
        before = path.read_bytes()
        assert sha(before) == EXPECTED_SOURCE_SHA256[relative], 'Expected untouched ce4c795 master; refuse applying the correction twice'
        _, old_frames = split(before)
        _, old_meta = read_ase(path)
        after = action(before)
        _, new_frames = split(after)
        if relative == EXCHANGE:
            for index, ((_, old), (_, new)) in enumerate(zip(old_frames, new_frames)):
                for (kind, original), (new_kind, final) in zip(old, new):
                    assert kind == new_kind
                    may_change = kind == 0x2005 and struct.unpack_from('<H', original)[0] == 2 and index % 12 in ENTRY
                    assert may_change or original == final, ('Unrelated Exchange native chunk changed', index, kind)
        else:
            for (_, old), (_, new) in zip(old_frames, new_frames):
                for (kind, original), (new_kind, final) in zip(old, new):
                    assert kind == new_kind
                    if kind == 0x2005: assert original[2:] == final[2:], 'Orbit cel pixels changed'
                    elif kind != 0x2004: assert original == final, 'Orbit non-layer metadata changed'
        path.write_bytes(after)
        _, new_meta = read_ase(path)
        for key in ['cell', 'pivot', 'tags', 'durations_ms']: assert old_meta[key] == new_meta[key], key
        assert set(old_meta['layers']) == set(new_meta['layers'])
        proof['files'].append({'path': relative, 'before_sha256': sha(before), 'after_sha256': sha(after), 'before_metadata': old_meta, 'after_metadata': new_meta, 'unchanged_contact_keys': [4, 5, 6] if relative == EXCHANGE else None, 'authored_incoming_positions': ENTRY if relative == EXCHANGE else None})
    args.out.write_text(json.dumps(proof, indent=2) + '\n')
    print(json.dumps({'native_master_proof': str(args.out), 'masters': len(proof['files']), 'metadata_preserved': True}))

if __name__ == '__main__': main()
