import Foundation
import UserNotifications

enum ScheduleKind: String, CaseIterable, Codable, Identifiable {
    case lesson = "任务"
    case eyeExercise = "眼保健操"

    var id: String { rawValue }
}

enum Repetition: String, CaseIterable, Codable, Identifiable {
    case once = "仅一次"
    case daily = "每天"
    case workdays = "周一至周五"
    case custom = "自选星期"

    var id: String { rawValue }
}

struct ScheduleEntry: Identifiable, Codable {
    var id = UUID()
    var title = ""
    var kind: ScheduleKind = .lesson
    var start = Calendar.current.date(byAdding: .minute, value: 5, to: .now) ?? .now
    var end = Calendar.current.date(byAdding: .minute, value: 35, to: .now) ?? .now
    var hasEnd = false
    var repetition: Repetition = .once
    var weekdays: Set<Int> = [2, 3, 4, 5, 6]

    static let week = [(2, "一"), (3, "二"), (4, "三"), (5, "四"), (6, "五"), (7, "六"), (1, "日")]

    var displayTitle: String {
        kind == .eyeExercise ? "眼保健操" : title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var repetitionLabel: String {
        guard repetition == .custom else { return repetition.rawValue }
        return "周" + Self.week.filter { weekdays.contains($0.0) }.map { $0.1 }.joined(separator: "、")
    }

    var nextStart: Date? {
        triggers(at: start).compactMap { $0.nextTriggerDate() }.min()
    }

    var valid: Bool {
        guard !displayTitle.isEmpty, repetition != .custom || !weekdays.isEmpty else { return false }
        let calendar = Calendar.current
        if repetition == .once && calendar.compare(start, to: .now, toGranularity: .minute) != .orderedDescending {
            return false
        }
        guard kind == .lesson && hasEnd else { return true }
        if repetition == .once {
            return calendar.compare(end, to: start, toGranularity: .minute) == .orderedDescending
        }
        return Self.minuteOfDay(end) > Self.minuteOfDay(start)
    }

    private static func minuteOfDay(_ date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    private func triggers(at date: Date) -> [UNCalendarNotificationTrigger] {
        let calendar = Calendar.current
        if repetition == .once {
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            return [UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)]
        }
        let time = calendar.dateComponents([.hour, .minute], from: date)
        if repetition == .daily {
            return [UNCalendarNotificationTrigger(dateMatching: time, repeats: true)]
        }
        let days = repetition == .workdays ? [2, 3, 4, 5, 6] : weekdays.sorted()
        return days.map { day in
            var parts = time
            parts.weekday = day
            return UNCalendarNotificationTrigger(dateMatching: parts, repeats: true)
        }
    }

    func requests() -> [UNNotificationRequest] {
        var requests = requests(at: start, isEnd: false)
        if kind == .lesson && hasEnd {
            requests += self.requests(at: end, isEnd: true)
        }
        return requests
    }

    private func requests(at date: Date, isEnd: Bool) -> [UNNotificationRequest] {
        let content = UNMutableNotificationContent()
        content.title = kind == .eyeExercise ? "眼保健操时间" : (isEnd ? "下课铃" : "上课铃")
        content.body = kind == .eyeExercise ? "轻点通知，播放完整版。" : displayTitle
        content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: isEnd ? "dismissal-bell.wav" : "class-bell.wav"))
        content.userInfo["playEyeExercise"] = kind == .eyeExercise

        return triggers(at: date).compactMap { trigger in
            guard let next = trigger.nextTriggerDate(), next > .now else { return nil }
            let boundary = isEnd ? "end" : "start"
            let day = trigger.dateComponents.weekday ?? 0
            return UNNotificationRequest(
                identifier: "schoolbell.\(id.uuidString).\(boundary).\(day)",
                content: content,
                trigger: trigger
            )
        }
    }
}
