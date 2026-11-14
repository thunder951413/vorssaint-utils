// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// English strings for the personal YTools + mac_gesture integration modules:
/// Jianguoyun YTCE2 E2EE Clipboard Cloud Sync, System Dictionary & Spelling,
/// Interactive Path Browser + Safe File Transfer, Large Type (⌘L),
/// Trackpad Multi-Touch Gestures, and Global Chord Key Remaps.
enum YToolsStrings {
    // MARK: - Clipboard Cloud Sync (Jianguoyun WebDAV · YTCE2)
    static let syncSectionTitle = "Cloud Sync (Jianguoyun WebDAV · E2EE)"
    static let syncEnableToggle = "Sync clipboard across devices"
    static let syncCaption = "End-to-end encrypted with PBKDF2-SHA256 (600,000 rounds) and AES-256-GCM using the YTCE2 wire format shared with YTools for Windows. Unchanged 4 KB device heads are polled every 15 minutes without downloading ciphertext."
    static let syncFolderLabel = "Remote WebDAV folder"
    static let syncFolderPlaceholder = "YTools"
    static let syncPropagateDeletes = "Propagate item deletions to other synced devices"
    static let syncPropagateDeletesCaption = "Writes encrypted tombstones so clearing or deleting an entry removes it on paired Windows and Mac clients."
    static let syncConfigureCredentials = "Configure Jianguoyun Credentials…"
    static let syncUpdateCredentials = "Update Credentials…"
    static let syncNowButton = "Sync Now"
    static let syncCredentialsConfigured = "Keychain vault ready"
    static let syncCredentialsMissing = "Credentials required"
    static let syncModalTitle = "Jianguoyun WebDAV & E2EE Key"
    static let syncAccountLabel = "Jianguoyun account email"
    static let syncAppPasswordLabel = "WebDAV app password"
    static let syncPassphraseLabel = "End-to-end sync passphrase (12+ characters)"
    static let syncPassphraseHint = "Must match the exact passphrase set in YTools on your Windows PC. Stored only in your macOS Keychain-protected local vault—never exported in Settings backups."
    static let syncSaveButton = "Save to Vault"
    static let syncCancelButton = "Cancel"

    // MARK: - Command Bar YTools Extensions
    static let extensionsSectionTitle = "YTools Extensions"
    static let extensionsSectionFooter = "Offline dictionary, spelling, interactive path navigation, atomic no-overwrite file transfer, Pinyin file matching, and Large Type."
    static let dictionaryToggle = "System Dictionary lookup (define / dict)"
    static let dictionaryAutoToggle = "Automatically define single English words without a prefix"
    static let spellToggle = "English spelling suggestions (spell)"
    static let directoryNavToggle = "Interactive folder navigation (/ and ~) & safe copy/move"
    static let pinyinFilesToggle = "Match Chinese Pinyin & initials in file and clipboard search"
    static let largeTypeToggle = "Large Type banner (⌘L on any row)"

    // MARK: - Command Bar Row Actions & Subtitles
    static let actionLargeType = "Show in Large Type"
    static let actionCopyToFolder = "Safe Copy to Folder…"
    static let actionMoveToFolder = "Safe Move to Folder…"
    static let actionBufferAdd = "Add to File Buffer"
    static let actionBufferCopyAll = "Copy Buffered Files Here…"
    static let actionBufferClear = "Clear File Buffer"
    static let dictionarySubtitlePrefix = "Dictionary"
    static let spellSubtitlePrefix = "Spelling"
    static let folderBrowserSubtitle = "Folder Browser · Return or Tab to open"

    // MARK: - Trackpad Multi-Touch Gestures & Chord Key Remaps (mac_gesture)
    static let gestureCardTitle = "Trackpad Multi-Touch Gestures & Keyboard Automation"
    static let gestureEnableTitle = "Multi-finger swipe & pinch gestures (2–5 fingers)"
    static let gestureEnableCaption = "Maps 2–5 finger swipes and 4–5 finger pinches/spreads to shortcuts, URLs, apps, or scripts with palm & misfire rejection."
    static let chordRemapEnableTitle = "Global keyboard hotkeys & clean chord remaps"
    static let chordRemapEnableCaption = "Intercepts key chords (keyDown/keyUp, repeat, per-app scope) and runs multi-step actions without modifier leak."
    static let gestureImportLegacyButton = "Import ~/.gesture/config.json"
    static let gestureResetPresetsButton = "Reset Presets"
    static let gestureAddRuleButton = "Add Gesture"
    static let chordAddRuleButton = "Add Key Remap"
}
