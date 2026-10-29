#!/usr/bin/env python3
"""Compare complete, already built .app bundles without executing either app."""

import hashlib
import json
from pathlib import Path
import plistlib
import stat
import subprocess
import sys


def logical_bytes(directory):
    return sum(
        path.lstat().st_size
        for path in directory.rglob("*")
        if not stat.S_ISDIR(path.lstat().st_mode)
    )


def measure(directory):
    if directory.suffix != ".app" or not directory.is_dir():
        raise ValueError("Both inputs must be existing .app directories")
    with (directory / "Contents/Info.plist").open("rb") as stream:
        metadata = plistlib.load(stream)
    binary = directory / "Contents/MacOS" / metadata["CFBundleExecutable"]
    total = logical_bytes(directory)
    resources = logical_bytes(directory / "Contents/Resources")
    return {
        "logicalBytes": total,
        "allocatedBytes": int(subprocess.check_output(["/usr/bin/du", "-sk", str(directory)], text=True).split()[0]) * 1024,
        "mainExecutableBytes": binary.stat().st_size,
        "resourcesBytes": resources,
        "otherBytes": total - binary.stat().st_size - resources,
        "mainExecutableSHA256": hashlib.sha256(binary.read_bytes()).hexdigest(),
    }


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("Usage: measure-app-size.py BASE.app CANDIDATE.app")
    baseline, candidate = (measure(Path(argument).resolve()) for argument in sys.argv[1:])
    delta = {key: candidate[key] - baseline[key] for key in baseline if key.endswith("Bytes")}
    print(json.dumps({"baseline": baseline, "candidate": candidate, "delta": delta}, indent=2, sort_keys=True))
