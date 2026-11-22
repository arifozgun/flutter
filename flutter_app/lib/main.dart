import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// A Flutter app for looking at the iOS system edit menu on a simulator.
///
/// One light screen with six text fields (see [_ProbePageState._fields]), a
/// status area that shows the state of the focused field, and a log file in the
/// app's Documents folder. The XCUITests in this repository drive it by bundle
/// id and read the status area through its semantics identifier.
///
/// The `Sized` button in the header (identifier `probe-page`) switches to a
/// second page with other fields: one per autofill configuration that gives
/// the engine's text input view a different frame (see
/// [_ProbePageState._sizedFields]); `Main` switches back. A launch environment
/// cannot select the page: Dart's `Platform.environment` is empty on iOS.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Without this, Flutter only builds its semantics tree when an assistive
  // technology is on, and XCUITest sees no identifiers or labels.
  SemanticsBinding.instance.ensureSemantics();
  runApp(const MenuProbeApp());
}

/// Appends lines to a file in the app's Documents folder, with dart:io only.
class ProbeLog {
  ProbeLog() : _file = _open();

  final File? _file;

  /// Where the log goes, or 'unavailable'.
  String get path => _file?.path ?? 'unavailable';

  static File? _open() {
    try {
      // On iOS the temp folder is <container>/tmp, next to <container>/Documents.
      String temp = Directory.systemTemp.path;
      while (temp.length > 1 && temp.endsWith('/')) {
        temp = temp.substring(0, temp.length - 1);
      }
      final documents = Directory('${Directory(temp).parent.path}/Documents');
      documents.createSync(recursive: true);
      final file = File('${documents.path}/menu_probe_log.txt');
      file.writeAsStringSync('', mode: FileMode.append, flush: true);
      return file;
    } on Object {
      return null;
    }
  }

  void write(String line) {
    final File? file = _file;
    if (file == null) {
      return;
    }
    try {
      file.writeAsStringSync('t=${_stamp()} $line\n', mode: FileMode.append, flush: true);
    } on Object {
      // A failed log write must not disturb the probe.
    }
  }

  static String _stamp() => (DateTime.now().millisecondsSinceEpoch / 1000).toStringAsFixed(3);
}

class MenuProbeApp extends StatelessWidget {
  const MenuProbeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.light, useMaterial3: true),
      home: const _ProbePage(),
    );
  }
}

enum _Kind { material, cupertino, selectable }

/// One field of the screen and everything the probe knows about it.
class _Field {
  _Field({
    required this.id,
    required this.title,
    required this.kind,
    required this.text,
    this.multiline = false,
    this.obscured = false,
    this.autofillHints = const <String>[],
    this.inAutofillGroup = false,
  }) : controller = TextEditingController(text: text),
       focusNode = FocusNode(debugLabel: id);

  final String id;
  final String title;
  final _Kind kind;
  final String text;
  final bool multiline;
  final bool obscured;

  /// Passed to the TextField as is. The default is TextField's own default, an
  /// empty list, which still sends an autofill configuration to the engine;
  /// null sends none.
  final List<String>? autofillHints;

  /// Whether the field is inside the page's [AutofillGroup].
  final bool inAutofillGroup;
  final TextEditingController controller;
  final FocusNode focusNode;

  /// Key of the box that holds the text, for measuring where the text is.
  final GlobalKey boxKey = GlobalKey();

  /// SelectableText has no controller; its selection comes from a callback.
  TextSelection selectableSelection = const TextSelection.collapsed(offset: -1);

  String lastLogged = '';

  TextSelection get selection =>
      kind == _Kind.selectable ? selectableSelection : controller.selection;

  TextRange get composing => kind == _Kind.selectable ? TextRange.empty : controller.value.composing;

  /// The distance from the box's corner to the text.
  Offset get inset => switch (kind) {
    _Kind.material => const Offset(12, 10),
    _Kind.cupertino => const Offset(7, 7),
    _Kind.selectable => const Offset(12, 10),
  };

  void dispose() {
    controller.dispose();
    focusNode.dispose();
  }
}

/// What the status area shows (`visible`) and what its accessibility label
/// holds (`semantic`: the visible lines plus the position of the selection and
/// of each word on screen, in points, for the UI tests).
typedef _StatusView = ({String visible, String semantic});

const TextStyle _fieldStyle = TextStyle(fontSize: 16);

class _ProbePage extends StatefulWidget {
  const _ProbePage();

  @override
  State<_ProbePage> createState() => _ProbePageState();
}

