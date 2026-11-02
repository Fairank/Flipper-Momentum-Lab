"""Prepare a primary-only first stage before switching Light to Full BLE.

This creates an update archive; it never connects to or programs a device.
The complete matching package must be installed after this stage boots.
"""

import argparse
import hashlib
import io
import json
from pathlib import Path
import struct
import tarfile
import zlib


def primary_extent(dfu):
    if len(dfu) < 317:
        raise ValueError("Truncated DFU")
    if struct.unpack_from("<5sBIB", dfu) != (b"DfuSe", 1, len(dfu) - 16, 1):
        raise ValueError("Expected a single-target DfuSe image")
    target = struct.unpack_from("<6sBI255sII", dfu, 11)
    address, size = struct.unpack_from("<II", dfu, 285)
    if (
        target[0] != b"Target"
        or target[-1] != 1
        or target[-2] != size + 8
        or address != 0x08000000
        or size < 8
        or len(dfu) != size + 309
    ):
        raise ValueError("Invalid primary image layout")
    if struct.unpack_from("<I", dfu, len(dfu) - 4)[0] != (
        ~zlib.crc32(dfu[:-4]) & 0xFFFFFFFF
    ):
        raise ValueError("Invalid primary image CRC")
    stack_pointer, reset = struct.unpack_from("<II", dfu, 293)
    if (
        stack_pointer != 0x20030000
        or not reset & 1
        or not address < reset < address + size
    ):
        raise ValueError("Invalid primary boot vectors")
    return address + size


def bootstrap_files(files):
    fields = dict(
        line.split(": ", 1)
        for line in files["update.fuf"].decode().splitlines()
        if ": " in line
    )
    if fields["Target"] != "7" or fields["Radio version"] != "01 14 00 00 02 01":
        raise ValueError("Expected target 7 and Full 1.20.0")
    radio = int.from_bytes(bytes.fromhex(fields["Radio address"]), "little")
    if radio != 0x080CE000 or primary_extent(files["firmware.dfu"]) > radio:
        raise ValueError("Primary overlaps the Full stack")
    loader = files["updater.bin"]
    if not 0 < len(loader) <= 131072 or zlib.crc32(loader) != int.from_bytes(
        bytes.fromhex(fields["Loader CRC"]), "little"
    ):
        raise ValueError("Invalid or oversized updater")
    # Use the official partial-update format. No radio, resources or option bytes.
    manifest = (
        "Filetype: Flipper firmware upgrade configuration\n"
        "Version: 2\n"
        f"Info: {fields['Info']}-bootstrap-primary-only\n"
        "Target: 7\n"
        "Loader: updater.bin\n"
        f"Loader CRC: {fields['Loader CRC']}\n"
        "Firmware: firmware.dfu\n"
        "Radio: \nRadio address: 00 00 00 00\n"
        "Radio version: 00 00 00 00 00 00\nRadio CRC: 00 00 00 00\n"
        "Resources: \nOB reference: \nOB mask: \nOB write mask: \nSplashscreen: \n"
    ).encode()
    return {
        "firmware.dfu": files["firmware.dfu"],
        "updater.bin": loader,
        "update.fuf": manifest,
    }


def main():
    from verify_native_ble_build import verify

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--installed-dfu", type=Path)
    args = parser.parse_args()
    report = verify(args.package)
    with tarfile.open(args.package) as archive:
        files = {
            Path(member.name).name: archive.extractfile(member).read()
            for member in archive
            if member.isfile()
        }
    files = bootstrap_files(files)
    old_end = (
        primary_extent(args.installed_dfu.read_bytes()) if args.installed_dfu else None
    )
    # Exclusive creation prevents replacing a previously reviewed package.
    with args.output.open("xb") as output, tarfile.open(
        fileobj=output, mode="w:gz"
    ) as archive:
        for name, content in files.items():
            member = tarfile.TarInfo("bootstrap-primary-only/" + name)
            member.size = len(content)
            member.mode = 0o644
            archive.addfile(member, io.BytesIO(content))
    report = {
        "bootstrap": args.output.name,
        "sha256": hashlib.sha256(args.output.read_bytes()).hexdigest(),
        "source_package_sha256": report["sha256"],
        "order": ["bootstrap-primary-only", "matching-complete-update"],
        "device_installation_verified": False,
    }
    if old_end is not None:
        report["installed_primary_end"] = hex(old_end)
        report["installed_primary_overlaps_full_stack"] = old_end > 0x080CE000
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
