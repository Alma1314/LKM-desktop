import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'package:island/admin/admin_pod.dart';
import 'package:island/admin/admin_widgets.dart';
import 'package:island/core/api/admin_api.dart';
import 'package:island/core/api/api_client.dart';
import 'package:island/shared/widgets/alert.dart';

/// `/admin/moderation/rules`: the auto-review rules. Every write needs a TOTP
/// step-up; the service checks `admin.moderation_manage` on top of that.
class AdminRulesTab extends HookConsumerWidget {
  const AdminRulesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(adminRulesProvider);

    Future<void> edit([AdminRule? rule]) async {
      final draft = await showDialog<_RuleDraft>(
        context: context,
        builder: (_) => _RuleEditorDialog(rule: rule),
      );
      if (draft == null || !context.mounted) return;
      try {
        await runAdminAction(context, ref, () {
          final api = ref.read(adminApiProvider);
          return rule == null
              ? api.createRule(
                  pattern: draft.pattern,
                  isRegex: draft.isRegex,
                  action: draft.action,
                  weight: draft.weight,
                  enabled: draft.enabled,
                )
              : api.updateRule(
                  rule.id,
                  pattern: draft.pattern,
                  isRegex: draft.isRegex,
                  action: draft.action,
                  weight: draft.weight,
                  enabled: draft.enabled,
                );
        });
        ref.invalidate(adminRulesProvider);
      } on ApiException catch (error) {
        if (context.mounted) showSnackBar(error.message);
      }
    }

    Future<void> toggle(AdminRule rule, bool enabled) async {
      try {
        await runAdminAction(
          context,
          ref,
          () => ref.read(adminApiProvider).updateRule(rule.id, enabled: enabled),
        );
        ref.invalidate(adminRulesProvider);
      } on ApiException catch (error) {
        if (context.mounted) showSnackBar(error.message);
      }
    }

