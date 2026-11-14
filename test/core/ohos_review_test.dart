import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_review/in_app_review.dart';

void main() {
  testWidgets('OHOS reviews use the existing API and native store routing', (
    tester,
  ) async {
    const channel = MethodChannel('dev.britannio.in_app_review');
    final messenger = tester.binding.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    var fail = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (fail) {
        throw PlatformException(code: 'error', details: 1021500006);
      }
      return call.method == 'isAvailable' ? true : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    InAppReviewOhos.registerWith();
    final review = InAppReview.instance;
    expect(await review.isAvailable(), isTrue);
    await review.requestReview();
    await review.openStoreListing();
    expect(calls.map((c) => c.method), [
      'isAvailable',
      'requestReview',
      'openStoreListing',
    ]);
    expect(calls.last.arguments, isNull);
    fail = true;
    expect(await review.isAvailable(), isFalse);
    await expectLater(
      review.requestReview(),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.details,
          'native error',
          1021500006,
        ),
      ),
    );
    await expectLater(
      review.openStoreListing(),
      throwsA(isA<PlatformException>()),
    );
  }, variant: TargetPlatformVariant({TargetPlatform.ohos}));
}
