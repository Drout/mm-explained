#!/usr/bin/env python3
"""Extract Maniac Mansion room data from a 1541 disk image and render a PNG.

The script follows the current repository knowledge:
- room lookup tables are read from Track 1 / Sector 1, starting at byte $02
- each room entry stores sector first, then track
- room resources use the shared 4-byte header followed by room metadata
- tile definitions are stored as 4x8 multicolor tiles (8 bytes per tile)
- tile matrix and color layer are decompressed with the same hybrid RLE +
  4-symbol dictionary format used by the game

Output is a PNG written with only the Python standard library.
"""

from __future__ import annotations

import argparse
import struct
import sys
import zlib
from pathlib import Path


ROOM_TABLE_DISK_TRACK = 1
ROOM_TABLE_DISK_SECTOR = 1
ROOM_TABLE_DISK_OFFSET = 2
ROOM_TABLE_BYTES = 0x3A2

ROOM_SIDE_TABLE_OFFSET = 0x00
ROOM_SECTOR_TRACK_TABLE_OFFSET = 0x37
ROOM_COUNT = 55

ROOM_HEADER_SIZE = 4
ROOM_TILES_SIZE = 0x0800
RSRC_TYPE_ROOM = 0x03

ROOM_META_WIDTH = 0x00
ROOM_META_HEIGHT = 0x01
ROOM_META_BG0 = 0x03
ROOM_META_BG1 = 0x04
ROOM_META_BG2 = 0x05
ROOM_META_TILEDEF = 0x06
ROOM_META_TILEMATRIX = 0x08
ROOM_META_COLOR = 0x0A
ROOM_META_MASK = 0x0C
ROOM_META_MASKIDX = 0x0E
ROOM_META_OBJ_COUNT = 0x10
ROOM_META_BBOX_START = 0x11
ROOM_META_SOUND_COUNT = 0x12
ROOM_META_SCRIPT_COUNT = 0x13
ROOM_META_EXIT_SCRIPT = 0x14
ROOM_META_ENTRY_SCRIPT = 0x16

SECTORS_PER_TRACK = [
    0,
    *([21] * 17),
    *([19] * 7),
    *([18] * 6),
    *([17] * 5),
]

TRANSPARENT = (0, 0, 0)

C64_PALETTE = {
    0x00: (0x00, 0x00, 0x00),
    0x01: (0xFF, 0xFF, 0xFF),
    0x02: (0x88, 0x00, 0x00),
    0x03: (0xAA, 0xFF, 0xEE),
    0x04: (0xCC, 0x44, 0xCC),
    0x05: (0x00, 0xCC, 0x55),
    0x06: (0x00, 0x00, 0xAA),
    0x07: (0xEE, 0xEE, 0x77),
    0x08: (0xDD, 0x88, 0x55),
    0x09: (0x66, 0x44, 0x00),
    0x0A: (0xFF, 0x77, 0x77),
    0x0B: (0x33, 0x33, 0x33),
    0x0C: (0x77, 0x77, 0x77),
    0x0D: (0xAA, 0xFF, 0x66),
    0x0E: (0x00, 0x88, 0xFF),
    0x0F: (0xBB, 0xBB, 0xBB),
}


