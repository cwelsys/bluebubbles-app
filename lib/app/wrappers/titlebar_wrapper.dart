import 'dart:io';

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/header/header_widgets.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';
import 'package:get/get_state_manager/src/rx_flutter/rx_obx_widget.dart';
import 'package:get/get_utils/src/extensions/context_extensions.dart';
import 'package:window_manager/window_manager.dart';

class TitleBarWrapper extends StatelessWidget {
  const TitleBarWrapper({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!kIsDesktop) {
      return Stack(
        children: <Widget>[
          child,
          const ConnectionIndicator(),
        ],
      );
    }

    return Obx(
      () => (SettingsSvc.settings.titleBarStyle.value == BBTitleBarStyle.custom && Platform.isLinux) ||
              (kIsDesktop && !Platform.isLinux)
          ? WindowBorder(
              color: Colors.transparent,
              width: 0,
              child: Stack(children: <Widget>[
                child,
                const TitleBar(),
                const ConnectionIndicator(),
              ]),
            )
          : Stack(
              children: <Widget>[
                child,
                const ConnectionIndicator(),
              ],
            ),
    );
  }
}

class TitleBar extends StatelessWidget {
  const TitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    return WindowTitleBarBox(
      child: Row(
        children: [
          Expanded(
            child: MoveWindow(),
          ),
          const WindowButtons()
        ],
      ),
    );
  }
}

class WindowButtons extends StatelessWidget {
  const WindowButtons({super.key});

  static const double _buttonSize = 22;
  static const double _sidePadding = 8;
  static const double width = _buttonSize + _sidePadding * 2;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _sidePadding),
      child: Material(
        type: MaterialType.transparency,
        child: IconButton(
          onPressed: () async => await windowManager.close(),
          icon: const Icon(Icons.close_rounded),
          iconSize: 14,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: _buttonSize, height: _buttonSize),
          style: IconButton.styleFrom(
            shape: const CircleBorder(),
            foregroundColor: colorScheme.onSurfaceVariant,
            backgroundColor: colorScheme.onSurface.withValues(alpha: 0.08),
            hoverColor: colorScheme.onSurface.withValues(alpha: 0.08),
            highlightColor: colorScheme.onSurface.withValues(alpha: 0.12),
          ),
        ),
      ),
    );
  }
}
