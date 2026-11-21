import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import AccountContext
import PresentationDataUtils
import MonoSettings

// "Mono" settings screen: every row is title + short description + switch.
// Rows are generated from MonoFeatures.all, grouped by MonoFeatureGroup.

private final class MonoSettingsArguments {
    let toggle: (String, Bool) -> Void

    init(toggle: @escaping (String, Bool) -> Void) {
        self.toggle = toggle
    }
}

private enum MonoSettingsEntry: ItemListNodeEntry {
    case header(id: Int, group: MonoFeatureGroup)
    case feature(id: Int, feature: MonoFeature, value: Bool, enabled: Bool)
    case footer(id: Int, group: MonoFeatureGroup, text: String)

    var section: ItemListSectionId {
        switch self {
        case let .header(_, group), let .footer(_, group, _):
            return group.rawValue
        case let .feature(_, feature, _, _):
            return feature.group.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case let .header(id, _), let .feature(id, _, _, _), let .footer(id, _, _):
            return id
        }
    }

    static func <(lhs: MonoSettingsEntry, rhs: MonoSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! MonoSettingsArguments
        switch self {
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
            entries.append(.feature(id: id(), feature: feature, value: settings.storedValue(feature.key), enabled: parentOn))
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

    let arguments = MonoSettingsArguments(toggle: { key, value in
        settings.set(key, value)
        revisionValue += 1
        revision.set(revisionValue)
    })

    let signal = combineLatest(context.sharedContext.presentationData, revision.get())
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Monogram"),
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

    return ItemListController(context: context, state: signal)
}
