import AccountContext
import Display
import Foundation
import ItemListUI
import MonoSettings
import PresentationDataUtils
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData

private struct MonoFeedCollection: Codable, Equatable {
    let id: UUID
    let name: String
    var channels: [Int64] = []
    var lastReadPeerId: Int64?
    var lastReadMessage: Int32?
    var mediaOnly = false
    var textOnly: Bool? = nil
    var hideForwards = false
    var excludedWords = ""
}

private struct MonoFeedPost: Equatable {
    let id: EngineMessage.Id
    let channel: String
    let timestamp: Int32
    let text: String
    let media: Bool
    let forwarded: Bool
    let source: EngineMessage.Id?
}

private struct MonoFeedState: Equatable {
    var collections: [MonoFeedCollection]
    var selected = 0
    var posts: [MonoFeedPost] = []
    var channelNames: [Int64: String] = [:]
    var subscribed: [Int64] = []
    var nameInput = ""
    var usernameInput = ""
    var loading = false
    var canLoadMore = false
    var resume = false
    var status = ""

    var current: MonoFeedCollection {
        return collections[selected]
    }
}

private final class MonoFeedModel {
    let state: ValuePromise<MonoFeedState>
    private var current: MonoFeedState
    private let context: AccountContext
    private let key: String
    private let requests = MetaDisposable()
    private let chatList = MetaDisposable()
    private let resolveRequest = MetaDisposable()
    private var pageSize: Int32 = 25

