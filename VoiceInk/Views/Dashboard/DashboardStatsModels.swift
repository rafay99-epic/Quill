import Foundation
import SwiftData
import SwiftUI

enum DashboardProductivityPeriod: String, CaseIterable, Identifiable, Sendable {
    case lastThreeDays
    case lastFiveDays
    case lastSevenDays
    case lastThirtyDays
    case thisYear
    case allTime

    static let modelPerformanceStorageKey = "modelPerfPanelFilter"

    var id: Self { self }

    var pickerTitle: LocalizedStringKey {
        switch self {
        case .lastThreeDays: return "Last 3 Days"
        case .lastFiveDays: return "Last 5 Days"
        case .lastSevenDays: return "Last 7 Days"
        case .lastThirtyDays: return "Last 30 Days"
        case .thisYear: return "This Year"
        case .allTime: return "All Time"
        }
    }

    var chartTitle: LocalizedStringKey {
        switch self {
        case .lastThreeDays: return "3-Day Productivity"
        case .lastFiveDays: return "5-Day Productivity"
        case .lastSevenDays: return "Weekly Productivity"
        case .lastThirtyDays: return "Monthly Productivity"
        case .thisYear: return "Yearly Productivity"
        case .allTime: return "All-Time Productivity"
        }
    }

    var modelPerformanceStorageValue: String {
        switch self {
        case .lastThreeDays: return "Last 3 Days"
        case .lastFiveDays: return "Last 5 Days"
        case .lastSevenDays: return "Last 7 Days"
        case .lastThirtyDays: return "Last 30 Days"
        case .thisYear: return "This Year"
        case .allTime: return "All Time"
        }
    }

    init(modelPerformanceStorageValue: String) {
        let match = Self.allCases.first {
            modelPerformanceStorageValue == $0.modelPerformanceStorageValue ||
            modelPerformanceStorageValue == $0.rawValue
        }
        self = match ?? .lastSevenDays
    }

    func startDate(now: Date, calendar: Calendar) -> Date? {
        let todayStart = calendar.startOfDay(for: now)

        switch self {
        case .lastThreeDays:
            return calendar.date(byAdding: .day, value: -2, to: todayStart) ?? todayStart
        case .lastFiveDays:
            return calendar.date(byAdding: .day, value: -4, to: todayStart) ?? todayStart
        case .lastSevenDays:
            return calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
        case .lastThirtyDays:
            return calendar.date(byAdding: .day, value: -29, to: todayStart) ?? todayStart
        case .thisYear:
            return calendar.dateInterval(of: .year, for: now)?.start
        case .allTime:
            return nil
        }
    }

    var sessionMetricPredicate: Predicate<SessionMetric>? {
        let now = Date()
        let calendar = DashboardPeriodWindows.dashboardCalendar()
        guard let start = startDate(now: now, calendar: calendar) else {
            return nil
        }

        return #Predicate<SessionMetric> { metric in
            metric.timestamp >= start
        }
    }
}

struct DashboardPeriodWindows {
    let now: Date
    let calendar: Calendar
    let recentThreeDayInterval: DateInterval
    let recentFiveDayInterval: DateInterval
    let recentSevenDayInterval: DateInterval
    let recentThirtyDayInterval: DateInterval
    let thisYearInterval: DateInterval
    let previousSevenDayInterval: DateInterval
    let thisYearStart: Date

    init(now: Date = Date(), calendar: Calendar = Self.dashboardCalendar()) {
        self.now = now
        self.calendar = calendar

        let todayStart = calendar.startOfDay(for: now)
        let recentThreeDayStart = calendar.date(byAdding: .day, value: -2, to: todayStart) ?? todayStart
        let recentFiveDayStart = calendar.date(byAdding: .day, value: -4, to: todayStart) ?? todayStart
        let recentSevenDayStart = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
        let recentThirtyDayStart = calendar.date(byAdding: .day, value: -29, to: todayStart) ?? todayStart
        let thisYearStart = calendar.dateInterval(of: .year, for: now)?.start ?? now
        let previousSevenDayStart = calendar.date(byAdding: .day, value: -7, to: recentSevenDayStart) ?? recentSevenDayStart

        self.thisYearStart = thisYearStart
        self.recentThreeDayInterval = DateInterval(start: recentThreeDayStart, end: now)
        self.recentFiveDayInterval = DateInterval(start: recentFiveDayStart, end: now)
        self.recentSevenDayInterval = DateInterval(start: recentSevenDayStart, end: now)
        self.recentThirtyDayInterval = DateInterval(start: recentThirtyDayStart, end: now)
        self.thisYearInterval = DateInterval(start: thisYearStart, end: now)
        self.previousSevenDayInterval = DateInterval(start: previousSevenDayStart, end: recentSevenDayStart)
    }

    static func dashboardCalendar() -> Calendar {
        var calendar = Calendar.current
        calendar.timeZone = .current
        calendar.firstWeekday = 2
        return calendar
    }
}

