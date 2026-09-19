import 'package:flutter/material.dart';
import 'package:wyw/bean/appbar/sys_app_bar.dart';

/// Tells a settings detail page how the settings page is hosting it.
///
/// Pages opened with pushNamed sit above the Navigator and never see this
/// scope, so the same page also works as a standalone route.
class SettingsPaneScope extends InheritedWidget {
  const SettingsPaneScope({
    super.key,
    required this.embedded,
    required this.showBackButton,
    this.onBack,
    required super.child,
  });

  /// Rendered as the right pane; the tab rail owns navigation.
  final bool embedded;

  /// Whether an embedded pane shows a back button in its leading slot.
  ///
  /// Requires [onBack]; without a callback no leading widget is rendered, so
  /// the pane never shows a back button that does nothing.
  final bool showBackButton;

  /// Rendered as a single-pane detail; back returns to the category list.
  ///
  /// Optional: wyw's embedded call sites render panes that do not need a back
  /// button, so they may omit this callback.
  final VoidCallback? onBack;

  static SettingsPaneScope? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<SettingsPaneScope>();
  }

  @override
  bool updateShouldNotify(SettingsPaneScope oldWidget) {
    return embedded != oldWidget.embedded ||
        showBackButton != oldWidget.showBackButton ||
        onBack != oldWidget.onBack;
  }
}

class SettingsDetailScaffold extends StatelessWidget {
  const SettingsDetailScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.leading,
    this.floatingActionButton,
  });

  final Widget title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? leading;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    final scope = SettingsPaneScope.of(context);

    if (scope != null && scope.embedded) {
      final paneLeading = leading ??
          (scope.showBackButton && scope.onBack != null
              ? BackButton(onPressed: scope.onBack)
              : null);
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,
          toolbarHeight: 64,
          titleSpacing:
              paneLeading == null ? 24 : NavigationToolbar.kMiddleSpacing,
          leading: paneLeading,
          title: title,
          titleTextStyle: Theme.of(context).textTheme.headlineSmall,
          actions: actions,
        ),
        body: body,
        floatingActionButton: floatingActionButton,
      );
    }

    final onBack = scope?.onBack;
    return Scaffold(
      appBar: SysAppBar(
        title: title,
        actions: actions,
        leading: leading ??
            (onBack == null
                ? null
                : IconButton(
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back),
                  )),
      ),
      body: body,
      floatingActionButton: floatingActionButton,
    );
  }
}
