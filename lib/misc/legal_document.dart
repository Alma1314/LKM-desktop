import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:material_ui/material_ui.dart';
import 'package:island/shared/widgets/app_scaffold.dart';
import 'package:island/shared/widgets/content/markdown.dart';

/// Packaged desktop documents: no website checkout, browser or network needed.
@RoutePage()
class LegalDocumentScreen extends HookWidget {
  const LegalDocumentScreen({
    super.key,
    @PathParam('document') required this.document,
  });
  final String document;

  @override
  Widget build(BuildContext context) {
    final title = switch (document) {
      'privacy' => 'aboutScreenPrivacyPolicyTitle'.tr(),
      'terms' => 'aboutScreenTermsOfServiceTitle'.tr(),
      _ => 'contentNotFound'.tr(),
    };
    final content = useMemoized(
      () => switch (document) {
        'privacy' ||
        'terms' => rootBundle.loadString('assets/legal/$document.md'),
        _ => Future<String>.value(''),
      },
      [document],
    );
    return AppScaffold(
      isNoBackground: false,
      appBar: AppBar(leading: const AutoLeadingButton(), title: Text(title)),
      body: FutureBuilder<String>(
        future: content,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('home.loadFailed'.tr()));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 850),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('legalDocument.language'.tr()),
                      const SizedBox(height: 16),
                      MarkdownTextContent(
                        content: snapshot.data!,
                        isSelectable: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
