/// Holds a stubbed request open until a test lets it go.
///
/// Overlap is what these tests are about — a write that fails after a later
/// one succeeded, a page that lands after sign-out — and sleeping to arrange it
/// is both slow and a race. A test holds a key, waits until the request is
/// parked on it, does whatever should happen meanwhile, then releases it.
actor TestGate {
    private var held: Set<String> = []
    private var parked: [String: CheckedContinuation<Void, Never>] = [:]
    private var watchers: [String: CheckedContinuation<Void, Never>] = [:]

    func hold(_ key: String) {
        held.insert(key)
    }

    /// Called by a stub. Returns at once unless the key is held.
    func pass(_ key: String) async {
        guard held.contains(key) else {
            return
        }

        await withCheckedContinuation { continuation in
            parked[key] = continuation
            watchers.removeValue(forKey: key)?.resume()
        }
    }

    /// Returns once a request is parked on the key, so the test acts while it
    /// is genuinely in flight.
    func waitUntilParked(_ key: String) async {
        guard parked[key] == nil else {
            return
        }

        await withCheckedContinuation { continuation in
            watchers[key] = continuation
        }
    }

    func release(_ key: String) {
        held.remove(key)
        parked.removeValue(forKey: key)?.resume()
    }
}