class DiskImage:
    def __init__(self, data: bytes) -> None:
        if len(data) < 174848:
            raise ValueError("disk image is too small to be a standard 35-track D64")
        self.data = data
        self.source_path = Path("<memory>")

    def sector_offset(self, track: int, sector: int) -> int:
        if track < 1 or track >= len(SECTORS_PER_TRACK):
            raise ValueError(f"invalid track {track}")
        if sector < 0 or sector >= SECTORS_PER_TRACK[track]:
            raise ValueError(f"invalid sector {sector} for track {track}")

        offset = 0
        for current_track in range(1, track):
            offset += SECTORS_PER_TRACK[current_track] * 256
        return offset + sector * 256

    def read_sector(self, track: int, sector: int) -> bytes:
        offset = self.sector_offset(track, sector)
        return self.data[offset : offset + 256]

    def next_physical_sector(self, track: int, sector: int) -> tuple[int, int]:
        sector += 1
        if sector >= SECTORS_PER_TRACK[track]:
            track += 1
            sector = 0
        if track >= len(SECTORS_PER_TRACK) or SECTORS_PER_TRACK[track] == 0:
            raise StopIteration
        return track, sector

    def read_sector_stream(self, track: int, sector: int):
        current_track = track
        current_sector = sector
        while True:
            raw_sector = self.read_sector(current_track, current_sector)
            next_track = raw_sector[0]
            next_sector = raw_sector[1]

            if next_track == 0:
                end_index = max(0, min(254, next_sector - 2))
                yield from raw_sector[2 : 2 + end_index]
                return

            yield from raw_sector[2:]
            current_track = next_track
            current_sector = next_sector

    def read_physical_sector_stream(self, track: int, sector: int, skip_bytes: int = 2):
        current_track = track
        current_sector = sector
        while True:
            raw_sector = self.read_sector(current_track, current_sector)
            if skip_bytes < 0 or skip_bytes > 255:
                raise ValueError(f"invalid skip_bytes value: {skip_bytes}")
            yield from raw_sector[skip_bytes:]
            try:
                current_track, current_sector = self.next_physical_sector(current_track, current_sector)
            except StopIteration:
                return

    def read_exact_stream(self, track: int, sector: int, count: int) -> bytes:
        stream = self.read_sector_stream(track, sector)
        data = bytearray()
        while len(data) < count:
            try:
                data.append(next(stream))
            except StopIteration as exc:
                raise ValueError(
                    f"disk chain ended after {len(data)} bytes; expected {count}"
                ) from exc
        return bytes(data)


class Decompressor:
    def __init__(self, source: bytes) -> None:
        if len(source) < 4:
            raise ValueError("compressed section is too short")
        self.source = source
        self.position = 4
        self.dictionary = bytes(source[:4])
        self.emit_mode = 0
        self.emit_remaining = 0
        self.run_symbol = 0

    def _read_byte(self) -> int:
        if self.position >= len(self.source):
            raise ValueError("compressed stream ended unexpectedly")
        value = self.source[self.position]
        self.position += 1
        return value

    def next_byte(self) -> int:
        if self.emit_remaining:
            self.emit_remaining -= 1
            if self.emit_mode == 0:
                return self._read_byte()
            return self.run_symbol

        control = self._read_byte()

        if control < 0x40:
            self.emit_remaining = control
            self.emit_mode = 0
            return self._read_byte()

        if control < 0x80:
            self.emit_remaining = control & 0x3F
            self.run_symbol = self._read_byte()
            self.emit_mode = 1
            return self.run_symbol

        self.emit_remaining = control & 0x1F
        dict_index = (control >> 5) & 0x03
        self.run_symbol = self.dictionary[dict_index]
        self.emit_mode = 1
        return self.run_symbol


def read_u16_le(data: bytes, offset: int) -> int:
    return data[offset] | (data[offset + 1] << 8)


def decompress_section(section: bytes, expected_size: int) -> bytes:
    decoder = Decompressor(section)
    output = bytearray()
    for _ in range(expected_size):
        output.append(decoder.next_byte())
    return bytes(output)


def parse_mc_order(spec: str) -> tuple[str, str, str, str]:
    parts = [p.strip().lower() for p in spec.split(",")]
    if len(parts) != 4:
        raise ValueError(
            f"invalid --mc-order format: {spec} (expected 4 comma-separated entries)"
        )
    allowed = {"b0", "b1", "b2", "fg"}
    if any(p not in allowed for p in parts):
        raise ValueError(
            f"invalid --mc-order entries: {spec} (allowed: b0,b1,b2,fg)"
        )
    if len(set(parts)) != 4:
        raise ValueError(
            f"invalid --mc-order entries: {spec} (must contain each of b0,b1,b2,fg exactly once)"
        )
    return (parts[0], parts[1], parts[2], parts[3])


