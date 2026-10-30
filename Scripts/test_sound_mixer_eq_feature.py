#!/usr/bin/env python3
"""Run EQ and output-routing TestStore tests against built dependency products.

Usage: python3 Scripts/test_sound_mixer_eq_feature.py --products /path/to/Build/Products/Debug
This compiles the actual feature/client/settings files without resolving or
rebuilding the app's unrelated dependencies. It requires a matching toolchain.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--products", type=Path, required=True)
options = parser.parse_args()
root = Path(__file__).resolve().parents[1]
developer = Path(subprocess.check_output(["xcode-select", "-p"], text=True).strip())
frameworks = developer / "Platforms/MacOSX.platform/Developer/Library/Frameworks"
plugin = developer / "Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
products = options.products.resolve()
with tempfile.TemporaryDirectory(prefix="onlyswitch-eq-feature-tests-") as temporary:
    out = Path(temporary)
    common = ["xcrun", "swiftc", "-swift-version", "6", "-target", "arm64-apple-macosx14.0", "-Xfrontend", "-disable-sandbox", "-module-cache-path", str(out / "cache"), "-I", str(out), "-I", str(products), "-F", str(frameworks)]
    for executable, module in [("ComposableArchitectureMacros", "ComposableArchitectureMacros"), ("CasePathsMacros", "CasePathsMacros"), ("PerceptionMacros", "PerceptionMacros"), ("DependenciesMacrosPlugin", "DependenciesMacrosPlugin")]:
        common += ["-load-plugin-executable", str(products / executable) + "#" + module]
    names = ["ComposableArchitecture", "CasePaths", "CasePathsCore", "Clocks", "CombineSchedulers", "ConcurrencyExtras", "CustomDump", "Dependencies", "DependenciesMacros", "IdentifiedCollections", "IssueReporting", "_IssueReporting", "XCTestDynamicOverlay", "OrderedCollections", "InternalCollectionsUtilities", "Perception", "PerceptionCore", "Sharing", "Sharing1", "Sharing2", "SwiftNavigation", "SwiftUINavigation", "UIKitNavigation", "UIKitNavigationShim"]
    objects = [str(products / (name + ".o")) for name in names if (products / (name + ".o")).exists()]
    sources = [str(root / "Modules/Sources/SoundMixerEQ" / name) for name in ["EqualizerSettings.swift", "EqualizerClient.swift", "EqualizerFeature.swift", "OutputRouteSelection.swift", "OutputRoutingClient.swift", "OutputRoutingFeature.swift"]]
    subprocess.run(common + ["-emit-library", "-emit-module", "-module-name", "SoundMixerEQ", "-enable-testing", *sources, *objects, "-o", str(out / "libSoundMixerEQ.dylib")], check=True, cwd=root)
    (out / "Runner.swift").write_text("import Testing\n@main struct Runner { static func main() async { await Testing.__swiftPMEntryPoint() as Never } }\n")
    executable = out / "EqualizerFeatureTests"
    tests = [str(root / "Modules/Tests/SoundMixerEQTests" / name) for name in ["EqualizerFeatureTests.swift", "OutputRoutingFeatureTests.swift"]]
    subprocess.run(common + ["-parse-as-library", "-module-name", "SoundMixerEQTests", "-load-plugin-library", str(plugin), *tests, str(out / "Runner.swift"), "-L", str(out), "-lSoundMixerEQ", "-Xlinker", "-rpath", "-Xlinker", str(out), "-Xlinker", "-rpath", "-Xlinker", str(frameworks), "-o", str(executable)], check=True, cwd=root)
    subprocess.run([str(executable)], check=True, cwd=root)