struct DashboardMetricTotals: Equatable, Sendable {
    var count: Int = 0
    var words: Int = 0
    var duration: TimeInterval = 0
}

struct DashboardProductivityPoint: Equatable, Identifiable, Sendable {
    var id: Date { date }
    let date: Date
    let label: String
    let accessibilityLabel: String
    var words: Int = 0
}

enum DashboardModelUsageKind: String, Sendable {
    case transcription
    case enhancement
}

struct DashboardModelUsageSummary: Equatable, Identifiable, Sendable {
    var id: String { "\(kind.rawValue)-\(name)" }
    let kind: DashboardModelUsageKind
    let name: String
    let sessionCount: Int
    let averageDuration: TimeInterval?
}

extension Sequence where Element == DashboardModelUsageSummary {
    func sortedForDashboardDisplay() -> [DashboardModelUsageSummary] {
        sorted { lhs, rhs in
            if lhs.sessionCount == rhs.sessionCount {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

            return lhs.sessionCount > rhs.sessionCount
        }
    }
}

struct DashboardHourlyActivityPoint: Equatable, Identifiable, Sendable {
    var id: Int { hour }
    let hour: Int
    let wordCount: Int
    let sessionCount: Int
}

struct DashboardPeakHoursSummary: Equatable, Sendable {
    static let empty = DashboardPeakHoursSummary(
        startHour: 0,
        endHour: 2,
        wordCount: 0,
        sessionCount: 0,
        hourlyActivity: (0..<24).map { hour in
            DashboardHourlyActivityPoint(hour: hour, wordCount: 0, sessionCount: 0)
        }
    )

    let startHour: Int
    let endHour: Int
    let wordCount: Int
    let sessionCount: Int
    let hourlyActivity: [DashboardHourlyActivityPoint]

    var hasData: Bool {
        wordCount > 0 || sessionCount > 0
    }
}

struct DashboardStatsSummary: Equatable, Sendable {
    static let empty = DashboardStatsSummary()

    var totalCount: Int = 0
    var totalWords: Int = 0
    var totalDuration: TimeInterval = 0
    var recentSevenDayCount: Int = 0
    var recentSevenDayWords: Int = 0
    var recentSevenDayDuration: TimeInterval = 0
    var previousSevenDayCount: Int = 0
    var previousSevenDayWords: Int = 0
    var previousSevenDayDuration: TimeInterval = 0
    var lastThreeDayCount: Int = 0
    var lastThreeDayWords: Int = 0
    var lastThreeDayDuration: TimeInterval = 0
    var lastFiveDayCount: Int = 0
    var lastFiveDayWords: Int = 0
    var lastFiveDayDuration: TimeInterval = 0
    var lastThreeDayProductivity: [DashboardProductivityPoint] = []
    var lastFiveDayProductivity: [DashboardProductivityPoint] = []
    var lastThreeDayModelUsage: [DashboardModelUsageSummary] = []
    var lastFiveDayModelUsage: [DashboardModelUsageSummary] = []
    var lastThreeDayPeakHours: DashboardPeakHoursSummary = .empty
    var lastFiveDayPeakHours: DashboardPeakHoursSummary = .empty
    var lastThirtyDayCount: Int = 0
    var lastThirtyDayWords: Int = 0
    var lastThirtyDayDuration: TimeInterval = 0
    var thisYearCount: Int = 0
    var thisYearWords: Int = 0
    var thisYearDuration: TimeInterval = 0
    var lastSevenDayProductivity: [DashboardProductivityPoint] = []
    var lastThirtyDayProductivity: [DashboardProductivityPoint] = []
    var thisYearProductivity: [DashboardProductivityPoint] = []
    var allTimeProductivity: [DashboardProductivityPoint] = []
    var lastSevenDayModelUsage: [DashboardModelUsageSummary] = []
    var lastThirtyDayModelUsage: [DashboardModelUsageSummary] = []
    var thisYearModelUsage: [DashboardModelUsageSummary] = []
    var allTimeModelUsage: [DashboardModelUsageSummary] = []
    var lastSevenDayPeakHours: DashboardPeakHoursSummary = .empty
    var lastThirtyDayPeakHours: DashboardPeakHoursSummary = .empty
    var thisYearPeakHours: DashboardPeakHoursSummary = .empty
    var allTimePeakHours: DashboardPeakHoursSummary = .empty
}

extension DashboardStatsSummary {
    var total: DashboardMetricTotals {
        DashboardMetricTotals(count: totalCount, words: totalWords, duration: totalDuration)
    }

    var recentSevenDays: DashboardMetricTotals {
        DashboardMetricTotals(
            count: recentSevenDayCount,
            words: recentSevenDayWords,
            duration: recentSevenDayDuration
        )
    }

    var previousSevenDays: DashboardMetricTotals {
        DashboardMetricTotals(
            count: previousSevenDayCount,
            words: previousSevenDayWords,
            duration: previousSevenDayDuration
        )
    }

