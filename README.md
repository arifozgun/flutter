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

Everything uses public API. No private selector is called, and none is named
in the source except in two places that are marked: v28, a diagnostic variant
that cannot ship, and the three undocumented color getters that
`FlutterLikeTextInputView` copies from the engine (they only affect drawing).
The dumps print the selector names UIKit hands over.

Round 2 (v16 to v31) asks what the engine must do so that iOS itself supplies
and performs Look Up, Translate, Share and Search Web for a view like
`FlutterTextInputView`, and what that costs:

- A. When must a `UITextInteraction` be attached for UIKit to offer its own
  rows (v16 to v19, v21 to v23)?
- B. What does the interaction change besides the menu (caret, selection,
  handles, loupe, gestures, views)? Also in a layout that copies the
  engine's: a zero-sized `FlutterTextInputView` in a zero-sized
  accessibility hider at the field's origin, the text drawn by another view
  (v20 to v23).
- C. Do the system rows work, and which `UITextInput` methods give UIKit the
  selected word? (row tap runs)
- D. Can the suggested tree be filtered to the framework's ordered item list
  with public API only (`UIResponderStandardEditActions` selectors for edit
  commands, public `UIMenu.Identifier`s for whole groups)? (v16, v24 to v28)
- E. Where does the UITextView's Search Web row come from? (v00, v29 to v31,
  and the selector logs of every variant)
- F. The same on iOS 18 and 17, where the bar pages instead of expanding.

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

Round 2. "TI" is the `UITextInteraction` attachment mode
(`InteractionMode` in `ProbeTextInputView.swift`); "filter-all" is
`MenuBuilders.systemFiltered` with the request cut, copy, paste, lookUp,
searchWeb, share. v11 is the `always` mode with the untouched tree.

| # | Slug | Host, layout, TI | Question | Tests |
|---|------|------------------|----------|-------|
| 16 | `custom-ti-always-filter-all` | custom, normal, always | A, D1, C, B | Interaction for the view's whole life. System rows (icons, titles) in the filtered tree; do they work? |
| 17 | `custom-ti-while-shown-filter-all` | custom, normal, whileMenuShown | A, C, B | Attached just before `presentEditMenu`, removed when the dismiss animation completes. |
| 18 | `custom-ti-present-only-filter-all` | custom, normal, presentOnly | A, C, B | Removed as soon as `presentEditMenu` returns (UIKit builds the menu after it returns). |
| 19 | `custom-ti-until-will-present-filter-all` | custom, normal, untilWillPresent | A, C, B | Removed in `willPresentMenu`: menu built with it, shown and performed without it. |
| 20 | `flutterlike-engine-today` | custom, flutterLike, engineTransient | B | Flutter today: the engine's layout, its transient interaction (`setTextInputState`) and its flat menu. Baseline for side effects. |
| 21 | `flutterlike-ti-always-filter-all` | custom, flutterLike, always | A, B, C | Engine layout with an interaction for the whole life. |
| 22 | `flutterlike-ti-while-shown-filter-all` | custom, flutterLike, whileMenuShown | A, B, C | Engine layout, interaction only while the menu is shown: the likeliest engine design. |
| 23 | `flutterlike-ti-until-will-present-filter-all` | custom, flutterLike, untilWillPresent | A, B, C | Engine layout, interaction until `willPresentMenu`. |
| 24 | `custom-filter-no-share` | custom, normal, always | D2 | Request without share. |
| 25 | `custom-filter-no-lookup` | custom, normal, always | D3 | Request without lookUp: the whole lookup group (Look Up and Translate) goes. |
| 26 | `custom-filter-custom-in-group` | custom, normal, always | D4 | A custom `UIAction` between copy and paste inside UIKit's standard-edit group, another after share. |
| 27 | `custom-filter-custom-split` | custom, normal, always | D4 | As v26, each custom action in its own inline group (the edit group splits in two). |
| 28 | `custom-filter-diag-lookup-only` | custom, normal, always | D | **Diagnostic, not shippable**: keeps only the lookup command whose selector name is Look Up's, to show Look Up without Translate. |
| 29 | `textview-untouched-returned` | UITextView | E | Delegate returns suggestedActions untouched instead of nil. Does Search Web disappear? |
| 30 | `textview-no-delegate` | UITextView, no delegate | E | The menu when no delegate is asked. |
| 31 | `textview-filter-all` | UITextView | E, D | The public-API filter on a real UITextView's tree (target look). |

Interaction modes: `always` attaches when the view is created; `whileMenuShown`
attaches before `presentEditMenu` and removes in the completion of the
dismiss animator; `presentOnly` removes right after `presentEditMenu`
returns; `untilWillPresent` removes in `willPresentMenu`; `engineTransient`
adds one only when `inputDelegate` is nil and the view is first responder and
removes it at once, as `setTextInputState:` does, right before each present.

