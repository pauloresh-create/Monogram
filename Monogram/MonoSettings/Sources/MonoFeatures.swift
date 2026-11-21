import Foundation
import SGAppGroupIdentifier

// Single source of truth for every Mono toggle: title, short description, group and default.
// The settings screen is generated from this list, so adding a feature = adding one entry here.

public enum MonoFeatureGroup: Int32, CaseIterable {
    case ghost
    case history
    case privacy
    case convenience
    case appearance
    case feed
    case risky

    public var title: String {
        switch self {
        case .ghost: return "РЕЖИМ ПРИЗРАКА"
        case .history: return "ИСТОРИЯ СООБЩЕНИЙ"
        case .privacy: return "ПРИВАТНОСТЬ"
        case .convenience: return "УДОБСТВО"
        case .appearance: return "ВНЕШНИЙ ВИД"
        case .feed: return "ЛЕНТА"
        case .risky: return "ЭКСПЕРИМЕНТАЛЬНОЕ"
        }
    }

    public var footer: String? {
        switch self {
        case .ghost: return "Работает только для этого устройства. Отправка сообщения может кратко показать «в сети» — это происходит на стороне сервера."
        case .history: return "Сохраняется только то, что успело прийти на телефон до удаления или правки."
        case .risky: return "Эти функции обходят ограничения Telegram и могут привести к ограничению аккаунта. Используйте на свой риск."
        default: return nil
        }
    }
}

public struct MonoFeature: Equatable {
    public let key: String
    public let title: String
    public let subtitle: String
    public let group: MonoFeatureGroup
    public let defaultValue: Bool
    /// Feature that needs another one enabled to make sense (e.g. "read on reply" needs "hide read").
    public let requires: String?

    public init(_ key: String, _ title: String, _ subtitle: String, group: MonoFeatureGroup, defaultValue: Bool = false, requires: String? = nil) {
        self.key = key
        self.title = title
        self.subtitle = subtitle
        self.group = group
        self.defaultValue = defaultValue
        self.requires = requires
    }
}

public enum MonoFeatureKey {
    public static let hideOnline = "mono.ghost.hideOnline"
    public static let hideTyping = "mono.ghost.hideTyping"
    public static let hideRead = "mono.ghost.hideRead"
    public static let readOnReply = "mono.ghost.readOnReply"
    public static let anonymousStories = "mono.ghost.anonymousStories"
    public static let ghostQuickToggle = "mono.ghost.quickToggle"
    public static let ghostExceptions = "mono.ghost.exceptions"
    public static let cleanUI = "mono.ui.clean"
    public static let hideSponsored = "mono.ui.hideSponsored"

    public static let keepDeleted = "mono.history.keepDeleted"
    public static let keepDeletedMedia = "mono.history.keepDeletedMedia"
    public static let editHistory = "mono.history.editHistory"
    public static let localArchive = "mono.history.localArchive"
    public static let messageFilters = "mono.history.filters"

    public static let chatLock = "mono.privacy.chatLock"
    public static let hiddenChats = "mono.privacy.hiddenChats"
    public static let streamerMode = "mono.privacy.streamerMode"
    public static let streamerAuto = "mono.privacy.streamerAuto"
    public static let kaboom = "mono.privacy.kaboom"
    public static let fakePasscode = "mono.privacy.fakePasscode"

    public static let customMenu = "mono.conv.customMenu"
    public static let unlimitedPins = "mono.conv.unlimitedPins"
    public static let forwardNoAuthor = "mono.conv.forwardNoAuthor"
    public static let deleteForAllDefault = "mono.conv.deleteForAll"
    public static let contactNotes = "mono.conv.contactNotes"
    public static let confirmActions = "mono.conv.confirm"
    public static let quickActions = "mono.conv.quickActions"
    public static let extendedProfile = "mono.conv.extendedProfile"
    public static let jumpToFirst = "mono.conv.jumpToFirst"
    public static let scheduleTemplates = "mono.conv.scheduleTemplates"
    public static let quickReplies = "mono.conv.quickReplies"
    public static let memberMessages = "mono.conv.memberMessages"
    public static let translate = "mono.conv.translate"
    public static let deviceSync = "mono.conv.sync"

