# RevoCC 0.1.0

Independent rootless Control Center editor for iOS/iPadOS 16.

## Build fix

This project intentionally has NO `SUBPROJECTS += prefs` line.

The previous CI failure:

    make[1]: *** prefs: No such file or directory. Stop.

was caused by the Makefile referencing a missing `prefs/` directory.

RevoCC 0.1 is a single tweak target, so Theos can build it without a preference-bundle subproject.

## Configuration provider

When available, RevoCC uses:

- CCSModuleSettingsProvider
- sharedProvider
- orderedUserEnabledModuleIdentifiers
- orderedFixedModuleIdentifiers
- setAndSaveOrderedUserEnabledModuleIdentifiers:

The provider is accessed dynamically so the tweak fails closed when a selector is unavailable.

## Current editor

Long-press Control Center to open the RevoCC editor.

A module can be moved upward. Fixed modules are protected.

The order is saved through the native Control Center settings provider.

## Stability choices

RevoCC does not:
- replace native module controllers;
- rebuild Apple's Control Center hierarchy;
- store private UIKit objects in preferences;
- message a private selector without checking it exists;
- reorder modules marked fixed;
- write an array containing duplicates or invalid entries.

## Build

Use a Theos environment with an iOS 16 SDK/private frameworks available:

    make clean package FINALPACKAGE=1

For rootless packaging, use your normal Theos rootless setup.

## Next version

The provider/order layer is intentionally separated from the UI so a later version can add:

- drag and drop;
- grid positions;
- resizing;
- pages;
- add/remove controls;
- iPad-specific layout;
- transactional rollback.
