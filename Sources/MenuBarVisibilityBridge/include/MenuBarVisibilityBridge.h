// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (Ice) © 2023–2025 Jordan Baird
// Copyright (Thaw) © 2026 Toni Förster
// Copyright (C) 2026 Vorssaint

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Returns whether the macOS 27 MenuBarClientCore visibility API is present.
BOOL VorssaintMenuBarVisibilityAvailable(void);

/// Activates the macOS 27 menu bar visibility allowlist.
///
/// The completion handler is called asynchronously on the main queue with nil
/// when activation succeeds, or an error when it fails. The returned opaque
/// handle keeps the restriction active until it is invalidated.
void *_Nullable VorssaintMenuBarVisibilityActivate(
    NSArray<NSString *> *_Nullable allowedBundleIdentifiers,
    NSArray<NSNumber *> *_Nullable allowedSystemItems,
    void (^_Nullable completion)(NSError *_Nullable error));

/// Invalidates and releases a handle returned by VorssaintMenuBarVisibilityActivate.
/// Safe to call with NULL.
void VorssaintMenuBarVisibilityInvalidate(void *_Nullable handle);

NS_ASSUME_NONNULL_END
