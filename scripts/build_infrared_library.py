"""Build a compatible, attributed household IR library from a pinned IRDB ZIP.

No device access or transmission. Unsupported records are reported, never guessed.
"""

import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path, PurePosixPath
import re
import unicodedata
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = "https://github.com/Lucaslhm/Flipper-IRDB"
CATEGORIES = frozenset(
    "TVs ACs Fans Air_Purifiers Audio_and_Video_Receivers SoundBars Speakers "
    "Projectors LED_Lighting Monitors Universal_TV_Remotes Streaming_Devices "
    "Cable_Boxes TV_Tuner DVB-T Converters Blu-Ray DVD_Players CD_Players VCR "
    "MiniDisc Laserdisc Humidifiers Heaters Vacuum_Cleaners Clocks Picture_Frames "
    "Multimedia".split()
)


def firmware_protocols(root=ROOT):
    result = {}
    for path in (root / "lib/infrared/encoder_decoder").rglob("infrared_protocol*.c"):
        for name, address, command in re.findall(
            r'\.name\s*=\s*"([^"]+)"\s*,\s*\.address_length\s*=\s*(\d+)\s*,\s*\.command_length\s*=\s*(\d+)',
            path.read_text(encoding="utf-8"),
        ):
            result[name] = (int(address), int(command))
    if not result:
        raise ValueError("No firmware protocol descriptors found")
    return result


def _records(text):
    header, records, current = {}, [], None
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if ":" not in line:
            if current is not None:
                current["invalid"] = "Malformed record line"
            continue
        key, value = (part.strip() for part in line.split(":", 1))
        if key == "name":
            current = {"name": value}
            records.append(current)
        elif current is None:
            header[key] = value
        elif key in current:
            current["invalid"] = "Duplicate record field"
        else:
            current[key] = value
    return header, records


def _signal(record, protocols):
    if "invalid" in record:
        raise ValueError(record["invalid"])
    name = record.get("name", "")
    if not name or len(name.encode("utf-8")) > 128 or any(ord(c) < 32 for c in name):
        raise ValueError("Invalid button name")
    kind = record.get("type")
    if kind == "parsed":
        protocol = record.get("protocol")
        if protocol not in protocols:
            raise ValueError("Unsupported parsed protocol")
        fields = []
        for key, bits in zip(("address", "command"), protocols[protocol]):
            data = bytes.fromhex(record.get(key, ""))
            if len(data) != 4 or int.from_bytes(data, "little") >= 1 << bits:
                raise ValueError("Parsed payload exceeds firmware field width")
            fields.append(key + ": " + data.hex(" ").upper())
        body = ["type: parsed", "protocol: " + protocol, *fields]
    elif kind == "raw":
        frequency = int(record.get("frequency", "0"))
        duty = float(record.get("duty_cycle", "nan"))
        timings = [int(value) for value in record.get("data", "").split()]
        if not 10000 <= frequency <= 1000000:
            raise ValueError("RAW carrier outside firmware limits")
        if not math.isfinite(duty) or not 0 < duty <= 1:
            raise ValueError("Invalid RAW duty cycle")
        if not 0 < len(timings) <= 1024 or any(
            not 0 < value <= 0xFFFFFFFF for value in timings
        ):
            raise ValueError("RAW samples exceed firmware limits")
        body = [
            "type: raw",
            "frequency: " + str(frequency),
            "duty_cycle: " + str(duty),
            "data: " + " ".join(map(str, timings)),
        ]
    else:
        raise ValueError("Unknown signal type")
    return name, kind, "\n".join(body)


def normalise_remote(data, protocols):
    header, records = _records(data.decode("utf-8-sig"))
    if header.get("Filetype") != "IR signals file" or header.get("Version") != "1":
        raise ValueError("Not a saved remote in version 1 format")
    report = {
        "signals": 0,
        "raw": 0,
        "parsed": 0,
        "rejected": [],
        "duplicates_removed": 0,
    }
    output = ["Filetype: IR signals file", "Version: 1", "#"]
    # Keep upstream device notes, especially the temperature/state of AC captures.
    output.extend(
        line.rstrip()
        for line in data.decode("utf-8-sig").splitlines()
        if line.lstrip().startswith("#") and line.strip() != "#"
    )
    names, seen = set(), set()
    for index, record in enumerate(records):
        try:
            name, kind, body = _signal(record, protocols)
        except (ValueError, OverflowError) as error:
            report["rejected"].append(
                {"index": index, "name": record.get("name"), "reason": str(error)}
            )
            continue
        if (name, body) in seen:
            report["duplicates_removed"] += 1
            continue
        seen.add((name, body))
        unique, suffix = name, 2
        while unique in names:
            unique = name + "_" + str(suffix)
            suffix += 1
        names.add(unique)
        output.extend(("#", "name: " + unique, body))
        report["signals"] += 1
        report[kind] += 1
    if not report["signals"]:
        raise ValueError("No compatible signals remain")
    return ("\n".join(output) + "\n").encode("utf-8"), report


def _component(value):
    value = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode()
    value = re.sub(r"[^a-zA-Z0-9_.+() -]", "_", value).strip(" .")
    if value in ("", ".", ".."):
        value = "Remote"
    if value.split(".")[0].upper() in {
        "CON",
        "PRN",
        "AUX",
        "NUL",
        *("COM" + str(i) for i in range(1, 10)),
        *("LPT" + str(i) for i in range(1, 10)),
    }:
        value = "_" + value
    return value[:80].rstrip(" .")


