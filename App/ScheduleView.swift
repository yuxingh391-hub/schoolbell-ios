import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ScheduleView: View {
    @ObservedObject var store: ScheduleStore
    @ObservedObject var audio: ExerciseAudio
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var editor: ScheduleEntry?
    @State private var importing = false

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { _ in
                List {
                    permissionSection
                    Section("安排") {
                        if store.entries.isEmpty {
                            ContentUnavailableView("课表还是空的", systemImage: "calendar",
                                                   description: Text("轻点右上角的加号，添加一项安排。"))
                        }
                        ForEach(sortedEntries) { entry in
                            Button {
                                editor = entry
                            } label: {
                                scheduleRow(entry)
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button("删除", role: .destructive) {
                                    Task { await store.remove(entry) }
                                }
                            }
                        }
                    }
                    Section("声音") {
                        Button("试听上课铃", systemImage: "bell") { audio.previewBell(ending: false) }
                        Button("试听下课铃", systemImage: "bell") { audio.previewBell(ending: true) }
                        Button(audio.filename == nil ? "导入眼保健操录音" : "更换眼保健操录音",
                               systemImage: "folder") { importing = true }
                        if audio.filename != nil {
                            Button("播放眼保健操", systemImage: "play.circle") { audio.play() }
                        }
                    }
                }
            }
            .navigationTitle("今日课表")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("添加安排", systemImage: "plus") { editor = ScheduleEntry() }
                        .labelStyle(.iconOnly)
                }
            }
            .sheet(item: $editor) { entry in
                ScheduleEditor(entry: entry, store: store)
            }
            .sheet(isPresented: $audio.showPlayer, onDismiss: audio.stop) {
                VStack(spacing: 20) {
                    Image(systemName: "headphones")
                        .font(.largeTitle)
                        .accessibilityHidden(true)
                    Text("眼保健操")
                        .font(.title2.bold())
                    Button("停止播放", systemImage: "stop.fill") {
                        audio.stop()
                        audio.showPlayer = false
                    }
                    .buttonStyle(.bordered)
                }
                .presentationDetents([.medium])
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.audio], onCompletion: audio.importAudio)
            .alert("课表", isPresented: errorBinding) {
                Button("好") { clearError() }
            } message: {
                Text(audio.error ?? store.error ?? "")
            }
        }
        .task(id: scenePhase) {
            if scenePhase == .active { await store.synchronize() }
        }
    }

    private var sortedEntries: [ScheduleEntry] {
        var nextStarts: [UUID: Date] = [:]
        for entry in store.entries {
            nextStarts[entry.id] = entry.nextStart
        }
        return store.entries.sorted { first, second in
            let firstTime = nextStarts[first.id] ?? Date.distantFuture
            let secondTime = nextStarts[second.id] ?? Date.distantFuture
            if firstTime == secondTime {
                return first.start < second.start
            }
            return firstTime < secondTime
        }
    }

    @ViewBuilder
    private var permissionSection: some View {
        if store.status == .notDetermined {
            Section {
                Button("开启定时铃声", systemImage: "bell.badge") {
                    Task { await store.authorize() }
                }
            }
        } else if store.status == .denied || !store.soundEnabled {
            Section {
                Button("在设置中开启通知声音", systemImage: "bell.slash") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
        }
    }

    private func scheduleRow(_ entry: ScheduleEntry) -> some View {
        HStack(spacing: 14) {
            scheduleTimes(entry)
            scheduleDescription(entry)
            Spacer()
            Image(systemName: entry.kind == .eyeExercise ? "eye" : "bell")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func scheduleTimes(_ entry: ScheduleEntry) -> some View {
        VStack(alignment: .leading) {
            Text(entry.start, style: .time)
                .font(.headline)
                .monospacedDigit()
            if entry.kind == .lesson && entry.hasEnd {
                Text(entry.end, style: .time)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 50, alignment: .leading)
    }

    private func scheduleDescription(_ entry: ScheduleEntry) -> some View {
        let detail = entry.repetition == .once
            ? Text(entry.start, style: .date)
            : Text(entry.repetitionLabel)
        return VStack(alignment: .leading, spacing: 4) {
            Text(entry.displayTitle).fontWeight(.medium)
            detail.font(.caption).foregroundStyle(.secondary)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { audio.error != nil || (editor == nil && store.error != nil) },
            set: { if !$0 { clearError() } }
        )
    }

    private func clearError() {
        audio.error = nil
        store.error = nil
    }
}

struct ScheduleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var entry: ScheduleEntry
    @ObservedObject var store: ScheduleStore

    private var timeComponents: DatePickerComponents {
        entry.repetition == .once ? [.date, .hourAndMinute] : [.hourAndMinute]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("类型", selection: $entry.kind) {
                        ForEach(ScheduleKind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if entry.kind == .lesson {
                        TextField("任务名称", text: $entry.title)
                    }
                }
                Section {
                    Picker("重复", selection: $entry.repetition) {
                        ForEach(Repetition.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if entry.repetition == .custom {
                        ForEach(ScheduleEntry.week, id: \.0) { day in
                            Toggle("星期" + day.1, isOn: Binding(
                                get: { entry.weekdays.contains(day.0) },
                                set: { selected in
                                    if selected {
                                        entry.weekdays.insert(day.0)
                                    } else {
                                        entry.weekdays.remove(day.0)
                                    }
                                }
                            ))
                        }
                    }
                    DatePicker("开始时间", selection: $entry.start, displayedComponents: timeComponents)
                    if entry.kind == .lesson {
                        Toggle("开启下课铃", isOn: $entry.hasEnd)
                        if entry.hasEnd {
                            DatePicker("结束时间", selection: $entry.end, displayedComponents: timeComponents)
                        }
                    }
                } header: {
                    Text("时间")
                } footer: {
                    if entry.kind == .eyeExercise {
                        Text("到点响铃，轻点通知播放已导入的完整版录音。")
                    } else if entry.hasEnd && entry.repetition != .once {
                        Text("重复任务的结束时间须晚于同一天的开始时间。")
                    }
                }
            }
            .navigationTitle("编辑安排")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            if await store.save(entry) { dismiss() }
                        }
                    }
                    .disabled(!entry.valid || store.isUpdating)
                }
            }
            .alert("课表", isPresented: Binding(
                get: { store.error != nil },
                set: { if !$0 { store.error = nil } }
            )) {
                Button("好") { store.error = nil }
            } message: {
                Text(store.error ?? "")
            }
        }
    }
}
