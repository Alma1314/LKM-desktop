import 'dart:math';

import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';

/// One letter category: the wire value, a visual marker and its label key.
class TreeholeCategory {
  const TreeholeCategory(this.key, this.emoji, this.labelKey);

  final String key;
  final String emoji;
  final String labelKey;
}

/// Mirrors the website's `CATEGORIES` (`constants.ts`).
const List<TreeholeCategory> treeholeCategories = [
  TreeholeCategory('confess', '💌', 'treeholeCatConfess'),
  TreeholeCategory('heart', '🌧️', 'treeholeCatHeart'),
  TreeholeCategory('roast', '🔥', 'treeholeCatRoast'),
  TreeholeCategory('help', '🆘', 'treeholeCatHelp'),
  TreeholeCategory('campus', '🎓', 'treeholeCatCampus'),
  TreeholeCategory('work', '💼', 'treeholeCatWork'),
  TreeholeCategory('crush', '🌙', 'treeholeCatCrush'),
  TreeholeCategory('heal', '🌿', 'treeholeCatHeal'),
  TreeholeCategory('fun', '🎉', 'treeholeCatFun'),
  TreeholeCategory('insight', '💡', 'treeholeCatInsight'),
];

TreeholeCategory treeholeCategory(String key) {
  for (final category in treeholeCategories) {
    if (category.key == key) return category;
  }
  return treeholeCategories.first;
}

const List<(String, String)> treeholeTags = [
  ('academic', 'treeholeTagAcademic'),
  ('campus', 'treeholeTagCampus'),
  ('work', 'treeholeTagWork'),
  ('growth', 'treeholeTagGrowth'),
  ('love', 'treeholeTagLove'),
  ('family', 'treeholeTagFamily'),
  ('life', 'treeholeTagLife'),
];

/// Moods are stored as Chinese words by the service and the website, so they
/// are shown verbatim instead of being mapped through i18n.
const List<String> treeholeMoods = [
  '开心',
  '难过',
  'emo',
  '平静',
  '焦虑',
  '期待',
  '释怀',
  '孤独',
  '心动',
  '疲惫',
  '勇敢',
  '迷茫',
  '感恩',
  '委屈',
  '治愈',
  '懵圈',
];

String treeholeTagLabel(String key) {
  for (final (itemKey, labelKey) in treeholeTags) {
    if (itemKey == key) return labelKey.tr();
  }
  return key;
}

String formatTreeholeTime(DateTime time) {
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

String randomTreeholeCodename() {
  const adjectives = [
    'Night',
    'Lost',
    'Gentle',
    'Silent',
    'Radiant',
    'Lazy',
    'Brave',
    'Sleepless',
    'Strolling',
    'Tipsy',
    'Wind-chasing',
    'Whispering',
  ];
  const nouns = [
    'Cat',
    'Whale',
    'Deer',
    'Courier',
    'Cloud',
    'Traveler',
    'Star',
    'Bear',
    'Robin',
    'Moon',
    'Firefly',
    'Chime',
  ];
  final random = Random.secure();
  final adjective = adjectives[random.nextInt(adjectives.length)];
  final noun = nouns[random.nextInt(nouns.length)];
  return '$adjective$noun${100 + random.nextInt(900)}';
}

/// Report reasons shared with the rest of the app's abuse-report dialog.
const List<String> treeholeReportReasons = [
  'abuseReportTypeInappropriate',
  'abuseReportTypeOffensiveContent',
  'abuseReportTypeHarassment',
  'abuseReportTypeCopyright',
  'abuseReportTypeOther',
];

/// Single-line input dialog shared by replies, bottles and wishes.
Future<String?> showTreeholeTextDialog(
  BuildContext context, {
  required String title,
  String? hint,
  String? initial,
  int maxLength = 1000,
  String confirmKey = 'send',
}) {
  final controller = TextEditingController(text: initial ?? '');
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: maxLength,
        minLines: 2,
        maxLines: 6,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text('cancel'.tr()),
        ),
        FilledButton(
          onPressed: () {
            final text = controller.text.trim();
            if (text.isEmpty) return;
            Navigator.of(dialogContext).pop(text);
          },
          child: Text(confirmKey.tr()),
        ),
      ],
    ),
  );
}

Future<bool> showTreeholeConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmKey = 'confirm',
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text('cancel'.tr()),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(confirmKey.tr()),
            ),
          ],
        ),
      ) ??
      false;
}

Future<String?> showTreeholeReportDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: Text('abuseReportTitle'.tr()),
      children: [
        for (final key in treeholeReportReasons)
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop(key.tr()),
            child: Text(key.tr()),
          ),
      ],
    ),
  );
}