The Flutter-like layout copies what the engine does on an iPhone with iOS 17+
for a field without autofill: `FlutterTextInputView` keeps `CGRectZero`
(`clearTextInputClient`, `setIsVisibleToAutofill:NO`) inside a
`FlutterTextInputViewAccessibilityHider` whose frame is the editable's origin
with zero size (`setEditableSizeAndTransform:`), added to the Flutter view
controller's view; it is not hidden, alpha is 1, `accessibilityElementsHidden`
is YES, the three undocumented color getters return clear, and it draws
nothing. Its geometry methods answer in the coordinate space of the visible
text, as the engine's do after converting from the host view.
`RenderedTextView` draws the text and selection, like Flutter's renderer, and
has no gestures.

What public API can and cannot express in the filter (D): edit commands are
matched by `UIResponderStandardEditActions` selectors (cut, copy, paste,
delete, selectAll); groups by `UIMenu.Identifier` (`.standardEdit`,
`.lookup`, `.share`, `.replace`, `.autofill`, ...). Look Up, Translate and
Find Selection share the `.lookup` group and their selectors are not public,
so "lookUp" and "translate" both mean the whole group; which of its rows
appear is UIKit's decision through `canPerformAction`. Share… is the only
command of `.share`. Search Web is in no suggested tree and has no public
identifier, so the filter cannot ask for it.

SF Symbol names in the candidates (`scissors`, `doc.on.doc`,
`doc.on.clipboard`, `character.book.closed`, `magnifyingglass`,
`square.and.arrow.up`) are guesses; the native ones are in the v00 dump.

## Running

The workflow `.github/workflows/menu-probe.yml` runs on a push to
`speakblend/menu-probe` (or manually). Four jobs: `macos-26` with the newest
Xcode 26 and iOS 26.x runtime (26.5 in round 1), `macos-15` with Xcode 26 and
its newest iOS 26 runtime (26.2 in round 1), and `macos-15` with Xcode 16 on
iOS 18.6 (on the image) and iOS 17.5 (downloaded). A job downloads a runtime
only if the image has no usable one. The app's deployment target is iOS 17;
API newer than the Xcode 16 SDK is guarded or used by key.

The UI test target has three kinds of test methods: `test_vNN` (menu shape,
every variant), `test_vNN_row_<row>` (row taps for v00, v16 to v19, v21 to
v23) and `test_vNN_gestures` (v01, v16 to v23). The lists are written out in
`MenuProbeUITests.swift`.

Locally: `xcodebuild test -project MenuProbe.xcodeproj -scheme MenuProbe
-destination 'platform=iOS Simulator,name=<device>'` with `TEST_RUNNER_PROBE_OUT=<dir>`
set to collect the files in `<dir>`.

## Artifacts

One artifact per job, `menu-probe-<runner>-xcode<x>-ios<y>`, with:

- `runner.txt`: the image's Xcodes, the selected Xcode, SDKs, runtimes, device types, the chosen runtime and device.
- `summary.txt`: one line per test, with the runner's clock (`start=`, `at`) so it can be matched with the app's timestamps.
  - Menu tests (`vNN-<slug> | ...`): how the menu was shown (`auto`, `presentButton`, `tapSelection`, ...), the collapsed labels, each chevron tap attempt and its target, `expandedBy=` the strategy that expanded it (`paged:<strategy>` with `pages=N` on iOS 16-18 where the bar pages; `none` means nothing changed), and `afterDismiss=` what was left after a tap on the header.
  - Row tests (`vNN-<slug>-row-<row> | ...`): how the row was found (`found at stepN`, the chevron taps), `result=absent` when the menu does not offer it, the tap time, the app's and Safari's state two seconds later, the labels then on screen, and how the result was dismissed.
  - Gesture tests (`vNN-<slug>-gestures | ...`): for each step (`g0` before any menu, `g1` menu shown, `g2` tap on "ship", `g3` double tap on "sailed", `g4` long press on "into", `g5` tap outside) the time, the selection range the app reports and the menu labels on screen.
- `screens/`:
  - `vNN-<slug>-1-collapsed.png`, `-2-expanded.png`, `-3-dismissed.png`: the menu test. `-attemptK-<strategy>.png` follow every chevron tap attempt; `-2-pageN.png` are the further pages on iOS 16-18 (`-2-expanded.png` is then the last page).
  - `vNN-<slug>-row-<row>-0-before-tap.png`, `-1-after-tap.png` (about two seconds after the tap: the Look Up card, the translation sheet, the share sheet or Safari), `-2-after-dismiss.png`; `-0-row-absent.png` when the row is not offered.
  - `vNN-<slug>-gestures-g0-...png` to `-g5-...png`: one per gesture step.
