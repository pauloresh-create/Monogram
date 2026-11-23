import AccountContext
import Display
import ItemListUI
import SwiftSignalKit
import TelegramPresentationData

private enum MonoContentDemo: Int32, CaseIterable, Hashable {
    case channel = 35
    case protectedMedia = 36
    case oneTimeMedia = 37
    case screenshotNotice = 38

    var title: String {
        switch self {
        case .channel: return "35. Ограниченный канал"
        case .protectedMedia: return "36. Защищённый материал"
        case .oneTimeMedia: return "37. Одноразовое медиа"
        case .screenshotNotice: return "38. Уведомление о скриншоте"
        }
    }

    var explanation: String {
        switch self {
        case .channel:
            return "Переключает между заглушкой и вымышленной публикацией канала."
        case .protectedMedia:
            return "Меняет значок замка на отметку «Сохранено» у демонстрационной карточки."
        case .oneTimeMedia:
            return "Показывает, как выглядит открытая карточка одноразового медиа."
        case .screenshotNotice:
            return "Скрывает предупреждение в нарисованном примере переписки."
        }
    }

    func preview(isEnabled: Bool) -> String {
        switch self {
        case .channel:
            return isEnabled ? "📰 Канал «Север». Сегодня открылась выставка полярных фотографий." : "🔒 Канал «Север». Контент скрыт."
        case .protectedMedia:
            return isEnabled ? "✅ Карточка «Горное озеро». Демо-отметка «Сохранено»." : "🔒 Карточка «Горное озеро». Сохранение недоступно."
        case .oneTimeMedia:
            return isEnabled ? "🌅 Карточка открыта. Тестовый кадр «Закат над морем»." : "◉ Одноразовая карточка закрыта."
        case .screenshotNotice:
            return isEnabled ? "Тестовая переписка\nЛера · Встречаемся в семь." : "Тестовая переписка\nЛера · Встречаемся в семь.\n📷 Сделан снимок экрана."
        }
    }
}

private final class MonoContentDemoArguments {
    let toggle: (MonoContentDemo, Bool) -> Void

    init(toggle: @escaping (MonoContentDemo, Bool) -> Void) {
        self.toggle = toggle
    }
}

private enum MonoContentDemoEntry: ItemListNodeEntry {
    case introduction
    case toggle(MonoContentDemo, Bool)
    case preview(MonoContentDemo, String)

    var section: ItemListSectionId {
        switch self {
        case .introduction: return 0
        case let .toggle(demo, _), let .preview(demo, _): return demo.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case .introduction: return 0
        case let .toggle(demo, _): return Int(demo.rawValue) * 2
        case let .preview(demo, _): return Int(demo.rawValue) * 2 + 1
        }
    }

    static func < (lhs: MonoContentDemoEntry, rhs: MonoContentDemoEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        switch self {
        case .introduction:
            return ItemListTextItem(
                presentationData: presentationData,
                text: .plain("Визуальное демо на вымышленных данных. Переключатели меняют только примеры на этом экране."),
                sectionId: self.section
            )
        case let .toggle(demo, value):
            let arguments = arguments as! MonoContentDemoArguments
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: demo.title,
                text: demo.explanation,
                value: value,
                maximumNumberOfLines: 0,
                sectionId: self.section,
                style: .blocks,
                updated: { value in arguments.toggle(demo, value) }
            )
        case let .preview(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

func monoContentDemoController(context: AccountContext) -> ViewController {
    var enabled = Set<MonoContentDemo>()
    let selection = ValuePromise<Set<MonoContentDemo>>([], ignoreRepeated: true)
    let arguments = MonoContentDemoArguments(toggle: { demo, value in
        if value {
            enabled.insert(demo)
        } else {
            enabled.remove(demo)
        }
        selection.set(enabled)
    })

    let signal = combineLatest(context.sharedContext.presentationData, selection.get())
    |> map { presentationData, selection -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [MonoContentDemoEntry] = [.introduction]
        for demo in MonoContentDemo.allCases {
            let isEnabled = selection.contains(demo)
            entries.append(.toggle(demo, isEnabled))
            entries.append(.preview(demo, demo.preview(isEnabled: isEnabled)))
        }
        let presentation = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(
            presentationData: presentation,
            title: .text("Демо 35–38"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let list = ItemListNodeState(presentationData: presentation, entries: entries, style: .blocks)
        return (state, (list, arguments))
    }
    return ItemListController(context: context, state: signal)
}
