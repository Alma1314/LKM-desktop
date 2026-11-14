import 'package:cupertino_ui/cupertino_ui.dart' as cupertino;
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pinput/pinput.dart';

void main() {
  testWidgets('shared UI supports the OHOS platform and text input', (
    tester,
  ) async {
    final editor = QuillController.basic();
    addTearDown(editor.dispose);

    expect(
      VisualDensity.defaultDensityForPlatform(TargetPlatform.ohos),
      VisualDensity.standard,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.ohos),
        home: Scaffold(
          body: Column(
            children: [
              const Pinput(length: 4),
              Math.tex('x + 1'),
              cupertino.CupertinoButton(
                onPressed: () {},
                child: const Text('Continue'),
              ),
              Expanded(child: QuillEditor.basic(controller: editor)),
            ],
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(Pinput), '1234');
    await tester.pump();
    expect(find.text('Continue'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant({TargetPlatform.ohos}));
}
