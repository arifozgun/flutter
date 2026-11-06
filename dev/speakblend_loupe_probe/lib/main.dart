import 'dart:io';

import 'package:flutter/material.dart';

void main() => runApp(const LoupeProbeApp());

/// Compares Flutter's text magnifier with the system loupe shown through
/// [SystemTextMagnifier].
class LoupeProbeApp extends StatefulWidget {
  const LoupeProbeApp({super.key});

  @override
  State<LoupeProbeApp> createState() => _LoupeProbeAppState();
}

class _LoupeProbeAppState extends State<LoupeProbeApp> {
  bool _useSystemLoupe = true;

  final TextEditingController _singleLine = TextEditingController(
    text: 'Long press and drag to move the caret.',
  );
  final TextEditingController _multiline = TextEditingController(
    text: 'A multiline field. Drag across lines to see the loupe follow the '
        'caret from one line to the next.',
  );
  final TextEditingController _large = TextEditingController(text: 'Huge');

  late final TextMagnifierConfiguration _systemConfiguration = TextMagnifierConfiguration(
    magnifierBuilder: (context, controller, magnifierInfo) {
      if (SystemTextMagnifier.isSupported(context)) {
        return SystemTextMagnifier(magnifierInfo: magnifierInfo);
      }
      return TextMagnifier.adaptiveMagnifierConfiguration.magnifierBuilder(
        context,
        controller,
        magnifierInfo,
      );
    },
  );

  TextMagnifierConfiguration get _configuration =>
      _useSystemLoupe ? _systemConfiguration : TextMagnifier.adaptiveMagnifierConfiguration;

  @override
  void dispose() {
    _singleLine.dispose();
    _multiline.dispose();
    _large.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: const Text('Loupe probe')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_useSystemLoupe ? 'System loupe' : 'Flutter magnifier'),
              subtitle: Text(
                _useSystemLoupe ? 'SystemTextMagnifier' : 'CupertinoTextMagnifier',
              ),
              value: _useSystemLoupe,
              onChanged: (value) => setState(() => _useSystemLoupe = value),
            ),
            Text('iOS: ${Platform.operatingSystemVersion}'),
            const SizedBox(height: 24),
            TextField(
              magnifierConfiguration: _configuration,
              controller: _singleLine,
              decoration: const InputDecoration(labelText: 'Single line'),
            ),
            const SizedBox(height: 24),
            TextField(
              magnifierConfiguration: _configuration,
              controller: _multiline,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Multiline'),
            ),
            const SizedBox(height: 24),
            SelectableText(
              'Selectable text. Long press a word, then drag a selection '
              'handle to see the loupe while the selection changes.',
              magnifierConfiguration: _configuration,
            ),
            const SizedBox(height: 24),
            // A caret taller than the loupe makes UIKit refuse the cursor,
            // so the loupe begins without one.
            TextField(
              magnifierConfiguration: _configuration,
              controller: _large,
              style: const TextStyle(fontSize: 96),
              decoration: const InputDecoration(labelText: 'Very large text'),
            ),
          ],
        ),
      ),
    );
  }
}
