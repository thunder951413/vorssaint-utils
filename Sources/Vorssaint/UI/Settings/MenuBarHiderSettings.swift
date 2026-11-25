// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (Ice) © 2023–2025 Jordan Baird
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct MenuBarHiderSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = MenuBarHiderService.shared

    @AppStorage(DefaultsKey.menuBarHiderEnabled) private var enabled = true
    @AppStorage(DefaultsKey.menuBarHiderShowTriggerIcon) private var showTriggerIcon = true
    @AppStorage(DefaultsKey.menuBarHiderShowOnEmptyClick) private var showOnEmptyClick = true
    @AppStorage(DefaultsKey.menuBarHiderEnableAlwaysHidden) private var enableAlwaysHidden = false
    @AppStorage(DefaultsKey.menuBarHiderOptionToggleAlwaysHidden) private var optionToggleAlwaysHidden = true
    @AppStorage(DefaultsKey.menuBarHiderBarStyle) private var barStyleRaw = MenuBarHiderBarStyle.frosted.rawValue
    @AppStorage(DefaultsKey.menuBarHiderBarLocation) private var barLocationRaw = MenuBarHiderBarLocation.dynamic.rawValue
    @AppStorage(DefaultsKey.menuBarHiderIconSize) private var iconSize = MenuBarHiderSupport.defaultIconSize
    @AppStorage(DefaultsKey.menuBarHiderItemSpacing) private var itemSpacing = MenuBarHiderSupport.defaultItemSpacing
    @AppStorage(DefaultsKey.menuBarHiderBarPadding) private var barPadding = MenuBarHiderSupport.defaultBarPadding
    @AppStorage(DefaultsKey.menuBarHiderAutoRehide) private var autoRehide = true
    @AppStorage(DefaultsKey.menuBarHiderRehideStrategy) private var rehideStrategyRaw = MenuBarHiderRehideStrategy.smart.rawValue
    @AppStorage(DefaultsKey.menuBarHiderRehideInterval) private var rehideInterval = MenuBarHiderSupport.defaultRehideInterval
    @AppStorage(DefaultsKey.menuBarHiderTempShowInterval) private var tempShowInterval = MenuBarHiderSupport.defaultTempShowInterval

    @State private var filterQuery = ""
    @State private var isConfirmingReset = false

    private var strings: MenuBarHiderFeatureStrings {
        FeatureStrings.menuBarHider(l10n.language)
    }

    private var activeSections: [MenuBarHiderSection] {
        enableAlwaysHidden ? [.visible, .hidden, .alwaysHidden] : [.visible, .hidden]
    }

    private var barStyle: MenuBarHiderBarStyle {
        MenuBarHiderBarStyle.sanitized(barStyleRaw)
    }

    private var barLocation: MenuBarHiderBarLocation {
        MenuBarHiderBarLocation.sanitized(barLocationRaw)
    }

    private var rehideStrategy: MenuBarHiderRehideStrategy {
        MenuBarHiderRehideStrategy.sanitized(rehideStrategyRaw)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(strings.title).font(.title2.bold())
                    Text(strings.pageCaption)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !MenuBarHiderSupport.isOSSupported {
                    SettingsCard {
                        Label(strings.unsupportedMacOS, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                } else {
                    overviewCard

                    if enabled && !permissions.accessibility {
                        SettingsCard(title: l10n.s.permissionRequired) {
                            PermissionRow(kind: .accessibility)
                        }
                    }

                    if service.isMenuBarHiddenBySystemUserDefaults {
                        autoHiddenCard
                    } else if enabled && permissions.accessibility {
                        iconsManagementSection
                    }

                    behaviorCard
                        .disabled(!enabled)
                        .opacity(enabled ? 1 : 0.65)
                }
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(22)
        }
        .toggleStyle(.switch)
        .onAppear {
            service.syncWithPreferences()
            if enabled && permissions.accessibility {
                Task { await service.cacheItemsIfNeeded() }
            }
        }
        .onChange(of: enabled) { _, newValue in
            if newValue && !permissions.accessibility {
                permissions.requestAccessibility()
                permissions.openAccessibilitySettings()
            }
            service.syncWithPreferences()
        }
        .onChange(of: showTriggerIcon) { _, _ in service.syncWithPreferences() }
        .onChange(of: enableAlwaysHidden) { _, _ in service.syncWithPreferences() }
        .confirmationDialog(
            strings.resetConfirmTitle,
            isPresented: $isConfirmingReset,
            titleVisibility: .visible
        ) {
            Button(strings.resetConfirmAction, role: .destructive) {
                service.resetAllAssignments()
            }
            Button(strings.cancelButton, role: .cancel) {}
        } message: {
            Text(strings.resetConfirmMessage)
        }
    }

    // MARK: - Overview Card

    private var overviewCard: some View {
        SettingsCard {
            SettingsRow(
                symbol: AppFeature.menuBarHider.symbolName,
                title: strings.enable,
                caption: strings.enableCaption
            ) {
                Toggle("", isOn: $enabled)
                    .labelsHidden()
            }

            if enabled && permissions.accessibility {
                Divider()

                HStack(spacing: 10) {
                    statusBadge
                    Spacer()
                    Button {
                        Task { await service.refreshItems() }
                    } label: {
                        Label(strings.refreshButton, systemImage: "arrow.clockwise")
                    }
                    .disabled(service.isRefreshing)

                    Button {
                        service.toggleHidingPaused()
                    } label: {
                        Label(
                            service.isHidingPaused ? strings.resumeButton : strings.pauseButton,
                            systemImage: service.isHidingPaused ? "play.fill" : "pause.fill"
                        )
                    }

                    Button(strings.resetButton, role: .destructive) {
                        isConfirmingReset = true
                    }
                }

                if let failure = service.visibilityFailureDescription {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if service.isHidingPaused {
            Label(strings.statusPaused, systemImage: "pause.circle.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.orange)
        } else {
            Label(
                String(format: strings.statusActiveFormat, service.hiddenItemCount),
                systemImage: "checkmark.circle.fill"
            )
            .font(.callout.weight(.medium))
            .foregroundStyle(.green)
        }
    }

    private var autoHiddenCard: some View {
        SettingsCard {
            VStack(spacing: 8) {
                Image(systemName: "menubar.arrow.up.rectangle")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text(strings.autoHiddenTitle)
                    .font(.headline)
                Text(strings.autoHiddenCaption)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Section Management

    private var iconsManagementSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(strings.searchPlaceholder, text: $filterQuery)
                        .textFieldStyle(.plain)
                    if !filterQuery.isEmpty {
                        Button {
                            filterQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Text(enableAlwaysHidden ? strings.cardMultiSectionAnnotation : strings.cardToggleAnnotation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(activeSections, id: \.self) { section in
                sectionCard(for: section)
            }
        }
    }

    private func filteredItems(for section: MenuBarHiderSection) -> [MenuBarHiderItem] {
        let all = service.managedItems(in: section)
        let query = filterQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return all }
        return all.filter { item in
            item.displayName.localizedCaseInsensitiveContains(query)
                || (item.bundleIdentifier?.localizedCaseInsensitiveContains(query) == true)
        }
    }

    private func sectionSymbol(for section: MenuBarHiderSection) -> String {
        switch section {
        case .visible: return "eye"
        case .hidden: return "eye.slash"
        case .alwaysHidden: return "archivebox"
        }
    }

    private func sectionCard(for section: MenuBarHiderSection) -> some View {
        let items = filteredItems(for: section)
        let totalCount = service.managedItems(in: section).count

        return SettingsCard {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(strings.sectionTitle(section), systemImage: sectionSymbol(for: section))
                    .font(.headline)
                Text("\(totalCount)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                Spacer()
                Text(strings.sectionSubtitle(section))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if items.isEmpty {
                HStack(spacing: 8) {
                    Spacer()
                    if !service.hasCompletedInitialScan {
                        ProgressView().controlSize(.small)
                        Text(strings.scanningItems)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(String(format: strings.emptySectionFormat, strings.sectionTitle(section)))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 12)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 155, maximum: 220), spacing: 10)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(items) { item in
                        MenuBarHiderAppCard(
                            item: item,
                            currentSection: section,
                            enableAlwaysHidden: enableAlwaysHidden,
                            strings: strings,
                            assignSection: { target in
                                service.assignItem(item, to: target)
                            },
                            openTemporarily: {
                                service.activateHiddenItem(item, mouseButton: .left)
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Behavior Card

    private var behaviorCard: some View {
        SettingsCard(title: strings.sectionBehaviorTitle) {
            SettingsRow(
                symbol: "chevron.left.square",
                title: strings.showTriggerIcon,
                caption: strings.showTriggerIconCaption
            ) {
                Toggle("", isOn: $showTriggerIcon).labelsHidden()
            }

            Divider()

            SettingsRow(
                symbol: "cursorarrow.click.2",
                title: strings.showOnEmptyClick,
                caption: strings.showOnEmptyClickCaption
            ) {
                Toggle("", isOn: $showOnEmptyClick).labelsHidden()
            }

            Divider()

            SettingsRow(
                symbol: "archivebox",
                title: strings.enableAlwaysHidden,
                caption: strings.enableAlwaysHiddenCaption
            ) {
                Toggle("", isOn: $enableAlwaysHidden).labelsHidden()
            }

            if enableAlwaysHidden {
                SettingsRow(
                    symbol: "option",
                    title: strings.optionToggleAlwaysHidden,
                    caption: strings.optionToggleAlwaysHiddenCaption
                ) {
                    Toggle("", isOn: $optionToggleAlwaysHidden).labelsHidden()
                }
            }

            Divider()

            SettingsRow(symbol: "sparkles.rectangle.stack", title: strings.barStyleLabel) {
                Picker("", selection: Binding(
                    get: { barStyle },
                    set: { barStyleRaw = $0.rawValue }
                )) {
                    Text(strings.barStyleFrosted).tag(MenuBarHiderBarStyle.frosted)
                    Text(strings.barStyleSolid).tag(MenuBarHiderBarStyle.solid)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            SettingsRow(symbol: "rectangle.topthird.inset.filled", title: strings.barLocationLabel) {
                Picker("", selection: Binding(
                    get: { barLocation },
                    set: { barLocationRaw = $0.rawValue }
                )) {
                    Text(strings.barLocationDynamic).tag(MenuBarHiderBarLocation.dynamic)
                    Text(strings.barLocationPointer).tag(MenuBarHiderBarLocation.mousePointer)
                    Text(strings.barLocationTrigger).tag(MenuBarHiderBarLocation.triggerIcon)
                }
                .labelsHidden()
                .frame(width: 180)
            }

            sliderRow(
                symbol: "square.resize",
                title: strings.iconSizeLabel,
                value: $iconSize,
                range: MenuBarHiderSupport.iconSizeRange,
                formatted: String(format: strings.pointsFormat, Int(iconSize.rounded()))
            )

            sliderRow(
                symbol: "arrow.left.and.right",
                title: strings.itemSpacingLabel,
                value: $itemSpacing,
                range: MenuBarHiderSupport.itemSpacingRange,
                formatted: String(format: strings.pointsFormat, Int(itemSpacing.rounded()))
            )

            sliderRow(
                symbol: "rectangle.inset.filled",
                title: strings.barPaddingLabel,
                value: $barPadding,
                range: MenuBarHiderSupport.barPaddingRange,
                formatted: String(format: strings.pointsFormat, Int(barPadding.rounded()))
            )

            Divider()

            SettingsRow(
                symbol: "eye.slash.circle",
                title: strings.autoRehide,
                caption: strings.autoRehideCaption
            ) {
                Toggle("", isOn: $autoRehide).labelsHidden()
            }

            if autoRehide {
                SettingsRow(symbol: "wand.and.stars", title: strings.rehideStrategyLabel) {
                    Picker("", selection: Binding(
                        get: { rehideStrategy },
                        set: { rehideStrategyRaw = $0.rawValue }
                    )) {
                        Text(strings.rehideSmart).tag(MenuBarHiderRehideStrategy.smart)
                        Text(strings.rehideTimed).tag(MenuBarHiderRehideStrategy.timed)
                        Text(strings.rehideFocusedApp).tag(MenuBarHiderRehideStrategy.focusedApp)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 250)
                }

                if rehideStrategy == .timed {
                    sliderRow(
                        symbol: "timer",
                        title: strings.rehideIntervalLabel,
                        value: $rehideInterval,
                        range: MenuBarHiderSupport.rehideIntervalRange,
                        formatted: String(format: strings.secondsFormat, Int(rehideInterval.rounded()))
                    )
                }
            }

            Divider()

            sliderRow(
                symbol: "clock.arrow.circlepath",
                title: strings.tempShowIntervalLabel,
                caption: strings.tempShowIntervalCaption,
                value: $tempShowInterval,
                range: MenuBarHiderSupport.tempShowIntervalRange,
                formatted: String(format: strings.secondsFormat, Int(tempShowInterval.rounded()))
            )
        }
    }

    private func sliderRow(
        symbol: String,
        title: String,
        caption: String? = nil,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        formatted: String
    ) -> some View {
        SettingsRow(symbol: symbol, title: title, caption: caption) {
            HStack(spacing: 10) {
                Slider(value: value, in: range, step: 1)
                    .frame(width: 140)
                Text(formatted)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }
}

// MARK: - App Card

private struct MenuBarHiderAppCard: View {
    let item: MenuBarHiderItem
    let currentSection: MenuBarHiderSection
    let enableAlwaysHidden: Bool
    let strings: MenuBarHiderFeatureStrings
    let assignSection: (MenuBarHiderSection) -> Void
    let openTemporarily: () -> Void

    @State private var isHovered = false

    private var availableSections: [MenuBarHiderSection] {
        enableAlwaysHidden ? [.visible, .hidden, .alwaysHidden] : [.visible, .hidden]
    }

    private var quickToggleTarget: MenuBarHiderSection {
        currentSection == .visible ? .hidden : .visible
    }

    var body: some View {
        Group {
            if enableAlwaysHidden {
                Menu {
                    sectionMenuItems
                } label: {
                    cardContent
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    assignSection(quickToggleTarget)
                } label: {
                    cardContent
                }
                .buttonStyle(.plain)
                .help(currentSection == .visible ? strings.cardMoveHintToHidden : strings.cardMoveHintToVisible)
            }
        }
        .contextMenu {
            sectionMenuItems
            Divider()
            Button(strings.cardRevealAndOpen) {
                openTemporarily()
            }
        }
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var sectionMenuItems: some View {
        ForEach(availableSections, id: \.self) { target in
            Button {
                assignSection(target)
            } label: {
                if target == currentSection {
                    Label(String(format: strings.cardCurrentSectionFormat, strings.sectionTitle(target)), systemImage: "checkmark")
                } else {
                    Text(String(format: strings.cardMoveToSectionFormat, strings.sectionTitle(target)))
                }
            }
            .disabled(target == currentSection)
        }
    }

    private var cardContent: some View {
        HStack(spacing: 10) {
            if let icon = item.owningApplication?.icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            Text(item.displayName)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Image(systemName: enableAlwaysHidden
                  ? "chevron.up.chevron.down"
                  : (currentSection == .visible ? "eye.slash" : "eye"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isHovered ? .primary : .tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.quinary))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
