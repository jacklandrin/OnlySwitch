#!/usr/bin/env python3
"""Run real parser/converter regression tests without the app's dependencies.

Pass Swift test options, e.g. --sanitize=thread or --sanitize=address, through
to the temporary package. No generated package files are kept in the checkout.
"""
from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile


root = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix="onlyswitch-audio-tests-") as directory:
    package = Path(directory)
    source = package / "Sources" / "OnlySwitch"
    tests = package / "Tests" / "OnlySwitchTests"
    source.mkdir(parents=True)
    tests.mkdir(parents=True)
    audio = root / "OnlySwitch/Player/CommonPlayer/AudioStreamer"
    for folder in ("Parse", "Read"):
        for file in (audio / folder).glob("*.swift"):
            shutil.copy2(file, source / file.name)
    shutil.copy2(root / "OnlySwitchTests/AudioStreamingTests.swift", tests)
    (package / "Package.swift").write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "AudioStreamingRegression",
    platforms: [.macOS(.v12)],
    targets: [
        .target(name: "OnlySwitch"),
        .testTarget(name: "OnlySwitchTests", dependencies: ["OnlySwitch"])
    ]
)
''')
    environment = os.environ.copy()
    environment["CLANG_MODULE_CACHE_PATH"] = str(package / "module-cache")
    environment["SWIFTPM_MODULECACHE_OVERRIDE"] = str(package / "module-cache")
    result = subprocess.run(
        ["swift", "test", "--disable-sandbox", "--package-path", directory, *sys.argv[1:]],
        env=environment,
    )
    sys.exit(result.returncode)
