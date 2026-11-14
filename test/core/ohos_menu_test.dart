import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_native_extensions/raw_menu.dart' as raw;
import 'package:super_native_extensions/src/menu_flutter.dart';

void main() {
  testWidgets('OHOS menus reuse the existing Flutter renderer', (tester) async {
    final context = await raw.MenuContext.instance();
    expect(context, isA<FlutterMenuContext>());
    final menu = raw.Menu(children: []);
    final handle = await context.registerMenu(
      menu,
      raw.MenuSerializationOptions(
        iconTheme: const IconThemeData(),
        destructiveIconTheme: const IconThemeData(),
        devicePixelRatio: 1,
      ),
    );
    var rendered = false;
    final result = await context.showContextMenu(
      raw.DesktopContextMenuRequest(
        menu: handle,
        position: Offset.zero,
        iconTheme: const IconThemeData(),
        writingToolsConfiguration: null,
        fallback: () async {
          rendered = true;
          return raw.MenuResult(itemSelected: true);
        },
      ),
    );
    expect(rendered, isTrue);
    expect(result.itemSelected, isTrue);
    handle.dispose();
  }, variant: TargetPlatformVariant({TargetPlatform.ohos}));
}
