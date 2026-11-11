import Foundation
import Observation
import SwiftData

/// Publishes a changed draft only after it has been saved successfully. This
/// keeps the gym screen aligned with the session recoverable after relaunch.
@MainActor @Observable
final class WorkoutSessionModel {
    private(set) var draft: StrengthDraft
    var error: String?
    var invalidInputs = Set<String>()
    init(draft: StrengthDraft) { self.draft = draft }

    @discardableResult
    func update(context: ModelContext, _ change: (inout StrengthDraft) -> Void) -> Bool {
        var next = draft
        change(&next)
        do {
            try WorkoutStore(context: context).saveSession(next)
            draft = next
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func finish(context: ModelContext, now: Date = .now) -> Bool {
        guard invalidInputs.isEmpty else { error = "Fix invalid set values before finishing."; return false }
        do {
            let finished = try draft.finished(at: now)
            try WorkoutStore(context: context).saveSession(finished)
            draft = finished
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func cancel(context: ModelContext) -> Bool {
        update(context: context) { $0.status = .cancelled; $0.end = .now; $0.restEndsAt = nil }
    }
}
