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

/// Keeps unfinished edits across navigation and commits all protection settings together.
@MainActor
final class ProtectionSettingsSession: ObservableObject {
    @Published var scheduleDraft: ProtectionSettingsDraft
    @Published var blurLevel: BlurLevel
    @Published var showsLabel: Bool
    @Published var transition: ProtectionTransition
    @Published var errorMessage: String?

    init(configuration: ProtectionConfiguration) {
        scheduleDraft = ProtectionSettingsDraft(schedule: configuration.schedule)
        blurLevel = configuration.blurLevel
        showsLabel = configuration.showsProtectionLabel
        transition = configuration.protectionTransition
    }

    func hasChanges(comparedTo configuration: ProtectionConfiguration) -> Bool {
        blurLevel != configuration.blurLevel || showsLabel != configuration.showsProtectionLabel
            || (ProtectionTransition.isUserSelectable && transition != configuration.protectionTransition)
            || scheduleDraft.scheduleValue != configuration.schedule
            || scheduleDraft.selectedWeekdays != Set(configuration.schedule.weeklyRanges.indices.filter {
                !configuration.schedule.weeklyRanges[$0].isEmpty
            })
    }

    func discard(configuration: ProtectionConfiguration) {
        blurLevel = configuration.blurLevel
        showsLabel = configuration.showsProtectionLabel
        transition = configuration.protectionTransition
        scheduleDraft = ProtectionSettingsDraft(schedule: configuration.schedule)
        errorMessage = nil
    }

    func save(controller: SensveilController) {
        do {
            try controller.saveProtectionSettings(
                blurLevel: blurLevel, showsProtectionLabel: showsLabel,
                schedule: scheduleDraft.scheduleValue,
                protectionTransition: ProtectionTransition.isUserSelectable ? transition : nil)
            discard(configuration: controller.configuration)
        } catch {
            errorMessage = controller.errorMessage ?? "无法保存设置，请检查时段是否有效。"
        }
    }
}

public struct ProtectionSettingsView: View {
    private static let weekdayLabels = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
    private static let minuteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    @ObservedObject private var controller: SensveilController
    @ObservedObject private var language = LanguagePreferences.shared
    @StateObject private var session: ProtectionSettingsSession
    @Environment(\.colorScheme) private var colorScheme

    public init(controller: SensveilController) {
        self.init(controller: controller,
                  session: ProtectionSettingsSession(configuration: controller.configuration))
    }

    init(controller: SensveilController, session: ProtectionSettingsSession) {
        self.controller = controller
        _session = StateObject(wrappedValue: session)
    }

