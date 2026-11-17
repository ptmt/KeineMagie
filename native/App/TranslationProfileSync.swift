import Foundation
import KeineMagieCore

extension AppModel {
    var canEditShortcuts: Bool { session.phase == .signedIn && session.user != nil && shortcutJournal.migrated && !shortcutStorageFailed }
    func loadShortcuts() {
        guard let owner = session.user?.id, session.phase == .signedIn else { shortcuts = []; return }
        let origin = session.serverURL
        do {
            if shortcutScope?.origin != origin || shortcutScope?.owner != owner {
                shortcutSyncID = nil
                shortcutJournal = try shortcutProfileStore.load(origin: origin, owner: owner)
                shortcutScope = (origin, owner); shortcutStorageFailed = false
            }
            if !shortcutJournal.migrated, session.canWrite {
                let legacy = try TranslationShortcutStore().load(server: origin, owner: owner)
                let selected = legacy.first(where: { $0.id.uuidString == selectedShortcutID })
                var next = shortcutJournal; try next.migrate(legacy)
                try persistShortcuts(next)
                if let selected {
                    selectedShortcutID = TranslationProfile.legacyID(id: selected.id.uuidString, title: selected.title, instruction: selected.instruction).uuidString
                }
            }
            shortcuts = shortcutJournal.shortcuts
            if !shortcutJournal.migrated { shortcuts = try TranslationShortcutStore().load(server: origin, owner: owner) }
        } catch { shortcutStorageFailed = true; shortcutSyncIssue = "shortcut.storage.error" }
    }
    func persistShortcuts(_ next: TranslationProfileJournal) throws {
        guard let scope = shortcutScope, scope.owner == session.user?.id, scope.origin == session.serverURL, session.phase == .signedIn else { throw APIError.missingToken }
        try shortcutProfileStore.save(next, origin: scope.origin, owner: scope.owner)
        shortcutJournal = next; shortcuts = next.shortcuts
        if let selected = selectedShortcutID, selected != "friendly", selected != "formal", !shortcuts.contains(where: { $0.id.uuidString == selected }) { selectedShortcutID = nil }
    }
    func saveShortcut(id: UUID = UUID(), title: String, instruction: String, expectedRevision: Int? = nil) throws {
        loadShortcuts()
        guard session.phase == .signedIn, session.user != nil, !shortcutStorageFailed, shortcutJournal.migrated else { throw APIError.missingToken }
        var next = shortcutJournal; try next.save(id: id, title: title, instruction: instruction, expectedRevision: expectedRevision)
        try persistShortcuts(next)
        Task { await syncShortcuts() }
    }
    func deleteShortcut(_ id: UUID, expectedRevision: Int? = nil) throws {
        loadShortcuts()
        guard session.phase == .signedIn, session.user != nil, !shortcutStorageFailed, shortcutJournal.migrated else { throw APIError.missingToken }
        var next = shortcutJournal; next.delete(id, expectedRevision: expectedRevision)
        try persistShortcuts(next)
        Task { await syncShortcuts() }
    }
    func resolveShortcutConflict(keepBoth: Bool) {
        do { var next = shortcutJournal; next.resolveConflict(keepBoth: keepBoth); try persistShortcuts(next); shortcutSyncIssue = nil; Task { await syncShortcuts() } }
        catch { shortcutSyncIssue = "shortcut.storage.error" }
    }
    func resetShortcuts() {
        // A generation change can be account replacement, not logout. Retain the
        // other owner's offline journal; only explicit revocation/logout purges.
        if let scope = shortcutScope, session.user == nil { try? shortcutProfileStore.remove(origin: scope.origin, owner: scope.owner) }
        shortcutScope = nil; shortcutSyncID = nil; shortcutJournal = TranslationProfileJournal()
        shortcutSyncIssue = nil; shortcutStorageFailed = false; shortcuts = []
    }
    func purgeShortcuts() {
        if let scope = shortcutScope { try? shortcutProfileStore.remove(origin: scope.origin, owner: scope.owner) }
        else if let owner = session.user?.id { try? shortcutProfileStore.remove(origin: session.serverURL, owner: owner) }
        resetShortcuts()
    }
    func syncShortcuts() async {
        guard shortcutSyncID == nil, session.canWrite, !Task.isCancelled else { return }
        loadShortcuts()
        guard !shortcutStorageFailed, let scope = shortcutScope else { return }
        let generation = session.generation, requestID = UUID()
        shortcutSyncID = requestID
        func current() -> Bool { !Task.isCancelled && session.generation == generation && session.user?.id == scope.owner && session.serverURL == scope.origin && shortcutSyncID == requestID }
        defer { if shortcutSyncID == requestID { shortcutSyncID = nil } }
        do {
            let client = try api()
            let remote = try await client.translationProfiles(owner: scope.owner)
            guard current() else { return }
            var next = shortcutJournal; try next.receive(remote); try persistShortcuts(next)
            while current(), !shortcutJournal.pending.isEmpty {
                next = shortcutJournal; next.prioritizeIndependentDeletion(); if next != shortcutJournal { try persistShortcuts(next) }
                guard let op = shortcutJournal.pending.first else { break }
                if op.conflict { shortcutSyncIssue = "shortcut.sync.conflict"; return }
                let value = try await client.translationProfiles(owner: scope.owner, operation: op)
                guard current() else { return }
                next = shortcutJournal; try next.acknowledge(op, value); try persistShortcuts(next)
            }
            if current() { shortcutSyncIssue = nil }
        } catch {
            // Revocation applies even when a content request was superseded.
            if session.generation == generation, session.user?.id == scope.owner, case APIError.http(401) = error {
                // A superseding content reset may already have forgotten the
                // active scope. Revoke the request's captured journal as well.
                try? shortcutProfileStore.remove(origin: scope.origin, owner: scope.owner)
                session.rejectUnauthorized(); resetSessionContent(); return
            }
            guard current() else { return }
            if case APIError.http(409) = error, !shortcutJournal.pending.isEmpty {
                do { var next = shortcutJournal; next.pending[0].conflict = true; try persistShortcuts(next); shortcutSyncIssue = "shortcut.sync.conflict" }
                catch { shortcutSyncIssue = "shortcut.storage.error" }
            } else if case APIError.http(422) = error, !shortcutJournal.pending.isEmpty {
                do { var next = shortcutJournal; next.pending[0].blocked = "limit"; try persistShortcuts(next); shortcutSyncIssue = "shortcut.sync.limit" }
                catch { shortcutSyncIssue = "shortcut.storage.error" }
            } else if case APIError.http(400) = error { shortcutSyncIssue = "shortcut.sync.validation" }
            else { shortcutSyncIssue = "shortcut.sync.pending" }
        }
    }
}
