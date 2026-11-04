import Foundation
import HealthKit
import SwiftData
import ObjectKeyCore

/// 건강 앱 값으로 습관을 자동 완료한다. 읽기만 하고, 건강 데이터를 기기 밖으로 보내지 않는다.
@MainActor
enum HealthSync {
    private static let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private static let noDataKey = "moki.health.noData"

    /// 최근 7일 동안 건강 앱에서 값이 하나도 안 들어온 물건. 권한이 꺼졌거나 기기에 기록이 없을 가능성이 크다.
    /// 건강 앱은 거절 여부를 알려 주지 않으므로, 값이 비어 있는 것으로 판단해 안내한다.
    static func hasNoData(_ key: KeyObject) -> Bool {
        (UserDefaults.standard.stringArray(forKey: noDataKey) ?? []).contains(key.id.uuidString)
    }

    private static func readType(_ metric: HealthMetric) -> HKObjectType {
        switch metric {
        case .steps: return HKQuantityType(.stepCount)
        case .exerciseMinutes: return HKQuantityType(.appleExerciseTime)
        case .mindfulMinutes: return HKCategoryType(.mindfulSession)
        }
    }

    /// 읽기 권한을 묻는다. 건강 앱은 거절 여부를 알려 주지 않으므로, 이후 값이 없으면 기록되지 않을 뿐이다.
    static func requestAccess(_ metric: HealthMetric) async {
        guard isAvailable else { return }
        try? await store.requestAuthorization(toShare: [], read: [readType(metric)])
    }

    /// 권한 창을 아직 띄운 적이 없는지. iOS는 이 창을 한 번만 띄우므로, 이미 물어봤으면 건강 앱에서 바꾸도록 안내해야 한다.
    /// 허용·거절 여부 자체는 개인정보라 알 수 없다.
    static func shouldAsk(_ metric: HealthMetric) async -> Bool {
        guard isAvailable else { return false }
        return (try? await store.statusForAuthorizationRequest(toShare: [], read: [readType(metric)])) == .shouldRequest
    }

    /// 최근 며칠의 하루 값(그날 0시 → 값).
    private static func dailyValues(_ metric: HealthMetric, days: Int) async -> [Date: Double] {
        let calendar = Calendar.current
        let end = Date.now
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: end)) else { return [:] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        switch metric {
        case .steps, .exerciseMinutes:
            let type = HKQuantityType(metric == .steps ? .stepCount : .appleExerciseTime)
            let unit = metric == .steps ? HKUnit.count() : HKUnit.minute()
            let descriptor = HKStatisticsCollectionQueryDescriptor(
                predicate: HKSamplePredicate.quantitySample(type: type, predicate: predicate),
                options: .cumulativeSum, anchorDate: start, intervalComponents: DateComponents(day: 1))
            guard let collection = try? await descriptor.result(for: store) else { return [:] }
            var values: [Date: Double] = [:]
            collection.enumerateStatistics(from: start, to: end) { stats, _ in
                values[calendar.startOfDay(for: stats.startDate)] = stats.sumQuantity()?.doubleValue(for: unit) ?? 0
            }
            return values
        case .mindfulMinutes:
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.categorySample(type: HKCategoryType(.mindfulSession), predicate: predicate)], sortDescriptors: [])
            guard let samples = try? await descriptor.result(for: store) else { return [:] }
            var values: [Date: Double] = [:]
            for s in samples { values[calendar.startOfDay(for: s.startDate), default: 0] += s.endDate.timeIntervalSince(s.startDate) / 60 }
            return values
        }
    }

    /// 건강 앱과 이어 둔 물건마다, 목표를 넘은 날 중 아직 기록 없는 날을 채운다. 앱이 앞으로 올 때 부른다.
    static func sync(context: ModelContext) async {
        guard isAvailable, let keys = try? context.fetch(FetchDescriptor<KeyObject>()) else { return }
        let linked = keys.filter { HealthMetric(rawValue: $0.healthMetric) != nil && $0.healthTarget > 0 }
        guard !linked.isEmpty, let logs = try? context.fetch(FetchDescriptor<ActivityLog>()) else { return }
        let calendar = Calendar.current
        var added = false
        var noData: [String] = []
        for key in linked {
            guard let metric = HealthMetric(rawValue: key.healthMetric) else { continue }
            let values = await dailyValues(metric, days: HealthRules.backfillDays)
            if values.values.allSatisfy({ $0 <= 0 }) { noData.append(key.id.uuidString) }
            let recorded = Set(logs.filter { $0.keyID == key.id && $0.kind == "health" }.map(\.startedAt))
            for day in HealthRules.daysToRecord(values: values, target: key.healthTarget, alreadyRecorded: recorded, calendar: calendar) {
                let at = calendar.isDateInToday(day) ? Date.now : day.addingTimeInterval(12 * 3600)
                context.insert(ActivityLog(keyID: key.id, keyName: key.name, kind: "health", startedAt: at, duration: 0, amount: 1))
                added = true
            }
        }
        UserDefaults.standard.set(noData, forKey: noDataKey)
        if added {
            try? context.save()
            WidgetBridge.refreshFromStore()
        }
    }
}