    Future<void> removeRule(AdminRule rule) async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(
            'adminPanel.ruleDeleteConfirm'.tr(args: [rule.pattern]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('cancel'.tr()),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('delete'.tr()),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      try {
        await runAdminAction(
          context,
          ref,
          () => ref.read(adminApiProvider).deleteRule(rule.id),
        );
        ref.invalidate(adminRulesProvider);
      } on ApiException catch (error) {
        if (context.mounted) showSnackBar(error.message);
      }
    }

    Future<void> test() => showDialog<void>(
      context: context,
      builder: (_) => const _RuleTestDialog(),
    );

    return rules.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: AdminErrorText(
          error: error,
          onRetry: () => ref.invalidate(adminRulesProvider),
        ),
      ),
      data: (items) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'adminPanel.rulesCount'.tr(args: ['${items.length}']),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                TextButton.icon(
                  onPressed: test,
                  icon: const Icon(Symbols.science),
                  label: Text('adminPanel.ruleTest'.tr()),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => edit(),
                  icon: const Icon(Symbols.add),
                  label: Text('adminPanel.ruleAdd'.tr()),
                ),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? Center(child: Text('adminPanel.ruleEmpty'.tr()))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final rule = items[index];
                      return Card(
                        elevation: 0,
                        child: ListTile(
                          leading: Icon(
                            rule.enabled ? Symbols.gavel : Symbols.block,
                          ),
                          title: Text(
                            rule.pattern,
                            style: const TextStyle(fontFamily: 'monospace'),
                          ),
                          subtitle: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              _chip(
                                rule.isRegex
                                    ? 'adminPanel.ruleRegex'.tr()
                                    : 'adminPanel.rulePlain'.tr(),
                              ),
                              _chip(
                                rule.action == 'hide'
                                    ? 'adminPanel.actionHide'.tr()
                                    : 'adminPanel.actionDerank'.tr(),
                              ),
                              _chip(
                                'adminPanel.ruleWeightChip'.tr(
                                  args: [rule.weight.toStringAsFixed(2)],
                                ),
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Switch(
                                value: rule.enabled,
                                onChanged: (value) => toggle(rule, value),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'edit') edit(rule);
                                  if (value == 'delete') removeRule(rule);
                                },
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text('edit'.tr()),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('delete'.tr()),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  static Widget _chip(String text) => Chip(
    label: Text(text),
    visualDensity: VisualDensity.compact,
    padding: EdgeInsets.zero,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}

class _RuleDraft {
  const _RuleDraft({
    required this.pattern,
    required this.isRegex,
    required this.action,
    required this.weight,
    required this.enabled,
  });

  final String pattern;
  final bool isRegex;
  final String action;
  final double weight;
  final bool enabled;
}

class _RuleEditorDialog extends HookWidget {
  const _RuleEditorDialog({this.rule});

  final AdminRule? rule;

  @override
  Widget build(BuildContext context) {
    final pattern = useTextEditingController(text: rule?.pattern ?? '');
    final isRegex = useState(rule?.isRegex ?? false);
    final action = useState(rule?.action ?? 'derank');
    final weight = useState(rule?.weight ?? 0.5);
    final enabled = useState(rule?.enabled ?? true);
    final error = useState<String?>(null);

    void submit() {
      final text = pattern.text.trim();
      if (text.isEmpty) {
        error.value = 'adminPanel.rulePatternRequired'.tr();
        return;
      }
      Navigator.of(context).pop(
        _RuleDraft(
          pattern: text,
          isRegex: isRegex.value,
          action: action.value,
          weight: weight.value,
          enabled: enabled.value,
        ),
      );
    }

    return AlertDialog(
      title: Text(
        rule == null ? 'adminPanel.ruleAdd'.tr() : 'adminPanel.ruleEdit'.tr(),
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: pattern,
                autofocus: true,
                maxLength: 255,
                decoration: InputDecoration(
                  labelText: 'adminPanel.rulePattern'.tr(),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('adminPanel.ruleRegex'.tr()),
                value: isRegex.value,
                onChanged: (value) => isRegex.value = value,
              ),
              DropdownButtonFormField<String>(
                value: action.value,
                decoration: InputDecoration(
                  labelText: 'adminPanel.ruleAction'.tr(),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'derank',
                    child: Text('adminPanel.actionDerank'.tr()),
                  ),
                  DropdownMenuItem(
                    value: 'hide',
                    child: Text('adminPanel.actionHide'.tr()),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) action.value = value;
                },
              ),
              const SizedBox(height: 12),
              Text(
                'adminPanel.ruleWeightChip'.tr(
                  args: [weight.value.toStringAsFixed(2)],
                ),
              ),
              Slider(
                value: weight.value,
                divisions: 20,
                label: weight.value.toStringAsFixed(2),
                onChanged: (value) => weight.value = value,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('adminPanel.ruleEnabled'.tr()),
                value: enabled.value,
                onChanged: (value) => enabled.value = value,
              ),
              if (error.value != null)
                Text(
                  error.value!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('cancel'.tr()),
        ),
        FilledButton(onPressed: submit, child: Text('save'.tr())),
      ],
    );
  }
}

class _RuleTestDialog extends HookConsumerWidget {
  const _RuleTestDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = useTextEditingController();
    final result = useState<AdminRuleTestResult?>(null);
    final busy = useState(false);

    Future<void> run() async {
      if (text.text.trim().isEmpty || busy.value) return;
      busy.value = true;
      try {
        final value = await ref
            .read(adminApiProvider)
            .testRules(text.text.trim());
        result.value = value;
      } on ApiException catch (error) {
        if (context.mounted) showSnackBar(error.message);
      } finally {
        busy.value = false;
      }
    }

    final hit = result.value;
    return AlertDialog(
      title: Text('adminPanel.ruleTest'.tr()),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: text,
              autofocus: true,
              minLines: 3,
              maxLines: 6,
              maxLength: 5000,
              decoration: InputDecoration(
                labelText: 'adminPanel.ruleTestHint'.tr(),
              ),
            ),
            if (hit != null) ...[
              const SizedBox(height: 8),
              Text(
                hit.matched
                    ? 'adminPanel.ruleMatched'.tr()
                    : 'adminPanel.ruleNotMatched'.tr(),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: hit.shouldHide
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
              ),
              Text(
                'adminPanel.rulePenalty'.tr(
                  args: [hit.penalty.toStringAsFixed(2)],
                ),
              ),
              Text(
                'adminPanel.ruleTotal'.tr(args: ['${hit.totalRules}']),
              ),
              if (hit.hits.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final item in hit.hits)
                  Text(
                    '• ${item.pattern} (${item.action}, '
                    '${item.weight.toStringAsFixed(2)})',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('close'.tr()),
        ),
        FilledButton(
          onPressed: busy.value ? null : run,
          child: Text(busy.value ? 'loading'.tr() : 'submit'.tr()),
        ),
      ],
    );
  }
}
