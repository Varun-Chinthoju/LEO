import Darwin
import Foundation

struct BenchmarkCase: Codable {
    let id: String
    let prompt: String
    let expectedShape: String
}

struct BenchmarkMetric: Codable {
    let value: Double?
    let unit: String
    let availability: String
    let reason: String?
}

struct CorpusSummary: Codable {
    let fixture: String
    let cases: Int
}

struct Metrics: Codable {
    let structuredOutputCorrectness: BenchmarkMetric
    let timeToFirstTokenMilliseconds: BenchmarkMetric
    let tokensPerSecond: BenchmarkMetric
    let peakResidentMemoryBytes: BenchmarkMetric
}

struct BenchmarkResult: Codable {
    let generatedAt: Date
    let schemaVersion: Int
    let backend: String
    let backendAvailability: String
    let corpus: CorpusSummary
    let metrics: Metrics
    let status: String
}

private struct CommandOutput {
    let stdout: String
    let stderr: String
    let status: Int32
    let elapsedNanoseconds: UInt64
    let firstOutputNanoseconds: UInt64?
}

private final class OutputCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var firstOutputNanoseconds: UInt64?

    func append(_ chunk: Data, firstObservedAt timestamp: UInt64) {
        lock.withLock {
            if firstOutputNanoseconds == nil {
                firstOutputNanoseconds = timestamp
            }
            data.append(chunk)
        }
    }

    func snapshot() -> (Data, UInt64?) {
        lock.withLock { (data, firstOutputNanoseconds) }
    }
}

private protocol CommandRunning {
    func run(executable: String, arguments: [String]) throws -> CommandOutput
}

private struct SubprocessRunner: CommandRunning {
    func run(executable: String, arguments: [String]) throws -> CommandOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        let start = DispatchTime.now().uptimeNanoseconds
        try process.run()
        let capture = OutputCapture()
        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            capture.append(chunk, firstObservedAt: DispatchTime.now().uptimeNanoseconds - start)
        }

        process.waitUntilExit()
        output.fileHandleForReading.readabilityHandler = nil
        let finalChunk = output.fileHandleForReading.readDataToEndOfFile()
        if !finalChunk.isEmpty {
            capture.append(finalChunk, firstObservedAt: DispatchTime.now().uptimeNanoseconds - start)
        }
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        let captured = capture.snapshot()
        return CommandOutput(
            stdout: String(decoding: captured.0, as: UTF8.self),
            stderr: String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            status: process.terminationStatus,
            elapsedNanoseconds: elapsed,
            firstOutputNanoseconds: captured.1
        )
    }
}

private let recognizedShapes = Set([
    "tool:apps.open", "tool:context.open", "tool:files.move", "retrieval:recent-file",
    "referent:alternate", "confirmation:quarantine", "tool:quarantine.undo",
    "integration:calendar.next", "tool:files.open", "tool:files.rename",
    "integration:calendar.day", "tool:files.reveal"
])

private func parseStructuredShape(from output: String) -> String? {
    let candidates = output.split { $0.isWhitespace || $0 == "," || $0 == "." || $0 == "`" }
    return candidates.map(String.init).first(where: recognizedShapes.contains)
}

private func residentMemoryBytes() -> UInt64? {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else { return nil }
    return UInt64(usage.ru_maxrss)
}

private func metric(_ value: Double, unit: String, reason: String? = nil) -> BenchmarkMetric {
    BenchmarkMetric(value: value, unit: unit, availability: "measured", reason: reason)
}

private func unavailableMetric(unit: String, reason: String) -> BenchmarkMetric {
    BenchmarkMetric(value: nil, unit: unit, availability: "unavailable", reason: reason)
}

private func unavailableResult(backend: String, cases: [BenchmarkCase], reason: String) -> BenchmarkResult {
    let unavailable = Metrics(
        structuredOutputCorrectness: unavailableMetric(unit: "fraction", reason: reason),
        timeToFirstTokenMilliseconds: unavailableMetric(unit: "milliseconds", reason: reason),
        tokensPerSecond: unavailableMetric(unit: "tokens/second", reason: reason),
        peakResidentMemoryBytes: unavailableMetric(unit: "bytes", reason: reason)
    )
    return BenchmarkResult(
        generatedAt: .now,
        schemaVersion: 2,
        backend: backend,
        backendAvailability: "unavailable",
        corpus: CorpusSummary(fixture: "Sources/LEOBenchmarks/Fixtures/model-cases.json", cases: cases.count),
        metrics: unavailable,
        status: "unavailable"
    )
}

private func installedModels(from output: String) -> Set<String> {
    Set(output.split(separator: "\n").dropFirst().compactMap { line in
        line.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init)
    })
}

