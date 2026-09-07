# RevoCC 0.3.1

RevoCC adds a clean-room Control Center chrome layer inspired by the requested
CCAster behavior:

- top-left add/edit button
- top-right power button
- vertical page selector
- page selection during the native Control Center opening phase
- page selection is hard-disabled once the native presentation reaches state 2
- runtime checks for private classes/selectors
- no copied CCAster source

The public CCAster repository was inspected only as a behavioral reference
for these requested concepts. RevoCC's implementation is independently
written.

## Page interaction rule

RevoCC intentionally uses:

- state `1`: opening -> page selector can be used
- state `2`: fully open -> page selector is visible but cannot switch pages
- state `3`: closing -> page selector cannot be used
- state `0`: dismissed -> chrome hidden

The state is checked both while laying out the controls and at the moment a
page button is pressed.

## Important

This version focuses on the requested chrome/page-selection behavior. The
full CCAster-style drag/resize/grid editor is a separate layer and is not
copied from CCAster.

## Build

    make clean package FINALPACKAGE=1

No `prefs/` subproject is required.


## 0.3.1 changes
- Plus button now opens a functional editing overlay.
- Long-press opens the same editor.
- Enabled modules can be reordered by dragging.
- Enabled modules can be removed.
- Available native modules can be added.
- Done saves through `CCSModuleSettingsProvider`.
- Page count now uses the native module collection's `contentSize` and viewport height.
- Page switching uses the native collection scroll view's `contentOffset`.
- Page buttons are vertically centered and aligned to the Control Center edge.
- Page buttons remain locked until presentation state 2 (fully open).


## 0.3.1 changes
- Fixed the GitHub Actions build failure caused by the unused `RVSendBool1` helper.
