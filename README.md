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

# Flutter menu harness

The UIKit probe above answers what UIKit does for a view like Flutter's text
input view. This second harness shows what a real **Flutter app** does with the
system edit menu, on the stock Flutter engine (baseline) or on a simulator
engine built by an earlier run of an engine workflow (engine run). Running both
on the same SDK ref and comparing the outputs shows what an engine change does
to the menu's look and to typing around it. It runs only on GitHub Actions
simulators: iOS 26 (a vertical menu with a chevron), iOS 18.6 and iOS 17.5 (a
horizontal, paged bar).

## What is in it

- `flutter_app/`: the probe app, only `pubspec.yaml` and `lib/main.dart`. The
  platform folder is made on CI with `flutter create --platforms=ios
  --project-name menu_probe --org dev.probe .`, which gives the bundle id
  `dev.probe.menuProbe` (the tests read it from the built app and fall back to
  that). One light screen with six fields, each with a visible label and a
  semantics identifier `field-<id>`:
  `single` (Material `TextField`, "The quiet harbor sailed away"), `multi` (three
  lines), `obscured`, `cupertino` (`CupertinoTextField`), `custom` (a
  `TextField` whose `contextMenuBuilder` returns `SystemContextMenu.editableText`
  with an explicit list: Cut, Copy, *Custom A*, Paste, Select All, Look Up,
  Search Web, Share, *Custom B*) and `selectable` (`SelectableText`). All
  others use Flutter's default menu, which is the system menu on iOS when
  `SystemContextMenu.isSupported` (shown at the top of the screen). `Reset`
  restores the texts and drops focus; `Done` only drops focus; `Sized`
  (identifier `probe-page`) switches to the second page below, `Main` back.
  The status area at the bottom (identifier `status`) shows the focused field's
  id, text, selection base/extent and composing range. Its accessibility label
  also holds the rectangles of the selection and of every word in points, which
  the tests use to double tap a word.
  The app appends every change, focus change, menu build and custom item press
  to `Documents/menu_probe_log.txt` (dart:io only), so results do not depend on
  accessibility. Every `change` line holds the field's whole
  `TextEditingValue`: text, selection and composing range.
  The second page (the `sized` scenarios tap `Sized`; a launch environment
  cannot select it, because Dart's `Platform.environment` is empty on iOS; the
  app's log has a `page=sized` line) has one field per configuration that
  gives the engine's text input view a different frame:
  `sized-plain` (TextField's default `autofillHints`, an empty list),
  `sized-nohints` (`autofillHints: null`), `sized-email` (`[email]`), and an
  `AutofillGroup` with `sized-username` (`[username]`) and `sized-password`
  (`[password]`, obscured). Each title says which frame it should give; see
  [The text input view's frame](#the-text-input-views-frame).
- `MenuProbeUITests/FlutterMenuUITests.swift`: XCUITests that drive that app by
  bundle id (`XCUIApplication(bundleIdentifier:)`). They are a second class in
  the existing UI test target, not a second target: a UI test target needs a
  target application and its own scheme, and this way the project, the scheme
  and the signing settings that already work on the runners stay as they are.
  The workflow runs only this class (`-only-testing`); the UIKit probe app is
  built because the target depends on it, and not used.
- `.github/workflows/flutter-menu.yml`: builds and runs it.

## Dispatching a run

`flutter_ref` is a branch, tag or commit of **this repository** (the Flutter
SDK fork). Dispatch from the probe's branch:

```
# Baseline: the stock engine of that SDK.
gh workflow run flutter-menu.yml --ref speakblend/menu-probe \
  -f flutter_ref=<sdk-branch-tag-or-sha> \
  -f prebuilt_engine_version=<engine commit that has prebuilt artifacts> \
  -f label=baseline

# Engine run: the same, plus the run that built the simulator engine.
gh workflow run flutter-menu.yml --ref speakblend/menu-probe \
  -f flutter_ref=<sdk-branch-tag-or-sha> \
  -f prebuilt_engine_version=<engine commit that has prebuilt artifacts> \
  -f engine_run_id=<id of the engine workflow run> \
  -f label=engine
```

Inputs:

- `flutter_ref` (required): the SDK to build with.
- `engine_run_id`: a run of this repository that uploaded the artifact
  `flutter-ios_debug_sim_unopt_arm64`. When set, its arm64 simulator
  `Flutter.framework` replaces the arm64 slice of the cached stock one. The job
  checks that the artifact belongs to that run and that the binary matches the
  sha256 in its manifest. Empty: the stock engine.
- `prebuilt_engine_version`: exported as `FLUTTER_PREBUILT_ENGINE_VERSION`. Needed
  when the SDK ref has engine source changes, because the engine version
  otherwise comes from a hash of the engine sources and no prebuilt artifacts
  exist for it.
- `label`: goes into the artifact name; default `baseline`, or `engine` when
  `engine_run_id` is set.
- `scenarios`: which scenarios run, comma separated; default `all`. Groups:
  `shape`, `rows`, `edit`, `typing`, `cycles`, `selectionChange`,
  `autocorrect`, `ime`, `sized`, `showcase`; a test method name such as
  `test_08_ime_c_menuWhileMarked` also works. The tests that are not selected
  are skipped (`PROBE_SCENARIOS`); an unknown group stops the job before
  anything is built. Example: `-f scenarios=ime,sized,showcase` runs only the
  new ones.
- `device`: `iphone` (default) or `ipad`. The iPad is the one configuration in
  which the engine gives the text input view the field's own size (Scribble),
  so `ipad` with `scenarios=sized` (or `all`) tests that case. The artifact
  name gets `-ipad`.
- `ios27`: `true` adds an iOS 27 job (newest 27.x runtime, Xcode 27) on the
  `xcode-27` image; off by default.

The simulator's runtime and device type are chosen together: a runtime that
supports one of the preferred device types (iPhone 17 Pro, 17, 16 Pro, ...; on
iPad an 11-inch Air or Pro) first, then a general runtime over one made for a
single device type (the `xcode-27` image has `iOS-27-2-iPhone19-4`, which only
runs the two-display iPhone Duo), then the newest. Without a preferred type,
the last type whose name does not say Duo, Fold or Flip. The choice is the
`Runtime ... on ...` line of `runner.txt`. Should a device with more than one
display still be chosen, the recordings use its primary display
(`tools/start_recording.sh`).

The workflow also has a push trigger on its own file; that run skips the job and
only registers the workflow.

The matrix runs iOS 26 (Xcode 26), 18.6 and 17.5 (Xcode 16), all on `macos-15`,
and with `ios27` also iOS 27 (Xcode 27) on `xcode-27`. That image is GitHub's
only one with iOS 27 simulator runtimes (27.0 and 27.2 per the runner-images
README `images/macos/xcode-27-arm64-Readme.md`, image 20261104); the
runner-images table still marks it "preview" (issue 14404), so the leg is
opt-in. The app is a debug simulator build (a simulator build can only be
debug).

When the selection includes `ime` (or `all`), the job adds a Japanese (Romaji,
`ja_JP-Romaji@sw=QWERTY-Japanese`) and a Chinese (Pinyin,
`zh_Hans-Pinyin@sw=Pinyin-Simplified`) keyboard to the simulator's
`AppleKeyboards` after the keyboards it already has, and reboots it. English
stays the first keyboard; the other scenarios then show a globe key where the
emoji key was. `runner.txt` holds the keyboard list before and after.

## Reading the output

One artifact per job, `flutter-menu-ios<version>-<label>`:

- `summary.txt`: one line per scenario, `<scenario> | ios=<version> | <notes>`,
  each ending in `RESULT=...`. Also shown in the job summary, with the tail of
  the app's log.
  - `shape-<field>`: how the word was selected, `collapsed=[...]` (known menu
    titles in tree order; a row appears twice in the tree, repeats are folded),
    `all=[...]` (every label in the menu's container), `mode=list` (iOS 26) or
    `paged` (17/18) with `pages=N` and each `pageK=[...]`, and the chevron taps.
  - `rows-<row>-<field>`: for Look Up, Translate, Share and Search Web in the
    `single` and `custom` fields. Each field starts from a clean state (Safari
    stopped, the app relaunched). After the tap the scenario polls for up to 6 s
    (`polls=`): Safari in the foreground gives `outcome=safari`; a sheet-like
    state (sheet, popover, card, close button) that has stopped loading gives
    `outcome=sheet`, and `foundAfter=` says when. Other outcomes: `left-the-app`,
    `menu-still-shown`, `nothing-visible`, `row-absent`. The app's element tree
    is read only while the app is in front, never for Search Web before the wait
    is over; the screenshot `-1-after-tap` is taken after the wait. Then the
    app is brought back (`dismissedBy=`) and its status is read. An older line
    has `after 2 s:` where this has `after tap:`.
  - `edit-cutThenPaste`, `edit-copyThenPaste`, `edit-selectAll`: each step's
    status next to the expected text (`PASS` / `FAIL`).
  - `typing`: after each step (menu shown, dismissed, "abc" typed, Look Up and
    "def", Copy and " ghi", autocorrect of "helo ", the keyboard's suggestions
    for "wrold" and a tap on one) whether the keyboard is up and the status
    line. A text that is missing what was typed is the regression to look for.
  - `cycles`: `menu per round` (`M` shown, `-` missing) for 20 open/dismiss
    rounds, whether the 20th still showed the menu, the text after typing "z".
  - `selectionChange`: a drag of the selection's end handle while the menu was
    shown; whether the selection moved, whether the menu came back, its labels.
  - `autocorrect`: whether moving the caret by a tap commits a pending
    autocorrection. Every variant taps at the end of the text, types `abc`,
    taps near the start of the field, and records `textAfterTyping=`,
    `textAfterTap=` and `autocorrectApplied=true|false` (`true` when the tap
    changed the text), plus the selection and composing range at both points.
    A: the fresh app. B: the menu shown, then dismissed by a tap. C: the menu,
    Look Up, the sheet closed. D: the menu, Copy. E: `x` typed while the menu is
    shown (`menuGoneAfterTyping=`, the text). Each variant starts from a
    reset. The scenario judges nothing; compare the two runs.
  - `ime-a` to `ime-d`: marked (composing) text from an IME keyboard in the
    `single` field. Each first puts the caret at the end of the text and
    taps the globe key until a probe proves an IME is up (`toIME:`): the
    probe types `a` and deletes it again, and only an IME leaves the `a`
    marked (`composing=` with a range, `ime=true`). `imeKeys=` lists the
    keys of the keyboard it reached (Japanese or Chinese). Then `kana` is
    composed (`かな` on the Japanese keyboard, `ka na` on the Chinese one) and
    committed with the return key (`confirm` while text is marked). Every
    step is a `<step> at <time>: keyboard= menu=[...] status: ...` note with
    the app's text, selection and composing range; `committed=true` means the
    text kept what was composed and nothing is marked any more.
    a: menu cycle (select "harbor", menu, dismiss by a tap), then compose and
    commit. b: Look Up, its sheet closed, then compose and commit. c: `kana`
    marked, then a double tap on "quiet" (`c2` after 0.4 s, `c3` after 1.6 s:
    what happened to the marked text and whether the menu came), then after a
    reset `kana` marked again and a long press on "harbor" (`c5`, `c6`). d:
    compose and commit, menu cycle, compose and commit again.
    **How to tell it really ran:** `exercised=yes markedAt=[...]` names the
    steps whose value had a composing range. `exercised=no` with
    `RESULT=ime-unreachable` means no IME keyboard was reached (no globe key,
    or no keyboard ever gave marked text); then `toIME:`, `imeKeys=`,
    `screens/ime-<x>-0-keyboard.png`, its hierarchy and the keyboard list in
    `runner.txt` show why, and the rest of the line proves nothing. A
    `<step>-retry` note means the first `kana` was not marked (typed as Latin)
    and the IME was brought up again. `toLatin:` switches back to a Latin
    keyboard for the scenarios that follow. The first globe tap on a new
    simulator covers the keys with a card ("Quickly Change Keyboards",
    Continue) that comes back at every globe tap until Continue is tapped;
    `toIME:` and `toLatin:` tap it away and say so (`keyboard introduction
    card: tap Continue, gone=true`). Before that was done, only the scenarios
    that started on an IME keyboard left over from the one before reached it. The app's log has the same values
    with their times (`change field=single ... composing=a..b`).
  - `sized-plain`, `sized-nohints`, `sized-email`, `sized-username`: one field
    of the `sized` page each (`expectedFrame=` says which frame of the text
    input view it should give, `screen=` the screen size in points, which
    tells an iPad run). `1`: the word "harbor" selected, `collapsed=[...]`,
    `all=[...]`, `unrequested=[...]` (rows Flutter's default menu does not
    ask for, such as Delete or Select: UIKit's own), on iPad `assistantBar=`,
    and the expanded list
    (iOS 26) or the pages (17/18). Separate lines
    `<field>-row-lookUp`, `-row-translate`, `-row-share` tap each row as the
    `rows` scenarios do (`outcome=sheet` when its sheet opened). `3a` to `3d`:
    from a fresh selection each, with the menu shown: a tap at the end of the
    same field, a tap in another field, a drag of the end handle 70 points to
    the right, a double tap on "quiet". After each, `menu=[...]`,
    `unrequested=[...]`, `foreign=[...]` (menus, popovers, text views or
    images that are neither the app's elements, the keyboard nor menu rows)
    and the app's value; a screenshot and a hierarchy dump of every step are
    in `screens/` and `hierarchy/`. `4`: `xyz` typed at the end
    (`typedOK=`). UIKit's own cursor and handles are not accessibility
    elements as far as the probe knows, so the screenshots of the `3x` steps
    are where they would show; an extra UIKit menu shows in `menu=` and
    `unrequested=`, and a tap taken by UIKit instead of Flutter shows as a
    status that does not follow the tap. `page=sized (page button tapped Nx)`
    says how the page came up. `exercised=yes` means the word was selected
    with the menu shown in that field; `RESULT=page-not-shown` means the page
    button did not bring up the sized page (screenshot and hierarchy
    `<field>-0-page-missing`).
  - `showcase`: a slow, clean run recorded on its own as `showcase.mp4`:
    select "harbor", the menu, one chevron tap (expanded list on iOS 26, next
    page on 17/18), Look Up (on 17/18 the menu is shown again first, since
    Look Up is on its first page), its sheet closed, the menu again by a
    double tap, Copy. About 1.5 to 2 s between steps. It runs after the other
    scenarios in a step of its own (its own `xcodebuild`, log
    `showcase-xcodebuild.log`). First a warm-up that is not recorded: a Look
    Up whose first-run card ("Look Up now shows personalized suggestions",
    Continue) is tapped away (`warmUp lookUp ... firstRunCard=`). When the
    warm-up could only get back to the app by a relaunch, Look Up is left out
    of the clip (`3 Look Up left out`). Then the test sets up the opening
    picture (no menu, the caret at the end of the field) and the workflow
    records only from there to the closing picture (the caret at the end
    again), each held about 1.5 s; the app stays in front until the recording
    has stopped. The test and the workflow agree through files in the output
    folder (`showcase-ready`, `-recording`, `-done`, `-stopped`).
    `recording=started`, `recordingStopped=true` and `inApp=true` say that
    the clip was recorded that way; `showcase-record.log` is the recorder's
    output. `clipStart=`/`clipEnd=` are wall-clock times.
- `screens/`: `<scenario>-<step>.png`, for example `shape-single-1-collapsed`,
  `shape-single-2-page2`, `shape-single-2-expanded`, `rows-lookUp-single-1-after-tap`,
  `typing-2c-typed-def`, `cycles-round20`, `selectionChange-2-after-drag`,
  `ime-c-c3-doubleTap-1.6s`, `sized-email-3a-tapSameField`.
  `first-launch.png` is the app on its own before the tests.
- `hierarchy/`: accessibility dumps (type, label, identifier, frame of every
  element plus `debugDescription`) at the collapsed and expanded states, after
  row taps and where a step failed.
- `app-documents/menu_probe_log.txt`: the app's own log (`t=<epoch s>`, same
  clock as the `start=` and `at` times in `summary.txt`).
- `app-log.txt`: the simulator's unified log for the app's process.
- `recording.mp4`: the test run without the showcase; `recording-start.txt`
  is when the recorder was started (epoch seconds). `showcase.mp4`: the
  showcase clip (above).
- `engine.txt`: for an engine run the manifest and slice info of the installed
  engine; always the app's bundle id and the checksum of the app's embedded
  `Flutter.framework`. `flutter-version.txt`, `flutter-build.log`, `runner.txt`
  (Xcode, runtimes, SDK commit and the inputs).
- `FlutterMenu.xcresult`, `attachments/`, `test-summary.json`, `xcodebuild.log`,
  `first-launch.txt`.

A scenario that cannot find what it needs records that (with a screenshot and
the hierarchy) and returns; the other scenarios still run. Only a launch that
never shows the app's first screen fails a test. A launch that fails (one
timed out after 40 s on an iPad runner) is tried once more; that writes a line
`launch-retry-<test method> | ... | first attempt: <error> | RESULT=retried`.

On an iPad the keyboard's shortcut bar (`SystemInputAssistantView`, above
the keys) has Cut, Copy and Paste buttons while text is selected. They are
not menu rows and are left out of every menu list and of `unrequested=`;
`shape` and `sized` lines list them as `assistantBar=[...]` (only when the
bar is there). Queries that could hang on an
app in the background are avoided, and the ones that remain are wrapped so that
a failure there is an expected one, not a failed test.

Selecting a word recovers when a round fails (up to three rounds): it closes a
leftover menu or sheet, taps an empty spot, and resets the app (or, in a
scenario that keeps the text, taps Done and focuses again). `Reset` itself is
checked (`field=none` in the status) and repeated when a menu swallowed the tap.
The recovery shows in the `select=` note.

### The text input view's frame

`FlutterTextInputView` takes a size in these places of the engine's
`FlutterTextInputPlugin.mm` (line numbers of the prototype this harness was
written against, commit `21977d0018e`):

| Where | What | Reached by |
|---|---|---|
| `initWithFrame:CGRectZero` (881) | every view starts at zero | - |
| `configureWithDictionary:` (1383) and `setIsVisibleToAutofill:` (1578) | `isVisibleToAutofill = autofill \|\| secureTextEntry`; visible means a 1x1 frame at (0,0), else zero. `autofill` is set whenever the field sends an autofill configuration, which every TextField and CupertinoTextField does by default: their `autofillHints` default is an empty list, not null | `sized-plain`, `sized-email`, `sized-username`, and the main page's `single`, `multi`, `obscured`, `cupertino`, `custom`: 1x1. Only `sized-nohints` (`autofillHints: null`) stays at zero |
| `AutofillTypeOf` (427) with `IsFieldPasswordRelated` (401), `getOrCreateAutofillableView:` (3392) | a field with hints, or in a group with a password-related field, gets a view kept in the autofill context; password-related ones are `FlutterSecureTextInputView`, which answers `isKindOfClass:[UITextField class]` with YES | `sized-email` (regular), `sized-username` (password group, secure view) |
| `setTextInputClient:withConfiguration:` (3262) via `changeInputViewsAutofillVisibility:` (3455) | before a new field is focused all views go back to zero, then the new configuration's views get 1x1 | every focus change |
| `setEditableSizeAndTransform:` (3129) when `isScribbleAvailable` (1588, any iPad on iOS 14+) | the view gets the field's width and height, and its parent (the accessibility hider) the field's origin and size, so it lies over the field and can be hit by taps | `device=ipad`, every field |
| `setEditableSizeAndTransform:`, iOS 17+ on iPhone (3153) | only the hider moves to the field's origin, with zero size; the 1x1 view inside it cannot be hit by taps, but nothing clips what an interaction draws there | every iPhone run |
| `triggerAutofillSave:` (3226) | all views in the autofill context go to 1x1 just before they are removed (`TextInput.finishAutofillContext(shouldSave: true)`) | not tested: transient, and no menu is shown then |
| `clearTextInputClient` (3500) | back to zero | every unfocus |

So on an iPhone the view has a size (1x1) for nearly every field, but sits in a
zero-sized parent; on an iPad it covers the field. The `sized` scenarios on
`device=ipad` are the ones where a `UITextInteraction` attached for the menu
can take taps, as it did in the UIKit probe's visible views (v16, v17).

## Comparing two runs

```
python3 tools/compare_runs.py <folder-of-run-A> <folder-of-run-B> [--all]
```

Each folder holds a `summary.txt` (for example two downloaded artifacts of the
same iOS version, a baseline and an engine run). For every scenario the script
prints the fields that differ, `A=` and `B=` under each field name. `start=`
times, `at <time>`, the showcase's `clip...=` times and the coordinates in
`frame=` are ignored; `after 2 s` and `after tap` count as the same field.
Scenarios with `exercised=no` are listed first as `NOT EXERCISED in A|B`: a
missing difference there proves nothing. Scenarios only one run has are listed;
`--all` also lists the ones without a difference. It reads files and prints,
nothing else (Python 3, standard library only).

# Autocorrect harness

A third harness, in the UIKit probe app, for one question: when does the
keyboard commit a pending autocorrection on a selection change, and does a
`UITextInteraction` that was attached to a custom `UITextInput` view and
removed again change that? In the Flutter app, with the engine change that
attaches an interaction for the edit menu (keeping the keyboard's
`inputDelegate`), "…sailed awayabc" became "…sailed away ax" when the
selection moved after typing; the stock engine kept "awayabc".

## What it runs

The app takes `-acVariant <id>` and shows `AutocorrectViewController`. The
text is "The quiet harbor sailed away", the caret at the end. The input view
is `ACInputView` (`MenuProbe/AutocorrectInputView.swift`), a separate class
from `ProbeTextInputView`, set up like `FlutterTextInputView`: keyboard edits
do not call `inputDelegate`; `engineSetState` is `setTextInputState:`
(will-change, assign, did-change, with the engine's transient interaction when
`inputDelegate` is nil); traits as in the engine (autocorrection and spell
checking default, inline predictions off); positions move in every direction
so `UITextInputStringTokenizer` finds words. The default layout is the
engine's: a zero-sized input view in a zero-sized hider, the text drawn by
another view.

Each variant is a timed script. The default (sequence T) is: select "harbor"
(10..16); 0.4 s later attach the interaction (the view ignores the
`inputDelegate` assignments UIKit makes while it is added or removed) and
present the menu; 2 s later move the selection to the end (28..28) and dismiss
the menu; remove the interaction when the dismiss animation completes; 2 s
later ask the test to type `abc` with key taps; 3.5 s after the last key move
the selection to 3..3 the engine's way; read the text then, 0.3 s and 2 s
later. Programmatic steps come from timers (no touch); real taps only where a
variant says so.

| id | What it does | Question |
|----|--------------|----------|
| n01 / n02 | UITextView: type, then a real tap near the start / `selectedRange = {3,0}` | Q1 |
| n03 / n04 | UITextField: type, then a real tap / `selectedTextRange =` | Q1 |
| s01 | Engine layout, no interaction, no menu, engine-style change | Q2 |
| s02 | s01, the change follows a real tap on the drawn text | Q2 |
| s03 | s01, selection assigned without will/did-change | Q2, Q4 |
| s04 / s05 | s01 with a 1x1 view / with inline predictions on | Q2, Q4 |
| t01, t99 | Sequence T (t99 repeats it at the end of the run) | Q3 |
| t02 | Sequence T with real taps (one at the end dismisses, one near the start changes) | Q3 |
| f01 | Interaction attached and removed at the same times, no menu | Q4 |
| f02 | Menu, no interaction ever (should equal s01) | Q4 |
| f03 / f04 / f05 | Removed in `willDismiss` / 2 s after the completion / never | Q4 |
| f06 | The selection moves to the end 1 s after the removal, not with the dismissal | Q4 |
| f07 | No guard, engine workaround off | Q4 |
| f08 | No guard, engine workaround on | Q4 |
| f09 | No guard, the earlier delegate put back after the removal | Q4 |
| f10 / f11 | Typed and changed once before the menu, text restored; same focus session / resign and become (sequence B's history) | Q4 |
| f12 / f13 | A second menu without interaction after the first; hidden at the first key / dismissed before typing | Q4 |
| f14 | A real tap at the end before typing (selection unchanged) | Q4 |
| f15 / f16 | After the removal: `textInput = nil` / the object released | Q4 |
| f17 / f18 | Two menu cycles, same interaction / a new one each | Q4 |
| f19 / f20 | After the removal: `reloadInputViews()` / resign and become first responder | Q4 |
| f21 / f22 | After the removal: selection / text will-did-change without a change | Q4 |
| f23 / f24 / f25 / f26 | t01 with a silent final change / 1x1 view / visible full-size view / inline predictions on | Q4 |
| f27 / f28 | t01 with a `.nonEditable` interaction / with `interactionShouldBegin` false | Q4 |

The ids in full are in `MenuProbe/AutocorrectVariants.swift`. The UI tests are
`MenuProbeUITests/AutocorrectProbeUITests.swift`, a class in the existing UI
test target (`menu-probe.yml` skips it).

## Dispatching a run

```
gh workflow run autocorrect-probe.yml --ref speakblend/menu-probe
gh workflow run autocorrect-probe.yml --ref speakblend/menu-probe -f tests="test_01_t01 test_13_f02"
```

`.github/workflows/autocorrect-probe.yml` runs only this class on iOS 26
(Xcode 26), 18.6 and 17.5 (Xcode 16), on `macos-15`. A push of its own file
starts a run whose job is skipped; that only registers the workflow. Artifact:
`autocorrect-probe-ios<version>`.

## Reading the summary

`summary.txt`, one line per variant:
`ac-<id> | ios=<v> | <the app's result> | suggestionsBeforeChange=[...] | literalOffered=... | test=[...]`.

- `committed=true|false`: the text 2 s after the final change differs from the
  text after typing. `committedSync`: it already differed when the change
  returned.
- `textAfterTyping`, `textAfterChange` (right after), `textAfter300ms`,
  `textLate` (2 s), `selAfterTyping`, `selLate`.
- `finalEdits=[...]`: every keyboard call on the view after typing, with the
  step it came in: `final:will` (inside `selectionWillChange`), `final:assign`,
  `final:did` (inside `selectionDidChange`), `final:after`, `final:awaitTap`
  (before the app changed anything, i.e. caused by the touch), `late`. The
  calls are `insertText`, `replace(range, withText:)`, `setMarkedText`,
  `unmarkText`, `deleteBackward`, `SET selectedTextRange`, with the time.
  `typingEdits` the same while typing.
- `delegateStart`, `delegateAfterAttach`, `delegateAfterRemoval`,
  `delegateBeforeChange`, `delegateLate`: `inputDelegate` as class@pointer.
  `delegateSets=N ignored=K`: assignments UIKit made, and how many the guard
  ignored.
- `interactionsBeforeChange`, `gesturesBeforeChange`: counts on the input
  view; `traits[...]`: what the view reports and how often UIKit read it.
- `historyTextAfterTyping`, `historyTextLate`, `historyCommitted` (f10, f11):
  the first round, before the menu.
- `suggestionsBeforeChange`: the prediction bar right after typing.
  `literalOffered=true` (a quoted entry, "keep what I typed") means an
  autocorrection was pending. `false` or `unknown` with `committed=false`
  proves nothing: the keyboard had nothing to commit.
- `notes`: missing dismiss completions, taps that did not come, typing that
  did not finish.

The job summary repeats one short line per variant. Per variant the app also
writes, under `trees/` (and `app-documents/trees/`), `ac-<id>-steps.txt` (text,
selection, input delegate, first responder, interactions by class and
gesture recognizer count at each step), `-edits.txt`, `-textinput-calls.txt`
(every UITextInput call), `-events.txt`, `-views.txt` (the view tree just
before the final change), `-menus.txt` and `-result.txt`. Screenshots:
`screens/ac-<id>-<seq>-menu-shown.png`, `-typed.png`, `-after-tapStart.png`,
`-after-tapEnd.png`, `-done.png`. Also `app-log.txt`, `recording.mp4`,
`Autocorrect.xcresult`.

## Limits

- `ACInputView` is not the engine's view: no Flutter view behind it, no
  framework round trip, no `FlutterTokenizer`, no scribble interaction, no
  autofill, and `insertText` does not report to anyone. Timing is close to the
  Flutter measurement, not equal.
- The keyboard learns: a word typed and kept many times in one simulator may
  stop being corrected. `literalOffered` shows whether a correction was
  pending in each variant.
- Native variants run with inline predictions off, as the engine's view.
- The test reads the prediction bar through accessibility right after typing;
  whether that changes anything for the keyboard is not known (every variant
  does the same).