def parse_room_metadata(resource: bytes) -> dict[str, int]:
    if len(resource) < ROOM_HEADER_SIZE + 0x18:
        raise ValueError("room resource is too short")

    meta_base = ROOM_HEADER_SIZE
    metadata = {
        "resource_size": read_u16_le(resource, 0),
        "resource_type": resource[2],
        "resource_index": resource[3],
        "width": resource[meta_base + ROOM_META_WIDTH],
        "height": resource[meta_base + ROOM_META_HEIGHT],
        "video_flag": resource[meta_base + ROOM_META_WIDTH + 2],
        "bg0": resource[meta_base + ROOM_META_BG0],
        "bg1": resource[meta_base + ROOM_META_BG1],
        "bg2": resource[meta_base + ROOM_META_BG2],
        "tile_defs_ofs": read_u16_le(resource, meta_base + ROOM_META_TILEDEF),
        "tile_matrix_ofs": read_u16_le(resource, meta_base + ROOM_META_TILEMATRIX),
        "color_layer_ofs": read_u16_le(resource, meta_base + ROOM_META_COLOR),
        "mask_layer_ofs": read_u16_le(resource, meta_base + ROOM_META_MASK),
        "mask_indexes_ofs": read_u16_le(resource, meta_base + ROOM_META_MASKIDX),
        "object_count": resource[meta_base + ROOM_META_OBJ_COUNT],
        "bbox_start_ofs": resource[meta_base + ROOM_META_BBOX_START],
        "sound_count": resource[meta_base + ROOM_META_SOUND_COUNT],
        "script_count": resource[meta_base + ROOM_META_SCRIPT_COUNT],
        "exit_script_ofs": read_u16_le(resource, meta_base + ROOM_META_EXIT_SCRIPT),
        "entry_script_ofs": read_u16_le(resource, meta_base + ROOM_META_ENTRY_SCRIPT),
    }
    return metadata


def decode_room_layers(resource: bytes) -> tuple[dict[str, int], bytes, bytes, bytes]:
    metadata = parse_room_metadata(resource)
    width = metadata["width"]
    height = metadata["height"]

    tile_defs = decompress_section(resource[metadata["tile_defs_ofs"] :], ROOM_TILES_SIZE)
    tile_matrix = decompress_section(
        resource[metadata["tile_matrix_ofs"] :], width * height
    )
    color_layer = decompress_section(
        resource[metadata["color_layer_ofs"] :], width * height
    )
    return metadata, tile_defs, tile_matrix, color_layer


def write_room_auxiliary_dumps(resource: bytes, output_dir: Path, room_number: int) -> None:
    metadata, tile_defs, tile_matrix, color_layer = decode_room_layers(resource)

    charset_path = output_dir / f"ROOM{room_number:02d}_charset.bin"
    tilemap_path = output_dir / f"ROOM{room_number:02d}_tilemap.bin"
    colorlayer_path = output_dir / f"ROOM{room_number:02d}_colorlayer.bin"

    output_dir.mkdir(parents=True, exist_ok=True)
    charset_path.write_bytes(tile_defs)
    tilemap_path.write_bytes(tile_matrix)
    colorlayer_path.write_bytes(color_layer)

    print(f"wrote charset: {charset_path} ({len(tile_defs)} bytes)")
    print(
        f"wrote tilemap: {tilemap_path} ({metadata['width']}x{metadata['height']} = {len(tile_matrix)} bytes)"
    )
    print(
        f"wrote color layer: {colorlayer_path} ({metadata['width']}x{metadata['height']} = {len(color_layer)} bytes)"
    )


