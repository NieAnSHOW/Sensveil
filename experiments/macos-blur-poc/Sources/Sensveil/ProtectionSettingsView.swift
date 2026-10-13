import SwiftUI

/// One editable protection interval in the settings draft.
struct ProtectionRangeDraft: Identifiable, Equatable {
    let id = UUID()
    var startMinute: Int  // 0...1439
    var endMinute: Int    // relative to the start day, 1...2879

    init(startMinute: Int, endMinute: Int) {
        self.startMinute = startMinute
        self.endMinute = endMinute
    }

    init(_ range: ProtectionTimeRange) {
        self.startMinute = range.startMinute
        self.endMinute = range.endMinute
    }

    var rangeValue: ProtectionTimeRange {
        ProtectionTimeRange(startMinute: startMinute, endMinute: endMinute)
    }
}

/// Local editing copy of the saved global protection settings. The draft is
/// independent of the persisted configuration until the user saves.
struct ProtectionSettingsDraft: Equatable {
    var mode: ProtectionScheduleMode
    var weeklyRanges: [[ProtectionRangeDraft]]
    var followsMainlandHolidays: Bool
    var holidayRanges: [ProtectionRangeDraft]
    var makeupWorkdayRanges: [ProtectionRangeDraft]

    init(schedule: ProtectionSchedule) {
        mode = schedule.mode
        weeklyRanges = schedule.weeklyRanges.map { $0.map(ProtectionRangeDraft.init) }
        followsMainlandHolidays = schedule.followsMainlandHolidays
        holidayRanges = schedule.holidayRanges.map(ProtectionRangeDraft.init)
        makeupWorkdayRanges = schedule.makeupWorkdayRanges.map(ProtectionRangeDraft.init)
    }

    var scheduleValue: ProtectionSchedule {
        ProtectionSchedule(
            mode: mode,
            weeklyRanges: weeklyRanges.map { $0.map(\.rangeValue) },
            followsMainlandHolidays: followsMainlandHolidays,
            holidayRanges: holidayRanges.map(\.rangeValue),
            makeupWorkdayRanges: makeupWorkdayRanges.map(\.rangeValue)
        )
    }
}

public struct ProtectionSettingsView: View {
    private static let weekdayLabels = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
    private static let minuteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    @ObservedObject private var controller: SensveilController
    @State private var draft: ProtectionSettingsDraft
    @State private var draftBlurLevel: BlurLevel
    @State private var draftShowsLabel: Bool
    @State private var saveError: String?