    public var body: some View {
        Form {
            effectsEditor
            Section(L10n.text("保护时段")) {
                Picker(L10n.text("保护模式"), selection: $session.scheduleDraft.mode) {
                    Text(L10n.text("全天保护")).tag(ProtectionScheduleMode.allDay)
                    Text(L10n.text("指定时段")).tag(ProtectionScheduleMode.specified)
                }.pickerStyle(.radioGroup).accessibilityLabel(L10n.text("保护时段模式"))
            }
            if session.scheduleDraft.mode == .specified {
                Section(L10n.text("每周安排")) { scheduleEditor }
                Section { holidayEditor }
                if session.scheduleDraft.weeklyRanges.allSatisfy(\.isEmpty) {
                    Section {
                        Label(L10n.text("指定时段为空，保存后不会保护任何应用。"), systemImage: "moon.zzz")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section(L10n.text("当前状态（已保存的设置）")) { evaluationSummary }
        }
        .formStyle(.grouped)
        .environment(\.locale, language.locale)
        .disabled(controller.isConfigurationReadOnly)
        .safeAreaInset(edge: .bottom, spacing: 0) { saveBar }
    }

    private var effectsEditor: some View {
        Group {
            Section {
                Picker(L10n.text("模糊强度"), selection: $session.blurLevel) {
                    Text(L10n.text("标准")).tag(BlurLevel.standard)
                    Text(L10n.text("增强")).tag(BlurLevel.enhanced)
                    Text(L10n.text("最强")).tag(BlurLevel.strongest)
                }.pickerStyle(.segmented)
                Text(L10n.text("保存后应用于受保护窗口。圆角采用外扩覆盖，当前支持本机单显示器普通窗口。"))
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: { Text(L10n.text("模糊效果")) }
            Section {
                Toggle(L10n.text("显示守护文案"), isOn: $session.showsLabel)
                Text(L10n.text("在受支持窗口确认保护后，显示“Sensveil 守护中”。"))
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: { Text(L10n.text("守护提示")) }
            if ProtectionTransition.isUserSelectable {
                Section(L10n.text("过渡动画")) {
                    Picker(L10n.text("动画时长"), selection: $session.transition) {
                        Text("200ms").tag(ProtectionTransition.ms200)
                        Text("500ms").tag(ProtectionTransition.ms500)
                        Text("800ms").tag(ProtectionTransition.ms800)
                        Text(L10n.text("关闭动画")).tag(ProtectionTransition.off)
                    }.pickerStyle(.segmented)
                }
            }
        }
    }

    private var hasChanges: Bool {
        session.hasChanges(comparedTo: controller.configuration)
    }

    private var saveBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error = session.errorMessage {
                Label(L10n.text(error), systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text(L10n.text(hasChanges ? "有未保存的修改" : "设置已保存"))
                    .font(.callout).foregroundStyle(.primary)
                Spacer()
                Button(L10n.text("放弃修改")) {
                    session.discard(configuration: controller.configuration)
                }.disabled(!hasChanges || controller.isConfigurationReadOnly)
                Button(L10n.text("保存设置")) {
                    session.save(controller: controller)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!hasChanges || controller.isConfigurationReadOnly)
            }
        }
        .padding(16)
        .background(colorScheme == .dark
                    ? Color(red: 44 / 255, green: 44 / 255, blue: 46 / 255) : Color.white,
                    in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.03 : 0.07), radius: 8, x: 0, y: 2)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .padding(.top, 8)
    }

    // MARK: - Schedule editor

    @ViewBuilder
    private var scheduleEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("每周日期（可多选）")).font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), alignment: .leading)], alignment: .leading, spacing: 12) {
                ForEach(0..<7, id: \.self) { index in
                    Toggle(L10n.text(Self.weekdayLabels[index]), isOn: weekdayBinding(index))
                        .toggleStyle(.checkbox)
                        .accessibilityLabel(L10n.text(Self.weekdayLabels[index]))
                }
            }
            Text(L10n.text("逐一设置所选日期；取消选择会清空该日时段，保存后生效。"))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(session.scheduleDraft.selectedWeekdays.sorted(), id: \.self) { index in
                VStack(alignment: .leading, spacing: 6) {
                    Divider()
                    HStack {
                        Text(L10n.text(Self.weekdayLabels[index])).font(.headline)
                        Text(daySummary(session.scheduleDraft.weeklyRanges[index]))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach($session.scheduleDraft.weeklyRanges[index]) { $row in
                        rangeRow($row)
                    }
                    Button {
                        session.scheduleDraft.weeklyRanges[index].append(newRow(after: session.scheduleDraft.weeklyRanges[index].last))
                    } label: { Label(L10n.text("添加时段"), systemImage: "plus") }
                    .accessibilityLabel(L10n.format("为%@添加时段", L10n.text(Self.weekdayLabels[index])))
                }
            }
        }
    }

    @ViewBuilder
    private var holidayEditor: some View {
        DisclosureGroup(L10n.text("节假日")) {
            Toggle(L10n.text("跟随中国大陆法定节假日安排"), isOn: $session.scheduleDraft.followsMainlandHolidays)
            if session.scheduleDraft.followsMainlandHolidays {
                rangeList($session.scheduleDraft.holidayRanges, title: "节假日与调休休息时段")
                rangeList($session.scheduleDraft.makeupWorkdayRanges, title: "调休上班时段")
            }
            Text(L10n.format("内置日历：%@", L10n.text(controller.holidayCoverageDescription))).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func rangeList(_ ranges: Binding<[ProtectionRangeDraft]>, title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text(title)).font(.callout)
            ForEach(ranges) { $row in
                rangeRow($row)
            }
            Button {
                ranges.wrappedValue.append(newRow(after: ranges.wrappedValue.last))
            } label: { Label(L10n.text("添加时段"), systemImage: "plus") }
            .accessibilityLabel(L10n.format("为%@添加时段", L10n.text(title)))
        }.padding(.leading, 12)
    }

    private func rangeRow(_ row: Binding<ProtectionRangeDraft>) -> some View {
        HStack(spacing: 8) {
            DatePicker(L10n.text("开始"), selection: startBinding(row), displayedComponents: .hourAndMinute)
                .labelsHidden().fixedSize().accessibilityLabel(L10n.text("开始时间"))
            DatePicker(L10n.text("结束"), selection: endBinding(row), displayedComponents: .hourAndMinute)
                .labelsHidden().fixedSize().accessibilityLabel(L10n.text("结束时间"))
            Text(endDisplay(row.wrappedValue))
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                .frame(minWidth: 76, alignment: .leading)
                .accessibilityLabel(L10n.format("结束说明 %@", endAccessibility(row.wrappedValue)))
            Spacer()
            Button {
                removeRow(row.wrappedValue)
            } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .accessibilityLabel(L10n.text("删除该时段"))
        }
    }

    @ViewBuilder
    private var evaluationSummary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.format("本机时区：%@", TimeZone.current.identifier)).font(.caption).foregroundStyle(.secondary)
            if let evaluation = controller.scheduleEvaluation {
                Text(evaluation.isActive
                     ? L10n.format("当前处于保护时段（%@）", localizedActiveSource(evaluation.activeSource ?? "全天"))
                     : L10n.text("当前不在保护时段"))
                    .font(.caption)
                    .foregroundStyle(evaluation.isActive ? Color.accentColor : .secondary)
                if !evaluation.missingHolidayYears.isEmpty {
                    Label(L10n.format("节假日日历不可用/需更新：缺少 %@ 年数据，相关日期按每周规则判断", evaluation.missingHolidayYears.sorted().map(String.init).joined(separator: L10n.text("、"))), systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                        .accessibilityLabel(L10n.text("节假日日历警告"))
                }
            }
        }
    }

    /// Keep the evaluation engine's canonical labels independent of UI language.
    private func localizedActiveSource(_ source: String) -> String {
        let weeklyPrefix = "每周·"
        if source.hasPrefix(weeklyPrefix) {
            return L10n.format("每周 · %@", L10n.text(String(source.dropFirst(weeklyPrefix.count))))
        }
        return L10n.text(source)
    }

    private func weekdayBinding(_ index: Int) -> Binding<Bool> {
        Binding(
            get: { session.scheduleDraft.selectedWeekdays.contains(index) },
            set: { session.scheduleDraft.setWeekday(index, selected: $0) }
        )
    }

    private func daySummary(_ rows: [ProtectionRangeDraft]) -> String {
        guard !rows.isEmpty else { return L10n.text("无时段") }
        return rows.map { "\(Self.minuteFormatter.string(from: startMinuteToDate($0.startMinute)))–\(endDisplay($0))" }
            .joined(separator: L10n.text("、"))
    }

    private func newRow(after previous: ProtectionRangeDraft?) -> ProtectionRangeDraft {
        // Start where the previous interval ends (same-day wallclock); default
        // to the workday window, rolling the end to the next day when needed.
        let start = (previous?.endMinute ?? 540).clampedToDayMinute()
        let end = 1080 > start ? 1080 : 1080 + 1440
        return ProtectionRangeDraft(startMinute: start, endMinute: end)
    }

    private func removeRow(_ row: ProtectionRangeDraft) {
        session.scheduleDraft.weeklyRanges = session.scheduleDraft.weeklyRanges.map { $0.filter { $0.id != row.id } }
        session.scheduleDraft.holidayRanges.removeAll { $0.id == row.id }
        session.scheduleDraft.makeupWorkdayRanges.removeAll { $0.id == row.id }
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
            return L10n.format("次日 %@", Self.minuteFormatter.string(from: startMinuteToDate(end - 1440)))
        }
        return Self.minuteFormatter.string(from: startMinuteToDate(end))
    }

    private func endAccessibility(_ row: ProtectionRangeDraft) -> String {
        if row.endMinute == 1440 { return L10n.text("当日 24:00（次日 0 点）") }
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
