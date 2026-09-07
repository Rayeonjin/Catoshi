#!/usr/bin/env python3
"""Run the same freshness regressions on Macs whose Command Line Tools omit XCTest.

Compiles the current production Swift sources (except the GUI entry point) with
the unmodified test methods. Only XCTest's assertions/runner are adapted in a
temporary directory. No app is launched and all network responses are mocked.
Full Xcode users can instead run: swift test --filter MarketDataFreshnessTests
"""
from pathlib import Path
import re
import hashlib
import platform
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
SUITE = ROOT / "Tests/CatoshiTests/MarketDataFreshnessTests.swift"

SUPPORT = r'''
import Foundation

class XCTestCase {}
enum RegressionAssertions {
    static var failures = 0
    static func check(_ condition: Bool, _ message: String, file: StaticString, line: UInt) {
        if !condition {
            failures += 1
            print("FAIL: \(file):\(line): \(message)")
        }
    }
}
func XCTAssertEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
    RegressionAssertions.check(actual == expected, "\(actual) != \(expected)", file: file, line: line)
}
func XCTAssertTrue(_ actual: Bool, file: StaticString = #filePath, line: UInt = #line) {
    RegressionAssertions.check(actual, "Expected true", file: file, line: line)
}
func XCTAssertFalse(_ actual: Bool, file: StaticString = #filePath, line: UInt = #line) {
    RegressionAssertions.check(!actual, "Expected false", file: file, line: line)
}
func XCTAssertNil<T>(_ actual: T?, file: StaticString = #filePath, line: UInt = #line) {
    RegressionAssertions.check(actual == nil, "Expected nil", file: file, line: line)
}
func XCTAssertNotNil<T>(_ actual: T?, file: StaticString = #filePath, line: UInt = #line) {
    RegressionAssertions.check(actual != nil, "Expected non-nil", file: file, line: line)
}
'''


def main():
    suite = SUITE.read_text()
    suite = suite.replace("import XCTest\n", "import Foundation\n")
    suite = suite.replace("@testable import Catoshi\n", "")
    methods = re.findall(r"^    func (test\w+)\(\)( async)?", suite, re.MULTILINE)
    if not methods:
        raise SystemExit("No test methods found; refusing an empty success.")

    calls = []
    for method, is_async in methods:
        calls.extend([
            "        do {",
            "            let before = RegressionAssertions.failures",
            f"            {'await ' if is_async else ''}suite.{method}()",
            f'            print("\(RegressionAssertions.failures == before ? "PASS" : "FAIL"): {method}")',
            "        }",
        ])
    runner = "\n".join([
        "import Foundation",
        "@main struct FreshnessRegressionRunner {",
        "    @MainActor static func main() async {",
        "        let suite = MarketDataFreshnessTests()",
        *calls,
        f'        print("{len(methods)} test groups; \(RegressionAssertions.failures) assertion failures")',
        "        if RegressionAssertions.failures != 0 { exit(1) }",
        "    }",
        "}",
    ])

    with tempfile.TemporaryDirectory(prefix="CatoshiFreshnessChecks.") as directory:
        work = Path(directory)
        (work / "Assertions.swift").write_text(SUPPORT)
        (work / "MarketDataFreshnessTests.swift").write_text(suite)
        (work / "Runner.swift").write_text(runner)
        originals = sorted((ROOT / "Sources/Catoshi").rglob("*.swift"))
        originals = [path for path in originals if path.name != "AppLifecycle.swift"]
        sources = []
        digest = hashlib.sha256()
        # Compile an exact temporary snapshot so concurrent editor saves cannot
        # invalidate a long compiler run or mix source versions inside one file.
        for original in originals:
            relative = original.relative_to(ROOT)
            content = original.read_bytes()
            digest.update(str(relative).encode() + b"\0" + content)
            copy = work / relative
            copy.parent.mkdir(parents=True, exist_ok=True)
            copy.write_bytes(content)
            sources.append(copy)
        print("Source snapshot SHA-256: " + digest.hexdigest(), flush=True)
        binary = work / "freshness-checks"
        subprocess.run([
            "xcrun", "swiftc", "-swift-version", "5", "-parse-as-library", "-whole-module-optimization",
            "-target", platform.machine() + "-apple-macosx13.0",
            "-module-cache-path", str(ROOT / ".build/freshness-module-cache"), "-o", str(binary),
            *map(str, sources), str(work / "Assertions.swift"),
            str(work / "MarketDataFreshnessTests.swift"), str(work / "Runner.swift"),
        ], check=True, cwd=ROOT)
        subprocess.run([str(binary)], check=True, cwd=ROOT)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as failure:
        raise SystemExit(failure.returncode)
