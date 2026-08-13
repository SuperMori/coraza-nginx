#!/usr/bin/env python3
"""Safely extract a source tarball without restoring host filesystem metadata."""

from __future__ import annotations

import pathlib
import sys
import tarfile


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} ARCHIVE DESTINATION", file=sys.stderr)
        return 2

    archive_path = pathlib.Path(sys.argv[1])
    destination = pathlib.Path(sys.argv[2])
    destination.mkdir(parents=True, exist_ok=True)

    with tarfile.open(archive_path, mode="r:*") as archive:
        # Python's data filter rejects absolute paths and traversal outside the
        # destination while stripping ownership and other unsafe metadata.
        archive.extractall(destination, filter="data")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