class _ProbePageState extends State<_ProbePage> {
  final ProbeLog _log = ProbeLog();
  final ScrollController _scroll = ScrollController();
  final ValueNotifier<_StatusView> _status = ValueNotifier<_StatusView>((
    visible: 'field=none',
    semantic: 'field=none',
  ));
  late final List<_Field> _mainPage;
  late final List<_Field> _sizedPage;
  _Field? _active;
  Timer? _timer;
  int _epoch = 0;
  String _lastCustom = '-';

  /// The page on screen: `main` or `sized`.
  String _page = 'main';

  List<_Field> get _fields => _page == 'sized' ? _sizedPage : _mainPage;

  @override
  void initState() {
    super.initState();
    _mainPage = _mainFields();
    _sizedPage = _sizedFields();
    for (final f in [..._mainPage, ..._sizedPage]) {
      f.controller.addListener(() => _onChanged(f));
      f.focusNode.addListener(() => _onFocus(f));
    }
    _log.write('start page=$_page log=${_log.path}');
    _timer = Timer.periodic(const Duration(milliseconds: 300), (_) => _refresh());
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  static const String _sentence = 'The quiet harbor sailed away';

  static List<_Field> _mainFields() {
    const sentence = _sentence;
    return <_Field>[
      _Field(id: 'single', title: 'Single-line TextField', kind: _Kind.material, text: sentence),
      _Field(
        id: 'multi',
        title: 'Multiline TextField',
        kind: _Kind.material,
        text: 'Alpha beta\nGamma delta\nEpsilon zeta',
        multiline: true,
      ),
      _Field(
        id: 'obscured',
        title: 'Obscured TextField',
        kind: _Kind.material,
        text: 'swordfish',
        obscured: true,
      ),
      _Field(id: 'cupertino', title: 'CupertinoTextField', kind: _Kind.cupertino, text: sentence),
      _Field(
        id: 'custom',
        title: 'TextField with custom menu items',
        kind: _Kind.material,
        text: sentence,
      ),
      _Field(id: 'selectable', title: 'SelectableText', kind: _Kind.selectable, text: sentence),
    ];
  }

  /// Fields whose configurations put the engine's FlutterTextInputView into
  /// each frame it can have on a simulator. An autofill configuration (any
  /// non-null autofillHints) or obscured text gives it a 1x1 frame on iPhone;
  /// no autofill configuration gives it a zero frame. On iPad (Scribble) it
  /// gets the field's size whatever the configuration. README.md has the table.
  static List<_Field> _sizedFields() {
    const sentence = _sentence;
    return <_Field>[
      _Field(
        id: 'sized-plain',
        title: 'TextField, default autofillHints (empty list): 1x1, no autofill type',
        kind: _Kind.material,
        text: sentence,
      ),
      _Field(
        id: 'sized-nohints',
        title: 'TextField, autofillHints: null: zero frame',
        kind: _Kind.material,
        text: sentence,
        autofillHints: null,
      ),
      _Field(
        id: 'sized-email',
        title: 'TextField, autofillHints: [email]: 1x1, regular autofill',
        kind: _Kind.material,
        text: sentence,
        autofillHints: const <String>[AutofillHints.email],
      ),
      _Field(
        id: 'sized-username',
        title: 'AutofillGroup, username: 1x1, password autofill (secure view)',
        kind: _Kind.material,
        text: sentence,
        autofillHints: const <String>[AutofillHints.username],
        inAutofillGroup: true,
      ),
      _Field(
        id: 'sized-password',
        title: 'AutofillGroup, password (obscured)',
        kind: _Kind.material,
        text: 'swordfish',
        obscured: true,
        autofillHints: const <String>[AutofillHints.password],
        inAutofillGroup: true,
      ),
    ];
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    _status.dispose();
    for (final f in [..._mainPage, ..._sizedPage]) {
      f.dispose();
    }
    super.dispose();
  }

  String _describe(_Field f) {
    final TextSelection sel = f.selection;
    final TextRange comp = f.composing;
    return 'field=${f.id} text=${jsonEncode(f.controller.text)} '
        'sel=${sel.baseOffset}..${sel.extentOffset} composing=${comp.start}..${comp.end}';
  }

  void _logState(_Field f, String event) {
    final String line = _describe(f);
    if (event == 'change' && line == f.lastLogged) {
      return;
    }
    f.lastLogged = line;
    _log.write('$event $line');
  }

  void _onChanged(_Field f) {
    if (f.focusNode.hasFocus) {
      _active = f;
    }
    _logState(f, 'change');
    _refresh();
  }

  void _onFocus(_Field f) {
    if (f.focusNode.hasFocus) {
      _active = f;
    }
    _logState(f, f.focusNode.hasFocus ? 'focus-gained' : 'focus-lost');
    _refresh();
  }

  void _onSelectableChanged(_Field f, TextSelection selection) {
    f.selectableSelection = selection;
    _active = f;
    _logState(f, 'change');
    _refresh();
  }

  void _onCustomItem(String title) {
    _lastCustom = title;
    _log.write('custom-item title=$title pressed');
    _refresh();
  }

  void _customA() => _onCustomItem('Custom A');

  void _customB() => _onCustomItem('Custom B');

  void _reset() {
    _log.write('reset');
    FocusManager.instance.primaryFocus?.unfocus();
    for (final f in _fields) {
      f.controller.value = TextEditingValue(text: f.text);
      f.selectableSelection = const TextSelection.collapsed(offset: -1);
    }
    _active = null;
    _lastCustom = '-';
    // A new key resets the SelectableText's own selection.
    setState(() => _epoch++);
    if (_scroll.hasClients) {
      _scroll.jumpTo(0);
    }
    _refresh();
  }

  /// Switches between the main page and the sized page, with no focus.
  void _togglePage() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _page = _page == 'sized' ? 'main' : 'sized');
    _active = null;
    _log.write('page=$_page');
    if (_scroll.hasClients) {
      _scroll.jumpTo(0);
    }
    _refresh();
  }

  void _done() {
    _log.write('done (keyboard dismissed)');
    FocusManager.instance.primaryFocus?.unfocus();
    _refresh();
  }

  // MARK: Status

  void _refresh() {
    if (!mounted) {
      return;
    }
    final _Field? f = _active;
    if (f == null) {
      _status.value = (visible: 'field=none custom=$_lastCustom', semantic: 'field=none');
      return;
    }
    final TextSelection sel = f.selection;
    final TextRange comp = f.composing;
    final String head = 'field=${f.id} focus=${f.focusNode.hasFocus}';
    final String text = 'text=${jsonEncode(f.controller.text)}';
    final String tail =
        'base=${sel.baseOffset} extent=${sel.extentOffset} '
        'composing=${comp.start}..${comp.end} custom=$_lastCustom';
    final (:selRect, :words) = _geometry(f);
    _status.value = (
      visible: '$head\n$text\n$tail',
      semantic: '$head\n$text\n$tail\nselRect=$selRect\nwords=$words',
    );
  }

  /// The selection and each word of [f] on screen, in points, found by laying
  /// the text out again with the field's style. Good to a few points.
  ({String selRect, String words}) _geometry(_Field f) {
    const none = (selRect: '-', words: '-');
    final BuildContext? context = f.boxKey.currentContext;
    final RenderObject? render = context?.findRenderObject();
    if (context == null || render is! RenderBox || !render.attached || !render.hasSize) {
      return none;
    }
    if (f.obscured) {
      return none;
    }
    final TextStyle style = switch (f.kind) {
      _Kind.material => Theme.of(context).textTheme.bodyLarge!.merge(_fieldStyle),
      _Kind.cupertino => CupertinoTheme.of(context).textTheme.textStyle,
      _Kind.selectable => DefaultTextStyle.of(context).style.merge(_fieldStyle),
    };
    final String text = f.controller.text;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: f.multiline ? null : 1,
    )..layout(maxWidth: render.size.width - 2 * f.inset.dx);
    final Offset origin = render.localToGlobal(Offset.zero) + f.inset;

    String? rectOf(int start, int end) {
      final int a = start < end ? start : end;
      final int b = start < end ? end : start;
      if (a < 0 || b > text.length) {
        return null;
      }
      Rect rect;
      if (a == b) {
        final Offset caret = painter.getOffsetForCaret(TextPosition(offset: a), Rect.zero);
        rect = Rect.fromLTWH(caret.dx, caret.dy, 0, painter.preferredLineHeight);
      } else {
        final List<TextBox> boxes = painter.getBoxesForSelection(
          TextSelection(baseOffset: a, extentOffset: b),
        );
        if (boxes.isEmpty) {
          return null;
        }
        rect = boxes.map((TextBox box) => box.toRect()).reduce((Rect x, Rect y) => x.expandToInclude(y));
      }
      final Rect global = rect.shift(origin);
      return '${global.left.toStringAsFixed(1)},${global.top.toStringAsFixed(1)},'
          '${global.right.toStringAsFixed(1)},${global.bottom.toStringAsFixed(1)}';
    }

    final TextSelection sel = f.selection;
    final String selRect = rectOf(sel.baseOffset, sel.extentOffset) ?? '-';
    final words = <String>[];
    for (final RegExpMatch match in RegExp(r'\S+').allMatches(text)) {
      final String? rect = rectOf(match.start, match.end);
      if (rect != null) {
        words.add('${match.group(0)}@$rect');
      }
    }
    painter.dispose();
    return (selRect: selRect, words: words.isEmpty ? '-' : words.join(';'));
  }

  // MARK: Context menu with an explicit item list

  Widget _customMenuBuilder(BuildContext context, EditableTextState state) {
    final bool system = SystemContextMenu.isSupportedByField(state);
    _log.write('menu-build field=custom systemMenu=$system');
    if (!system) {
      return AdaptiveTextSelectionToolbar.editableText(editableTextState: state);
    }
    return SystemContextMenu.editableText(
      editableTextState: state,
      items: <IOSSystemContextMenuItem>[
        const IOSSystemContextMenuItemCut(),
        const IOSSystemContextMenuItemCopy(),
        IOSSystemContextMenuItemCustom(title: 'Custom A', onPressed: _customA),
        const IOSSystemContextMenuItemPaste(),
        const IOSSystemContextMenuItemSelectAll(),
        const IOSSystemContextMenuItemLookUp(),
        const IOSSystemContextMenuItemSearchWeb(),
        const IOSSystemContextMenuItemShare(),
        IOSSystemContextMenuItemCustom(title: 'Custom B', onPressed: _customB),
      ],
    );
  }

  // MARK: Layout

  @override
  Widget build(BuildContext context) {
    final bool supported = SystemContextMenu.isSupported(context);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _header(supported),
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                children: <Widget>[
                  for (final f in _fields)
                    if (!f.inAutofillGroup) _block(f),
                  if (_fields.any((f) => f.inAutofillGroup))
                    AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          for (final f in _fields)
                            if (f.inAutofillGroup) _block(f),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            _statusArea(),
          ],
        ),
      ),
    );
  }

  Widget _header(bool supported) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Semantics(
              identifier: 'supported',
              container: true,
              child: Text(
                'SystemContextMenu.isSupported: $supported',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          Semantics(
            identifier: 'probe-page',
            container: true,
            child: TextButton(
              onPressed: _togglePage,
              child: Text(_page == 'sized' ? 'Main' : 'Sized'),
            ),
          ),
          Semantics(
            identifier: 'probe-reset',
            container: true,
            child: TextButton(onPressed: _reset, child: const Text('Reset')),
          ),
          Semantics(
            identifier: 'probe-done',
            container: true,
            child: TextButton(onPressed: _done, child: const Text('Done')),
          ),
        ],
      ),
    );
  }

  Widget _block(_Field f) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(f.title, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 4),
          Semantics(identifier: 'field-${f.id}', container: true, child: _input(f)),
        ],
      ),
    );
  }

  static const InputDecoration _decoration = InputDecoration(
    border: OutlineInputBorder(),
    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    isDense: true,
  );

  Widget _input(_Field f) {
    switch (f.kind) {
      case _Kind.cupertino:
        // The default context menu of CupertinoTextField.
        return CupertinoTextField(key: f.boxKey, controller: f.controller, focusNode: f.focusNode);
      case _Kind.selectable:
        return Container(
          key: f.boxKey,
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(border: Border.all(color: Colors.black38)),
          width: double.infinity,
          child: SelectableText(
            f.text,
            key: ValueKey<int>(_epoch),
            focusNode: f.focusNode,
            style: _fieldStyle,
            onSelectionChanged: (TextSelection selection, SelectionChangedCause? cause) =>
                _onSelectableChanged(f, selection),
          ),
        );
      case _Kind.material:
        if (f.id == 'custom') {
          return TextField(
            key: f.boxKey,
            controller: f.controller,
            focusNode: f.focusNode,
            style: _fieldStyle,
            decoration: _decoration,
            contextMenuBuilder: _customMenuBuilder,
          );
        }
        // The default context menu: the system menu on iOS when it is supported.
        return TextField(
          key: f.boxKey,
          controller: f.controller,
          focusNode: f.focusNode,
          obscureText: f.obscured,
          minLines: f.multiline ? 3 : 1,
          maxLines: f.multiline ? null : 1,
          keyboardType: f.multiline ? TextInputType.multiline : TextInputType.text,
          autofillHints: f.autofillHints,
          style: _fieldStyle,
          decoration: _decoration,
        );
    }
  }

  Widget _statusArea() {
    return Container(
      width: double.infinity,
      color: const Color(0xFFF2F2F2),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: ValueListenableBuilder<_StatusView>(
        valueListenable: _status,
        builder: (BuildContext context, _StatusView view, Widget? child) {
          return Semantics(
            identifier: 'status',
            container: true,
            label: view.semantic,
            excludeSemantics: true,
            child: Text(
              view.visible,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'Menlo', fontSize: 10, color: Colors.black87),
            ),
          );
        },
      ),
    );
  }
}