    public init(controller: SensveilController) {
        self.controller = controller
        _draft = State(initialValue: ProtectionSettingsDraft(schedule: controller.configuration.schedule))
        _draftBlurLevel = State(initialValue: controller.configuration.blurLevel)
        _draftShowsLabel = State(initialValue: controller.configuration.showsProtectionLabel)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("模糊档位", selection: $draftBlurLevel) {
                Text("标准").tag(BlurLevel.standard)
                Text("增强").tag(BlurLevel.enhanced)
                Text("最强").tag(BlurLevel.strongest)
            }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("模糊档位")

            Toggle("显示守护文案（Sensveil 守护中）", isOn: $draftShowsLabel)
            Text("遮罩按目标窗口的真实轮廓自动匹配；轮廓无法识别的窗口会显示无法保护。过渡动画固定启用（200 毫秒）。")
                .font(.caption).foregroundStyle(.secondary)

            Picker("保护时段", selection: $draft.mode) {
                Text("全天保护").tag(ProtectionScheduleMode.allDay)
                Text("指定时段").tag(ProtectionScheduleMode.specified)
            }.pickerStyle(.radioGroup).accessibilityLabel("保护时段模式")

            if draft.mode == .specified {
                scheduleEditor
                holidayEditor
                if draft.weeklyRanges.allSatisfy(\.isEmpty) {
                    Label("指定时段为空，当前不会保护", systemImage: "moon.zzz")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            evaluationSummary

            HStack {
                Button("保存设置") { save() }.disabled(controller.isConfigurationReadOnly)
                Button("放弃修改") { discardDraft() }.disabled(!hasChanges)
                Spacer()
            }
            if let saveError {
                Label(saveError, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Schedule editor

    @ViewBuilder
    private var scheduleEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(0..<7, id: \.self) { index in
                DisclosureGroup {
                    ForEach($draft.weeklyRanges[index]) { $row in
                        rangeRow($row)
                    }
                    Button {
                        draft.weeklyRanges[index].append(newRow(after: draft.weeklyRanges[index].last))
                    } label: { Label("添加时段", systemImage: "plus") }
                    .accessibilityLabel("为\(Self.weekdayLabels[index])添加时段")
                } label: {
                    HStack {
                        Text(Self.weekdayLabels[index]).frame(width: 40, alignment: .leading)
                        Text(daySummary(draft.weeklyRanges[index]))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var holidayEditor: some View {
        DisclosureGroup("节假日") {
            Toggle("跟随中国大陆法定节假日安排", isOn: $draft.followsMainlandHolidays)
            if draft.followsMainlandHolidays {
                rangeList($draft.holidayRanges, title: "节假日与调休休息时段")
                rangeList($draft.makeupWorkdayRanges, title: "调休上班时段")
            }
            Text("内置日历：\(controller.holidayCoverageDescription)").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func rangeList(_ ranges: Binding<[ProtectionRangeDraft]>, title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.callout)
            ForEach(ranges) { $row in
                rangeRow($row)
            }
            Button {
                ranges.wrappedValue.append(newRow(after: ranges.wrappedValue.last))
            } label: { Label("添加时段", systemImage: "plus") }
            .accessibilityLabel("为\(title)添加时段")
        }.padding(.leading, 12)
    }

    private func rangeRow(_ row: Binding<ProtectionRangeDraft>) -> some View {
        HStack(spacing: 8) {
            DatePicker("开始", selection: startBinding(row), displayedComponents: .hourAndMinute)
                .labelsHidden().fixedSize().accessibilityLabel("开始时间")
            DatePicker("结束", selection: endBinding(row), displayedComponents: .hourAndMinute)
                .labelsHidden().fixedSize().accessibilityLabel("结束时间")
            Text(endDisplay(row.wrappedValue))
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                .frame(width: 44, alignment: .leading)
                .accessibilityLabel("结束说明 \(endAccessibility(row.wrappedValue))")
            Spacer()
            Button {
                removeRow(row.wrappedValue)
            } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .accessibilityLabel("删除该时段")
        }
    }

    @ViewBuilder
    private var evaluationSummary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("本机时区：\(TimeZone.current.identifier)").font(.caption).foregroundStyle(.secondary)
            if let evaluation = controller.scheduleEvaluation {
                Text(evaluation.isActive
                     ? "当前处于保护时段（\(evaluation.activeSource ?? "全天")）"
                     : "当前不在保护时段")
                    .font(.caption)
                    .foregroundStyle(evaluation.isActive ? Color.accentColor : .secondary)
                if !evaluation.missingHolidayYears.isEmpty {
                    Label("节假日日历不可用/需更新：缺少 \(evaluation.missingHolidayYears.sorted().map(String.init).joined(separator: "、")) 年数据，相关日期按每周规则判断", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                        .accessibilityLabel("节假日日历警告")
                }
            }
        }
    }

    // MARK: - Editing helpers

    private var hasChanges: Bool {
        // Compare schedule values, not draft structs: row identity UUIDs are
        // regenerated on every conversion and must not mark the draft dirty.
        draft.scheduleValue != controller.configuration.schedule
            || draftBlurLevel != controller.configuration.blurLevel
            || draftShowsLabel != controller.configuration.showsProtectionLabel
    }

    private func discardDraft() {
        draft = ProtectionSettingsDraft(schedule: controller.configuration.schedule)
        draftBlurLevel = controller.configuration.blurLevel
        draftShowsLabel = controller.configuration.showsProtectionLabel
        saveError = nil
    }

    private func save() {
        do {
            try controller.saveProtectionSettings(
                blurLevel: draftBlurLevel,
                showsProtectionLabel: draftShowsLabel,
                schedule: draft.scheduleValue)
            saveError = nil
            // Echo the persisted (normalized, merged) configuration back.
            draft = ProtectionSettingsDraft(schedule: controller.configuration.schedule)
        } catch {
            saveError = controller.errorMessage ?? "无法保存设置，请检查时段是否有效。"
        }
    }

    private func daySummary(_ rows: [ProtectionRangeDraft]) -> String {
        guard !rows.isEmpty else { return "无时段" }
        return rows.map { "\(Self.minuteFormatter.string(from: startMinuteToDate($0.startMinute)))–\(endDisplay($0))" }
            .joined(separator: "、")
    }

    private func newRow(after previous: ProtectionRangeDraft?) -> ProtectionRangeDraft {
        // Start where the previous interval ends (same-day wallclock); default
        // to the workday window, rolling the end to the next day when needed.
        let start = (previous?.endMinute ?? 540).clampedToDayMinute()
        let end = 1080 > start ? 1080 : 1080 + 1440
        return ProtectionRangeDraft(startMinute: start, endMinute: end)
    }

    private func removeRow(_ row: ProtectionRangeDraft) {
        draft.weeklyRanges = draft.weeklyRanges.map { $0.filter { $0.id != row.id } }
        draft.holidayRanges.removeAll { $0.id == row.id }
        draft.makeupWorkdayRanges.removeAll { $0.id == row.id }
    }

    /// Only the wallclock HH:mm is edited; the stored value is the minute
    /// offset, so no hidden fixed date leaks into the schedule.
    private func startBinding(_ row: Binding<ProtectionRangeDraft>) -> Binding<Date> {
        Binding(
            get: { startMinuteToDate(row.wrappedValue.startMinute) },
            set: { row.wrappedValue.startMinute = minuteOfDay(of: $0) }
        )
    }

    /// An end that lands at or before the start rolls to the next day
    /// (+1440), matching the documented editor semantics; an existing
    /// next-day offset is preserved while editing.
    private func endBinding(_ row: Binding<ProtectionRangeDraft>) -> Binding<Date> {
        Binding(
            get: { startMinuteToDate(row.wrappedValue.endMinute.clampedToDayMinute()) },
            set: {
                let picked = minuteOfDay(of: $0)
                let offset = row.wrappedValue.endMinute > 1440 ? 1440 : 0
                var candidate = offset + picked
                if candidate <= row.wrappedValue.startMinute { candidate = picked + 1440 }
                row.wrappedValue.endMinute = candidate
            }
        )
    }

    private func startMinuteToDate(_ minute: Int) -> Date {
        let minute = minute.clampedToDayMinute()
        return Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
    }

    private func minuteOfDay(of date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    /// An end that lands at or before the start rolls to the next day
    /// (+1440), matching the documented editor semantics; an existing
    /// next-day offset is preserved while editing.
    private func endDisplay(_ row: ProtectionRangeDraft) -> String {
        let end = row.endMinute
        if end == 1440 { return "24:00" }
        if end > 1440 {
            return "次日 " + Self.minuteFormatter.string(from: startMinuteToDate(end - 1440))
        }
        return Self.minuteFormatter.string(from: startMinuteToDate(end))
    }

    private func endAccessibility(_ row: ProtectionRangeDraft) -> String {
        if row.endMinute == 1440 { return "当日 24:00（次日 0 点）" }
        return endDisplay(row)
    }
}

extension Int {
    /// Wraps minutes back into one wallclock day for display purposes only.
    fileprivate func clampedToDayMinute() -> Int {
        let value = self % 1440
        return value < 0 ? value + 1440 : value
    }
}