    init(context: AccountContext) {
        self.context = context
        let key = "mono.feed.collections.\(context.account.id.int64)"
        let stored = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([MonoFeedCollection].self, from: $0) } ?? []
        let initial = MonoFeedState(collections: stored.isEmpty ? [MonoFeedCollection(id: UUID(), name: "Моя лента")] : stored)
        self.key = key
        self.current = initial
        self.state = ValuePromise(initial, ignoreRepeated: true)
    }

    deinit {
        requests.dispose()
        chatList.dispose()
        resolveRequest.dispose()
    }

    func loadSubscriptions() {
        chatList.set((combineLatest(
            context.engine.messages.chatList(group: .root, count: 250),
            context.engine.messages.chatList(group: .archive, count: 250)
        )
        |> deliverOnMainQueue).start(next: { [weak self] root, archive in
            guard let self else { return }
            var channels: [Int64] = []
            var names = self.current.channelNames
            var seen = Set<Int64>()
            let contentSettings = self.context.currentContentSettings.with { $0 }
            for item in root.items + archive.items {
                if case let .channel(channel)? = item.renderedPeer.chatMainPeer,
                   case .broadcast = channel.info,
                   channel.restrictionText(platform: "ios", contentSettings: contentSettings) == nil,
                   seen.insert(channel.id.toInt64()).inserted {
                    let id = channel.id.toInt64()
                    channels.append(id)
                    names[id] = channel.title
                }
            }
            self.update { state in
                state.subscribed = channels
                state.channelNames = names
            }
        }))
    }

    func update(_ edit: (inout MonoFeedState) -> Void, save: Bool = false) {
        edit(&current)
        if save, let data = try? JSONEncoder().encode(current.collections) {
            UserDefaults.standard.set(data, forKey: key)
        }
        state.set(current)
    }

    func select(_ index: Int) {
        guard current.collections.indices.contains(index) else { return }
        update { state in
            state.selected = index
            state.resume = false
            state.posts = []
        }
        refresh()
    }

    func addCollection() {
        let name = String(current.nameInput.trimmingCharacters(in: .whitespacesAndNewlines).prefix(48))
        guard !name.isEmpty, current.collections.count < 12 else { return }
        update({ state in
            state.collections.append(MonoFeedCollection(id: UUID(), name: name))
            state.nameInput = ""
        }, save: true)
        select(current.collections.count - 1)
    }

    func toggleChannel(_ id: Int64) {
        if !current.current.channels.contains(id), current.current.channels.count >= 15 {
            update { $0.status = "В одну подборку можно добавить до 15 каналов." }
            return
        }
        update({ state in
            if state.current.channels.contains(id) {
                state.collections[state.selected].channels.removeAll(where: { $0 == id })
            } else {
                state.collections[state.selected].channels.append(id)
            }
            state.posts.removeAll()
            state.resume = false
        }, save: true)
        refresh()
    }

    func addPublicChannel() {
        let name = current.usernameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let collectionId = current.current.id
        resolveRequest.set((context.engine.peers.resolvePeerByName(name: name, referrer: nil) |> deliverOnMainQueue).start(next: { [weak self] result in
            guard let self, self.current.current.id == collectionId, case let .result(peer) = result else { return }
            guard case let .channel(channel)? = peer,
                  case .broadcast = channel.info,
                  channel.restrictionText(platform: "ios", contentSettings: self.context.currentContentSettings.with { $0 }) == nil else {
                self.update { $0.status = "Канал недоступен. Проверь его @username." }
                return
            }
            let id = channel.id.toInt64()
            self.update { state in
                state.usernameInput = ""
                state.channelNames[id] = channel.title
            }
            if !self.current.current.channels.contains(id) {
                self.toggleChannel(id)
            }
        }))
    }

    func refresh(more: Bool = false) {
        if more {
            pageSize = min(100, pageSize + 25)
        } else {
            pageSize = 25
        }
        let channels = current.current.channels
        guard !channels.isEmpty else {
            requests.set(nil)
            update { state in
                state.posts = []
                state.loading = false
                state.status = ""
            }
            return
        }
        let context = self.context
        let collectionId = current.current.id
        let limit = pageSize
        let requests = channels.map { id -> Signal<[MonoFeedPost], NoError> in
            let peerId = EnginePeer.Id(id)
            return context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
            |> mapToSignal { peer -> Signal<[MonoFeedPost], NoError> in
                guard case let .channel(channel)? = peer,
                      case .broadcast = channel.info,
                      channel.restrictionText(platform: "ios", contentSettings: context.currentContentSettings.with { $0 }) == nil else {
                    return .single([])
                }
                return context.engine.messages.searchMessages(location: .peer(peerId: peerId, fromId: nil, tags: nil, reactions: nil, threadId: nil, minDate: nil, maxDate: nil), query: "", state: nil, limit: limit)
                |> map { result, _ in
                    result.messages.compactMap { message in
                        guard !message.attributes.contains(where: { $0 is RestrictedContentMessageAttribute || $0 is AutoclearTimeoutMessageAttribute || $0 is AutoremoveTimeoutMessageAttribute }), !message.text.isEmpty || !message.media.isEmpty else {
                            return nil
                        }
                        return MonoFeedPost(id: message.id, channel: channel.title, timestamp: message.timestamp, text: message.text, media: !message.media.isEmpty, forwarded: message.forwardInfo != nil, source: message.forwardInfo?.sourceMessageId)
                    }
                }
            }
        }
        update { state in
            state.loading = true
            state.canLoadMore = limit < 100
            state.status = ""
        }
        self.requests.set((combineLatest(requests) |> take(1) |> deliverOnMainQueue).start(next: { [weak self] batches in
            guard let self, self.current.current.id == collectionId else { return }
            var posts: [MonoFeedPost] = []
            for batch in batches {
                posts.append(contentsOf: batch)
            }
            posts.sort { lhs, rhs in
                if lhs.timestamp != rhs.timestamp {
                    return lhs.timestamp > rhs.timestamp
                }
                let lhsPeer = lhs.id.peerId.toInt64()
                let rhsPeer = rhs.id.peerId.toInt64()
                if lhsPeer != rhsPeer {
                    return lhsPeer > rhsPeer
                }
                return lhs.id.id > rhs.id.id
            }
            self.update { state in
                state.loading = false
                state.posts = posts
            }
        }))
    }

    func recordRead(_ post: MonoFeedPost) {
        guard MonoSettings.shared.isEnabled(MonoFeatureKey.feedRememberPosition) else { return }
        update({ state in
            state.collections[state.selected].lastReadPeerId = post.id.peerId.toInt64()
            state.collections[state.selected].lastReadMessage = post.id.id
        }, save: true)
    }
}

