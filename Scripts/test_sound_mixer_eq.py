#!/usr/bin/env python3
"""Run actual EQ domain/DSP sources without the app's unrelated dependencies.

The TCA reducer tests remain in the main package; this small harness exercises
settings, DSP frequency response, channel layout, and tap lifecycle policy.
Pass Swift test options such as --sanitize=address through to the temp package.
"""
from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile


root = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix="onlyswitch-eq-tests-") as directory:
    package = Path(directory)
    source = package / "Sources" / "SoundMixerEQ"
    tests = package / "Tests" / "SoundMixerEQTests"
    source.mkdir(parents=True)
    tests.mkdir(parents=True)
    for name in ("EqualizerSettings.swift", "EqualizerDSP.swift", "EqualizerTapPolicy.swift", "OutputRouteSelection.swift"):
        path = root / "Modules/Sources/SoundMixerEQ" / name
        if path.exists():
            shutil.copy2(path, source / name)
    # Before implementation this permits the test compiler to report missing
    # domain types, rather than SwiftPM failing on an empty-target manifest.
    if not list(source.glob("*.swift")):
        (source / "Empty.swift").write_text("// TDD: production EQ types do not exist yet.\n")
    for name in ("EqualizerSettingsTests.swift", "EqualizerDSPTests.swift", "EqualizerTapPolicyTests.swift", "EqualizerAudioBuffersTests.swift", "OutputRouteSelectionTests.swift", "OutputRoutingAudioBuffersTests.swift"):
        shutil.copy2(root / "Modules/Tests/SoundMixerEQTests" / name, tests / name)
    c_source = root / "Modules/Sources/CSoundMixerEQ"
    has_c = c_source.exists()
    if has_c:
        shutil.copytree(c_source, package / "Sources/CSoundMixerEQ")
    c_target = '.target(name: "CSoundMixerEQ"),' if has_c else ""
    dependencies = '["CSoundMixerEQ"]' if has_c else "[]"
    test_dependencies = '["SoundMixerEQ", "CSoundMixerEQ"]' if has_c else '["SoundMixerEQ"]'
    (package / "Package.swift").write_text(f'''// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "SoundMixerEQRegression",
    platforms: [.macOS(.v14)],
    targets: [
        {c_target}
        .target(name: "SoundMixerEQ", dependencies: {dependencies}),
        .testTarget(name: "SoundMixerEQTests", dependencies: {test_dependencies})
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
