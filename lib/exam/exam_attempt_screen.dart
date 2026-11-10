import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/exam_api.dart';
import 'package:island/exam/exam_pod.dart';
import 'package:island/shared/widgets/alert.dart';
import 'package:island/shared/widgets/app_scaffold.dart';

/// One attempt: the server already handed us the candidate-safe questions, so
/// everything here is local until the final submit.
@RoutePage()
class ExamAttemptScreen extends HookConsumerWidget {
  const ExamAttemptScreen({super.key, required this.attempt, this.title});

  final ExamAttempt attempt;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final questions = attempt.questions;
    final answers = useState<Map<String, String>>({});
    final index = useState(0);
    final submitting = useState(false);
    final submitted = useState(false);
    final remaining = useState<int?>(_secondsLeft(attempt.deadline));
    final theme = Theme.of(context);

    Future<void> submit({bool auto = false}) async {
      if (submitting.value || submitted.value || questions.isEmpty) return;
      if (!auto) {
        final missing = questions
            .where((q) => !answers.value.containsKey(q.id))
            .length;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('exam.submitExam'.tr()),
            content: Text(
              missing > 0
                  ? 'exam.submitConfirm'.tr(args: ['$missing'])
                  : 'exam.submitConfirmClean'.tr(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('cancel'.tr()),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text('exam.submitExam'.tr()),
              ),
            ],
          ),
        );
        if (confirmed != true || !context.mounted) return;
      }
      submitting.value = true;
      try {
        final result = await ref
            .read(lkmApiSessionProvider)
            .run(
              () => ref
                  .read(examApiProvider)
                  .submitAttempt(attempt.attemptId, answers.value),
            );
        submitted.value = true;
        submitting.value = false;
        ref.invalidate(myCertificatesProvider);
        ref.invalidate(examsProvider);
        ref.invalidate(examLeaderboardProvider(attempt.examId));
        if (!context.mounted) return;
        await _showResult(context, result);
        if (context.mounted) context.router.maybePop();
      } on ApiException catch (err) {
        submitting.value = false;
        if (context.mounted) showSnackBar(err.message);
      } catch (_) {
        submitting.value = false;
        if (context.mounted) showSnackBar('exam.actionFailed'.tr());
      }
    }

    useEffect(() {
      final deadline = attempt.deadline;
      if (deadline == null) return null;
      late final Timer timer;
      timer = Timer.periodic(const Duration(seconds: 1), (_) {
        final left = deadline.difference(DateTime.now()).inSeconds;
        remaining.value = left;
        if (left <= 0) {
          timer.cancel();
          if (!submitted.value) unawaited(submit(auto: true));
        }
      });
      return timer.cancel;
    }, const []);

    final question = questions.isEmpty ? null : questions[index.value];
    final answered = answers.value.length;

    return AppScaffold(
      isNoBackground: false,
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: Text(
          title?.isNotEmpty == true ? title! : 'exam.detail'.tr(),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                remaining.value == null
                    ? 'exam.answered'.tr(
                        args: ['$answered', '${questions.length}'],
                      )
                    : '${'exam.answered'.tr(args: ['$answered', '${questions.length}'])}  '
                          '${_formatSeconds(remaining.value!)}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: remaining.value != null && remaining.value! < 300
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
              ),
            ),
          ),
        ],
      ),
      body: question == null
          ? Center(child: Text('exam.empty'.tr()))
          : Column(
              children: [
                LinearProgressIndicator(
                  value: questions.isEmpty ? 0 : answered / questions.length,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      Text(
                        'exam.questionOf'.tr(
                          args: ['${index.value + 1}', '${questions.length}'],
                        ),
                        style: theme.textTheme.labelLarge,
                      ),
                      const Spacer(),
                      Text(
                        '${question.score}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      Text(
                        question.content,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      ..._optionKeys(question).map(
                        (key) => _OptionTile(
                          label: _optionLabel(question, key),
                          selected: answers.value[question.id] == key,
                          onTap: () {
                            answers.value = {
                              ...answers.value,
                              question.id: key,
                            };
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: index.value == 0
                              ? null
                              : () => index.value -= 1,
                          child: Text('exam.prev'.tr()),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: index.value >= questions.length - 1
                              ? null
                              : () => index.value += 1,
                          child: Text('exam.next'.tr()),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: submitting.value ? null : submit,
                          child: Text(
                            submitting.value
                                ? 'exam.submitting'.tr()
                                : 'exam.submitExam'.tr(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
            color: selected
                ? scheme.primary.withValues(alpha: 0.08)
                : Colors.transparent,
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Symbols.radio_button_checked
                    : Symbols.radio_button_unchecked,
                size: 20,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showResult(BuildContext context, ExamResult result) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('exam.resultTitle'.tr()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('exam.resultScore'.tr(args: ['${result.score}'])),
          Text('exam.passScore'.tr(args: ['${result.passScore}'])),
          const SizedBox(height: 6),
          Text(result.passed ? 'exam.passed'.tr() : 'exam.failed'.tr()),
          if (result.certificateId != null) ...[
            const SizedBox(height: 6),
            Text('exam.certificateIssued'.tr()),
          ],
          if ((result.unlockLevel ?? '').isNotEmpty ||
              (result.unlockRole ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'exam.unlock'.tr(
                args: [
                  [
                    if ((result.unlockLevel ?? '').isNotEmpty)
                      result.unlockLevel!,
                    if ((result.unlockRole ?? '').isNotEmpty) result.unlockRole!,
                  ].join(' / '),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('exam.finish'.tr()),
        ),
      ],
    ),
  );
}

List<String> _optionKeys(ExamQuestion question) {
  if (!question.isJudge) {
    return question.options.map((o) => o.key).toList(growable: false);
  }
  return const ['T', 'F'];
}

String _optionLabel(ExamQuestion question, String key) {
  if (question.isJudge) {
    return key == 'T' ? 'exam.judgeTrue'.tr() : 'exam.judgeFalse'.tr();
  }
  for (final option in question.options) {
    if (option.key == key) return '${option.key}. ${option.text}';
  }
  return key;
}

int? _secondsLeft(DateTime? deadline) {
  if (deadline == null) return null;
  return deadline.difference(DateTime.now()).inSeconds;
}

String _formatSeconds(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  final h = safe ~/ 3600;
  final m = (safe % 3600) ~/ 60;
  final s = safe % 60;
  String two(int value) => value.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}
