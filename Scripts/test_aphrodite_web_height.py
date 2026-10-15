#!/usr/bin/env python3
"""Compile real Aphrodite rendering sources and exercise local WebKit reflow.

Run on macOS with Xcode: rtk proxy python3 scripts/test_aphrodite_web_height.py
The native fixture needs access to macOS WebKit subprocesses outside restrictive
command sandboxes. It makes no network requests and uses ephemeral storage.
"""

from pathlib import Path
import subprocess
import tempfile


def main():
    root = Path(__file__).resolve().parents[1]
    sources = [
        root / "Modules/Sources/Aphrodite/SecureAphroditeWebView.swift",
        root / "Modules/Sources/Aphrodite/AphroditeContentHeightReport.swift",
        root / "Modules/Sources/Aphrodite/AphroditeSandboxDocument.swift",
        root / "Modules/Tests/Integration/AphroditeWebHeightHarness.swift",
    ]
    with tempfile.TemporaryDirectory(prefix="aphrodite-height-") as temporary:
        directory = Path(temporary)
        executable = directory / "AphroditeWebHeightHarness"
        subprocess.run(
            ["xcrun", "swiftc", "-swift-version", "6", "-parse-as-library",
             "-module-cache-path", str(directory / "cache"),
             *map(str, sources), "-o", str(executable)],
            check=True,
            cwd=root,
            timeout=120,
        )
        subprocess.run([str(executable)], check=True, timeout=30)

        fitted_sources = [
            root / "Modules/Sources/Aphrodite/SecureAphroditeWebView.swift",
            root / "Modules/Sources/Aphrodite/AphroditeContentHeightReport.swift",
            root / "Modules/Sources/Aphrodite/AphroditeSandboxDocument.swift",
            root / "Modules/Sources/Aphrodite/AphroditeEditorPreviewScalePolicy.swift",
            root / "Modules/Sources/Aphrodite/AphroditeFittedPreview.swift",
            root / "Modules/Tests/Integration/AphroditeFittedPreviewHarness.swift",
        ]
        fitted_executable = directory / "AphroditeFittedPreviewHarness"
        subprocess.run(
            ["xcrun", "swiftc", "-swift-version", "6", "-parse-as-library",
             "-module-cache-path", str(directory / "fitted-cache"),
             *map(str, fitted_sources), "-o", str(fitted_executable)],
            check=True, cwd=root, timeout=120,
        )
        subprocess.run([str(fitted_executable)], check=True, timeout=30)


if __name__ == "__main__":
    main()
