#!/usr/bin/env python3
"""Run brightness and DDC regression tests using cached Xcode dependency products.

Usage: python3 Scripts/test_display_brightness.py [--products /path/to/Build/Products/Debug]

Compiles the actual package sources, including the SwiftUI views, under Swift 6
for macOS 14. This avoids resolving unrelated app dependencies and the existing
IssueReporting package-identity conflict. Build OnlySwitch once with the current
Xcode toolchain before running; no live display settings are changed by tests.
"""

import argparse
from pathlib import Path
import subprocess
import sys
import tempfile


DEPENDENCY_OBJECTS = [
    "Extensions", "Defines", "ComposableArchitecture", "CasePaths", "CasePathsCore",
    "Clocks", "CombineSchedulers", "ConcurrencyExtras", "CustomDump", "Dependencies",
    "DependenciesMacros", "IdentifiedCollections", "IssueReporting", "_IssueReporting",
    "XCTestDynamicOverlay", "OrderedCollections", "InternalCollectionsUtilities",
    "Perception", "PerceptionCore", "Sharing", "Sharing1", "Sharing2", "SwiftNavigation",
    "SwiftUINavigation", "UIKitNavigation", "UIKitNavigationShim",
]
MACRO_PLUGINS = [
    ("ComposableArchitectureMacros", "ComposableArchitectureMacros"),
    ("CasePathsMacros", "CasePathsMacros"),
    ("PerceptionMacros", "PerceptionMacros"),
    ("DependenciesMacrosPlugin", "DependenciesMacrosPlugin"),
]


def find_products(specified: Path | None) -> Path:
    required = ["ComposableArchitecture.o", "Dependencies.o", "Extensions.o", "Defines.o"]
    required += [name for name, _ in MACRO_PLUGINS]
    if specified is not None:
        candidates = [specified.expanduser().resolve()]
    else:
        cache = Path.home() / "Library/Developer/Xcode/DerivedData"
        candidates = sorted(
            cache.glob("*/Build/Products/Debug"), key=lambda p: p.stat().st_mtime, reverse=True
        )
    for candidate in candidates:
        if all((candidate / name).exists() for name in required):
            return candidate
    raise RuntimeError(
        "No matching cached dependency products found. Build OnlySwitch with the current "
        "Xcode toolchain, then pass its Build/Products/Debug directory with --products."
    )


def run_suite(root: Path, output: Path, module: str, common: list[str],
              objects: list[str], testing_plugin: Path, frameworks: Path) -> None:
    sources = sorted((root / "Modules/Sources" / module).rglob("*.swift"))
    tests = sorted((root / "Modules/Tests" / (module + "Tests")).rglob("*.swift"))
    if not sources or not tests:
        raise RuntimeError(f"Missing sources or tests for {module}")
    print(f"Compiling {module} and {len(tests)} test files", flush=True)
    subprocess.run(common + [
        "-emit-library", "-emit-module", "-module-name", module, "-enable-testing",
        *map(str, sources), *objects, "-o", str(output / ("lib" + module + ".dylib")),
    ], check=True, cwd=root)
    runner = output / (module + "Runner.swift")
    runner.write_text(
        "import Testing\n"
        "@main struct Runner {\n"
        "    static func main() async { await Testing.__swiftPMEntryPoint() as Never }\n"
        "}\n"
    )
    executable = output / (module + "Tests")
    subprocess.run(common + [
        "-parse-as-library", "-module-name", module + "Tests", "-load-plugin-library",
        str(testing_plugin), *map(str, tests), str(runner), "-L", str(output), "-l" + module,
        "-Xlinker", "-rpath", "-Xlinker", str(output),
        "-Xlinker", "-rpath", "-Xlinker", str(frameworks), "-o", str(executable),
    ], check=True, cwd=root)
    subprocess.run([str(executable)], check=True, cwd=root)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--products", type=Path, help="Cached Xcode macOS Debug dependency products")
    options = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    products = find_products(options.products)
    developer = Path(subprocess.check_output(["xcode-select", "-p"], text=True).strip())
    frameworks = developer / "Platforms/MacOSX.platform/Developer/Library/Frameworks"
    testing_plugin = developer / "Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
    print(f"Using dependency products: {products}", flush=True)
    with tempfile.TemporaryDirectory(prefix="onlyswitch-brightness-tests-") as temporary:
        output = Path(temporary)
        common = [
            "xcrun", "swiftc", "-swift-version", "6", "-target", "arm64-apple-macosx14.0",
            "-Xfrontend", "-disable-sandbox", "-module-cache-path", str(output / "cache"),
            "-I", str(output), "-I", str(products), "-F", str(frameworks),
        ]
        for executable, module in MACRO_PLUGINS:
            common += ["-load-plugin-executable", str(products / executable) + "#" + module]
        objects = [str(products / (name + ".o")) for name in DEPENDENCY_OBJECTS
                   if (products / (name + ".o")).exists()]
        run_suite(root, output, "DisplayBrightness", common, objects, testing_plugin, frameworks)
        run_suite(root, output, "DisplayDDC", common, [], testing_plugin, frameworks)


if __name__ == "__main__":
    try:
        main()
    except RuntimeError as error:
        print(f"Display brightness checks failed: {error}", file=sys.stderr)
        sys.exit(1)
    except subprocess.CalledProcessError as error:
        print(f"Display brightness checks failed: {error.cmd[0]} exited with status {error.returncode}.", file=sys.stderr)
        sys.exit(error.returncode)
