#!/usr/bin/env python3
"""Compile actual sizing sources and verify real NSPopover geometry."""

from pathlib import Path
import subprocess
import tempfile


def main():
    root = Path(__file__).resolve().parents[1]
    sources = [
        root / "Modules/Sources/Utilities/AdaptivePanelHeightPolicy.swift",
        root / "Modules/Sources/Utilities/PanelScreenHeightReader.swift",
        root / "Modules/Tests/Integration/PopoverLayoutHarness.swift",
    ]
    with tempfile.TemporaryDirectory(prefix="popover-layout-") as temporary:
        directory = Path(temporary)
        executable = directory / "PopoverLayoutHarness"
        subprocess.run([
            "xcrun", "swiftc", "-swift-version", "6", "-parse-as-library",
            "-module-cache-path", str(directory / "cache"), *map(str, sources),
            "-o", str(executable),
        ], check=True, cwd=root, timeout=120)
        subprocess.run([str(executable)], check=True, timeout=20)


if __name__ == "__main__":
    main()
