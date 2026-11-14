// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Full BetterTouchTool-style Trackpad & Keyboard Automation section ported from
/// `tools/gesture` (`SettingsViews.swift` + `RuleEditorViews.swift`).
struct TrackpadGestureSettingsSection: View {
    private enum CategoryFilter: String, CaseIterable, Identifiable {
        case all
        case trackpad
        case keyboard

        var id: String { rawValue }

        func title(chinese: Bool) -> String {
            switch self {
            case .all: return chinese ? "全部规则" : "All Rules"
            case .trackpad: return chinese ? "触控板" : "Trackpad"
            case .keyboard: return chinese ? "键盘" : "Keyboard"
            }
        }
    }

    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = TrackpadGestureService.shared
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage(DefaultsKey.trackpadGesturesEnabled) private var trackpadGesturesEnabled = false
    @AppStorage(DefaultsKey.trackpadChordRemapEnabled) private var trackpadChordRemapEnabled = false

    @State private var filter: CategoryFilter = .all
    @State private var selectedRuleID: UUID?
    @State private var tuningExpanded = false
    @State private var syncFeedback: String?

    private var isChinese: Bool {
        l10n.language.rawValue.hasPrefix("zh")
    }

    private var filteredRules: [GestureAutomationRule] {
        switch filter {
        case .all:
            return service.configuration.rules
        case .trackpad:
            return service.configuration.rules.filter { $0.category == .trackpad }
        case .keyboard:
            return service.configuration.rules.filter { $0.category == .keyboard }
        }
    }

    var body: some View {
        SettingsCard(title: isChinese ? "触控板多指手势与键盘自动化 (Gesture)" : YToolsStrings.gestureCardTitle) {
            SettingsRow(
                symbol: "hand.draw",
                title: isChinese ? "触控板多指滑动 / 捏合手势" : YToolsStrings.gestureEnableTitle,
                caption: isChinese
                    ? "支持 2–5 指滑动与 4–5 指捏合/张开，内置相对面积掌缘过滤、孤立掌根过滤、多指共同移动校验与公开事件兼容降级。"
                    : YToolsStrings.gestureEnableCaption
            ) {
                HStack(spacing: 8) {
                    if trackpadGesturesEnabled && service.trackpadBackendState.isRunning {
                        statusBadge(isChinese ? "运行中" : "Active", active: true)
                    }
                    Toggle("", isOn: $trackpadGesturesEnabled)
                        .labelsHidden()
                        .onChange(of: trackpadGesturesEnabled) { _, enabled in
                            service.syncWithPreferences()
                            if enabled { permissions.requestAccessibility() }
                        }
                }
            }

            SettingsRow(
                symbol: "keyboard",
                title: isChinese ? "全局键盘热键与无泄漏重映射" : YToolsStrings.chordRemapEnableTitle,
                caption: isChinese
                    ? "支持按下/松开时机、长按连发、按 App 限定范围及多动作序列（快捷键、网址、应用、Shell、AppleScript、等待）。"
                    : YToolsStrings.chordRemapEnableCaption
            ) {
                HStack(spacing: 8) {
                    if trackpadChordRemapEnabled && service.isChordRunning {
                        statusBadge(isChinese ? "已监听" : "Active", active: true)
                    }
                    Toggle("", isOn: $trackpadChordRemapEnabled)
                        .labelsHidden()
                        .onChange(of: trackpadChordRemapEnabled) { _, enabled in
                            service.syncWithPreferences()
                            if enabled { permissions.requestAccessibility() }
                        }
                }
            }

            if trackpadGesturesEnabled || trackpadChordRemapEnabled {
                diagnosticsBar
            }

            Divider()

            automationRuleWorkspace

            Divider()

            tuningAndConfigFooter
        }
        .onAppear {
            repairSelection()
        }
        .onChange(of: filter) { _, _ in
            repairSelection()
        }
        .onChange(of: service.configuration.rules.map(\.id)) { _, _ in
            repairSelection()
        }
    }