- `hierarchy/*.txt`: the accessibility snapshot (type, label, identifier, frame of every element) and `debugDescription` before and after each tap, to diagnose a missed chevron.
- `trees/` (written by the app; `app-documents/trees/` is the same, copied from the app container):
  - `vNN-<slug>-custom-suggestedActions.txt` / `-textview-suggestedActions.txt`: the tree UIKit passed in (question 1). Appended once per menu build.
  - `vNN-<slug>-custom-returned.txt` / `-textview-returned.txt`: the tree the variant returned.
  - `vNN-<slug>-custom-canPerformAction.txt` / `-textview-canPerformAction.txt`: every selector UIKit asked about, how often, and the answer (`super=` is what UIResponder or UITextView answered). Shows which Look Up / Translate / Share selectors exist and whether the custom view is offered them.
  - `vNN-<slug>-custom-buildMenu.txt` / `-textview-buildMenu.txt`: the root menu of `buildMenu(with:)` if UIKit calls it.
  - `vNN-<slug>-custom-validate.txt`: commands passed to `validate(_:)`.
  - `vNN-<slug>-events.txt`: timeline: launch, first responder, `UITextInteraction attached/removed (reason); inputDelegate=...`, `presentEditMenu called/returned`, menu built, will present, animations completed, will dismiss, every touch (`touch began/ended at x,y view=... window=...`), `UIKit set selectedTextRange ...`, scene activity (a row that leaves the app shows `willResignActive`/`didEnterBackground`).
  - `vNN-<slug>-custom-targetForAction.txt`, `-textview-targetForAction.txt`, `-vc-canPerformAction.txt`, `-vc-targetForAction.txt`, `-app-canPerformAction.txt`, `-app-targetForAction.txt`: every selector the view, its view controller and the application were asked about, with the answer or target and when (first and last time). Not a fixed list.
  - `vNN-<slug>-sendAction.txt`: every action sent through the application: selector, target (`nil` = responder chain) and sender (for a menu row, the tapped command with its title and image). A row that does not appear here did not use a selector sent through the application.
  - `vNN-<slug>-textinput-calls.txt` (custom view): every UITextInput call UIKit made, with arguments and results (`text(in: {25, 6}) -> "harbor"`), consecutive repeats folded (`(x12)`), and marker lines (`----`) for menu builds, attach/remove and snapshots. `SET selectedTextRange` lines are selection changes made by UIKit; `set inputDelegate` shows when UIKit gave or took the input delegate.
  - `vNN-<slug>-views.txt`: view snapshots, before each present, after attaching, 0.8 s after `willPresentMenu`, 0.6 s after the dismiss animation, and (row and gesture runs) 0.9 s after every touch: the custom view's interactions, gesture recognizers and subviews, its superview chain, and every window of the scene with its view tree (class, frame, hidden, alpha, label text, image symbol).
  - `vNN-<slug>-displayed.txt`: the labels and images visible outside the probe's own views, written whenever they change (polled every 0.7 s), plus a dump when a menu is shown. This is the displayed menu, including rows that are in no tree (Search Web), with their icons.
  - `vNN-<slug>-custom-textinput-editMenu.txt`: the suggested actions when UITextInteraction presents a menu of its own and asks the view through `UITextInput.editMenu(for:suggestedActions:)` (gesture runs).
  - Row and gesture runs write the same files under `vNN-<slug>-row-<row>-...` and `vNN-<slug>-gestures-...`.
- `app-log.txt`: the same records from the unified log (subsystem `dev.probe.editmenu`).
- `recording.mp4`: the whole test run.
- `MenuProbe.xcresult`, `attachments/` (exported screenshots and texts), `test-summary.json`, `xcodebuild.log`.

### Where each round 2 question is answered

- A (attachment time): `summary.txt` collapsed and expanded labels of v16 to v19 and v21 to v23 next to v02 and v20; `-custom-suggestedActions.txt` (`hasTextInteraction=` in the build header) and `-custom-canPerformAction.txt` (`super=` for the lookup and share selectors) of the same variants; whether the rows work is C.
- B (side effects): the `-gestures` summary lines and screenshots; `-gestures-textinput-calls.txt` (`SET selectedTextRange`, `set inputDelegate`, geometry queries after each touch) and `-gestures-views.txt` (views, interactions and gesture recognizers before, during and after the menu, and after each touch); v20 is the engine today, v01 the custom view without an interaction.
- C (rows work): `-row-<row>` summary lines and `-1-after-tap.png`; `-row-<row>-sendAction.txt` (which selector the row sent and to whom), `-row-<row>-textinput-calls.txt` (`text(in:)` returning "harbor"), `-row-<row>-events.txt` (order of dismiss, interaction removal and the action).
- D (public filter): screenshots of v16 and v24 to v28, `-custom-returned.txt`.
- E (Search Web): `v00-...-displayed.txt` against `v00-...-textview-suggestedActions.txt`; v29 and v30 screenshots; `v00-textview-native-row-searchWeb-sendAction.txt`, `-events.txt` and `-textview-canPerformAction.txt` / `-textview-targetForAction.txt` around the tap time; the same row on v16 and v17.
- F (older iOS): the `xcode16-ios18.6` and `xcode16-ios17.5` artifacts, `-2-pageN.png`.

### Tree dump format

One line per element, children indented:

```
MENU class=UIMenu title="" image=nil identifier=com.apple.menu.standard-edit options=1[displayInline] preferredElementSize=0[small] selectedElements=0 children=3
  COMMAND class=UICommand title="Cut" image=yes:symbol(system: scissors) action=cut: attributes=0[] state=0 alternates=0
```

`image=yes:symbol(...)` names the SF Symbol when UIKit's description has one.
`preferredImageVisibility` is printed on iOS 27 only.