    public static let avatarShape = "mono.look.avatarShape"
    public static let altIcons = "mono.look.altIcons"
    public static let compactMode = "mono.look.compact"
    public static let hideElements = "mono.look.hideElements"
    public static let customThemes = "mono.look.themes"
    public static let reduceAnimations = "mono.look.reduceAnimations"

    public static let feed = "mono.feed.enabled"
    public static let feedDedup = "mono.feed.dedup"
    public static let feedRememberPosition = "mono.feed.rememberPosition"

    public static let ignoreRestrictions = "mono.risky.ignoreRestrictions"
    public static let saveProtected = "mono.risky.saveProtected"
    public static let saveViewOnce = "mono.risky.saveViewOnce"
    public static let hideScreenshotNotice = "mono.risky.hideScreenshot"
}

public enum MonoFeatures {
    private typealias K = MonoFeatureKey

    public static let all: [MonoFeature] = [
        // Ghost
        MonoFeature(K.ghostQuickToggle, "Кнопка призрака", "Иконка над списком чатов включает и выключает призрак одним нажатием", group: .ghost, defaultValue: true),
        MonoFeature(K.hideOnline, "Скрыть «в сети»", "Собеседники видят «был(а) недавно», даже когда ты в приложении", group: .ghost),
        MonoFeature(K.hideTyping, "Скрыть «печатает»", "Не показывать, что ты печатаешь, записываешь голосовое или выбираешь стикер", group: .ghost),
        MonoFeature(K.hideRead, "Скрыть прочтение", "У собеседника остаётся одна галочка. Прочитать можно вручную из меню чата", group: .ghost),
        MonoFeature(K.readOnReply, "Читать при ответе", "Когда ты отвечаешь в чате, прочтение отправляется автоматически", group: .ghost, defaultValue: true, requires: K.hideRead),
        MonoFeature(K.anonymousStories, "Анонимные сторис", "Твой просмотр не попадает в список зрителей", group: .ghost),
        MonoFeature(K.ghostExceptions, "Исключения", "Выбранные чаты видят тебя как обычно. Настраивается долгим нажатием на чат", group: .ghost),

        // History
        MonoFeature(K.keepDeleted, "Сохранять удалённые", "Удалённые собеседником сообщения остаются с пометкой 🗑", group: .history),
        MonoFeature(K.keepDeletedMedia, "Сохранять медиа удалённых", "Фото, видео и голосовые тоже остаются, если успели загрузиться", group: .history, requires: K.keepDeleted),
        MonoFeature(K.editHistory, "История правок", "У изменённых сообщений можно посмотреть все прошлые версии", group: .history),
        MonoFeature(K.localArchive, "Локальный архив", "Переписка выбранных чатов хранится на телефоне и не стирается при очистке кэша", group: .history),
        MonoFeature(K.messageFilters, "Фильтры сообщений", "Скрывать сообщения по словам или от конкретных людей в группах", group: .history),

        // Privacy
        MonoFeature(K.chatLock, "Пароль на чаты", "Отдельные чаты и папки открываются только по Face ID или коду", group: .privacy),
        MonoFeature(K.hiddenChats, "Скрытые чаты", "Чаты и аккаунты появляются только после секретного жеста", group: .privacy),
        MonoFeature(K.streamerMode, "Режим стримера", "Размывает номера, имена, аватарки и превью сообщений", group: .privacy),
        MonoFeature(K.streamerAuto, "Автоматически при записи", "Режим стримера включается сам, когда идёт запись или трансляция экрана", group: .privacy, defaultValue: true, requires: K.streamerMode),
        MonoFeature(K.kaboom, "Kaboom", "Кнопка экстренного выхода из всех аккаунтов и стирания данных приложения", group: .privacy),
        MonoFeature(K.fakePasscode, "Ложный код", "Особый код на экране блокировки запускает Kaboom", group: .privacy, requires: K.kaboom),

        // Convenience
        MonoFeature(K.customMenu, "Своё меню сообщения", "Выбери, какие пункты показывать при долгом нажатии и в каком порядке", group: .convenience),
        MonoFeature(K.unlimitedPins, "Без лимита закрепов", "Закрепляй сколько угодно чатов. Сверх лимита — только на этом телефоне", group: .convenience),
        MonoFeature(K.forwardNoAuthor, "Пересылка без автора", "Кнопка «Переслать без подписи» в меню и окне пересылки", group: .convenience, defaultValue: true),
        MonoFeature(K.deleteForAllDefault, "«Удалить для всех» сразу", "Галочка удаления у собеседника стоит по умолчанию", group: .convenience),
        MonoFeature(K.contactNotes, "Заметки о людях", "Своё имя и заметка к любому человеку, видны только тебе", group: .convenience),
        MonoFeature(K.confirmActions, "Подтверждения", "Спрашивать перед звонком, отправкой стикера, GIF или голосового", group: .convenience),
        MonoFeature(K.quickActions, "Быстрые действия", "Двойной тап по сообщению, копирование части текста, «В Избранное» в один тап", group: .convenience, defaultValue: true),
        MonoFeature(K.extendedProfile, "Подробный профиль", "ID, дата-центр, примерная дата регистрации и первое сообщение в чате", group: .convenience, defaultValue: true),
        MonoFeature(K.jumpToFirst, "К началу чата", "Кнопки «К первому сообщению» и «К дате…» в меню чата", group: .convenience, defaultValue: true),
        MonoFeature(K.scheduleTemplates, "Быстрое отложенное", "Долгое нажатие на «Отправить»: через час, завтра в 9:00, свои варианты", group: .convenience),
        MonoFeature(K.quickReplies, "Шаблоны ответов", "Сохранённые фразы по «/» или кнопке у поля ввода", group: .convenience),
        MonoFeature(K.memberMessages, "Сообщения участника", "В профиле участника группы — все его сообщения в этой группе", group: .convenience, defaultValue: true),
        MonoFeature(K.translate, "Перевод", "Перевод входящих и исходящих встроенным переводчиком iOS, без внешних серверов", group: .convenience),
        MonoFeature(K.deviceSync, "Синхронизация устройств", "Удалённые, правки, заметки и настройки одинаковы на iPhone и iPad через iCloud", group: .convenience),

        // Appearance
        MonoFeature(K.avatarShape, "Форма аватарок", "Круг, скруглённый квадрат или квадрат", group: .appearance),
        MonoFeature(K.altIcons, "Иконки приложения", "Альтернативные иконки, включая маскировочные", group: .appearance),
        MonoFeature(K.compactMode, "Компактный режим", "Плотнее список чатов, меньше пузыри, отдельный размер шрифта", group: .appearance),
        MonoFeature(K.hideElements, "Скрыть лишнее", "Сторис, реакции, счётчики просмотров, Premium-значки, эмодзи-статусы", group: .appearance),
        MonoFeature(K.cleanUI, "Без Premium и подарков", "Убрать баннеры Premium, подарки, звёзды и витрину мини-приложений", group: .appearance, defaultValue: true),
        MonoFeature(K.hideSponsored, "Без рекламы в каналах", "Не загружать спонсорские сообщения", group: .appearance, defaultValue: true),
        MonoFeature(K.customThemes, "Свои темы", "Цвет акцента, фон, шрифт, экспорт и импорт темы", group: .appearance),
        MonoFeature(K.reduceAnimations, "Меньше анимаций", "Без полноэкранных эффектов, статичные стикеры, экономия батареи", group: .appearance),

        // Feed
        MonoFeature(K.feed, "Лента постов", "Вкладка с постами из выбранных каналов в одной ленте", group: .feed),
        MonoFeature(K.feedDedup, "Убирать дубли", "Один и тот же репост из разных каналов показывается один раз", group: .feed, defaultValue: true, requires: K.feed),
        MonoFeature(K.feedRememberPosition, "Помнить место", "Лента открывается там, где ты остановился", group: .feed, defaultValue: true, requires: K.feed),

        // Risky
        MonoFeature(K.ignoreRestrictions, "Каналы с ограничениями", "Открывать каналы, скрытые для iOS", group: .risky),
        MonoFeature(K.saveProtected, "Сохранять защищённое", "Копирование и сохранение там, где автор запретил пересылку", group: .risky),
        MonoFeature(K.saveViewOnce, "Сохранять одноразовые", "Фото и видео «просмотреть один раз» сохраняются в галерею", group: .risky),
        MonoFeature(K.hideScreenshotNotice, "Скрыть скриншот", "В секретных чатах собеседник не узнает о скриншоте", group: .risky),
    ]

