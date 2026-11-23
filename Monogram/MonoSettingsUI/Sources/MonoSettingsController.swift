import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import AccountContext
import PresentationDataUtils
import MonoSettings
import SGSimpleSettings

// "Mono" settings screen: every row is title + short description + switch.
// Rows are generated from MonoFeatures.all, grouped by MonoFeatureGroup.

private final class MonoSettingsArguments {
    let toggle: (String, Bool) -> Void
    let openHistory: () -> Void
    let openFeed: () -> Void

    init(toggle: @escaping (String, Bool) -> Void, openHistory: @escaping () -> Void, openFeed: @escaping () -> Void) {
        self.toggle = toggle
        self.openHistory = openHistory
        self.openFeed = openFeed
    }
}

private enum MonoSettingsEntry: ItemListNodeEntry {
    case header(id: Int, group: MonoFeatureGroup)
    case history(id: Int)
    case feed(id: Int)
    case feature(id: Int, feature: MonoFeature, value: Bool, enabled: Bool)
    case footer(id: Int, group: MonoFeatureGroup, text: String)

    var section: ItemListSectionId {
        switch self {
        case let .header(_, group), let .footer(_, group, _):
            return group.rawValue
        case .history:
            return MonoFeatureGroup.history.rawValue
        case .feed:
            return MonoFeatureGroup.feed.rawValue
        case let .feature(_, feature, _, _):
            return feature.group.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case let .header(id, _), let .history(id), let .feed(id), let .feature(id, _, _, _), let .footer(id, _, _):
            return id
        }
    }

    static func <(lhs: MonoSettingsEntry, rhs: MonoSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! MonoSettingsArguments
        switch self {
        case .feed:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Открыть ленту каналов", label: "", sectionId: self.section, style: .blocks, action: arguments.openFeed)
        case .history:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Открыть локальную историю", label: "", sectionId: self.section, style: .blocks, action: arguments.openHistory)
        case let .header(_, group):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: group.title, sectionId: self.section)
        case let .feature(_, feature, value, enabled):
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: feature.title,
                text: feature.subtitle,
                value: value,
                enabled: enabled,
                maximumNumberOfLines: 0,
                sectionId: self.section,
                style: .blocks,
                updated: { newValue in
                    arguments.toggle(feature.key, newValue)
                }
            )
        case let .footer(_, _, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func monoDisplayedValue(_ key: String, settings: MonoSettings) -> Bool {
    switch key {
    case MonoFeatureKey.confirmCalls:
        return SGSimpleSettings.shared.confirmCalls
    case MonoFeatureKey.hideStoriesBar:
        return SGSimpleSettings.shared.hideStories
    case MonoFeatureKey.translate:
        return SGSimpleSettings.shared.translationBackendEnum == .system
    default:
        return settings.storedValue(key)
    }
}

private func monoSetValue(_ key: String, value: Bool, settings: MonoSettings) {
    switch key {
    case MonoFeatureKey.confirmCalls:
        SGSimpleSettings.shared.confirmCalls = value
    case MonoFeatureKey.hideStoriesBar:
        SGSimpleSettings.shared.hideStories = value
    case MonoFeatureKey.translate:
        let backend: SGSimpleSettings.TranslationBackend = value ? .system : .default
        SGSimpleSettings.shared.translationBackend = backend.rawValue
    default:
        settings.set(key, value)
    }
}

private func monoSettingsEntries(settings: MonoSettings) -> [MonoSettingsEntry] {
    var entries: [MonoSettingsEntry] = []
    var nextId = 0
    func id() -> Int {
        nextId += 1
        return nextId
    }

    for group in MonoFeatureGroup.allCases {
        let features = MonoFeatures.visibleFeatures(in: group)
        guard !features.isEmpty else {
            continue
        }
        entries.append(.header(id: id(), group: group))
        for feature in features {
            // Child toggles are greyed out until their parent is on.
            let parentOn = feature.requires.map { settings.isEnabled($0) } ?? true
            entries.append(.feature(id: id(), feature: feature, value: monoDisplayedValue(feature.key, settings: settings), enabled: parentOn))
        }
        if group == .history {
            entries.append(.history(id: id()))
        }
        if group == .feed && settings.isEnabled(MonoFeatureKey.feed) {
            entries.append(.feed(id: id()))
        }
        if let footer = group.footer {
            entries.append(.footer(id: id(), group: group, text: footer))
        }
    }
    return entries
}

public func monoSettingsController(context: AccountContext) -> ViewController {
    let settings = MonoSettings.shared
    let revision = ValuePromise<Int>(0, ignoreRepeated: false)
    var revisionValue = 0
    var openHistory: (() -> Void)?
    var openFeed: (() -> Void)?

    let arguments = MonoSettingsArguments(toggle: { key, value in
        monoSetValue(key, value: value, settings: settings)
        revisionValue += 1
        revision.set(revisionValue)
    }, openHistory: { openHistory?() }, openFeed: { openFeed?() })

    let signal = combineLatest(context.sharedContext.presentationData, revision.get())
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Мои функции"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: monoSettingsEntries(settings: settings),
            style: .blocks
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    openHistory = { [weak controller] in
        controller?.push(monoHistoryController(context: context))
    }
    openFeed = { [weak controller] in
        controller?.push(monoFeedController(context: context))
    }
    return controller
}
