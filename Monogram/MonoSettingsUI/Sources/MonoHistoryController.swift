import AccountContext
import Display
import Foundation
import ItemListUI
import PresentationDataUtils
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import UIKit

private final class MonoHistoryArguments {
    let search: (String) -> Void
    let clear: () -> Void
    let changeLimit: (Int) -> Void
    let open: (MonoHistoryEntry) -> Void
    let export: (Bool) -> Void

    init(search: @escaping (String) -> Void, clear: @escaping () -> Void, changeLimit: @escaping (Int) -> Void, open: @escaping (MonoHistoryEntry) -> Void, export: @escaping (Bool) -> Void) {
        self.search = search
        self.clear = clear
        self.changeLimit = changeLimit
        self.open = open
        self.export = export
    }
}

private enum MonoHistoryItem: ItemListNodeEntry {
    case search(String)
    case limit(Int)
    case exportJSON
    case exportHTML
    case clear
    case status(String)
    case entry(Int, MonoHistoryEntry)

    var section: ItemListSectionId {
        switch self {
        case .search:
            return 0
        case .limit, .exportJSON, .exportHTML, .clear:
            return 1
        case .status, .entry:
            return 2
        }
    }

    var stableId: Int {
        switch self {
        case .search: return 0
        case .limit: return 1
        case .exportJSON: return 2
        case .exportHTML: return 3
        case .clear: return 4
        case .status: return 5
        case let .entry(index, _): return index + 6
        }
    }

    static func < (lhs: MonoHistoryItem, rhs: MonoHistoryItem) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! MonoHistoryArguments
        switch self {
        case let .search(query):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: ""), text: query, placeholder: "Поиск текста, автора или чата", returnKeyType: .done, spacing: 3.0, clearType: .always, sectionId: self.section, textUpdated: arguments.search, action: {}, dismissKeyboardOnEnter: true)
        case let .limit(limit):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Лимит истории", label: "\(limit) МБ", sectionId: self.section, style: .blocks, action: { arguments.changeLimit(limit) })
        case .exportJSON:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Экспорт JSON", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: { arguments.export(false) })
        case .exportHTML:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Экспорт HTML", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: { arguments.export(true) })
        case .clear:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Очистить локальную историю", kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: arguments.clear)
        case let .status(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .entry(_, entry):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "\(monoHistoryKind(entry.kind)) · \(entry.chatTitle)", label: String(entry.text.prefix(100)), labelStyle: .detailText, sectionId: self.section, style: .blocks, action: { arguments.open(entry) })
        }
    }
}

private func monoHistoryKind(_ kind: MonoHistoryEntry.Kind) -> String {
    switch kind {
    case .deleted: return "Удалено"
    case .edited: return "Правка"
    case .archived: return "Архив"
    }
}

private func monoHistoryDate(_ value: Int32) -> String {
    return DateFormatter.localizedString(from: Date(timeIntervalSince1970: TimeInterval(value)), dateStyle: .short, timeStyle: .short)
}

private func monoHistoryChangeSummary(previous: String, replacement: String) -> String {
    let oldWords = previous.split(whereSeparator: { $0.isWhitespace })
    let newWords = replacement.split(whereSeparator: { $0.isWhitespace })
    let changes = newWords.difference(from: oldWords)
    var removed: [Substring] = []
    var inserted: [Substring] = []
    for change in changes {
        switch change {
        case let .remove(_, word, _): removed.insert(word, at: 0)
        case let .insert(_, word, _): inserted.append(word)
        }
    }
    return [
        removed.isEmpty ? nil : "− " + removed.joined(separator: " "),
        inserted.isEmpty ? nil : "+ " + inserted.joined(separator: " ")
    ].compactMap { $0 }.joined(separator: "\n")
}

private func monoHistoryEscapeHTML(_ text: String) -> String {
    return text.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&#39;")
}