def write_room_metadata_txt(
    resource: bytes,
    output_path: Path,
    room_number: int,
    track: int,
    sector: int,
    side: int,
    disk_source_path: Path,
) -> None:
    metadata = parse_room_metadata(resource)
    if metadata["resource_size"] != len(resource):
        raise ValueError(
            f"resource size mismatch: header says {metadata['resource_size']}, extracted {len(resource)} bytes"
        )

    output_lines = [
        f"room_number={room_number}",
        f"disk_image={disk_source_path}",
        f"disk_side_byte=0x{side:02X}",
        f"start_track={track}",
        f"start_sector={sector}",
        f"resource_size={metadata['resource_size']}",
        f"resource_type=0x{metadata['resource_type']:02X}",
        f"resource_index=0x{metadata['resource_index']:02X}",
        f"width_tiles={metadata['width']}",
        f"height_tiles={metadata['height']}",
        f"video_flag=0x{metadata['video_flag']:02X}",
        f"bg0=0x{metadata['bg0']:02X}",
        f"bg1=0x{metadata['bg1']:02X}",
        f"bg2=0x{metadata['bg2']:02X}",
        f"tile_defs_ofs=0x{metadata['tile_defs_ofs']:04X}",
        f"tile_matrix_ofs=0x{metadata['tile_matrix_ofs']:04X}",
        f"color_layer_ofs=0x{metadata['color_layer_ofs']:04X}",
        f"mask_layer_ofs=0x{metadata['mask_layer_ofs']:04X}",
        f"mask_indexes_ofs=0x{metadata['mask_indexes_ofs']:04X}",
        f"object_count={metadata['object_count']}",
        f"bbox_start_ofs=0x{metadata['bbox_start_ofs']:02X}",
        f"sound_count={metadata['sound_count']}",
        f"script_count={metadata['script_count']}",
        f"exit_script_ofs=0x{metadata['exit_script_ofs']:04X}",
        f"entry_script_ofs=0x{metadata['entry_script_ofs']:04X}",
    ]
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(output_lines) + "\n", encoding="utf-8")


def get_room_tables(disk: DiskImage) -> tuple[bytes, bytes]:
    table_stream = disk.read_physical_sector_stream(
        ROOM_TABLE_DISK_TRACK, ROOM_TABLE_DISK_SECTOR, skip_bytes=2
    )
    table_bytes = bytearray()
    while len(table_bytes) < ROOM_TABLE_BYTES:
        try:
            table_bytes.append(next(table_stream))
        except StopIteration as exc:
            raise ValueError(
                f"table area ended after {len(table_bytes)} bytes; expected {ROOM_TABLE_BYTES}"
            ) from exc
    table_bytes = bytes(table_bytes)
    side_table = table_bytes[ROOM_SIDE_TABLE_OFFSET : ROOM_SIDE_TABLE_OFFSET + ROOM_COUNT]
    sector_track_table = table_bytes[
        ROOM_SECTOR_TRACK_TABLE_OFFSET : ROOM_SECTOR_TRACK_TABLE_OFFSET + ROOM_COUNT * 2
    ]
    return side_table, sector_track_table


def room_disk_side(side_table: bytes, room_number: int) -> int:
    return side_table[room_number]


def room_start_sector(sector_track_table: bytes, room_number: int) -> tuple[int, int]:
    offset = room_number * 2
    sector = sector_track_table[offset]
    track = sector_track_table[offset + 1]
    return track, sector


def extract_room_resource(disk: DiskImage, start_track: int, start_sector: int) -> bytes:
    # Room payloads in this disk format start at byte 0 of the sector.
    stream = disk.read_physical_sector_stream(start_track, start_sector, skip_bytes=0)
    header = bytearray()
    while len(header) < ROOM_HEADER_SIZE:
        try:
            header.append(next(stream))
        except StopIteration as exc:
            raise ValueError("room resource ended before the header was complete") from exc

    total_size = header[0] | (header[1] << 8)
    resource = bytearray(header)
    while len(resource) < total_size:
        try:
            resource.append(next(stream))
        except StopIteration as exc:
            raise ValueError(
                f"room resource ended after {len(resource)} bytes; expected {total_size}"
            ) from exc
    return bytes(resource)


