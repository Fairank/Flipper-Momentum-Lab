"""Verify the native BLE bundle, live SDK table and isolated radar imports.

Read-only and host independent. This does not replace RF/device acceptance.
"""

import argparse
import csv
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import struct
import tarfile
import zlib

ROOT = Path(__file__).resolve().parents[1]


def api_entries(path):
    with path.open(encoding="utf-8", newline="") as file:
        return {
            (row["entry"], row["name"], row["type"], row["params"])
            for row in csv.DictReader(file)
            if row["entry"] in ("Function", "Variable") and row["status"] == "+"
        }


def gnu_hash(name):
    value = 0x1505
    for byte in name.encode():
        value = (value * 33 + byte) & 0xFFFFFFFF
    return value


def live_api(elf, expected, radio):
    data = elf.read_bytes()
    assert data[:7] == b"\x7fELF\x01\x01\x01", "Expected little-endian ELF32"
    assert struct.unpack_from("<H", data, 18)[0] == 40, "Expected ARM image"
    entry = struct.unpack_from("<I", data, 24)[0]
    assert entry & 1 and 0x08000000 <= entry < radio, "Invalid reset entry"
    offset = struct.unpack_from("<I", data, 32)[0]
    stride, count, _ = struct.unpack_from("<HHH", data, 46)
    sections = [
        struct.unpack_from("<10I", data, offset + i * stride) for i in range(count)
    ]
    symbols = []
    for section in sections:
        if section[1] != 2:
            continue
        strings = sections[section[6]]
        strings = data[strings[4] : strings[4] + strings[5]]
        for position in range(section[4], section[4] + section[5], section[9]):
            name, address, size, _, _, index = struct.unpack_from(
                "<IIIBBH", data, position
            )
            name = strings[name : strings.find(b"\0", name)].decode()
            if "elf_api_table" in name and size:
                symbols.append((address, size, index))
    assert len(symbols) == 1, "Live SDK table missing or ambiguous"
    address, size, index = symbols[0]
    section = sections[index]
    offset = section[4] + address - section[3]
    table = dict(struct.iter_unpack("<II", data[offset : offset + size]))
    assert len(table) == len(expected) == size // 8, "SDK entry count changed"
    for kind, name, _, _ in expected:
        value = table.get(gnu_hash(name))
        assert value, f"SDK symbol missing: {name}"
        if kind == "Function":
            assert (
                value & 1 and 0x08000000 <= value < radio
            ), f"Invalid API function: {name}"
    return len(table)


