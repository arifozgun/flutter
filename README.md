# Edit menu probe

A small UIKit app (no Flutter) that shows why a custom `UITextInput` view's
system edit menu expands into a flat list on iOS 26 and later, while
`UITextView` expands into a native menu (an icon row for Cut / Copy / Paste,
then separated groups whose rows have icons).

The custom view, `ProbeTextInputView`, is set up the way Flutter's
`FlutterTextInputView` is for the system context menu: a `UIView` that adopts
`UITextInput`, implements `cut:` / `copy:` / `paste:` / `delete:` /
`selectAll:` with the engine's `canPerformAction:withSender:` rules, owns a
`UIEditMenuInteraction` whose delegate it is, and presents the menu itself with
`UIEditMenuConfiguration(identifier: nil, sourcePoint: .zero)` and a target
rect from the delegate. `MenuBuilders.engineFlat` is a line-by-line port of the
engine's `editMenuInteraction:menuForConfiguration:suggestedActions:` with the
items `SystemContextMenu.getDefaultItems` sends for a selected word: cut, copy,
paste, Look Up, Search Web, Share.

Everything uses public API. No private selector is called or named in the
source; the dumps only print the selector names UIKit hands over.

## Variants

The app takes `-variant N` as a launch argument.

| # | Slug | Host | Tests |
|---|------|------|-------|
| 0 | `textview-native` | UITextView | Native reference: system default menu (delegate returns nil). |
| 1 | `custom-untouched` | custom | What UIKit suggests for a custom `UITextInput` view, shown untouched. |
| 2 | `custom-engine-flat` | custom | The engine's current flat structure. Expected to reproduce Flutter's flat list. |
| 3 | `custom-keep-parents` | custom | Lifted commands stay in their original suggested parent menus; extras flat, no images. Does the system parent alone give the icon row? |
| 4 | `custom-flat-extra-icons` | custom | v02 plus SF Symbols on the extras only. Do images alone give row icons? |
| 5 | `custom-inline-groups` | custom | Inline groups with `.standardEdit`, `.lookup`, `.share`; no size, no images. Separators? Does the identifier alone give the icon row? |
| 6 | `custom-small-size-only` | custom | Inline groups with probe identifiers; `.small` on the Cut/Copy/Paste group only; no images. Does the size alone give the icon row? |
| 7 | `custom-groups-small-icons` | custom | Hand-built candidate: `.standardEdit` + `.small`, `.lookup`, `.share`, SF Symbols on extras. |
| 8 | `custom-keep-parents-grouped-icons` | custom | Tree-filter candidate: suggested tree filtered to the requested commands, extras in `.lookup` / `.share` groups with SF Symbols. |
| 9 | `custom-groups-medium-icons` | custom | v07 with `.medium` instead of `.small`. |
| 10 | `custom-self-built` | custom | Ignores suggestedActions: own Cut/Copy/Paste commands (public selectors, SF Symbols) in a `.small` `.standardEdit` group, extras grouped. |
| 11 | `custom-textinteraction-untouched` | custom | Diagnostic: a `UITextInteraction` attached (the engine adds one when `inputDelegate` is nil). Does it change suggestedActions? |
| 12 | `custom-yes-to-all-untouched` | custom | Diagnostic only, cannot ship: `canPerformAction` answers YES to everything, listing every command UIKit could offer before filtering. Rows are never tapped. |
| 13 | `textview-engine-flat` | UITextView | Cross-check: the engine's flat structure built from a real UITextView's suggestions. |
| 14 | `textview-keep-parents-grouped-icons` | UITextView | Cross-check: the v08 algorithm on a real UITextView's tree. |
| 15 | `custom-groups-small-icons-visible` | custom | v07 plus `preferredImageVisibility = .visible` (iOS 27 API, set by key; same as v07 on iOS 26). |

SF Symbol names in the candidates (`scissors`, `doc.on.doc`,
`doc.on.clipboard`, `character.book.closed`, `magnifyingglass`,
`square.and.arrow.up`) are guesses; the native ones are in the v00 dump.

## Running

The workflow `.github/workflows/menu-probe.yml` runs on a push to
`speakblend/menu-probe` (or manually). Three jobs: `macos-26` with the newest
Xcode 26 and iOS 26.x runtime, `macos-26` with the newest Xcode and runtime on
the image, and `macos-15` with Xcode 26 / iOS 26 as a fallback image. A job
downloads a runtime only if the image has no usable one.

Locally: `xcodebuild test -project MenuProbe.xcodeproj -scheme MenuProbe
-destination 'platform=iOS Simulator,name=<device>'` with `TEST_RUNNER_PROBE_OUT=<dir>`
set to collect the files in `<dir>`.

## Artifacts

One artifact per job, `menu-probe-<runner>-xcode<x>-ios<y>`, with:

- `runner.txt`: the image's Xcodes, the selected Xcode, SDKs, runtimes, device types, the chosen runtime and device.
- `summary.txt`: one line per variant: how the menu was shown (`auto`, `presentButton`, `tapSelection`, ...), the collapsed labels, each chevron tap attempt and its target, and which strategy expanded it (`expandedBy=none` means none did).
- `screens/vNN-<slug>-1-collapsed.png` and `screens/vNN-<slug>-2-expanded.png`: the two screenshots per variant. `-attemptK-<strategy>.png` are taken after every chevron tap attempt.
- `hierarchy/*.txt`: the accessibility snapshot (type, label, identifier, frame of every element) and `debugDescription` before and after each tap, to diagnose a missed chevron.
- `trees/` (written by the app; `app-documents/trees/` is the same, copied from the app container):
  - `vNN-<slug>-custom-suggestedActions.txt` / `-textview-suggestedActions.txt`: the tree UIKit passed in (question 1). Appended once per menu build.
  - `vNN-<slug>-custom-returned.txt` / `-textview-returned.txt`: the tree the variant returned.
  - `vNN-<slug>-custom-canPerformAction.txt` / `-textview-canPerformAction.txt`: every selector UIKit asked about, how often, and the answer (`super=` is what UIResponder or UITextView answered). Shows which Look Up / Translate / Share selectors exist and whether the custom view is offered them.
  - `vNN-<slug>-custom-buildMenu.txt` / `-textview-buildMenu.txt`: the root menu of `buildMenu(with:)` if UIKit calls it.
  - `vNN-<slug>-custom-validate.txt`: commands passed to `validate(_:)`.
  - `vNN-<slug>-events.txt`: timeline (first responder, menu built, will present, will dismiss).
- `app-log.txt`: the same records from the unified log (subsystem `dev.probe.editmenu`).
- `recording.mp4`: the whole test run.
- `MenuProbe.xcresult`, `attachments/` (exported screenshots and texts), `test-summary.json`, `xcodebuild.log`.

### Tree dump format

One line per element, children indented:

```
MENU class=UIMenu title="" image=nil identifier=com.apple.menu.standard-edit options=1[displayInline] preferredElementSize=0[small] selectedElements=0 children=3
  COMMAND class=UICommand title="Cut" image=yes:symbol(system: scissors) action=cut: attributes=0[] state=0 alternates=0
```

`image=yes:symbol(...)` names the SF Symbol when UIKit's description has one.
`preferredImageVisibility` is printed on iOS 27 only.