private final class MonoFeedArguments {
    let perform: (MonoFeedAction) -> Void
    let update: (Int, String) -> Void

    init(perform: @escaping (MonoFeedAction) -> Void, update: @escaping (Int, String) -> Void) {
        self.perform = perform
        self.update = update
    }
}

private enum MonoFeedAction: Equatable {
    case select(Int)
    case add
    case subscribe(Int64)
    case addPublic
    case filterMedia
    case filterText
    case filterForwards
    case resume
    case refresh
    case loadMore
    case post(MonoFeedPost)
}

private enum MonoFeedItem: ItemListNodeEntry {
    case action(Int, ItemListSectionId, String, String, MonoFeedAction)
    case input(Int, ItemListSectionId, String, String)
    case text(Int, ItemListSectionId, String)

    var section: ItemListSectionId {
        switch self {
        case let .action(_, section, _, _, _), let .input(_, section, _, _), let .text(_, section, _):
            return section
        }
    }

    var stableId: Int {
        switch self {
        case let .action(id, _, _, _, _), let .input(id, _, _, _), let .text(id, _, _):
            return id
        }
    }

    static func < (lhs: MonoFeedItem, rhs: MonoFeedItem) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! MonoFeedArguments
        switch self {
        case let .action(_, _, title, label, action):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, labelStyle: .detailText, sectionId: section, style: .blocks, action: { arguments.perform(action) })
        case let .input(id, _, placeholder, text):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: ""), text: text, placeholder: placeholder, returnKeyType: .done, spacing: 3.0, clearType: .always, sectionId: section, textUpdated: { arguments.update(id, $0) }, action: {}, dismissKeyboardOnEnter: true)
        case let .text(_, _, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        }
    }
}

