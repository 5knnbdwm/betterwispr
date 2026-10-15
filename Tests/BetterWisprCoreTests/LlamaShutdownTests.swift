import Foundation
import Testing
@testable import BetterWisprCore

private final class ClosingWeights: LanguageWeights {
    let contextLength = 8192
    let closing = DispatchSemaphore(value: 0)
    let finishClosing = DispatchSemaphore(value: 0)

    func tokens(for prompt: ChatPrompt) throws -> [Int32] { [] }
    func open(grammar: String?) throws -> any TokenStream { throw LlamaEngineError.contextFailed }

    func close() {
        closing.signal()
        _ = finishClosing.wait(timeout: .now() + 5)
    }
}

private func didSignal(_ semaphore: DispatchSemaphore, within seconds: Double = 2) async -> Bool {
    await withCheckedContinuation { continuation in
        DispatchQueue.global().async {
            continuation.resume(returning: semaphore.wait(timeout: .now() + seconds) == .success)
        }
    }
}

@Test(arguments: [true, false])
func shutdownWaitsUntilAnIdleOrExplicitUnloadFinishes(idle: Bool) async throws {
    let weights = ClosingWeights()
    let engine = LlamaEngine(idleDelay: idle ? .zero : .seconds(300)) { weights }
    await engine.warmUp()
    let unload = Task { if !idle { await engine.unload() } }
    defer { weights.finishClosing.signal() }
    try #require(await didSignal(weights.closing))
    let stopped = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
        engine.shutdown()
        stopped.signal()
    }
    #expect(await didSignal(stopped, within: 0.2) == false)
    weights.finishClosing.signal()
    #expect(await didSignal(stopped))
    await unload.value
}

@Test func shutdownWaitsForTheLateLoadedWeightsToFinishClosing() async throws {
    let weights = ClosingWeights()
    let loading = DispatchSemaphore(value: 0)
    let finishLoading = DispatchSemaphore(value: 0)
    let engine = LlamaEngine {
        loading.signal()
        _ = finishLoading.wait(timeout: .now() + 5)
        return weights
    }
    let warmup = Task { await engine.warmUp() }
    defer {
        finishLoading.signal()
        weights.finishClosing.signal()
    }
    try #require(await didSignal(loading))
    let stopped = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
        engine.shutdown()
        stopped.signal()
    }
    await warmup.value
    finishLoading.signal()
    try #require(await didSignal(weights.closing))
    #expect(await didSignal(stopped, within: 0.2) == false)
    weights.finishClosing.signal()
    #expect(await didSignal(stopped))
}
