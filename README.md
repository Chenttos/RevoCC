# RevoCC 0.2.1

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
