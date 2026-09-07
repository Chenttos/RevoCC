# RevoCC 0.1.2

This release fixes the strict Clang private-controller pointer errors from CI.

The previous implementation still exposed a `UIViewController *` parameter in
the initializer. RevoCC now uses `id` throughout the private
`CCUIControlCenterViewController` boundary, so Clang cannot compare or pass
the private pointer type as a distinct UIKit pointer type.

The project has no `prefs` subproject.

Build:

    make clean package FINALPACKAGE=1

Core configuration provider:

    CCSModuleSettingsProvider
    sharedProvider
    orderedUserEnabledModuleIdentifiers
    orderedFixedModuleIdentifiers
    setAndSaveOrderedUserEnabledModuleIdentifiers:

The implementation is independently written and does not copy CCAster source.
