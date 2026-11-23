import Foundation
import Postbox
import SwiftSignalKit
import MonoSettings

public struct MonoHistoryEntry: Codable, Equatable {
    public enum Kind: String, Codable {
        case deleted
        case edited
        case archived
    }

    public let kind: Kind
    public let peerId: Int64
    public let chatTitle: String
    public let authorName: String
    public let messageId: Int32
    public let sentAt: Int32
    public let recordedAt: Int32
    public let text: String
    public let replacement: String?

    fileprivate var identity: String {
        let key = "\(kind.rawValue):\(peerId):\(messageId)"
        if kind == .edited {
            return "\(key):\(recordedAt):\(text):\(replacement ?? "")"
        }
        return key
    }
}

public struct MonoHistoryConfiguration: Codable, Equatable {
    public let archivePeerIds: Set<Int64>
    public let limitInMB: Int
}

private struct MonoHistoryRecords: Codable {
    let entries: [MonoHistoryEntry]
}

public enum MonoHistory {
    private static let configurationKey = applicationSpecificPreferencesKey(470)
    private static let recordsKey = applicationSpecificPreferencesKey(471)
    private static let defaultConfiguration = MonoHistoryConfiguration(archivePeerIds: [], limitInMB: 2)
    private static let recordLimit = 1500

    static func configuration(transaction: Transaction) -> MonoHistoryConfiguration {
        return transaction.getPreferencesEntry(key: configurationKey)?.get(MonoHistoryConfiguration.self) ?? defaultConfiguration
    }

    public static func configurations(postbox: Postbox) -> Signal<MonoHistoryConfiguration, NoError> {
        return postbox.preferencesView(keys: [configurationKey])
        |> map { view in
            view.values[configurationKey]?.get(MonoHistoryConfiguration.self) ?? defaultConfiguration
        }
        |> distinctUntilChanged
    }

    public static func entries(postbox: Postbox) -> Signal<[MonoHistoryEntry], NoError> {
        return postbox.preferencesView(keys: [recordsKey])
        |> map { view in
            view.values[recordsKey]?.get(MonoHistoryRecords.self)?.entries ?? []
        }
    }

    public static func clear(postbox: Postbox) -> Signal<Void, NoError> {
        return postbox.transaction { transaction in
            transaction.updatePreferencesEntry(key: recordsKey, { _ in nil })
        }
    }

    public static func setLimit(postbox: Postbox, limitInMB: Int) -> Signal<Void, NoError> {
        return postbox.transaction { transaction in
            let current = configuration(transaction: transaction)
            let updated = MonoHistoryConfiguration(archivePeerIds: current.archivePeerIds, limitInMB: min(4, max(1, limitInMB)))
            transaction.updatePreferencesEntry(key: configurationKey, { _ in PreferencesEntry(updated) })
            save([], transaction: transaction, configuration: updated, enforceLimit: true)
        }
    }

    public static func archiveMenuState(postbox: Postbox, peerId: PeerId) -> Signal<Bool?, NoError> {
        return postbox.transaction { transaction -> Bool? in
            guard canArchive(peerId: peerId, transaction: transaction) else {
                return nil
            }
            return configuration(transaction: transaction).archivePeerIds.contains(peerId.toInt64())
        }
    }

    public static func toggleArchive(postbox: Postbox, peerId: PeerId) -> Signal<Bool, NoError> {
        return postbox.transaction { transaction in
            guard canArchive(peerId: peerId, transaction: transaction) else {
                return false
            }
            let current = configuration(transaction: transaction)
            var peers = current.archivePeerIds
            let rawPeerId = peerId.toInt64()
            let isEnabled = peers.insert(rawPeerId).inserted
            if !isEnabled {
                peers.remove(rawPeerId)
            }
            let updated = MonoHistoryConfiguration(archivePeerIds: peers, limitInMB: current.limitInMB)
            transaction.updatePreferencesEntry(key: configurationKey, { _ in PreferencesEntry(updated) })
            if isEnabled {
                var entries: [MonoHistoryEntry] = []
                var scanned = 0
                transaction.withAllMessages(peerId: peerId, namespace: Namespaces.Message.Cloud, reversed: true) { message in
                    scanned += 1
                    if let entry = snapshot(message, kind: .archived, transaction: transaction) {
                        entries.append(entry)
                    }
                    return scanned < 500
                }
                save(Array(entries.reversed()), transaction: transaction, configuration: updated)
            }
            return isEnabled
        }
    }

    static func canArchive(peerId: PeerId, transaction: Transaction) -> Bool {
        guard let peer = transaction.getPeer(peerId),
              peerId.namespace != Namespaces.Peer.SecretChat,
              peer.restrictionText(platform: "ios", contentSettings: getContentSettings(transaction: transaction)) == nil else {
            return false
        }
        if let group = peer as? TelegramGroup, group.flags.contains(.copyProtectionEnabled) {
            return false
        }
        if let channel = peer as? TelegramChannel, channel.flags.contains(.copyProtectionEnabled) {
            return false
        }
        if let data = transaction.getPeerCachedData(peerId: peerId) as? CachedUserData, data.flags.contains(.copyProtectionEnabled) {
            return false
        }
        return true
    }

    static func snapshot(_ message: Message, kind: MonoHistoryEntry.Kind, transaction: Transaction, replacement: String? = nil, recordedAt: Int32? = nil) -> MonoHistoryEntry? {
        guard message.id.namespace == Namespaces.Message.Cloud,
              !message.flags.contains(.CopyProtected),
              !message.containsSecretMedia,
              !message.attributes.contains(where: { $0 is AutoclearTimeoutMessageAttribute || $0 is AutoremoveTimeoutMessageAttribute || $0 is RestrictedContentMessageAttribute }),
              !message.text.isEmpty,
              canArchive(peerId: message.id.peerId, transaction: transaction) else {
            return nil
        }

        return MonoHistoryEntry(
            kind: kind,
            peerId: message.id.peerId.toInt64(),
            chatTitle: String((transaction.getPeer(message.id.peerId)?.debugDisplayTitle ?? "Чат").prefix(256)),
            authorName: String((message.author?.debugDisplayTitle ?? "").prefix(256)),
            messageId: message.id.id,
            sentAt: message.timestamp,
            recordedAt: recordedAt ?? Int32(clamping: Int64(Date().timeIntervalSince1970)),
            text: String(message.text.prefix(8192)),
            replacement: replacement.map { String($0.prefix(8192)) }
        )
    }

    static func save(_ entries: [MonoHistoryEntry], transaction: Transaction, configuration: MonoHistoryConfiguration, enforceLimit: Bool = false) {
        guard !entries.isEmpty || enforceLimit else {
            return
        }
        transaction.updatePreferencesEntry(key: recordsKey, { current in
            var records = current?.get(MonoHistoryRecords.self)?.entries ?? []
            var incoming = Set<String>()
            let additions = entries.reversed().filter { incoming.insert($0.identity).inserted }.reversed()
            records.removeAll(where: { incoming.contains($0.identity) })
            records.append(contentsOf: additions)
            records = Array(records.suffix(recordLimit))

            let limit = min(4, max(1, configuration.limitInMB)) * 1_048_576
            let encoder = JSONEncoder()
            while !records.isEmpty, let encoded = try? encoder.encode(records), encoded.count > limit {
                let removeCount = max(1, records.count * (encoded.count - limit) / encoded.count)
                records.removeFirst(removeCount)
            }
            return records.isEmpty ? nil : PreferencesEntry(MonoHistoryRecords(entries: records))
        })
    }
}