func monoHistoryController(context: AccountContext) -> ViewController {
    let postbox = context.account.postbox
    let search = ValuePromise("", ignoreRepeated: true)
    var present: ((ViewController) -> Void)?
    var presentExport: ((URL) -> Bool)?

    let arguments = MonoHistoryArguments(
        search: { search.set($0) },
        clear: {
            present?(textAlertController(context: context, title: "Очистить локальную историю?", text: "Сохранённые копии и версии будут удалены с этого устройства.", actions: [
                TextAlertAction(type: .genericAction, title: "Отмена", action: {}),
                TextAlertAction(type: .destructiveAction, title: "Очистить", action: {
                    let _ = MonoHistory.clear(postbox: postbox).startStandalone()
                })
            ]))
        },
        changeLimit: { current in
            let options = [1, 2, 4].map { size in
                TextAlertAction(type: size == current ? .defaultAction : .genericAction, title: "\(size) МБ", action: {
                    let _ = MonoHistory.setLimit(postbox: postbox, limitInMB: size).startStandalone()
                })
            }
            present?(textAlertController(context: context, title: "Лимит истории", text: "При уменьшении лимита старые записи удаляются первыми.", actions: [TextAlertAction(type: .genericAction, title: "Отмена", action: {})] + options, actionLayout: .vertical))
        },
        open: { entry in
            var detail = "\(entry.authorName)\nОтправлено \(monoHistoryDate(entry.sentAt))\nЗаписано \(monoHistoryDate(entry.recordedAt))\n\n\(entry.text)"
            if let replacement = entry.replacement {
                detail += "\n\nНовая версия\n\(replacement)"
                let changes = monoHistoryChangeSummary(previous: entry.text, replacement: replacement)
                if !changes.isEmpty {
                    detail += "\n\nИзменения\n\(changes)"
                }
            }
            present?(textAlertController(context: context, title: monoHistoryKind(entry.kind), text: detail, actions: [
                TextAlertAction(type: .defaultAction, title: "Готово", action: {})
            ]))
        },
        export: { asHTML in
            let _ = (MonoHistory.entries(postbox: postbox) |> take(1) |> deliverOnMainQueue).startStandalone(next: { entries in
                guard !entries.isEmpty else {
                    return
                }
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("Monogram-\(UUID().uuidString)").appendingPathExtension(asHTML ? "html" : "json")
                do {
                    let data: Data
                    if asHTML {
                        let body = entries.map { entry in
                            let heading = "\(monoHistoryKind(entry.kind)) · \(entry.chatTitle) · \(monoHistoryDate(entry.recordedAt))"
                            let replacement = entry.replacement.map { "<h3>Новая версия</h3><pre>\(monoHistoryEscapeHTML($0))</pre>" } ?? ""
                            return "<article><h2>\(monoHistoryEscapeHTML(heading))</h2><p>\(monoHistoryEscapeHTML(entry.authorName))</p><pre>\(monoHistoryEscapeHTML(entry.text))</pre>\(replacement)</article>"
                        }.joined(separator: "\n")
                        data = Data(("<!doctype html><html lang=ru><meta charset=utf-8><title>Monogram — История</title><style>body{font:1rem system-ui;margin:2rem;max-width:60rem}pre{white-space:pre-wrap;overflow-wrap:anywhere}</style><h1>История Monogram</h1>" + body + "</html>").utf8)
                    } else {
                        let encoder = JSONEncoder()
                        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                        data = try encoder.encode(entries)
                    }
                    try data.write(to: url, options: [.atomic, .completeFileProtection])
                    if presentExport?(url) != true {
                        try? FileManager.default.removeItem(at: url)
                    }
                } catch {
                    present?(textAlertController(context: context, title: nil, text: "Не удалось экспортировать историю.", actions: [
                        TextAlertAction(type: .defaultAction, title: "Готово", action: {})
                    ]))
                }
            })
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, MonoHistory.entries(postbox: postbox), MonoHistory.configurations(postbox: postbox), search.get())
    |> map { presentationData, records, configuration, query -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let queryText = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = records.reversed().filter { entry in
            queryText.isEmpty || [entry.chatTitle, entry.authorName, entry.text, entry.replacement ?? ""].contains(where: { $0.localizedCaseInsensitiveContains(queryText) })
        }
        var list: [MonoHistoryItem] = [.search(query), .limit(configuration.limitInMB), .exportJSON, .exportHTML, .clear]
        let explanation = records.isEmpty ? "История пуста. Включи нужное сохранение в «Моих функциях»." : "Найдено: \(visible.count). Показаны до 250 последних записей."
        list.append(.status(explanation))
        list.append(contentsOf: visible.prefix(250).enumerated().map { .entry($0.offset, $0.element) })
        let presentation = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(presentationData: presentation, title: .text("История Monogram"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: presentation, entries: list, style: .blocks), arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    present = { [weak controller] alert in
        controller?.present(alert, in: .window(.root))
    }
    presentExport = { [weak controller] url in
        guard var host = controller?.view.window?.rootViewController else {
            return false
        }
        while let presented = host.presentedViewController {
            host = presented
        }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = host.view
            popover.sourceRect = CGRect(x: host.view.bounds.midX, y: host.view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        activity.completionWithItemsHandler = { _, _, _, _ in try? FileManager.default.removeItem(at: url) }
        host.present(activity, animated: true)
        return true
    }
    return controller
}
