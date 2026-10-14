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
    // Selection is editing state, not a new persisted schedule field. An
    // empty day remains selected while the user edits its ranges.
    private(set) var selectedWeekdays: Set<Int>
    var followsMainlandHolidays: Bool
    var holidayRanges: [ProtectionRangeDraft]
    var makeupWorkdayRanges: [ProtectionRangeDraft]

    init(schedule: ProtectionSchedule) {
        mode = schedule.mode
        weeklyRanges = schedule.weeklyRanges.map { $0.map(ProtectionRangeDraft.init) }
        selectedWeekdays = Set(schedule.weeklyRanges.indices.filter { !schedule.weeklyRanges[$0].isEmpty })
        followsMainlandHolidays = schedule.followsMainlandHolidays
        holidayRanges = schedule.holidayRanges.map(ProtectionRangeDraft.init)
        makeupWorkdayRanges = schedule.makeupWorkdayRanges.map(ProtectionRangeDraft.init)
    }

    mutating func setWeekday(_ index: Int, selected: Bool) {
        guard weeklyRanges.indices.contains(index) else { return }
        if selected {
            if selectedWeekdays.insert(index).inserted, weeklyRanges[index].isEmpty {
                weeklyRanges[index] = [ProtectionRangeDraft(startMinute: 540, endMinute: 1080)]
            }
        } else {
            selectedWeekdays.remove(index)
            weeklyRanges[index].removeAll()
        }
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
    @State private var draftTransition: ProtectionTransition
    @State private var saveError: String?

    public init(controller: SensveilController) {
        self.controller = controller
        _draft = State(initialValue: ProtectionSettingsDraft(schedule: controller.configuration.schedule))
        _draftBlurLevel = State(initialValue: controller.configuration.blurLevel)
        _draftShowsLabel = State(initialValue: controller.configuration.showsProtectionLabel)
        _draftTransition = State(initialValue: controller.configuration.protectionTransition)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("模糊档位", selection: $draftBlurLevel) {
                Text("标准").tag(BlurLevel.standard)
                Text("增强").tag(BlurLevel.enhanced)
                Text("最强").tag(BlurLevel.strongest)
            }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("模糊档位")

            if ProtectionTransition.isUserSelectable {
                HStack {
                    Text("过渡动画")
                    Picker("过渡动画", selection: $draftTransition) {
                        Text("200ms").tag(ProtectionTransition.ms200)
                        Text("500ms").tag(ProtectionTransition.ms500)
                        Text("800ms").tag(ProtectionTransition.ms800)
                        Text("关闭动画").tag(ProtectionTransition.off)
                    }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("过渡动画")
                }
            }

            Toggle("显示守护文案（Sensveil 守护中）", isOn: $draftShowsLabel)
            Text("模糊档位保存后应用于窗口。守护文案在受支持窗口确认保护后显示。")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("圆角采用外扩覆盖。当前支持本机单显示器普通窗口。")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

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
        VStack(alignment: .leading, spacing: 10) {
            Text("每周日期（可多选）").font(.callout)
            HStack(spacing: 12) {
                ForEach(0..<7, id: \.self) { index in
                    Toggle(Self.weekdayLabels[index], isOn: weekdayBinding(index))
                        .toggleStyle(.checkbox)
                        .accessibilityLabel(Self.weekdayLabels[index])
                }
            }
            Text("逐一设置所选日期；取消选择会清空该日时段，保存后生效。")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(draft.selectedWeekdays.sorted(), id: \.self) { index in
                VStack(alignment: .leading, spacing: 6) {
                    Divider()
                    HStack {
                        Text(Self.weekdayLabels[index]).font(.headline)
                        Text(daySummary(draft.weeklyRanges[index]))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach($draft.weeklyRanges[index]) { $row in
                        rangeRow($row)
                    }
                    Button {
                        draft.weeklyRanges[index].append(newRow(after: draft.weeklyRanges[index].last))
                    } label: { Label("添加时段", systemImage: "plus") }
                    .accessibilityLabel("为\(Self.weekdayLabels[index])添加时段")
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
            || draft.selectedWeekdays != Set(controller.configuration.schedule.weeklyRanges.indices.filter {
                !controller.configuration.schedule.weeklyRanges[$0].isEmpty
            })
            || draftBlurLevel != controller.configuration.blurLevel
            || draftShowsLabel != controller.configuration.showsProtectionLabel
            || (ProtectionTransition.isUserSelectable
                && draftTransition != controller.configuration.protectionTransition)
    }

    private func discardDraft() {
        draft = ProtectionSettingsDraft(schedule: controller.configuration.schedule)
        draftBlurLevel = controller.configuration.blurLevel
        draftShowsLabel = controller.configuration.showsProtectionLabel
        draftTransition = controller.configuration.protectionTransition
        saveError = nil
    }

    private func weekdayBinding(_ index: Int) -> Binding<Bool> {
        Binding(
            get: { draft.selectedWeekdays.contains(index) },
            set: { draft.setWeekday(index, selected: $0) }
        )
    }

    private func save() {
        do {
            try controller.saveProtectionSettings(
                blurLevel: draftBlurLevel,
                showsProtectionLabel: draftShowsLabel,
                schedule: draft.scheduleValue,
                protectionTransition: ProtectionTransition.isUserSelectable ? draftTransition : nil)
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