func monoFeedController(context: AccountContext) -> ViewController {
    let model = MonoFeedModel(context: context)
    var openPost: ((MonoFeedPost) -> Void)?
    let arguments = MonoFeedArguments(perform: { action in
        switch action {
        case let .select(index): model.select(index)
        case .add: model.addCollection()
        case let .subscribe(id): model.toggleChannel(id)
        case .addPublic: model.addPublicChannel()
        case .filterMedia:
            model.update({ state in
                let index = state.selected
                state.collections[index].mediaOnly.toggle()
                if state.collections[index].mediaOnly { state.collections[index].textOnly = false }
            }, save: true)
        case .filterText:
            model.update({ state in
                let index = state.selected
                let enabled = state.collections[index].textOnly == true
                state.collections[index].textOnly = !enabled
                if !enabled { state.collections[index].mediaOnly = false }
            }, save: true)
        case .filterForwards: model.update({ $0.collections[$0.selected].hideForwards.toggle() }, save: true)
        case .resume: model.update { $0.resume.toggle() }
        case .refresh: model.refresh()
        case .loadMore: model.refresh(more: true)
        case let .post(post):
            model.recordRead(post)
            openPost?(post)
        }
    }, update: { id, text in
        switch id {
        case 20: model.update { $0.nameInput = text }
        case 30: model.update { $0.usernameInput = text }
        case 40: model.update({ $0.collections[$0.selected].excludedWords = text }, save: true)
        default: break
        }
    })

    let signal = combineLatest(context.sharedContext.presentationData, model.state.get())
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [MonoFeedItem] = state.collections.enumerated().map { index, collection in
            .action(index, 0, collection.name, index == state.selected ? "Выбрано" : "", .select(index))
        }
        entries.append(.input(20, 0, "Название новой подборки", state.nameInput))
        entries.append(.action(21, 0, "Создать подборку", "", .add))
        entries.append(.input(30, 1, "@username публичного канала", state.usernameInput))
        entries.append(.action(31, 1, "Добавить канал", "", .addPublic))
        let selected = state.current
        var added = Set<Int64>()
        let available = (selected.channels + state.subscribed).filter { added.insert($0).inserted }
        for (index, channel) in available.prefix(80).enumerated() {
            entries.append(.action(100 + index, 1, state.channelNames[channel] ?? "Канал \(channel)", selected.channels.contains(channel) ? "В подборке" : "", .subscribe(channel)))
        }
        entries.append(.input(40, 2, "Исключить слова через запятую", selected.excludedWords))
        entries.append(.action(41, 2, "Только публикации с медиа", selected.mediaOnly ? "Вкл." : "Выкл.", .filterMedia))
        entries.append(.action(42, 2, "Скрыть репосты", selected.hideForwards ? "Вкл." : "Выкл.", .filterForwards))
        entries.append(.action(43, 2, "Обновить ленту", "", .refresh))
        if selected.lastReadMessage != nil && MonoSettings.shared.isEnabled(MonoFeatureKey.feedRememberPosition) {
            entries.append(.action(44, 2, state.resume ? "К новым публикациям" : "Продолжить чтение", "", .resume))
        }
        entries.append(.action(45, 2, "Только текст", selected.textOnly == true ? "Вкл." : "Выкл.", .filterText))
        if !state.status.isEmpty {
            entries.append(.text(180, 2, state.status))
        }
        let filterWords = selected.excludedWords.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var seen = Set<EngineMessage.Id>()
        let deduplicate = MonoSettings.shared.isEnabled(MonoFeatureKey.feedDedup)
        var posts = state.posts.filter { post in
            (!selected.mediaOnly || post.media) && (selected.textOnly != true || !post.media) && (!selected.hideForwards || !post.forwarded)
                && !filterWords.contains(where: { post.text.localizedCaseInsensitiveContains($0) })
                && (!deduplicate || seen.insert(post.source ?? post.id).inserted)
        }
        if state.resume, let readIndex = posts.firstIndex(where: { $0.id.id == selected.lastReadMessage && $0.id.peerId.toInt64() == selected.lastReadPeerId }) {
            posts = Array(posts.dropFirst(readIndex))
        }
        if state.loading {
            entries.append(.text(200, 3, "Загрузка публикаций…"))
        } else if posts.isEmpty {
            entries.append(.text(200, 3, selected.channels.isEmpty ? "Добавь каналы в подборку." : "Подходящих публикаций нет."))
        }
        for (index, post) in posts.enumerated() {
            let date = DateFormatter.localizedString(from: Date(timeIntervalSince1970: TimeInterval(post.timestamp)), dateStyle: .short, timeStyle: .short)
            let title = "\(post.channel) · \(date)"
            entries.append(.action(201 + index, 3, title, post.text.isEmpty ? "Медиа" : String(post.text.prefix(120)), .post(post)))
        }
        if !state.loading && state.canLoadMore && !selected.channels.isEmpty {
            entries.append(.action(1900, 3, "Загрузить больше", "", .loadMore))
        }
        let presentation = ItemListPresentationData(presentationData)
        let controller = ItemListControllerState(presentationData: presentation, title: .text("Лента каналов"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (controller, (ItemListNodeState(presentationData: presentation, entries: entries.sorted(), style: .blocks), arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    openPost = { [weak controller] post in
        guard let controller else { return }
        let preview = post.text.isEmpty ? "Медиа доступно в самом канале." : post.text
        controller.present(textAlertController(context: context, title: post.channel, text: preview, actions: [
            TextAlertAction(type: .genericAction, title: "Закрыть", action: {}),
            TextAlertAction(type: .defaultAction, title: "Открыть в канале", action: { [weak controller] in
                let peer = context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: post.id.peerId))
                let _ = (peer |> take(1) |> deliverOnMainQueue).startStandalone(next: { [weak controller] peer in
                    guard let peer, let navigation = controller?.navigationController as? NavigationController else {
                        return
                    }
                    context.sharedContext.navigateToChatController(NavigateToChatControllerParams(
                        navigationController: navigation,
                        context: context,
                        chatLocation: .peer(peer),
                        subject: .message(id: .id(post.id), highlight: nil, timecode: nil, setupReply: false),
                        keepStack: .always
                    ))
                })
            })
        ], actionLayout: .vertical), in: .window(.root))
    }
    model.loadSubscriptions()
    model.refresh()
    return controller
}
