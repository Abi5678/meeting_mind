import Foundation

/// Whether `work` finishes without throwing within `limit`. Past the limit this returns false and
/// leaves `work` running, so a download it started can still finish, ready for next time.
func finishes(within limit: Duration, _ work: @escaping @Sendable () async throws -> Void) async -> Bool {
    let (outcome, report) = AsyncStream.makeStream(of: Bool.self)
    Task.detached { report.yield((try? await work()) != nil) }
    let deadline = Task { try? await Task.sleep(for: limit); report.yield(false) }
    var outcomes = outcome.makeAsyncIterator()
    let finished = await outcomes.next() ?? false
    deadline.cancel()
    return finished
}
