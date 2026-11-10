import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'package:island/admin/admin_pod.dart';
import 'package:island/core/api/api_client.dart';
import 'package:island/shared/widgets/alert.dart';

/// Runs one dangerous admin write, stepping up with TOTP when the service
/// answers `MFA_REQUIRED` and replaying it once after a successful step-up.
///
/// Returns null when the user cancels or the code is rejected; non-MFA
/// failures are rethrown so the calling screen can refresh/show its own error.
Future<T?> runAdminAction<T>(
  BuildContext context,
  WidgetRef ref,
  Future<T> Function() action,
) async {
  try {
    return await action();
  } on ApiException catch (error) {
    if (error.code != ApiCode.mfaRequired) rethrow;
    if (!context.mounted) return null;
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const _MfaDialog(),
    );
    if (code == null || code.isEmpty) return null;
    try {
      await ref.read(adminApiProvider).verify2fa(code);
    } on ApiException catch (verifyError) {
      if (context.mounted) showSnackBar(verifyError.message);
      return null;
    }
    return await action();
  }
}

class _MfaDialog extends HookConsumerWidget {
  const _MfaDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = useTextEditingController();
    return AlertDialog(
      title: Text('adminPanel.mfaTitle'.tr()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('adminPanel.mfaHint'.tr()),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'adminPanel.mfaCode'.tr(),
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('cancel'.tr()),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(controller.text.trim()),
          child: Text('adminPanel.verify'.tr()),
        ),
      ],
    );
  }
}

/// Lazy page stepper shared by the admin lists. The service returns
/// `{page, pages}` on every paged endpoint, so no total-count math is needed.
class AdminPager extends StatelessWidget {
  const AdminPager({
    super.key,
    required this.page,
    required this.pages,
    required this.onPage,
  });

  final int page;
  final int pages;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'adminPanel.previous'.tr(),
          onPressed: page > 1 ? () => onPage(page - 1) : null,
          icon: const Icon(Symbols.chevron_left),
        ),
        Text(
          '$page / ${pages < 1 ? 1 : pages}',
          style: theme.textTheme.bodySmall,
        ),
        IconButton(
          tooltip: 'adminPanel.next'.tr(),
          onPressed: page < pages ? () => onPage(page + 1) : null,
          icon: const Icon(Symbols.chevron_right),
        ),
      ],
    );
  }
}

/// One-line failure with a retry affordance, used under every admin list.
class AdminErrorText extends StatelessWidget {
  const AdminErrorText({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(
            '$error',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: Text('retry'.tr())),
        ],
      ),
    );
  }
}

/// `yyyy-MM-dd HH:mm` in local time; avoids pulling a formatter into every tab.
String adminDate(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

/// Human-readable byte size for the file queue.
String adminFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
