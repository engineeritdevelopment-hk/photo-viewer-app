import Foundation

/// Estimates remaining time from monotonic progress samples.
struct ProgressETAEstimator {
    private var startedAt: Date?
    private var lastDone = 0
    private var lastSampleAt: Date?
    private var smoothedRemaining: TimeInterval?

    mutating func reset() {
        startedAt = nil
        lastDone = 0
        lastSampleAt = nil
        smoothedRemaining = nil
    }

  /// Returns a user-facing label when `done` is in `(0, total)`.
    mutating func update(done: Int, total: Int) -> String? {
        guard total > 0, done < total else {
            if done >= total { reset() }
            return nil
        }

        let now = Date()
        if startedAt == nil {
            startedAt = now
            lastDone = done
            lastSampleAt = now
        }

        var estimate: TimeInterval?
        if let lastSampleAt, done > lastDone {
            let interval = now.timeIntervalSince(lastSampleAt)
            let delta = done - lastDone
            if interval >= 0.2, delta > 0 {
                let rate = Double(delta) / interval
                estimate = Double(total - done) / rate
            }
        }

        if estimate == nil, let startedAt, done > 0 {
            let elapsed = now.timeIntervalSince(startedAt)
            if elapsed >= 1.5 {
                let rate = Double(done) / elapsed
                estimate = Double(total - done) / rate
            }
        }

        if let estimate, estimate.isFinite, estimate > 0 {
            if let smoothed = smoothedRemaining {
                smoothedRemaining = smoothed * 0.65 + estimate * 0.35
            } else {
                smoothedRemaining = estimate
            }
        }

        lastDone = done
        lastSampleAt = now

        guard let remaining = smoothedRemaining, remaining.isFinite, remaining >= 1 else { return nil }
        return Self.format(remaining: remaining)
    }

    static func format(remaining: TimeInterval) -> String {
        let seconds = Int(remaining.rounded())
        if seconds < 60 {
            return "~\(seconds)s remaining"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            let remSeconds = seconds % 60
            if remSeconds < 8 { return "~\(minutes) min remaining" }
            return "~\(minutes) min \(remSeconds)s remaining"
        }
        let hours = minutes / 60
        let remMinutes = minutes % 60
        if remMinutes == 0 { return "~\(hours)h remaining" }
        return "~\(hours)h \(remMinutes)m remaining"
    }
}