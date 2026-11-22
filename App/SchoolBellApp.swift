import AVFoundation
import SwiftUI
import UIKit
import UserNotifications

@main
struct SchoolBellApp: App {
    @UIApplicationDelegateAdaptor(NotificationDelegate.self) private var notificationDelegate
    @StateObject private var store = ScheduleStore()
    @StateObject private var audio = ExerciseAudio()

    var body: some Scene {
        WindowGroup {
            ScheduleView(store: store, audio: audio)
                .onReceive(notificationDelegate.$exerciseRequest.compactMap { $0 }) { _ in
                    audio.play()
                }
        }
    }
}

final class NotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    @Published var exerciseRequest: UUID?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let isExercise = response.notification.request.content.userInfo["playEyeExercise"] as? Bool
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier, isExercise == true else { return }
        await MainActor.run { exerciseRequest = UUID() }
    }
}

@MainActor
final class ScheduleStore: ObservableObject {
    @Published private(set) var entries: [ScheduleEntry] = []
    @Published private(set) var status: UNAuthorizationStatus = .notDetermined
    @Published private(set) var soundEnabled = false
    @Published private(set) var isUpdating = false
    @Published var error: String?

    private let center = UNUserNotificationCenter.current()
    private let file = URL.applicationSupportDirectory.appending(path: "schedule.json")
    private var loadFailed = false

    init() {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            entries = try JSONDecoder().decode([ScheduleEntry].self, from: Data(contentsOf: file))
        } catch {
            loadFailed = true
            self.error = "无法读取已有课表。请先保留 App 数据，再重试。"
        }
    }

    func save(_ entry: ScheduleEntry) async -> Bool {
        var updated = entries.filter { $0.id != entry.id }
        updated.append(entry)
        return await commit(updated)
    }

    func remove(_ entry: ScheduleEntry) async {
        _ = await commit(entries.filter { $0.id != entry.id })
    }

    private func commit(_ updated: [ScheduleEntry]) async -> Bool {
        guard !isUpdating else { return false }
        guard !loadFailed else {
            error = "已有课表无法读取，暂时无法保存修改。"
            return false
        }
        guard updated.flatMap({ $0.requests() }).count <= 60 else {
            error = "待响铃项目太多。请删减提醒，或将相同时间的安排设为「每天」。"
            return false
        }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(updated).write(to: file, options: .atomic)
            entries = updated
        } catch {
            self.error = "课表保存失败，请重试。"
            return false
        }
        await synchronize()
        return true
    }

    func authorize() async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            self.error = "无法请求通知权限，请在系统设置中检查。"
        }
        await synchronize()
    }

    func synchronize() async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }

        let settings = await center.notificationSettings()
        status = settings.authorizationStatus
        soundEnabled = settings.soundSetting == .enabled
        guard status == .authorized || status == .provisional, !loadFailed else { return }

        let requests = entries.flatMap { $0.requests() }
        let desiredIDs = Set(requests.map(\.identifier))
        let pending = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix("schoolbell.") }
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { !desiredIDs.contains($0) })
        let existing = Dictionary(uniqueKeysWithValues: pending.map { ($0.identifier, $0) })
        for request in requests {
            if let previous = existing[request.identifier],
               let previousTrigger = previous.trigger as? UNCalendarNotificationTrigger,
               let nextTrigger = request.trigger as? UNCalendarNotificationTrigger,
               previousTrigger.dateComponents == nextTrigger.dateComponents,
               previousTrigger.repeats == nextTrigger.repeats,
               previous.content.title == request.content.title,
               previous.content.body == request.content.body {
                continue
            }
            do {
                try await center.add(request)
            } catch {
                self.error = "有提醒未能设置。课表已保存，请重新打开 App 重试。"
            }
        }
    }
}

@MainActor
final class ExerciseAudio: ObservableObject {
    @Published private(set) var filename: String? = UserDefaults.standard.string(forKey: "exerciseAudio")
    @Published var showPlayer = false
    @Published var error: String?
    private(set) var player: AVAudioPlayer?

    private func localURL(for name: String) -> URL {
        URL.applicationSupportDirectory.appending(path: name)
    }

    func importAudio(_ result: Result<URL, Error>) {
        do {
            let original = try result.get()
            let access = original.startAccessingSecurityScopedResource()
            defer { if access { original.stopAccessingSecurityScopedResource() } }
            let name = "exercise-\(UUID().uuidString).\(original.pathExtension)"
            let destination = localURL(for: name)
            try FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: original, to: destination)
            do {
                _ = try AVAudioPlayer(contentsOf: destination)
            } catch {
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
            if let previous = filename {
                try? FileManager.default.removeItem(at: localURL(for: previous))
            }
            filename = name
            UserDefaults.standard.set(name, forKey: "exerciseAudio")
        } catch {
            self.error = "无法导入这段录音。请选择已下载到手机的 MP3、M4A 或 WAV 文件。"
        }
    }

    func play() {
        guard let filename else {
            error = "请先用「导入录音」添加你常听的眼保健操。"
            return
        }
        if playFile(at: localURL(for: filename)) {
            showPlayer = true
        }
    }

    func previewBell(ending: Bool) {
        let name = ending ? "dismissal-bell" : "class-bell"
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else {
            error = "找不到铃声文件。"
            return
        }
        _ = playFile(at: url)
    }

    private func playFile(at url: URL) -> Bool {
        do {
            stop()
            let next = try AVAudioPlayer(contentsOf: url)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback)
            try session.setActive(true)
            player = next
            guard next.play() else {
                stop()
                error = "音频无法播放。"
                return false
            }
            return true
        } catch {
            self.error = "音频无法播放。"
            return false
        }
    }

    func stop() {
        guard let player else { return }
        player.stop()
        self.player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
