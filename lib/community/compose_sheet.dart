import 'dart:async';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mime/mime.dart';

import 'package:island/community/content_detail_pod.dart';
import 'package:island/community/notification_pod.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/content_api.dart';
import 'package:island/core/api/files_api.dart';
import 'package:island/shared/widgets/alert.dart';
import 'package:island/shared/widgets/layouts/sheet_scaffold.dart';

enum _AttachmentStage { uploading, pending, approved, failed }

class _Attachment {
  const _Attachment({
    required this.localId,
    required this.bytes,
    required this.name,
    required this.mime,
    this.stage = _AttachmentStage.uploading,
    this.progress,
    this.fileId,
    this.error,
  });

  final String localId;
  final Uint8List bytes;
  final String name;
  final String mime;
  final _AttachmentStage stage;
  final double? progress;
  final String? fileId;
  final String? error;

  _Attachment copyWith({
    _AttachmentStage? stage,
    double? progress,
    String? fileId,
    String? error,
  }) => _Attachment(
    localId: localId,
    bytes: bytes,
    name: name,
    mime: mime,
    stage: stage ?? this.stage,
    progress: progress ?? this.progress,
    fileId: fileId ?? this.fileId,
    error: error ?? this.error,
  );
}

/// Composes a forum discussion. Only active boards are offered — applying to
/// open a board is a separate review flow left for later.
///
/// Attachments upload immediately and land in `pending`: until a reviewer
/// approves one it is shown as an "under review" placeholder and its URL is
/// never written into the post (decision 3).
class LkmComposeSheet extends HookConsumerWidget {
  const LkmComposeSheet({super.key, this.initialBoardId});

  /// Preselects the board when composing from inside a board page.
  final String? initialBoardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boards = ref.watch(contentBoardsProvider);
    final filesApi = ref.watch(filesApiProvider);
    final session = ref.read(lkmApiSessionProvider);
    final title = useTextEditingController();
    final body = useTextEditingController();
    final tags = useTextEditingController();
    final selected = useState<String?>(initialBoardId);
    final submitting = useState(false);
    final error = useState<String?>(null);
    final attachments = useState<List<_Attachment>>(const []);
    final theme = Theme.of(context);

    final activeBoards = (boards.value ?? const <LkmBoard>[])
        .where((board) => board.isActive)
        .toList(growable: false);
    final boardId = selected.value ??
        (activeBoards.isEmpty ? null : activeBoards.first.id);

    void update(String localId, _Attachment Function(_Attachment) change) {
      attachments.value = [
        for (final attachment in attachments.value)
          attachment.localId == localId ? change(attachment) : attachment,
      ];
    }

    void remove(String localId) {
      attachments.value = [
        for (final attachment in attachments.value)
          if (attachment.localId != localId) attachment,
      ];
    }

    Future<void> uploadAttachment(_Attachment attachment) async {
      try {
        final file = await session.run(
          () => filesApi.upload(
            bytes: attachment.bytes,
            originalName: attachment.name,
            mimeType: attachment.mime,
            onProgress: (progress) => update(
              attachment.localId,
              (current) => current.copyWith(progress: progress),
            ),
          ),
        );
        update(
          attachment.localId,
          (current) => current.copyWith(
            stage: file.isApproved
                ? _AttachmentStage.approved
                : _AttachmentStage.pending,
            fileId: file.id,
            progress: 1,
          ),
        );
      } catch (failure) {
        update(
          attachment.localId,
          (current) => current.copyWith(
            stage: _AttachmentStage.failed,
            error: '$failure',
          ),
        );
      }
    }

    Future<void> refreshAttachment(_Attachment attachment) async {
      final fileId = attachment.fileId;
      if (fileId == null) return;
      try {
        final file = await session.run(() => filesApi.file(fileId));
        if (file.isApproved) {
          update(
            attachment.localId,
            (current) => current.copyWith(stage: _AttachmentStage.approved),
          );
        } else if (file.isRejected) {
          remove(attachment.localId);
          if (context.mounted) showSnackBar('lkmUploadRejected'.tr());
        }
      } catch (_) {
        // Transient lookup failures keep the placeholder; the next tick retries.
      }
    }

    // The service announces a registered upload over the `upload` channel;
    // use it to refresh the placeholder immediately instead of waiting for
    // the next poll tick.
    ref.listen(lkmWsEventsProvider, (_, next) {
      next.whenData((event) {
        if (event.event != 'upload_registered') return;
        final file = event.data['file'];
        final fileId = file is Map ? '${file['id'] ?? ''}' : '';
        if (fileId.isEmpty) return;
        for (final attachment in attachments.value) {
          if (attachment.fileId == fileId) {
            unawaited(refreshAttachment(attachment));
          }
        }
      });
    });