def _resource_path(relative, unique=False):
    destination = PurePosixPath(
        *(_component(part) for part in relative.parts[:-1]),
        _component(relative.stem) + ".ir",
    )
    prefix = "infrared/More_Remotes/"
    digest = hashlib.sha256(str(relative).encode()).hexdigest()[:10]
    available = 100 - len(prefix + str(destination.parent) + "/") - 3
    if len(prefix + str(destination)) > 100 or (unique and available < 12):
        brand = _component(relative.parts[1]) if len(relative.parts) > 2 else "Other"
        if len(brand) > 24:
            brand = brand[:17] + "_" + digest[:6]
        model = (
            _component("_".join(relative.parts[2:])[:-3])
            if len(relative.parts) > 2
            else _component(relative.stem)
        )
        destination = PurePosixPath(relative.parts[0], brand, model + ".ir")
        available = 100 - len(prefix + str(destination.parent) + "/") - 3
    if unique or len(destination.stem) > available:
        destination = destination.with_name(
            destination.stem[: available - 11] + "_" + digest + ".ir"
        )
    if len(prefix + str(destination)) > 100:
        raise ValueError("Remote path exceeds the firmware resource limit")
    return destination


def build_library(source, output, commit, protocols):
    if output.exists():
        raise FileExistsError("Refusing to overwrite an existing library")
    if not re.fullmatch("[0-9a-f]{40}", commit):
        raise ValueError("A pinned upstream commit is required")
    entries, rejected_files, occupied = [], [], set()
    totals, category_counts = Counter(), Counter()
    with zipfile.ZipFile(source) as archive:
        members = archive.infolist()
        for member in members:
            path = PurePosixPath(member.filename)
            if path.is_absolute() or ".." in path.parts or "\\" in member.filename:
                raise ValueError("Unsafe source archive path")
        license_members = [
            m
            for m in members
            if len(PurePosixPath(m.filename).parts) == 2
            and PurePosixPath(m.filename).name == "LICENSE"
        ]
        if len(license_members) != 1:
            raise ValueError("Missing upstream license")
        license_data = archive.read(license_members[0])
        if b"CC0 1.0 Universal" not in license_data:
            raise ValueError("Unexpected upstream license")
        output.mkdir(parents=True)
        for member in sorted(members, key=lambda item: item.filename):
            path = PurePosixPath(member.filename)
            if (
                len(path.parts) < 3
                or path.parts[1] not in CATEGORIES
                or path.suffix.lower() != ".ir"
            ):
                continue
            relative = PurePosixPath(*path.parts[1:])
            original = archive.read(member)
            try:
                content, result = normalise_remote(original, protocols)
            except (ValueError, UnicodeError) as error:
                rejected_files.append(
                    {"source_path": str(relative), "reason": str(error)}
                )
                continue
            destination = _resource_path(relative)
            if str(destination).casefold() in occupied:
                destination = _resource_path(relative, unique=True)
            if str(destination).casefold() in occupied:
                raise ValueError("Duplicate source path")
            occupied.add(str(destination).casefold())
            local = output.joinpath(*destination.parts)
            local.parent.mkdir(parents=True, exist_ok=True)
            with local.open("xb") as file:
                file.write(content)
            totals.update(
                {
                    key: result[key]
                    for key in ("signals", "raw", "parsed", "duplicates_removed")
                }
            )
            totals["rejected_signals"] += len(result["rejected"])
            category_counts[destination.parts[0]] += 1
            entries.append(
                {
                    "path": str(destination),
                    "source_path": str(relative),
                    "source_sha256": hashlib.sha256(original).hexdigest(),
                    "sha256": hashlib.sha256(content).hexdigest(),
                    "md5": hashlib.md5(content).hexdigest(),
                    "bytes": len(content),
                    **result,
                }
            )
    report = {
        "source": SOURCE,
        "commit": commit,
        "license": "CC0-1.0",
        "source_zip_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
        "files": len(entries),
        **dict(totals),
        "categories": dict(category_counts),
        "rejected_files": rejected_files,
    }
    (output / "LICENSE-CC0.txt").write_bytes(license_data.replace(b"\r\n", b"\n"))
    (output / "catalog.json").write_bytes(
        (
            json.dumps({**report, "entries": entries}, indent=2, ensure_ascii=False)
            + "\n"
        ).encode("utf-8")
    )
    (output / "README.txt").write_text(
        "More Remotes - household infrared library\n"
        "Open Infrared > Saved Remotes > More_Remotes, then choose category, brand and model.\n"
        "AC buttons replay captured states; they are not a universal temperature dial.\n"
        "A matching brand alone does not guarantee compatibility.\n"
        f"Source: {SOURCE}/tree/{commit}\nLicense: CC0-1.0; see LICENSE-CC0.txt.\n"
        "Only compatible records are included; exclusions and origin hashes are in catalog.json.\n",
        encoding="utf-8",
        newline="\n",
    )
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-zip", type=Path, required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    print(
        json.dumps(
            build_library(
                args.source_zip, args.output, args.commit, firmware_protocols()
            ),
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