    func totals(for period: DashboardProductivityPeriod) -> DashboardMetricTotals {
        switch period {
        case .lastThreeDays:
            return DashboardMetricTotals(
                count: lastThreeDayCount,
                words: lastThreeDayWords,
                duration: lastThreeDayDuration
            )
        case .lastFiveDays:
            return DashboardMetricTotals(
                count: lastFiveDayCount,
                words: lastFiveDayWords,
                duration: lastFiveDayDuration
            )
        case .lastSevenDays:
            return recentSevenDays
        case .lastThirtyDays:
            return DashboardMetricTotals(
                count: lastThirtyDayCount,
                words: lastThirtyDayWords,
                duration: lastThirtyDayDuration
            )
        case .thisYear:
            return DashboardMetricTotals(
                count: thisYearCount,
                words: thisYearWords,
                duration: thisYearDuration
            )
        case .allTime:
            return total
        }
    }

    func productivity(for period: DashboardProductivityPeriod) -> [DashboardProductivityPoint] {
        switch period {
        case .lastThreeDays:
            return lastThreeDayProductivity
        case .lastFiveDays:
            return lastFiveDayProductivity
        case .lastSevenDays:
            return lastSevenDayProductivity
        case .lastThirtyDays:
            return lastThirtyDayProductivity
        case .thisYear:
            return thisYearProductivity
        case .allTime:
            return allTimeProductivity
        }
    }

    func modelUsage(for period: DashboardProductivityPeriod) -> [DashboardModelUsageSummary] {
        switch period {
        case .lastThreeDays:
            return lastThreeDayModelUsage
        case .lastFiveDays:
            return lastFiveDayModelUsage
        case .lastSevenDays:
            return lastSevenDayModelUsage
        case .lastThirtyDays:
            return lastThirtyDayModelUsage
        case .thisYear:
            return thisYearModelUsage
        case .allTime:
            return allTimeModelUsage
        }
    }

    func peakHours(for period: DashboardProductivityPeriod) -> DashboardPeakHoursSummary {
        switch period {
        case .lastThreeDays:
            return lastThreeDayPeakHours
        case .lastFiveDays:
            return lastFiveDayPeakHours
        case .lastSevenDays:
            return lastSevenDayPeakHours
        case .lastThirtyDays:
            return lastThirtyDayPeakHours
        case .thisYear:
            return thisYearPeakHours
        case .allTime:
            return allTimePeakHours
        }
    }
}

enum DashboardTimeSaving {
    private static let averageTypingSpeedWordsPerMinute: Double = 40

    static func estimatedTypingTime(words: Int) -> TimeInterval {
        let estimatedTypingTimeInMinutes = Double(words) / averageTypingSpeedWordsPerMinute
        return estimatedTypingTimeInMinutes * 60
    }

    static func timeSaved(words: Int, duration: TimeInterval) -> TimeInterval {
        max(estimatedTypingTime(words: words) - duration, 0)
    }
}

enum DashboardProgressBenchmark {
    enum Equivalence {
        case matched(title: String)
        case repeated(title: String, count: Int)
        case remaining(words: Int, title: String)
    }

    private struct Milestone {
        let title: LocalizedStringResource
        let wordCount: Int

        var localizedTitle: String {
            String(localized: title)
        }
    }

    private static let repeatBenchmark = Milestone(
        title: "Tolstoy's War and Peace",
        wordCount: 700_000
    )

    private static let oneTimeMilestones = [
        Milestone(title: "The Metamorphosis", wordCount: 21_180),
        Milestone(title: "Animal Farm", wordCount: 29_966),
        Milestone(title: "The Great Gatsby", wordCount: 47_094),
        Milestone(title: "Homer's Iliad", wordCount: 114_715),
        Milestone(title: "Homer's Odyssey", wordCount: 121_365),
        Milestone(title: "Homer's Iliad and Odyssey", wordCount: 236_080)
    ]

    static func equivalence(for words: Int) -> Equivalence {
        if words >= repeatBenchmark.wordCount {
            let wholeMultiple = words / repeatBenchmark.wordCount

            if wholeMultiple >= 2 {
                return .repeated(title: repeatBenchmark.localizedTitle, count: wholeMultiple)
            }

            return .matched(title: repeatBenchmark.localizedTitle)
        }

        if let milestone = oneTimeMilestones.last(where: { words >= $0.wordCount }) {
            return .matched(title: milestone.localizedTitle)
        }

        guard let firstMilestone = oneTimeMilestones.first else {
            return .remaining(words: 0, title: "")
        }

        let remainingWords = firstMilestone.wordCount - words
        return .remaining(words: remainingWords, title: firstMilestone.localizedTitle)
    }
}

final class DashboardStatsCache: @unchecked Sendable {
    static let shared = DashboardStatsCache()

    private let lock = NSLock()
    private var summary: DashboardStatsSummary?

    private init() {}

    func currentSummary() -> DashboardStatsSummary? {
        lock.lock()
        defer { lock.unlock() }
        return summary
    }

    func update(_ summary: DashboardStatsSummary) {
        lock.lock()
        self.summary = summary
        lock.unlock()
    }
}
