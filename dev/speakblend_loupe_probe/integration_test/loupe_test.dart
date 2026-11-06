import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:loupe_probe/main.dart';

/// Drives slow long-press drags over each field so that a screen recording of
/// the simulator shows how the magnifier opens, follows the touch and closes.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  final stopwatch = Stopwatch();

  void mark(String step) {
    // Matched against the recording to find each step.
    debugPrint('LOUPE_STEP ${stopwatch.elapsedMilliseconds} $step');
  }

  Future<void> wait(WidgetTester tester, int milliseconds) async {
    await tester.binding.delayed(Duration(milliseconds: milliseconds));
  }

  Future<void> longPressDrag(
    WidgetTester tester,
    String name,
    Finder field,
    Offset Function(Rect rect) start,
    Offset Function(Rect rect) end, {
    int steps = 50,
  }) async {
    // Focusing the field first lets the keyboard and the scroll position
    // settle, so the drag starts where the field is drawn.
    await tester.ensureVisible(field);
    await wait(tester, 400);
    await tester.tap(field);
    await wait(tester, 1200);
    await tester.ensureVisible(field);
    await wait(tester, 600);
    final Rect rect = tester.getRect(field);
    final Offset from = start(rect);
    final Offset to = end(rect);
    mark('$name down');
    final TestGesture gesture = await tester.startGesture(from);
    await wait(tester, 900);
    mark('$name drag');
    for (var i = 1; i <= steps; i += 1) {
      await gesture.moveTo(Offset.lerp(from, to, i / steps)!);
      await wait(tester, 40);
    }
    await wait(tester, 600);
    mark('$name up');
    await gesture.up();
    await wait(tester, 1200);
  }

  testWidgets('long-press drags over every field', (WidgetTester tester) async {
    await tester.pumpWidget(const LoupeProbeApp());
    await wait(tester, 1500);
    stopwatch.start();
    mark('start');

    // The text fields' editables; SelectableText has an EditableText too.
    // Fields scrolled out of view count too; ensureVisible scrolls to them.
    final Finder editable = find.descendant(
      of: find.byType(TextField, skipOffstage: false),
      matching: find.byType(EditableText, skipOffstage: false),
      skipOffstage: false,
    );

    // Single line: from the end of the text to its start.
    await longPressDrag(
      tester,
      'single line',
      editable.at(0),
      (Rect rect) => Offset(rect.right - 20, rect.center.dy),
      (Rect rect) => Offset(rect.left + 10, rect.center.dy),
    );

    // Multiline: from the start of the first line to the end of the last.
    await longPressDrag(
      tester,
      'multiline',
      editable.at(1),
      (Rect rect) => Offset(rect.left + 20, rect.top + 8),
      (Rect rect) => Offset(rect.right - 20, rect.bottom - 8),
    );

    // Selectable text: a long press selects a word, dragging extends it.
    await longPressDrag(
      tester,
      'selectable text',
      find.byType(SelectableText),
      (Rect rect) => Offset(rect.left + 30, rect.top + 6),
      (Rect rect) => Offset(rect.right - 30, rect.bottom - 6),
    );

    // Very large text: the caret is taller than the loupe.
    await longPressDrag(
      tester,
      'large text',
      editable.at(2),
      (Rect rect) => Offset(rect.right - 10, rect.center.dy),
      (Rect rect) => Offset(rect.left + 10, rect.center.dy),
      steps: 40,
    );

    // The same single line drag with Flutter's own magnifier, for comparison.
    final Finder toggle = find.byType(Switch, skipOffstage: false);
    await tester.ensureVisible(toggle);
    await wait(tester, 400);
    await tester.tap(toggle);
    await wait(tester, 800);
    mark('flutter magnifier');
    await longPressDrag(
      tester,
      'flutter single line',
      editable.at(0),
      (Rect rect) => Offset(rect.right - 20, rect.center.dy),
      (Rect rect) => Offset(rect.left + 10, rect.center.dy),
    );
    mark('end');
  });
}