def render_room_png(
    resource: bytes,
    output_path: Path,
    room_number: int,
    mc_order: tuple[str, str, str, str],
) -> None:
    metadata, tile_defs, tile_matrix, color_layer = decode_room_layers(resource)
    resource_size = metadata["resource_size"]
    header_byte2 = metadata["resource_type"]
    header_byte3 = metadata["resource_index"]

    if resource_size != len(resource):
        raise ValueError(
            f"resource size mismatch: header says {resource_size}, extracted {len(resource)} bytes"
        )

    print(
        f"room size: {resource_size} bytes "
        f"(header bytes: ${header_byte2:02X} ${header_byte3:02X})"
    )

    width = metadata["width"]
    height = metadata["height"]
    bg0 = metadata["bg0"]
    bg1 = metadata["bg1"]
    bg2 = metadata["bg2"]

    raw_pixel_width = width * 4
    display_pixel_width = width * 8
    pixel_height = height * 8

    print(
        f"room dimensions: {width}x{height} tiles "
        f"(raw {raw_pixel_width}x{pixel_height}, png {display_pixel_width}x{pixel_height})"
    )

    pixel_width = display_pixel_width
    rgb = bytearray(pixel_width * pixel_height * 3)

    bg0_rgb = C64_PALETTE[bg0 & 0x0F]
    bg1_rgb = C64_PALETTE[bg1 & 0x0F]
    bg2_rgb = C64_PALETTE[bg2 & 0x0F]

    for tile_y in range(height):
        for tile_x in range(width):
            # C64 room layer streams are column-major: 17 bytes per column.
            layer_idx = tile_x * height + tile_y
            tile_index = tile_matrix[layer_idx]
            tile_offset = tile_index * 8
            if tile_offset + 8 > len(tile_defs):
                raise ValueError(
                    f"tile index {tile_index} is out of range for {len(tile_defs) // 8} tiles"
                )

            color_nybble = color_layer[layer_idx] & 0x0F
            fg_rgb_multicolor = C64_PALETTE[color_nybble & 0x07]
            tile = tile_defs[tile_offset : tile_offset + 8]

            for row_in_tile in range(8):
                pattern = tile[row_in_tile]
                y = tile_y * 8 + row_in_tile
                pixel_span = 2
                tile_span = 8
                source_map = {
                    #"b0": bg0_rgb,
                    #"b1": bg1_rgb,
                    #"b2": bg2_rgb,
                    #"fg": fg_rgb_multicolor,
                    "b0": (0, 0, 0),  # bg2_rgb,
                    "b1": bg0_rgb,
                    "b2": bg1_rgb,
                    "fg": fg_rgb_multicolor,
                }
                for pixel_in_row in range(4):
                    shift = 6 - (pixel_in_row * 2)
                    value = (pattern >> shift) & 0x03
                    pixel = source_map[mc_order[value]]

                    x = tile_x * tile_span + pixel_in_row * pixel_span
                    for sx in range(pixel_span):
                        offset = (y * pixel_width + x + sx) * 3
                        rgb[offset : offset + 3] = bytes(pixel)

    write_png(output_path, pixel_width, pixel_height, bytes(rgb))


def extract_room_charset_bin(resource: bytes, output_path: Path, room_number: int) -> None:
    metadata, tile_defs, _, _ = decode_room_layers(resource)
    resource_size = metadata["resource_size"]
    header_byte2 = metadata["resource_type"]
    header_byte3 = metadata["resource_index"]

    if resource_size != len(resource):
        raise ValueError(
            f"resource size mismatch: header says {resource_size}, extracted {len(resource)} bytes"
        )

    print(
        f"room size: {resource_size} bytes "
        f"(header bytes: ${header_byte2:02X} ${header_byte3:02X})"
    )

    width = metadata["width"]
    height = metadata["height"]
    print(f"room dimensions: {width}x{height} tiles ({width * 4}x{height * 8} pixels)")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(tile_defs)
    print(f"wrote charset bin: {output_path} ({len(tile_defs)} bytes)")


