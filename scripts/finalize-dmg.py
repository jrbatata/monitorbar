#!/usr/bin/env python3
"""Bind the Finder background to actual HFS+ catalog identities, without mounting.

Only edits the .DS_Store data fork in a newly generated, unmounted HFS image.
No catalog changes or filesystem allocations. Fails if the layout is unexpected.
"""
import pathlib
import plistlib
import struct
import sys

image_path, template_path, verified_path = map(pathlib.Path, sys.argv[1:4])
image = bytearray(image_path.read_bytes())
u16 = lambda b, p: struct.unpack_from(">H", b, p)[0]
u32 = lambda b, p: struct.unpack_from(">I", b, p)[0]
p16 = lambda n: struct.pack(">H", n & 0xffff)
p32 = lambda n: struct.pack(">I", n & 0xffffffff)
assert image[512:514] == b"PM", "Expected Apple Partition Map"
partitions = u32(image, 516)
base = None
for index in range(1, partitions + 1):
    offset = index * 512
    if image[offset + 48:offset + 80].rstrip(b"\0") == b"Apple_HFS":
        base = u32(image, offset + 8) * 512
        break
assert base is not None
header = base + 1024
assert image[header:header + 2] == b"H+", "Only HFS+ images supported"
volume_date = u32(image, header + 16)
block_size = u32(image, header + 40)

def fork_at(buffer, offset):
    size = struct.unpack_from(">Q", buffer, offset)[0]
    extents = [struct.unpack_from(">II", buffer, offset + 16 + 8 * i) for i in range(8)]
    ranges = [(base + start * block_size, count * block_size) for start, count in extents if count]
    assert sum(length for _, length in ranges) >= size, "Overflow extents unsupported"
    return size, ranges

def read_fork(fork):
    size, ranges = fork
    return b"".join(image[start:start + length] for start, length in ranges)[:size]

catalog = read_fork(fork_at(image, header + 272))
node_size = u16(catalog, 32)
node_id = u32(catalog, 24)
files = {}
volume_name = None
volume_utc_date = None
seen = set()
while node_id:
    assert node_id not in seen, "Catalog cycle"
    seen.add(node_id)
    node = catalog[node_id * node_size:(node_id + 1) * node_size]
    assert node[8] == 255, "Expected catalog leaf"
    for index in range(u16(node, 10)):
        offset = u16(node, node_size - 2 * (index + 1))
        key_length = u16(node, offset)
        parent = u32(node, offset + 2)
        name_length = u16(node, offset + 6)
        name = node[offset + 8:offset + 8 + 2 * name_length].decode("utf-16be")
        record = offset + 2 + key_length
        kind = u16(node, record)
        if kind == 1 and parent == 1 and u32(node, record + 8) == 2:
            volume_name = name
            volume_utc_date = u32(node, record + 12)
        if kind == 2 and parent == 2:
            files[name] = (u32(node, record + 8), u32(node, record + 12), fork_at(node, record + 88))
    node_id = u32(node, 0)
assert volume_name and '.background.tiff' in files and '.DS_Store' in files
assert volume_utc_date is not None
# The alias's legacy dates are in local time; high-resolution tags are UTC.
# HFS image creation preserves both via volume header and root catalog dates.
legacy_offset = volume_date - volume_utc_date
assert abs(legacy_offset) <= 86400
file_id, file_date, background_fork = files['.background.tiff']
assert read_fork(background_fork)[:4] in (b'II*\0', b'MM\0*'), "Background is not a TIFF"

store = bytearray(template_path.read_bytes())
allocator = u32(store, 8) + 4
addresses = [u32(store, allocator + 8 + 4 * i) for i in range(u32(store, allocator))]
master = (addresses[1] & ~31) + 4
leaf = (addresses[u32(store, master)] & ~31) + 4
assert u32(store, leaf) == 0, "Only a single leaf is supported"
count = u32(store, leaf + 4)
cursor = leaf + 8
entries = []
for _ in range(count):
    start = cursor
    name_length = u32(store, cursor); cursor += 4
    name = bytes(store[cursor:cursor + name_length * 2]).decode('utf-16be'); cursor += name_length * 2
    key = bytes(store[cursor:cursor + 4]); kind = bytes(store[cursor + 4:cursor + 8]); cursor += 8
    prefix = bytes(store[start:cursor])
    if kind == b'blob':
        length = u32(store, cursor); cursor += 4
        value = bytes(store[cursor:cursor + length]); cursor += length
        if name == '.' and key == b'icvp':
            options = plistlib.loads(value)
            alias = bytearray(options['backgroundImageAlias'][:150])
            alias[38:42] = p32(volume_date)
            alias[46:50] = p32(2)
            alias[114:118] = p32(file_id)
            alias[118:122] = p32(file_date + legacy_offset)
            alias[134:138] = p32(0x902)  # Native HFS disk-image volume attributes.
            def tag(kind, data):
                return p16(kind) + p16(len(data)) + data + b'\0' * (len(data) % 2)
            alias += tag(0, volume_name.encode())
            alias += tag(16, struct.pack('>Q', volume_utc_date << 16))
            alias += tag(17, struct.pack('>Q', file_date << 16))
            alias += tag(1, b'')
            alias += tag(2, (volume_name + ':.background.tiff').encode())
            for kind, name in [(14, '.background.tiff'), (15, volume_name)]:
                data = name.encode('utf-16be')
                alias += tag(kind, p16(len(data) // 2) + data)
            alias += tag(18, b'/.background.tiff')
            alias += tag(19, ('/Volumes/' + volume_name).encode())
            alias += p16(-1) + p16(0)
            alias[4:6] = p16(len(alias))
            options['backgroundImageAlias'] = bytes(alias)
            value = plistlib.dumps(options, fmt=plistlib.FMT_BINARY)
        entries.append(prefix + p32(len(value)) + value)
    else:
        assert kind in (b'long', b'type')
        entries.append(prefix + bytes(store[cursor:cursor + 4])); cursor += 4
payload = p32(0) + p32(count) + b''.join(entries)
assert len(payload) <= 4096
store[leaf:leaf + 4096] = payload.ljust(4096, b'\0')
size, ranges = files['.DS_Store'][2]
assert len(store) == size, "Must not resize a data fork"
position = 0
for start, length in ranges:
    chunk = store[position:position + length]
    image[start:start + len(chunk)] = chunk
    position += len(chunk)
    if position == size:
        break
assert read_fork(files['.DS_Store'][2]) == store
image_path.write_bytes(image)
verified_path.write_bytes(store)
print(f'Bound background: volume={volume_name!r}, volumeDate={volume_date}, parent=2, fileID={file_id}, fileDate={file_date}')
