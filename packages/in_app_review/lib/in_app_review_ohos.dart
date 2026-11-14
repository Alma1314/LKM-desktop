import 'package:flutter/services.dart';
import 'package:in_app_review_platform_interface/in_app_review_platform_interface.dart';
import 'package:in_app_review_platform_interface/method_channel_in_app_review.dart';

/// OHOS uses the same review channel and opens the current app's store listing.
class InAppReviewOhos extends MethodChannelInAppReview {
  static void registerWith() {
    InAppReviewPlatform.instance = InAppReviewOhos();
  }

  @override
  Future<void> openStoreListing({
    String? appStoreId,
    String? microsoftStoreId,
  }) =>
      const MethodChannel(
        'dev.britannio.in_app_review',
      ).invokeMethod<void>('openStoreListing');
}