def write_png(path: Path, width: int, height: int, rgb_data: bytes) -> None:
    stride = width * 3
    if len(rgb_data) != stride * height:
        raise ValueError("RGB buffer size does not match image dimensions")

    raw = bytearray()
    for row in range(height):
        start = row * stride
        raw.append(0)
        raw.extend(rgb_data[start : start + stride])

    def chunk(tag: bytes, payload: bytes) -> bytes:
        return (
            struct.pack(">I", len(payload))
            + tag
            + payload
            + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)
        )

    png = bytearray()
    png.extend(b"\x89PNG\r\n\x1a\n")
    png.extend(
        chunk(
            b"IHDR",
            struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0),
        )
    )
    png.extend(chunk(b"IDAT", zlib.compress(bytes(raw), level=9)))
    png.extend(chunk(b"IEND", b""))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Extract Maniac Mansion room resources from a D64 image and render PNGs."
    )
    parser.add_argument("--side1", type=Path, help="Disk image for side 1")
    parser.add_argument("--side2", type=Path, help="Disk image for side 2")
    parser.add_argument(
        "--disk-dir",
        type=Path,
        help="Directory containing .d64 images. Used to auto-fill --side1/--side2 when omitted.",
    )
    parser.add_argument(
        "--room",
        type=int,
        help="Room number to render (0-54). If omitted, use --all.",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Render every room that exists on the provided disk side image(s).",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="Output PNG path for --room. Defaults to ROOMnn.png.",
    )
    parser.add_argument(
        "--charset-bin-output",
        type=Path,
        help="Output .bin path for --room charset extraction.",
    )
    parser.add_argument(
        "--metadata-output",
        type=Path,
        help="Output .txt path for --room metadata dump. Defaults to ROOMnn_metadata.txt.",
    )
    parser.add_argument(
        "--charset-only",
        action="store_true",
        help="Extract only the decompressed room charset (tile definitions) to .bin.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("room_png"),
        help="Directory for --all output PNGs.",
    )
    parser.add_argument(
        "--mc-order",
        default="b0,b1,b2,fg",
        help="Multicolor pair source order for values 00,01,10,11. Example: b0,b1,b2,fg (default) or fg,b0,b1,b2.",
    )
    parser.add_argument(
        "--strict-room-header",
        action="store_true",
        help="Fail if resource header type/index does not match expected room values.",
    )
    return parser.parse_args()


def auto_discover_disk_images(disk_dir: Path) -> tuple[Path | None, Path | None]:
    candidates = sorted(
        path for path in disk_dir.iterdir() if path.is_file() and path.suffix.lower() == ".d64"
    )
    if not candidates:
        return None, None

    side1 = next((path for path in candidates if path.stem.lower().endswith(("_a", "-1", "1"))), None)
    side2 = next((path for path in candidates if path.stem.lower().endswith(("_b", "-2", "2"))), None)

    if side1 is None and candidates:
        side1 = candidates[0]
    if side2 is None and len(candidates) > 1:
        side2 = next((path for path in candidates if path != side1), None)

    return side1, side2


def load_disk(path: Path | None) -> DiskImage | None:
    if path is None:
        return None
    data = path.read_bytes()
    disk = DiskImage(data)
    disk.source_path = path
    return disk


def pick_disk(side: int, side1: DiskImage | None, side2: DiskImage | None) -> DiskImage:
    if side == 0x31:
        if side1 is None:
            raise ValueError("room requires side 1 but no --side1 image was provided")
        return side1
    if side == 0x32:
        if side2 is None:
            raise ValueError("room requires side 2 but no --side2 image was provided")
        return side2
    raise ValueError(f"unexpected room disk side byte ${side:02X}")


