import Foundation
import XCTest

final class BenchmarkFixtureTests: XCTestCase {
    private struct BenchmarkCase: Decodable {
        let id: String
        let prompt: String
        let expectedShape: String
    }

    private func loadCases() throws -> [BenchmarkCase] {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/LEOBenchmarks/Fixtures/model-cases.json")
        return try JSONDecoder().decode([BenchmarkCase].self, from: Data(contentsOf: fixtureURL))
    }

    func testFixtureContainsAtLeastTwentyUniqueLEOReasoningCases() throws {
        let cases = try loadCases()
        XCTAssertGreaterThanOrEqual(cases.count, 20)
        XCTAssertEqual(Set(cases.map(\.id)).count, cases.count)
        XCTAssertTrue(cases.allSatisfy { !$0.prompt.isEmpty && !$0.expectedShape.isEmpty })
    }

    func testFixtureCoversTaskFourteenReasoningShapes() throws {
        let prompts = Set(try loadCases().map(\.prompt))
        XCTAssertTrue(prompts.isSuperset(of: [
            "open Xcode", "open this", "move this to Downloads",
            "find the PDF from earlier", "use the other one", "trash this",
            "undo that", "what is next on my calendar?"
        ]))
    }

    func testOllamaBenchmarkReportsUnavailableWithoutPullingWhenModelIsMissing() throws {
        let script = try makeFakeOllama(listOutput: "NAME\\tID", runOutput: "unexpected run")
        let result = try runBenchmark(backend: "gemma3:4b", ollama: script)

        XCTAssertEqual(result.status, "unavailable")
        XCTAssertEqual(result.backendAvailability, "unavailable")
        XCTAssertNil(result.metrics.structuredOutputCorrectness.value)
        XCTAssertEqual(result.metrics.structuredOutputCorrectness.availability, "unavailable")
        XCTAssertTrue(result.metrics.structuredOutputCorrectness.reason?.contains("not installed") == true)
    }

    func testOllamaBenchmarkDoesNotClaimStructuredAccuracyForUnparseableOutput() throws {
        let script = try makeFakeOllama(
            listOutput: "NAME\\tID\\ngemma3:4b\\tlocal",
            runOutput: "I can help with that."
        )
        let result = try runBenchmark(backend: "gemma3:4b", ollama: script)

        XCTAssertEqual(result.status, "partial")
        XCTAssertEqual(result.backendAvailability, "available")
        XCTAssertNil(result.metrics.structuredOutputCorrectness.value)
        XCTAssertEqual(result.metrics.structuredOutputCorrectness.availability, "unavailable")
        XCTAssertTrue(result.metrics.structuredOutputCorrectness.reason?.contains("parser evidence") == true)
    }

    private struct JSONResult: Decodable {
        let status: String
        let backendAvailability: String
        let metrics: JSONMetrics
    }

    private struct JSONMetrics: Decodable {
        let structuredOutputCorrectness: JSONMetric
    }

    private struct JSONMetric: Decodable {
        let value: Double?
        let availability: String
        let reason: String?
    }

    private func runBenchmark(backend: String, ollama: URL) throws -> JSONResult {
        let process = Process()
        process.executableURL = benchmarkExecutable
        process.arguments = [backend]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = ollama.deletingLastPathComponent().path + ":" + (environment["PATH"] ?? "")
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        process.currentDirectoryURL = packageRoot
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return try JSONDecoder().decode(JSONResult.self, from: output.fileHandleForReading.readDataToEndOfFile())
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var benchmarkExecutable: URL {
        Bundle(for: BenchmarkFixtureTests.self).bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("leo-benchmark")
    }

    private func makeFakeOllama(listOutput: String, runOutput: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("ollama")
        let script = "#!/bin/sh\nif [ \"$1\" = \"list\" ]; then\n  printf '%b\\n' '" + listOutput + "'\nelse\n  printf '%b\\n' '" + runOutput + "'\nfi\n"
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return executable
    }
}