    /// Features that already work in this build; the settings screen shows only these.
    public static let implemented: Set<String> = [
        K.hideOnline,
        K.hideTyping,
        K.hideRead,
        K.readOnReply,
        K.anonymousStories,
        K.ghostExceptions,
        K.hideSponsored,
    ]

    public static func visibleFeatures(in group: MonoFeatureGroup) -> [MonoFeature] {
        return features(in: group).filter { implemented.contains($0.key) }
    }

    public static func features(in group: MonoFeatureGroup) -> [MonoFeature] {
        return all.filter { $0.group == group }
    }

    public static func feature(forKey key: String) -> MonoFeature? {
        return all.first { $0.key == key }
    }
}

// Thin storage layer. Shared app group so extensions (notifications, share) see the same values.
public final class MonoSettings {
    public static let shared = MonoSettings()

    private let defaults: UserDefaults

    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? MonoSettings.makeDefaults()
    }

    private static func makeDefaults() -> UserDefaults {
        return UserDefaults(suiteName: sgAppGroupIdentifier()) ?? .standard
    }

    public func isEnabled(_ key: String) -> Bool {
        guard let feature = MonoFeatures.feature(forKey: key) else {
            return false
        }
        if let parent = feature.requires, !isEnabled(parent) {
            return false
        }
        if defaults.object(forKey: key) == nil {
            return feature.defaultValue
        }
        return defaults.bool(forKey: key)
    }

    /// Raw stored value, ignoring the `requires` chain (used by the settings screen).
    public func storedValue(_ key: String) -> Bool {
        guard defaults.object(forKey: key) != nil else {
            return MonoFeatures.feature(forKey: key)?.defaultValue ?? false
        }
        return defaults.bool(forKey: key)
    }

    public func set(_ key: String, _ value: Bool) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: MonoSettings.didChange, object: key)
    }

    // Master ghost switch from the chat list button: flips all ghost features at once.
    private static let ghostKeys = [MonoFeatureKey.hideOnline, MonoFeatureKey.hideTyping, MonoFeatureKey.hideRead, MonoFeatureKey.anonymousStories]

    public var isGhostActive: Bool {
        return MonoSettings.ghostKeys.contains { isEnabled($0) }
    }

    public func setGhost(_ active: Bool) {
        MonoSettings.ghostKeys.forEach { set($0, active) }
    }

    // Ghost exceptions: chats (raw PeerId.toInt64() values) that see you normally.
    private static let exceptionsKey = "mono.ghost.exceptionPeers"

    public var ghostExceptionPeerIds: Set<Int64> {
        let raw = defaults.array(forKey: MonoSettings.exceptionsKey) as? [NSNumber] ?? []
        return Set(raw.map { $0.int64Value })
    }

    public func isGhostException(peerId: Int64) -> Bool {
        return isEnabled(MonoFeatureKey.ghostExceptions) && ghostExceptionPeerIds.contains(peerId)
    }

    public func setGhostException(peerId: Int64, _ excluded: Bool) {
        var updated = ghostExceptionPeerIds
        if excluded {
            updated.insert(peerId)
        } else {
            updated.remove(peerId)
        }
        defaults.set(updated.map { NSNumber(value: $0) }, forKey: MonoSettings.exceptionsKey)
        NotificationCenter.default.post(name: MonoSettings.didChange, object: MonoSettings.exceptionsKey)
    }

    // One-shot permissions to send a read mark while hideRead is on (manual read, read on reply).
    private let readPermissionLock = NSLock()
    private var readPermissions = Set<Int64>()

    public func grantReadPermission(peerId: Int64) {
        readPermissionLock.lock()
        readPermissions.insert(peerId)
        readPermissionLock.unlock()
    }

    /// Returns true once per grant.
    public func consumeReadPermission(peerId: Int64) -> Bool {
        readPermissionLock.lock()
        defer { readPermissionLock.unlock() }
        return readPermissions.remove(peerId) != nil
    }

    /// A ghost feature applies to this chat: the feature is on and the chat is not an exception.
    /// `peerId` is nil for actions not tied to a chat.
    public func ghostApplies(_ key: String, peerId: Int64?) -> Bool {
        guard isEnabled(key) else {
            return false
        }
        if let peerId, isGhostException(peerId: peerId) {
            return false
        }
        return true
    }

    public static let didChange = Notification.Name("MonoSettingsDidChange")
}