    // MARK: - Live Diagnostics & Warnings

    private var diagnosticsBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                Label(
                    service.trackpadBackendState.label(chinese: isChinese),
                    systemImage: service.trackpadBackendState.isRunning
                        ? "checkmark.circle.fill"
                        : "exclamationmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(service.trackpadBackendState.isRunning ? Color.secondary : Color.orange)

                if !service.lastTriggeredSummary.isEmpty {
                    Text((isChinese ? "最近触发：" : "Last: ") + service.lastTriggeredSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if !service.lastTouchObservation.isEmpty || !service.lastGestureObservation.isEmpty {
                HStack(spacing: 12) {
                    if !service.lastTouchObservation.isEmpty {
                        Text(service.lastTouchObservation)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    if !service.lastGestureObservation.isEmpty {
                        Text(service.lastGestureObservation)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            ForEach(service.configurationWarnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            ForEach(service.errorMessages, id: \.self) { errorMsg in
                Label(errorMsg, systemImage: "exclamationmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Rule Manager & Detail Split

    private var automationRuleWorkspace: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Picker("", selection: $filter) {
                    ForEach(CategoryFilter.allCases) { item in
                        Text(item.title(chinese: isChinese)).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 260)

                Spacer()

                Menu {
                    Button(isChinese ? "新建触控板手势规则" : "New Trackpad Gesture Rule") {
                        addRule(.trackpad)
                    }
                    Button(isChinese ? "新建键盘快捷键规则" : "New Keyboard Shortcut Rule") {
                        addRule(.keyboard)
                    }
                } label: {
                    Label(isChinese ? "添加规则" : "Add Rule", systemImage: "plus")
                        .font(.caption)
                }
                .menuStyle(.borderedButton)
                .fixedSize()

                Button {
                    moveSelectedRule(by: -1)
                } label: {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!canMoveSelectedRule(by: -1))
                .help(isChinese ? "提高规则匹配优先级" : "Move Rule Up")

                Button {
                    moveSelectedRule(by: 1)
                } label: {
                    Image(systemName: "arrow.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!canMoveSelectedRule(by: 1))
                .help(isChinese ? "降低规则匹配优先级" : "Move Rule Down")

                Button {
                    if let selectedRuleID { duplicateRule(selectedRuleID) }
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(selectedRuleID == nil)
                .help(isChinese ? "复制所选规则" : "Duplicate Rule")

                Button {
                    if let selectedRuleID { deleteRule(selectedRuleID) }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(selectedRuleID == nil)
                .help(isChinese ? "删除所选规则" : "Delete Rule")
            }

            HStack(alignment: .top, spacing: 12) {
                ruleListColumn
                    .frame(width: 225)

                Divider()

                ruleDetailColumn
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(minHeight: 300)
        }
    }

    private var ruleListColumn: some View {
        ScrollView {
            VStack(spacing: 4) {
                if filteredRules.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "wand.and.stars")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text(isChinese ? "暂无规则" : "No Rules")
                            .font(.caption.weight(.medium))
                        Text(isChinese ? "点击右上角 + 创建规则" : "Click + above to create a rule")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                } else {
                    ForEach(filteredRules) { rule in
                        let selected = selectedRuleID == rule.id
                        HStack(spacing: 8) {
                            Image(systemName: rule.category.systemImage)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(rule.isEnabled ? Color.accentColor : .secondary)
                                .frame(width: 16)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.name.isEmpty ? (isChinese ? "未命名规则" : "Untitled") : rule.name)
                                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                                    .lineLimit(1)
                                Text(triggerSummary(for: rule))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 4)

                            Toggle("", isOn: Binding(
                                get: { rule.isEnabled },
                                set: { enabled in
                                    if let idx = service.configuration.rules.firstIndex(where: { $0.id == rule.id }) {
                                        service.configuration.rules[idx].isEnabled = enabled
                                        service.saveConfiguration()
                                    }
                                }
                            ))
                            .labelsHidden()
                            .controlSize(.mini)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            selected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.05),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(selected ? Color.accentColor.opacity(0.55) : .clear, lineWidth: 1)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .onTapGesture {
                            selectedRuleID = rule.id
                        }
                        .contextMenu {
                            Button(isChinese ? "测试动作" : "Test Actions") {
                                service.testActions(for: rule)
                            }
                            Button(isChinese ? "复制规则" : "Duplicate") {
                                duplicateRule(rule.id)
                            }
                            Divider()
                            Button(isChinese ? "删除规则" : "Delete", role: .destructive) {
                                deleteRule(rule.id)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var ruleDetailColumn: some View {
        if let id = selectedRuleID,
           service.configuration.rules.contains(where: { $0.id == id }) {
            GestureRuleDetailEditor(
                rule: ruleBinding(for: id),
                isChinese: isChinese,
                locale: Locale(identifier: l10n.language.rawValue),
                onCommit: { service.saveConfiguration() },
                onTest: { currentRule in service.testActions(for: currentRule) }
            )
        } else {
            VStack(spacing: 8) {
                Image(systemName: "sidebar.right")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(isChinese ? "从左侧选择一条规则进行编辑" : "Select a rule on the left to edit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 220)
        }
    }

    // MARK: - Recognition Tuning & Config Sync Footer

    private var tuningAndConfigFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureGroup(
                isExpanded: $tuningExpanded,
                content: {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(
                            isChinese
                                ? "强制使用公开 API 兼容模式（仅两指滚动/捏合/系统 Swipe，不加载私有触点框架）"
                                : "Force Public NSEvent Compatibility Mode (2-finger scroll/magnify/swipe only)",
                            isOn: Binding(
                                get: { service.configuration.settings.useCompatibilityTrackpadMode },
                                set: {
                                    service.configuration.settings.useCompatibilityTrackpadMode = $0
                                    service.saveConfiguration()
                                }
                            )
                        )
                        .font(.caption)

                        tuningSliderRow(
                            title: isChinese ? "实时触发距离" : "Live trigger distance",
                            value: Binding(
                                get: { service.configuration.settings.liveTriggerDistance },
                                set: {
                                    service.configuration.settings.liveTriggerDistance = $0
                                    service.saveConfiguration()
                                }
                            ),
                            range: 0.01...0.30,
                            step: 0.01
                        )

                        tuningSliderRow(
                            title: isChinese ? "最小滑动距离" : "Minimum swipe distance",
                            value: Binding(
                                get: { service.configuration.settings.minimumSwipeDistance },
                                set: {
                                    service.configuration.settings.minimumSwipeDistance = $0
                                    service.saveConfiguration()
                                }
                            ),
                            range: 0.00...0.10,
                            step: 0.005
                        )

                        tuningSliderRow(
                            title: isChinese ? "对角线拒绝比例" : "Diagonal reject ratio",
                            value: Binding(
                                get: { service.configuration.settings.diagonalRejectRatio },
                                set: {
                                    service.configuration.settings.diagonalRejectRatio = $0
                                    service.saveConfiguration()
                                }
                            ),
                            range: 0.50...1.00,
                            step: 0.01
                        )

                        tuningSliderRow(
                            title: isChinese ? "向下偏移修正比例" : "Downward bias ratio",
                            value: Binding(
                                get: { service.configuration.settings.downBiasRatio },
                                set: {
                                    service.configuration.settings.downBiasRatio = $0
                                    service.saveConfiguration()
                                }
                            ),
                            range: 0.05...1.00,
                            step: 0.01
                        )

                        tuningSliderRow(
                            title: isChinese ? "向下最小纵向分量" : "Downward bias min |dy|",
                            value: Binding(
                                get: { service.configuration.settings.downBiasMinimumY },
                                set: {
                                    service.configuration.settings.downBiasMinimumY = $0
                                    service.saveConfiguration()
                                }
                            ),
                            range: 0.01...0.30,
                            step: 0.01
                        )

                        tuningSliderRow(
                            title: isChinese ? "捏合/张开阈值" : "Pinch/spread threshold",
                            value: Binding(
                                get: { service.configuration.settings.spreadThreshold },
                                set: {
                                    service.configuration.settings.spreadThreshold = $0
                                    service.saveConfiguration()
                                }
                            ),
                            range: 0.01...0.20,
                            step: 0.005
                        )

                        tuningSliderRow(
                            title: isChinese ? "捏合优先位移比" : "Spread-to-translation ratio",
                            value: Binding(
                                get: { service.configuration.settings.spreadToDistanceRatio },
                                set: {
                                    service.configuration.settings.spreadToDistanceRatio = $0
                                    service.saveConfiguration()
                                }
                            ),
                            range: 0.50...5.00,
                            step: 0.10
                        )

                        HStack(spacing: 10) {
                            Text(isChinese
                                ? "动作防抖：\(service.configuration.settings.debounceMilliseconds) ms"
                                : "Action debounce: \(service.configuration.settings.debounceMilliseconds) ms")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Stepper(
                                "",
                                value: Binding(
                                    get: { service.configuration.settings.debounceMilliseconds },
                                    set: {
                                        service.configuration.settings.debounceMilliseconds = $0
                                        service.saveConfiguration()
                                    }
                                ),
                                in: 0...2_000,
                                step: 25
                            )
                            .labelsHidden()

                            Spacer()

                            Button(isChinese ? "恢复默认识别参数" : "Reset Tuning") {
                                service.resetTuningToDefaults()
                                syncFeedback = isChinese ? "已恢复默认识别参数" : "Tuning reset to defaults"
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.top, 8)
                },
                label: {
                    Label(
                        isChinese ? "手势识别调优与后端模式" : "Recognition Tuning & Backend Mode",
                        systemImage: "slider.horizontal.3"
                    )
                    .font(.caption.weight(.medium))
                }
            )

            HStack(spacing: 8) {
                Button(isChinese ? "导入 ~/.gesture/config.json" : YToolsStrings.gestureImportLegacyButton) {
                    if service.importLegacyConfigFromHome() {
                        syncFeedback = isChinese ? "已导入 ~/.gesture/config.json" : "Imported ~/.gesture/config.json"
                    } else {
                        syncFeedback = isChinese ? "未找到或无法解析 ~/.gesture/config.json" : "No valid ~/.gesture/config.json found"
                    }
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(isChinese ? "导出到 ~/.gesture/config.json" : "Export ~/.gesture/config.json") {
                    if service.exportConfigurationToHome() {
                        syncFeedback = isChinese ? "已导出到 ~/.gesture/config.json" : "Exported to ~/.gesture/config.json"
                    } else {
                        syncFeedback = isChinese ? "导出失败" : "Export failed"
                    }
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(isChinese ? "恢复默认规则" : YToolsStrings.gestureResetPresetsButton) {
                    service.resetToPresets()
                    syncFeedback = isChinese ? "已恢复默认规则预设" : "Presets restored"
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    let traceURL = service.traceLogURL
                    let dirURL = traceURL.deletingLastPathComponent()
                    try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
                    if FileManager.default.fileExists(atPath: traceURL.path) {
                        NSWorkspace.shared.activateFileViewerSelecting([traceURL])
                    } else {
                        NSWorkspace.shared.open(dirURL)
                    }
                } label: {
                    Label(isChinese ? "触点诊断日志" : "Touch Traces", systemImage: "folder")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if let syncFeedback {
                    Text(syncFeedback)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Helpers

    private func tuningSliderRow(title: String,
                                 value: Binding<Double>,
                                 range: ClosedRange<Double>,
                                 step: Double) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)
            Slider(value: value, in: range, step: step)
                .frame(maxWidth: 220)
            Text(String(format: "%.3f", locale: Locale(identifier: l10n.language.rawValue), value.wrappedValue))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }

    private func statusBadge(_ text: String, active: Bool) -> some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.caption.weight(.medium))
            .foregroundStyle(PanelMetricColor.green(for: colorScheme))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(PanelMetricColor.green(for: colorScheme).opacity(0.12), in: Capsule())
    }

    private func triggerSummary(for rule: GestureAutomationRule) -> String {
        let scopeSuffix: String
        switch rule.applicationScope.mode {
        case .all:
            scopeSuffix = ""
        case .include:
            scopeSuffix = " · +\(rule.applicationScope.bundleIdentifiers.count) App"
        case .exclude:
            scopeSuffix = " · -\(rule.applicationScope.bundleIdentifiers.count) App"
        }
        switch rule.trigger {
        case .trackpad(let t):
            let base = isChinese
                ? "\(t.fingers) 指 · \(t.direction.shortTitle(chinese: true))"
                : "\(t.fingers)F · \(t.direction.shortTitle(chinese: false))"
            return base + scopeSuffix
        case .keyboard(let k):
            return GestureKeyNames.formatted(k.keys) + scopeSuffix
        }
    }

    private func ruleBinding(for id: UUID) -> Binding<GestureAutomationRule> {
        Binding(
            get: {
                service.configuration.rules.first(where: { $0.id == id })
                    ?? GestureAutomationConfiguration.defaults.rules[0]
            },
            set: { updated in
                guard let idx = service.configuration.rules.firstIndex(where: { $0.id == id }) else { return }
                service.configuration.rules[idx] = updated
                service.saveConfiguration()
            }
        )
    }

    private func repairSelection() {
        if !filteredRules.contains(where: { $0.id == selectedRuleID }) {
            selectedRuleID = filteredRules.first?.id
        }
    }

    private func addRule(_ category: GestureRuleCategory) {
        let newRule: GestureAutomationRule
        switch category {
        case .trackpad:
            newRule = GestureAutomationRule(
                name: isChinese ? "新触控板手势" : "New Trackpad Gesture",
                trigger: .trackpad(TrackpadTriggerSpec(fingers: 3, direction: .down, minimumDistance: 0.18)),
                actions: [.keyboard(["cmd", "w"])]
            )
            if !trackpadGesturesEnabled {
                trackpadGesturesEnabled = true
                permissions.requestAccessibility()
            }
        case .keyboard:
            newRule = GestureAutomationRule(
                name: isChinese ? "新键盘热键" : "New Keyboard Rule",
                trigger: .keyboard(KeyboardTriggerSpec(keys: ["cmd", "j"])),
                actions: [.keyboard(["down"])]
            )
            if !trackpadChordRemapEnabled {
                trackpadChordRemapEnabled = true
                permissions.requestAccessibility()
            }
        }
        service.configuration.rules.append(newRule)
        service.saveConfiguration()
        filter = category == .trackpad ? .trackpad : .keyboard
        selectedRuleID = newRule.id
    }

    private func duplicateRule(_ id: UUID) {
        guard var copy = service.configuration.rules.first(where: { $0.id == id }) else { return }
        copy.id = UUID()
        copy.name += isChinese ? " 副本" : " Copy"
        copy.actions = copy.actions.map { action in
            var cloned = action
            cloned.id = UUID()
            return cloned
        }
        service.configuration.rules.append(copy)
        service.saveConfiguration()
        selectedRuleID = copy.id
    }

    private func deleteRule(_ id: UUID) {
        service.configuration.rules.removeAll { $0.id == id }
        service.saveConfiguration()
        repairSelection()
    }

    private func canMoveSelectedRule(by offset: Int) -> Bool {
        guard let index = filteredRules.firstIndex(where: { $0.id == selectedRuleID }) else { return false }
        return filteredRules.indices.contains(index + offset)
    }

    private func moveSelectedRule(by offset: Int) {
        guard canMoveSelectedRule(by: offset),
              let index = filteredRules.firstIndex(where: { $0.id == selectedRuleID }),
              let source = service.configuration.rules.firstIndex(where: { $0.id == filteredRules[index].id }),
              let dest = service.configuration.rules.firstIndex(where: { $0.id == filteredRules[index + offset].id }) else {
            return
        }
        service.configuration.rules.swapAt(source, dest)
        service.saveConfiguration()
    }
}

// MARK: - Rule Detail Editor (`RuleEditorViews.swift`)

private struct GestureRuleDetailEditor: View {
    @Binding var rule: GestureAutomationRule
    let isChinese: Bool
    let locale: Locale
    let onCommit: () -> Void
    let onTest: (GestureAutomationRule) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                TextField(isChinese ? "规则名称" : "Rule Name", text: $rule.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, weight: .semibold))
                    .onSubmit { onCommit() }

                Button {
                    onTest(rule)
                } label: {
                    Label(isChinese ? "测试动作" : "Test", systemImage: "play.fill")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(isChinese ? "立即执行一次当前规则的动作序列" : "Execute this rule's actions immediately")

                Toggle(isChinese ? "启用" : "Enabled", isOn: $rule.isEnabled)
                    .font(.caption)
                    .controlSize(.small)
            }

            GroupBox(isChinese ? "触发条件" : "Trigger") {
                triggerSection
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox(isChinese ? "生效应用范围 (App Scope)" : "Application Scope") {
                scopeSection
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox(isChinese ? "执行动作序列（按顺序依次执行）" : "Actions (Executed Sequentially)") {
                actionsSection
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var triggerSection: some View {
        switch rule.trigger {
        case .trackpad(let spec):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text(isChinese ? "手指数" : "Fingers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 62, alignment: .leading)

                    Picker("", selection: Binding(
                        get: { spec.fingers },
                        set: { newFingers in
                            var copy = spec
                            copy.fingers = newFingers
                            rule.trigger = .trackpad(copy)
                        }
                    )) {
                        ForEach(2...5, id: \.self) { count in
                            Text(isChinese ? "\(count) 指" : "\(count) Fingers").tag(count)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 100)

                    Text(isChinese ? "方向" : "Gesture")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("", selection: Binding(
                        get: { spec.direction },
                        set: { newDir in
                            var copy = spec
                            copy.direction = newDir
                            rule.trigger = .trackpad(copy)
                        }
                    )) {
                        ForEach(TrackpadGestureDirection.allCases) { dir in
                            Text(dir.title(chinese: isChinese)).tag(dir)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 145)
                }

                HStack(spacing: 10) {
                    Text(isChinese ? "触发距离" : "Distance")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 62, alignment: .leading)

                    Slider(
                        value: Binding(
                            get: { spec.minimumDistance },
                            set: { newDist in
                                var copy = spec
                                copy.minimumDistance = newDist
                                rule.trigger = .trackpad(copy)
                            }
                        ),
                        in: 0.02...0.50,
                        step: 0.01
                    )
                    .frame(maxWidth: 200)

                    Text(String(format: "%.2f", locale: locale, spec.minimumDistance))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }
            }

        case .keyboard(let spec):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text(isChinese ? "触发热键" : "Shortcut")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 62, alignment: .leading)

                    GestureShortcutCaptureButton(
                        keys: Binding(
                            get: { spec.keys },
                            set: { newKeys in
                                var copy = spec
                                copy.keys = newKeys
                                rule.trigger = .keyboard(copy)
                            }
                        ),
                        isChinese: isChinese
                    )

                    TextField("cmd+j", text: Binding(
                        get: { spec.keys.joined(separator: "+") },
                        set: { raw in
                            var copy = spec
                            copy.keys = TrackpadGestureKeyCodec.parseKeyList(raw)
                            rule.trigger = .keyboard(copy)
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 110)
                }

                HStack(spacing: 14) {
                    Text(isChinese ? "触发时机" : "Trigger on")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 62, alignment: .leading)

                    Picker("", selection: Binding(
                        get: { spec.phase },
                        set: { newPhase in
                            var copy = spec
                            copy.phase = newPhase
                            rule.trigger = .keyboard(copy)
                        }
                    )) {
                        ForEach(GestureTriggerPhase.allCases) { phase in
                            Text(phase.title(chinese: isChinese)).tag(phase)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)

                    Toggle(
                        isChinese ? "按住连续触发" : "Allow key repeat",
                        isOn: Binding(
                            get: { spec.allowRepeat },
                            set: { allow in
                                var copy = spec
                                copy.allowRepeat = allow
                                rule.trigger = .keyboard(copy)
                            }
                        )
                    )
                    .font(.caption)
                    .controlSize(.small)
                }
            }
        }
    }

    private var scopeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $rule.applicationScope.mode) {
                ForEach(GestureAppScopeMode.allCases) { mode in
                    Text(mode.title(chinese: isChinese)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if rule.applicationScope.mode != .all {
                ForEach(rule.applicationScope.bundleIdentifiers, id: \.self) { bundleID in
                    HStack(spacing: 8) {
                        Image(systemName: "app.dashed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(bundleID)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        Button {
                            rule.applicationScope.bundleIdentifiers.removeAll { $0 == bundleID }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 8) {
                    Button(isChinese ? "从应用程序选择…" : "Choose App…") {
                        chooseApplicationsFromPanel()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Menu(isChinese ? "从运行中 App 添加" : "Running Apps") {
                        ForEach(runningRegularApps(), id: \.bundleID) { app in
                            Button("\(app.name) (\(app.bundleID))") {
                                if !rule.applicationScope.bundleIdentifiers.contains(app.bundleID) {
                                    rule.applicationScope.bundleIdentifiers.append(app.bundleID)
                                }
                            }
                        }
                    }
                    .font(.caption)
                    .controlSize(.small)
                    .fixedSize()
                }
            }
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach($rule.actions) { $action in
                GestureActionStepEditor(
                    action: $action,
                    isChinese: isChinese,
                    onDelete: { [actionID = action.id] in
                        rule.actions.removeAll { $0.id == actionID }
                    }
                )
            }

            Menu {
                ForEach(GestureActionKind.allCases) { kind in
                    Button(kind.title(chinese: isChinese)) {
                        rule.actions.append(defaultAction(for: kind))
                    }
                }
            } label: {
                Label(isChinese ? "添加动作步骤" : "Add Action Step", systemImage: "plus.circle")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func defaultAction(for kind: GestureActionKind) -> GestureAutomationAction {
        switch kind {
        case .keyboardShortcut:
            return GestureAutomationAction(kind: .keyboardShortcut, keys: ["cmd", "w"])
        case .openURL:
            return GestureAutomationAction(kind: .openURL, value: "https://")
        case .launchApplication:
            return GestureAutomationAction(kind: .launchApplication, value: "com.apple.Safari")
        case .shellScript:
            return GestureAutomationAction(kind: .shellScript, value: "echo hello")
        case .appleScript:
            return GestureAutomationAction(kind: .appleScript, value: "beep")
        case .delay:
            return GestureAutomationAction(kind: .delay, delayMilliseconds: 250)
        }
    }

    private func runningRegularApps() -> [(name: String, bundleID: String)] {
        var seen = Set<String>()
        var list: [(name: String, bundleID: String)] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let id = app.bundleIdentifier, seen.insert(id).inserted else { continue }
            list.append((app.localizedName ?? id, id))
        }
        return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func chooseApplicationsFromPanel() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let bundleID = Bundle(url: url)?.bundleIdentifier,
               !rule.applicationScope.bundleIdentifiers.contains(bundleID) {
                rule.applicationScope.bundleIdentifiers.append(bundleID)
            }
        }
    }
}

// MARK: - Individual Action Step Editor

private struct GestureActionStepEditor: View {
    @Binding var action: GestureAutomationAction
    let isChinese: Bool
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("", selection: $action.kind) {
                    ForEach(GestureActionKind.allCases) { kind in
                        Text(kind.title(chinese: isChinese)).tag(kind)
                    }
                }
                .labelsHidden()
                .frame(width: 165)

                Spacer()

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(isChinese ? "删除此动作" : "Remove Action")
            }

            switch action.kind {
            case .keyboardShortcut:
                HStack(spacing: 8) {
                    GestureShortcutCaptureButton(keys: $action.keys, isChinese: isChinese)
                    TextField("cmd+w", text: Binding(
                        get: { action.keys.joined(separator: "+") },
                        set: { action.keys = TrackpadGestureKeyCodec.parseKeyList($0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 115)
                }

            case .openURL:
                TextField("https://example.com", text: $action.value)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))

            case .launchApplication:
                HStack(spacing: 6) {
                    TextField("com.apple.Safari / /Applications/Safari.app", text: $action.value)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                    Button(isChinese ? "选择…" : "Browse…") {
                        let panel = NSOpenPanel()
                        panel.directoryURL = URL(fileURLWithPath: "/Applications")
                        panel.allowedContentTypes = [.application]
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url {
                            action.value = Bundle(url: url)?.bundleIdentifier ?? url.path
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

            case .shellScript:
                TextEditor(text: $action.value)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(minHeight: 68, maxHeight: 110)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))

            case .appleScript:
                TextEditor(text: $action.value)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(minHeight: 68, maxHeight: 110)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))

            case .delay:
                HStack(spacing: 8) {
                    Stepper(
                        value: $action.delayMilliseconds,
                        in: 0...60_000,
                        step: 50
                    ) {
                        Text("\(action.delayMilliseconds) ms")
                            .font(.caption.monospacedDigit())
                    }
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Live Shortcut Recorder (`ShortcutCaptureButton`)

@MainActor
private final class GestureShortcutRecorderState: ObservableObject {
    private static weak var activeRecorder: GestureShortcutRecorderState?
    @Published var isRecording = false
    var monitor: Any?
    private var onStop: (() -> Void)?

    func begin(onStop: @escaping () -> Void) {
        Self.activeRecorder?.stop()
        Self.activeRecorder = self
        self.onStop = onStop
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        isRecording = false
        onStop?()
        onStop = nil
        if Self.activeRecorder === self {
            Self.activeRecorder = nil
        }
    }
}

@MainActor
private struct GestureShortcutCaptureButton: View {
    @Binding var keys: [String]
    let isChinese: Bool
    @StateObject private var recorder = GestureShortcutRecorderState()

    var body: some View {
        Button {
            toggleRecording()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: recorder.isRecording ? "record.circle" : "keyboard")
                    .font(.caption)
                if recorder.isRecording {
                    Text(isChinese ? "请按下组合键…" : "Press shortcut…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(keys.isEmpty
                        ? (isChinese ? "点击录制" : "Record")
                        : GestureKeyNames.formatted(keys))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }
            }
            .frame(minWidth: 115)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .onDisappear { recorder.stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            recorder.stop()
        }
    }

    private func toggleRecording() {
        if recorder.isRecording {
            recorder.stop()
            return
        }
        recorder.stop()
        recorder.begin {
            TrackpadGestureService.shared.setShortcutRecording(false)
        }
        recorder.isRecording = true
        TrackpadGestureService.shared.setShortcutRecording(true)
        recorder.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            var captured: [String] = []
            if event.modifierFlags.contains(.control) { captured.append("ctrl") }
            if event.modifierFlags.contains(.option) { captured.append("option") }
            if event.modifierFlags.contains(.shift) { captured.append("shift") }
            if event.modifierFlags.contains(.command) { captured.append("cmd") }
            let code = CGKeyCode(event.keyCode)
            let flags = GestureKeyboardShortcut.eventModifiers(
                CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)),
                keyCode: code
            )
            if flags.contains(.maskSecondaryFn) {
                captured.append("fn")
            }
            guard let name = GestureKeyNames.name(for: code) else { return nil }
            captured.append(name)
            keys = captured
            recorder.stop()
            return nil
        }
        if recorder.monitor == nil {
            recorder.stop()
        }
    }
}
