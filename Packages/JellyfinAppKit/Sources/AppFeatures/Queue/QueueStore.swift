import AppCore
import Foundation
import Instrumentation
import JellyfinAPI
import Observation

/// Queue, kept per account: what you've added, in order, and when you
/// want to be done. "Done by" arms the sleep timer for that time, so the
/// plan *is* the sleep timer for the evening.
@MainActor
@Observable
final class QueueStore {
    private(set) var plan = QueuePlan()
    /// Ticks once a minute so the times on screen stay true.
    private(set) var now = Date.now
    @ObservationIgnored private var key = "tonight"      // the stored key from before the rename (keeps saved queues)
    /// The app's settings store (the mock profile has its own, cleared by -reset).
    @ObservationIgnored private var defaults: UserDefaults = .standard
    @ObservationIgnored private weak var sleepTimer: SleepTimer?
    @ObservationIgnored private var clock: Task<Void, Never>?
    /// Next-up episodes: where suggestions come from.
    @ObservationIgnored var candidates: [BaseItem] = [] { didSet { refreshSuggestions() } }
    /// Changes go out to the companion app.
    @ObservationIgnored var onChange: (() -> Void)?

    func attach(account: String, sleepTimer: SleepTimer, defaults: UserDefaults) {
        key = "tonight-\(account)"
        self.sleepTimer = sleepTimer
        self.defaults = defaults
        plan = QueuePlan()
        if let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode(QueuePlan.self, from: data) {
            plan = saved
            if let doneBy = plan.doneBy, doneBy < .now { plan.doneBy = nil }    // yesterday's
        }
        clock?.cancel()
        clock = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.now = .now
            }
        }
        armSleepTimer()
    }

    var isEmpty: Bool { plan.entries.isEmpty }
    func contains(_ id: String) -> Bool { plan.contains(id) }
    var timeline: [QueuePlan.Slot] { plan.timeline(now: now) }

    func add(_ item: BaseItem) { change { $0.add(item) }; TraceFile.write("queue", "add \(item.name ?? item.id)") }
    func remove(_ id: String) { change { $0.remove(id) } }
    func move(_ id: String, by offset: Int) { change { $0.move(id, by: offset) } }
    func finished(_ id: String) { change { $0.finished(id) } }
    func toggle(_ item: BaseItem) { contains(item.id) ? remove(item.id) : add(item) }
    func next(after id: String?) -> BaseItem? { plan.next(after: id)?.item }

    func setDoneBy(_ date: Date?) {
        change { $0.doneBy = date }
        armSleepTimer()
    }

    /// "Done by" presets: the next few half hours, from an hour from now.
    func doneByChoices(now: Date = .now) -> [Date] {
        let cal = Calendar.current
        let start = cal.nextDate(after: now.addingTimeInterval(45 * 60), matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? now
        return (0..<6).map { start.addingTimeInterval(Double($0) * 30 * 60) }
    }

    func replace(with plan: QueuePlan) {
        self.plan = plan
        save()
        armSleepTimer()
        onChange?()
    }

    private func change(_ edit: (inout QueuePlan) -> Void) {
        edit(&plan)
        plan.suggest(candidates.filter { !plan.contains($0.id) }, now: now)
        save()
        onChange?()
    }

    private func refreshSuggestions() {
        guard !plan.picks.isEmpty else { return }       // nothing to suggest around yet
        let before = plan
        plan.suggest(candidates, now: now)
        if plan != before { save(); onChange?() }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(plan) { defaults.set(data, forKey: key) }
    }

    private func armSleepTimer() {
        guard let sleepTimer else { return }
        if let doneBy = plan.doneBy {
            let seconds = Int(doneBy.timeIntervalSinceNow)
            if seconds > 60 { sleepTimer.set(seconds: seconds) }
        }
    }
}
