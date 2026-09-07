# AsterCC 0.2

Independent clean-room Control Center editor for rootless iOS 16.

## What changed

The 0.1 prototype incorrectly treated Control Center as a collection of views. Version 0.2 uses Apple's private Control Center configuration provider as the persistence layer:

- `CCSModuleSettingsProvider`
- `sharedProvider`
- `orderedUserEnabledModuleIdentifiers`
- `orderedFixedModuleIdentifiers`
- `setAndSaveOrderedUserEnabledModuleIdentifiers:`

These selectors are publicly visible in the open-source CCAster project, but this implementation is independently written and does not copy its source.

## Stability model

AsterCC:
- never replaces Apple's module controllers;
- never stores UIKit/private objects in preferences;
- checks every private class/selector before messaging it;
- treats fixed modules as immutable;
- leaves native Control Center responsible for module presentation;
- avoids rebuilding the Control Center hierarchy during editing;
- performs provider writes as small, validated arrays;
- uses weak editor ownership to avoid retaining dismissed Control Center instances.

## Current functionality

- Long press Control Center to enter AsterCC edit mode.
- Reads the real native module order.
- Shows module identifiers in an editor panel.
- Move a module upward.
- Tap a module to move it downward.
- Detects fixed modules and refuses to reorder them.
- Persists order through Apple's module settings provider.
- Sends a settings-change notification.
- Rootless Theos packaging.
- Preferences bundle.

## Important

This is deliberately a stable core rather than a fake full clone. Full iOS 18-style behavior needs an additional layout adapter for `CCUILayoutRect`/`CCUILayoutOptions`, plus a native-safe drag/resize layer. Those pieces should be added only after verifying the exact iOS 16.7.x private class layout on-device.

## Build

```sh
make clean package FINALPACKAGE=1
```

For rootless Theos with ElleKit, use the normal rootless packaging configuration on the target device.