private func benchmarkOllama(model: String, cases: [BenchmarkCase], runner: CommandRunning) -> BenchmarkResult {
    let list: CommandOutput
    do {
        list = try runner.run(executable: "ollama", arguments: ["list"])
    } catch {
        return unavailableResult(backend: model, cases: cases, reason: "Ollama runtime is unavailable: \(error.localizedDescription)")
    }
    guard list.status == 0 else {
        return unavailableResult(backend: model, cases: cases, reason: "Ollama runtime is unavailable: \(list.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
    }
    guard installedModels(from: list.stdout).contains(model) else {
        return unavailableResult(backend: model, cases: cases, reason: "Model '\(model)' is not installed; benchmark will not pull or download it.")
    }

    var totalTokens = 0
    var totalNanoseconds: UInt64 = 0
    var firstTokenSamples: [UInt64] = []
    var parsed = 0
    var correct = 0
    var failures = 0
    let instruction = "Respond with exactly one recognized shape token and no explanation. Recognized shapes: \(recognizedShapes.sorted().joined(separator: ", ")). Request:"

    for item in cases {
        do {
            let output = try runner.run(executable: "ollama", arguments: ["run", model, "\(instruction) \(item.prompt)"])
            totalNanoseconds += output.elapsedNanoseconds
            if let first = output.firstOutputNanoseconds { firstTokenSamples.append(first) }
            if output.status != 0 {
                failures += 1
                continue
            }
            totalTokens += output.stdout.split { $0.isWhitespace }.count
            if let shape = parseStructuredShape(from: output.stdout) {
                parsed += 1
                if shape == item.expectedShape { correct += 1 }
            }
        } catch {
            failures += 1
        }
    }

    let parserReason = parsed == 0
        ? "No structured accuracy claimed: parser evidence was absent from every model response."
        : "Parser evidence found in \(parsed) of \(cases.count) responses."
    let elapsedSeconds = max(Double(totalNanoseconds) / 1_000_000_000, 0.000001)
    let timingReason = failures == 0 ? nil : "\(failures) model invocations failed; timing covers successful invocations only."
    let structured = parsed == 0
        ? unavailableMetric(unit: "fraction", reason: parserReason)
        : metric(Double(correct) / Double(cases.count), unit: "fraction", reason: parserReason)
    let timing = firstTokenSamples.isEmpty
        ? unavailableMetric(unit: "milliseconds", reason: "No model response produced measurable output.")
        : metric(Double(firstTokenSamples.reduce(0, +) / UInt64(firstTokenSamples.count)) / 1_000_000, unit: "milliseconds", reason: timingReason)
    let tokens = totalTokens == 0
        ? unavailableMetric(unit: "tokens/second", reason: "No model tokens were observed.")
        : metric(Double(totalTokens) / elapsedSeconds, unit: "tokens/second", reason: timingReason)
    let memory = residentMemoryBytes().map { metric(Double($0), unit: "bytes", reason: timingReason) }
        ?? unavailableMetric(unit: "bytes", reason: "Peak resident memory could not be measured.")

    return BenchmarkResult(
        generatedAt: .now,
        schemaVersion: 2,
        backend: model,
        backendAvailability: "available",
        corpus: CorpusSummary(fixture: "Sources/LEOBenchmarks/Fixtures/model-cases.json", cases: cases.count),
        metrics: Metrics(structuredOutputCorrectness: structured, timeToFirstTokenMilliseconds: timing, tokensPerSecond: tokens, peakResidentMemoryBytes: memory),
        status: failures == cases.count
            ? "unavailable"
            : (failures == 0 && parsed > 0 ? "measured" : "partial")
    )
}

let fixtureURL = Bundle.module.url(forResource: "model-cases", withExtension: "json", subdirectory: "Fixtures")!
let cases = try JSONDecoder().decode([BenchmarkCase].self, from: Data(contentsOf: fixtureURL))
let backend = CommandLine.arguments.dropFirst().first ?? "mock"
guard cases.count >= 20, Set(cases.map(\.id)).count == cases.count else {
    fatalError("Benchmark fixture must contain at least 20 uniquely identified cases")
}

let result: BenchmarkResult
if backend == "mock" {
    let reason = "Measured against the deterministic mock backend; not representative of a local LLM."
    result = BenchmarkResult(
        generatedAt: .now, schemaVersion: 2, backend: backend, backendAvailability: "fixture-only",
        corpus: CorpusSummary(fixture: "Sources/LEOBenchmarks/Fixtures/model-cases.json", cases: cases.count),
        metrics: Metrics(
            structuredOutputCorrectness: unavailableMetric(unit: "fraction", reason: "No structured model output or parser evidence is produced by the mock backend."),
            timeToFirstTokenMilliseconds: metric(0, unit: "milliseconds", reason: reason),
            tokensPerSecond: metric(0, unit: "tokens/second", reason: reason),
            peakResidentMemoryBytes: residentMemoryBytes().map { metric(Double($0), unit: "bytes", reason: reason) } ?? unavailableMetric(unit: "bytes", reason: reason)
        ), status: "partial"
    )
} else if backend == "gemma3:4b" || backend == "qwen3.5:0.8b" {
    result = benchmarkOllama(model: backend, cases: cases, runner: SubprocessRunner())
} else {
    result = unavailableResult(backend: backend, cases: cases, reason: "No benchmark backend is configured for '\(backend)'.")
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
encoder.dateEncodingStrategy = .iso8601
print(String(decoding: try encoder.encode(result), as: UTF8.self))