def render_one_room(
    room_number: int,
    side_table: bytes,
    sector_track_table: bytes,
    side1: DiskImage | None,
    side2: DiskImage | None,
    output_path: Path,
    metadata_output_path: Path | None,
    charset_only: bool,
    mc_order: tuple[str, str, str, str],
    strict_room_header: bool,
) -> None:
    side = room_disk_side(side_table, room_number)
    disk = pick_disk(side, side1, side2)
    track, sector = room_start_sector(sector_track_table, room_number)
    print(
        f"processing ROOM{room_number:02d} from {disk.source_path} "
        f"(track {track}, sector {sector})"
    )
    resource = extract_room_resource(disk, track, sector)
    metadata = parse_room_metadata(resource)
    if metadata["resource_type"] != RSRC_TYPE_ROOM or metadata["resource_index"] != room_number:
        msg = (
            "header mismatch at lookup location: "
            f"type=0x{metadata['resource_type']:02X} (expected 0x{RSRC_TYPE_ROOM:02X}), "
            f"index=0x{metadata['resource_index']:02X} (expected 0x{room_number:02X})"
        )
        if strict_room_header:
            raise ValueError(msg)
        print(f"warning: {msg}")

    if charset_only:
        extract_room_charset_bin(resource, output_path, room_number)
    else:
        render_room_png(resource, output_path, room_number, mc_order)
        write_room_auxiliary_dumps(resource, output_path.parent, room_number)

    metadata_path = metadata_output_path
    if metadata_path is None:
        metadata_path = output_path.parent / f"ROOM{room_number:02d}_metadata.txt"

    write_room_metadata_txt(
        resource,
        metadata_path,
        room_number,
        track,
        sector,
        side,
        disk.source_path,
    )
    print(f"wrote metadata: {metadata_path}")


def main() -> int:
    args = parse_args()
    try:
        mc_order = parse_mc_order(args.mc_order)
    except ValueError as exc:
        raise SystemExit(str(exc)) from exc

    if not args.all and args.room is None:
        raise SystemExit("specify either --room N or --all")

    if args.disk_dir is not None:
        auto_side1, auto_side2 = auto_discover_disk_images(args.disk_dir)
        if args.side1 is None and auto_side1 is not None:
            args.side1 = auto_side1
        if args.side2 is None and auto_side2 is not None:
            args.side2 = auto_side2

    side1 = load_disk(args.side1)
    side2 = load_disk(args.side2)

    if side1 is None and side2 is None:
        raise SystemExit("provide at least one disk image with --side1/--side2 or --disk-dir")

    table_disk = side1 if side1 is not None else side2
    assert table_disk is not None
    print(f"loading room tables from {table_disk.source_path}")
    side_table, sector_track_table = get_room_tables(table_disk)

    if args.room is not None:
        if args.room < 0 or args.room >= ROOM_COUNT:
            raise SystemExit(f"room must be between 0 and {ROOM_COUNT - 1}")
        if args.charset_only:
            output_path = args.charset_bin_output or Path(f"ROOM{args.room:02d}_charset.bin")
        else:
            output_path = args.output or Path(f"ROOM{args.room:02d}.png")
        render_one_room(
            args.room,
            side_table,
            sector_track_table,
            side1,
            side2,
            output_path,
            args.metadata_output,
            args.charset_only,
            mc_order,
            args.strict_room_header,
        )
        if not args.charset_only:
            print(f"wrote {output_path}")
        return 0

    args.output_dir.mkdir(parents=True, exist_ok=True)
    for room_number in range(ROOM_COUNT):
        room_side = side_table[room_number]
        if room_side not in (0x31, 0x32):
            continue
        try:
            if args.charset_only:
                output_path = args.output_dir / f"ROOM{room_number:02d}_charset.bin"
            else:
                output_path = args.output_dir / f"ROOM{room_number:02d}.png"
            render_one_room(
                room_number,
                side_table,
                sector_track_table,
                side1,
                side2,
                output_path,
                None,
                args.charset_only,
                mc_order,
                args.strict_room_header,
            )
            if not args.charset_only:
                print(f"wrote {output_path}")
        except ValueError as exc:
            print(f"skipped ROOM{room_number:02d}: {exc}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())