# Native text loupe probe

A small UIKit app (no Flutter) that answers one question on iOS simulators:

> Does the system text loupe (the magnifier shown while dragging the caret)
> appear in native text views when the text is very large, and does
> `UITextLoupeSession.begin(at:fromSelectionWidgetView:in:)` return a session
> when the caret is taller than the loupe?

Nothing here has a built-in answer. The app, the UI test and the workflow only
record what UIKit does; every case passes or fails on whether it could run, not
on whether a loupe appeared.

Everything uses public API. No private selector is called or named in the
source. The loupe's own class names are private, so the app does not look for
one name: it reports every view class that exists after a gesture started and
did not exist before, and marks the ones whose name contains `loupe`, `magnif`
or `lollipop`.

## Cases

The app takes `-case <name>` as a launch argument. The word on every screen is
`Hi`; font sizes are 17, 48, 96, 150 and 220 pt (system font). Every screen
shows the case name, font size, iOS version and live state in plain text.

| Case | View | What happens |
|------|------|--------------|
| `textview-<size>` | `UITextView` | Editable, first responder, caret between `H` and `i`. The UI test long-presses in the word and drags right slowly, holding for about two seconds. UIKit's own gesture should show its loupe. |
| `textfield-<size>` | `UITextField` | The same with a `UITextField`. |
| `session-widget-<size>` | plain `UIView` | The app calls `UITextLoupeSession.begin` itself at the caret, with a `UIStandardTextCursorView` (iOS 17.4+; invisible, not touchable, framed as the caret rect) as the selection widget, then moves the session along the word for two seconds and invalidates it. This is the call a Flutter engine makes. |
| `session-nil-<size>` | plain `UIView` | The same call with a nil selection widget view. |

That is 20 cases, `<size>` being 17, 48, 96, 150 and 220. The caret rect of a
session case is `width 2`, `height = font.lineHeight`, placed after the `H`.
The native cases log UIKit's own caret rect for comparison (`caretHeight`).

## Evidence for the loupe

The loupe exists only while a gesture or session is on, so a still taken
afterwards shows nothing. There are four sources, most certain first:

1. **The screen recording** `recording.mp4`, for the whole run. `events.txt`
   (epoch ms per step) and `runner.txt` (`recording_started_epoch_ms`) let a
   step be found in the video. If `ffmpeg` is on the runner, `frames/` holds one
   still per second.
2. **Timed screenshots from outside the test process**, `shots/<case>-<epoch
   ms>.jpg`. While a gesture or a held session is on, the UI test keeps a file
   `shoot-now` in the output folder and `scripts/shots.sh` takes a
   `simctl io screenshot` every ~0.3 s. Names carry the case and the time.
3. **The app's own hierarchy log.** A 0.1 s timer (also while touches are
   tracked) lists all windows of all scenes, including system ones, and logs
   every change of the view classes in them against a baseline taken before the
   gesture. See below.
4. **UI test screenshots** `screens/<case>-1-ready.png`, `-1-held.png` and so
   on, taken between gestures. For native cases these show the field before and
   after the gesture, not the loupe; for session cases `-1-held` and `-2-held`
   are taken while the session is held.

There is no screenshot taken from inside the gesture by the test process:
`XCUIScreenshotProviding` is main-actor isolated and the gesture call blocks
the test thread, so that would be a nested XCUITest call. The timed `simctl`
screenshots take its place.

The app also writes `shots/inapp-<case>-N.png` (all of its windows drawn into
one image) the first times a loupe-named view appears. A loupe drawn by another
process will not be in them.

## Artifacts

One artifact per job, `loupe-native-probe-xcode<x>-ios<y>`:

- `runner.txt`: Xcodes, selected Xcode, runtimes, the runtime and device chosen.
- `summary.txt`: one line per case from the UI test, with the status label text
  and the app's JSON result.
- `app/results/<case>.json` (and `app-documents/results/`, copied from the app
  container): one JSON line per case, rewritten whenever something changes.
  Keys: `case`, `kind`, `fontSize`, `ios`, `model`, `caretRect` (native: window
  coordinates, session: canvas coordinates), `caretHeight`; native cases:
  `wordRect`, `gestureObserved`, `presses`; session cases: `widget`,
  `sessionReturned` (`false` means `begin` returned nil), `sessionPoint`,
  `moves`; all cases: `loupeSeen`, `loupeClasses`, `loupeFrames`,
  `addedClasses` (class name to count of instances beyond the baseline),
  `baselineClasses`, `lastWindows`.
- `app/log-<case>.txt` (and `app-log.txt` from the unified log, subsystem
  `dev.probe.nativeloupe`): timestamped lines. The ones to read:
  - `beginLoupeSession point=... caretRect=... widget=... -> session=returned|nil`
  - `hierarchy windows=[...] loupe=[Class xN@frame] added=[Class xN@frame]`:
    logged on every change; `added` are classes that appeared after the
    baseline, with the frame of the first instance in window coordinates.
  - `press began` / `press ended`: the app saw the user's long press.
- `recording.mp4`, `frames/`, `shots/`, `screens/`, `hierarchy/` (accessibility
  dumps when a case failed to run), `LoupeProbe.xcresult`, `attachments/`,
  `test-summary.json`, `xcodebuild.log`, `xcodebuild-build.log`.

The job summary prints a table by font size (one cell per case) and a per-case
table with caret heights and the class names.

## Running

The workflow `.github/workflows/loupe-native-probe.yml` runs on a push to
`speakblend/loupe-native-probe` or manually. Three jobs on `macos-15`:

| iOS | Xcode | Runtime |
|-----|-------|---------|
| 26 (newest 26.x) | newest 26 | preinstalled |
| 18.6 | newest 16 | preinstalled |
| 17.5 | newest 16 | downloaded with `xcodebuild -downloadPlatform iOS -buildVersion 17.5` |

The app is written to build with Xcode 16.4 and 26 (not yet compiled by either): deployment target iOS 17.0, and
`UIStandardTextCursorView` is guarded by `#available(iOS 17.4, *)` (so on
iOS 17.0 to 17.3 `session-widget` passes nil and says so in `widget`).

Locally: `xcodebuild test -project LoupeProbe.xcodeproj -scheme LoupeProbe
-destination 'platform=iOS Simulator,name=<device>'` with
`TEST_RUNNER_PROBE_OUT=<dir>` set to collect the files in `<dir>`.