    // Reviews are human-paced: poll the pending rows instead of promising a
    // push channel (the WS only carries notifications).
    useEffect(() {
      final timer = Timer.periodic(const Duration(seconds: 5), (_) {
        for (final attachment in attachments.value) {
          if (attachment.stage == _AttachmentStage.pending &&
              attachment.fileId != null) {
            unawaited(refreshAttachment(attachment));
          }
        }
      });
      return timer.cancel;
    }, const []);

    Future<void> pickImages() async {
      final picked = await FilePicker.pickFiles(type: FileType.image);
      for (final item in picked) {
        final bytes = await item.xFile.readAsBytes();
        if (bytes.isEmpty) continue;
        final attachment = _Attachment(
          localId: '${item.name}-${DateTime.now().microsecondsSinceEpoch}',
          bytes: bytes,
          name: item.name,
          mime: lookupMimeType(item.name) ?? 'application/octet-stream',
        );
        attachments.value = [...attachments.value, attachment];
        unawaited(uploadAttachment(attachment));
      }
    }

    Future<void> submit() async {
      final heading = title.text.trim();
      final content = body.text.trim();
      if (boardId == null ||
          heading.isEmpty ||
          content.isEmpty ||
          submitting.value) {
        return;
      }
      if (attachments.value.any(
        (attachment) => attachment.stage != _AttachmentStage.approved,
      )) {
        error.value = 'lkmUploadWaitReview'.tr();
        return;
      }
      submitting.value = true;
      error.value = null;
      try {
        final withImages = [
          content,
          for (final attachment in attachments.value)
            if (attachment.fileId != null)
              '![${attachment.name}](${filesApi.previewUrl(attachment.fileId!)})',
        ].join('\n\n');
        final id = await session.run(
          () => ref.read(contentApiProvider).createDiscussion(
            boardId: boardId,
            title: heading,
            content: withImages,
            tags: tags.text
                .split(',')
                .map((tag) => tag.trim())
                .where((tag) => tag.isNotEmpty)
                .toSet()
                .toList(growable: false),
          ),
        );
        if (context.mounted) Navigator.of(context).pop(id);
      } catch (failure) {
        error.value = '$failure';
      } finally {
        submitting.value = false;
      }
    }

    return SheetScaffold(
      titleText: 'lkmComposeTitle'.tr(),
      heightFactor: 0.9,
      actions: [
        TextButton(
          onPressed: submitting.value ? null : submit,
          child: submitting.value
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('lkmComposePublish'.tr()),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          boards.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (failure, _) => Text(
              '$failure',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            data: (_) => activeBoards.isEmpty
                ? Text(
                    'lkmComposeEmptyBoards'.tr(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                : DropdownButtonFormField<String>(
                    initialValue: boardId,
                    decoration: InputDecoration(
                      labelText: 'lkmComposeBoard'.tr(),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final board in activeBoards)
                        DropdownMenuItem(
                          value: board.id,
                          child: Text(board.title),
                        ),
                    ],
                    onChanged: (value) => selected.value = value,
                  ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: title,
            decoration: InputDecoration(
              labelText: 'postTitle'.tr(),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: body,
            minLines: 8,
            maxLines: 20,
            decoration: InputDecoration(
              labelText: 'postContent'.tr(),
              border: const OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: tags,
            decoration: InputDecoration(
              labelText: 'tags'.tr(),
              hintText: 'tagsHint'.tr(),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              onPressed: pickImages,
              icon: const Icon(Symbols.add_photo_alternate, size: 18),
              label: Text('lkmAddImage'.tr()),
            ),
          ),
          if (attachments.value.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final attachment in attachments.value)
                  _AttachmentTile(
                    attachment: attachment,
                    onRemove: () => remove(attachment.localId),
                  ),
              ],
            ),
          ],
          if (error.value != null) ...[
            const SizedBox(height: 12),
            Text(
              '$error',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({required this.attachment, required this.onRemove});

  final _Attachment attachment;
  final VoidCallback onRemove;

  String _label() {
    switch (attachment.stage) {
      case _AttachmentStage.uploading:
        final progress = attachment.progress;
        return progress == null
            ? 'lkmUploadUploading'.tr()
            : '${(progress * 100).round()}%';
      case _AttachmentStage.pending:
        return 'lkmUploadPending'.tr();
      case _AttachmentStage.approved:
        return 'lkmUploadApproved'.tr();
      case _AttachmentStage.failed:
        return 'lkmUploadFailed'.tr();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tile = Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            attachment.bytes,
            width: 88,
            height: 88,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            color: Colors.black.withValues(alpha: 0.6),
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              _label(),
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(color: Colors.white),
            ),
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: InkWell(
            onTap: onRemove,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 16,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
    return Tooltip(
      message: attachment.error ?? attachment.name,
      child: SizedBox(width: 88, height: 88, child: tile),
    );
  }
}