def verify(package, baseline=None):
    with tarfile.open(package) as archive:
        files = {}
        for member in archive:
            path = PurePosixPath(member.name)
            assert (
                not path.is_absolute() and ".." not in path.parts
            ), "Unsafe archive path"
            if member.isdir():
                continue
            assert member.isfile() and len(path.parts) == 2 and path.name not in files
            files[path.name] = archive.extractfile(member).read()
    assert set(files) == {
        "firmware.dfu",
        "updater.bin",
        "update.fuf",
        "resources.tar.gz",
        "radio.bin",
        "splash.bin",
        "firstboot.bin",
    }, "Incomplete package"
    fields = dict(
        line.split(": ", 1)
        for line in files["update.fuf"].decode().splitlines()
        if ": " in line
    )
    assert fields["Target"] == "7"
    radio = int.from_bytes(bytes.fromhex(fields["Radio address"]), "little")
    assert radio == 0x080CE000, "Native scanning requires the pinned Full stack"
    assert (
        files["radio.bin"]
        == (
            ROOT / "lib/stm32wb_copro/firmware/stm32wb5x_BLE_Stack_full_fw.bin"
        ).read_bytes()
    )
    for name, key in (("radio.bin", "Radio CRC"), ("updater.bin", "Loader CRC")):
        assert zlib.crc32(files[name]) == int.from_bytes(
            bytes.fromhex(fields[key]), "little"
        )
    assert 0 < len(files["updater.bin"]) <= 131072, "Updater exceeds legacy load limit"
    dfu = files["firmware.dfu"]
    assert struct.unpack_from("<5sBIB", dfu) == (b"DfuSe", 1, len(dfu) - 16, 1)
    target = struct.unpack_from("<6sBI255sII", dfu, 11)
    address, size = struct.unpack_from("<II", dfu, 285)
    assert target[0] == b"Target" and target[-1] == 1
    assert address == 0x08000000 and address + size <= radio and len(dfu) == size + 309
    assert struct.unpack_from("<I", dfu, len(dfu) - 4)[0] == (
        ~zlib.crc32(dfu[:-4]) & 0xFFFFFFFF
    )
    firmware = dfu[293 : 293 + size]
    stack_pointer, reset = struct.unpack_from("<II", firmware)
    assert (
        stack_pointer == 0x20030000 and reset & 1 and address < reset < address + size
    )
    assert firmware == (ROOT / "build/f7-firmware-C/firmware.bin").read_bytes()
    expected = api_entries(ROOT / "targets/f7/api_symbols.csv")
    if baseline:
        assert api_entries(baseline) <= expected, "An existing SDK contract was removed"
    api_count = live_api(ROOT / "build/f7-firmware-C/firmware.elf", expected, radio)
    valid = {entry[1] for entry in expected}
    imports = {}
    for app in ("nearby_radar", "wifi_radar", "archive_ui"):
        path = ROOT / "build/f7-firmware-C/.extapps" / (app + ".impsyms")
        imports[app] = {
            line.split()[0] for line in path.read_text().splitlines() if line.strip()
        }
        assert (
            imports[app] <= valid
        ), f"Unresolvable imports: {app}: {imports[app] - valid}"
    native = {
        "furi_hal_bt_start_scan",
        "furi_hal_bt_stop_scan",
        "furi_hal_bt_is_scan_active",
    }
    assert native <= imports["nearby_radar"] and not native & imports["wifi_radar"]
    assert not any(
        name.startswith(("furi_hal_serial_", "expansion_"))
        for name in imports["nearby_radar"]
    )
    assert "furi_hal_serial_control_acquire" in imports["wifi_radar"]
    with tarfile.open(fileobj=io.BytesIO(files["resources.tar.gz"])) as resources:
        manifest = resources.extractfile("Manifest").read().decode()
        entries = {}
        for line in manifest.splitlines():
            if not line.startswith("F:"):
                continue
            _, md5, length, path = line.split(":", 3)
            name = PurePosixPath(path)
            assert (
                not name.is_absolute()
                and ".." not in name.parts
                and path not in entries
            )
            content = resources.extractfile(path).read()
            assert (
                len(content) == int(length) and hashlib.md5(content).hexdigest() == md5
            ), path
            entries[path] = (md5, int(length))
        faps = sum(path.endswith(".fap") for path in entries)
        fals = sum(path.endswith(".fal") for path in entries)
        assert (faps, fals) == (297, 122), "Merged application/module inventory changed"
        for path in (
            "apps/Bluetooth/nearby_radar.fap",
            "apps/WiFi/wifi_radar.fap",
            "apps_data/archive/plugins/archive_ui.fal",
        ):
            assert path in entries, f"Missing required module: {path}"
            built = ROOT / "build/f7-firmware-C/.extapps" / PurePosixPath(path).name
            assert hashlib.md5(built.read_bytes()).hexdigest() == entries[path][0], path
    return {
        "passed": True,
        "package": package.name,
        "info": fields["Info"],
        "sha256": hashlib.sha256(package.read_bytes()).hexdigest(),
        "firmware_bytes": size,
        "radio_start": hex(radio),
        "radio_gap_bytes": radio - address - size,
        "updater_bytes": len(files["updater.bin"]),
        "sdk_entries": api_count,
        "fap_count": faps,
        "fal_count": fals,
        "resource_files": len(entries),
        "radar_backends_isolated": True,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", type=Path, required=True)
    parser.add_argument("--baseline-api", type=Path)
    args = parser.parse_args()
    print(json.dumps(verify(args.package, args.baseline_api), indent=2))


if __name__ == "__main__":
    main()
