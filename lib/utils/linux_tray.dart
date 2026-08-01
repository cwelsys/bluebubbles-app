import 'dart:async';

import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:dbus/dbus.dart';
import 'package:synchronized/synchronized.dart';
import 'package:universal_io/io.dart';
import 'package:xdg_status_notifier_item/xdg_status_notifier_item.dart' as sni;

/// A single entry in the Linux tray menu. A null [label] renders a separator.
class LinuxTrayMenuItem {
  const LinuxTrayMenuItem({required this.label, required this.onClicked});

  const LinuxTrayMenuItem.separator()
      : label = null,
        onClicked = null;

  final String? label;
  final Future<void> Function()? onClicked;
}

/// Linux tray icon over the StatusNotifierItem D-Bus spec.
///
/// Every other desktop uses `tray_manager`, but its Linux backend is an AppIndicator
/// (`app_indicator_new`) whose plugin only implements setIcon/setTitle/setContextMenu/destroy —
/// it opens no event channel for the icon itself. `TrayListener.onTrayIconMouseDown` therefore
/// can never fire on Linux and left-clicking the icon does nothing. SNI gives us a real
/// `Activate` call. Still true as of tray_manager 0.5.3.
class LinuxTray {
  LinuxTray._();

  static const String _tag = 'LinuxTray';
  static const String _watcherName = 'org.kde.StatusNotifierWatcher';
  static const int _maxRetries = 10;
  static const Duration _retryDelay = Duration(seconds: 2);

  /// Serializes registration. A tray host that bounces its bus name several times in a row
  /// would otherwise start overlapping retry loops that fight over [_client] and the bus name.
  static final Lock _lock = Lock();

  static DBusClient? _bus;
  static sni.StatusNotifierItemClient? _client;
  static StreamSubscription<DBusNameOwnerChangedEvent>? _watcherSub;

  static String _iconName = '';
  static String _title = '';
  static Future<void> Function()? _onActivate;
  static List<LinuxTrayMenuItem> _menu = const [];

  /// The bus name the SNI client claims. Derived from the pid, so it is fixed for the
  /// lifetime of the process — which is why re-registering must never re-request it.
  static String get _itemName => 'org.kde.StatusNotifierItem-$pid-1';

  static Future<void> init({
    required String iconName,
    required String title,
    required Future<void> Function() onActivate,
    required List<LinuxTrayMenuItem> menu,
  }) async {
    if (!Platform.isLinux || _bus != null) return;

    _iconName = iconName;
    _title = title;
    _onActivate = onActivate;
    _menu = menu;

    _bus = DBusClient.session();
    // Subscribe before the first attempt so a watcher appearing mid-retry can't slip
    // through the gap between a failed attempt and the listener being wired up.
    _watcherSub = _bus!.nameOwnerChanged.listen(_onNameOwnerChanged);

    // Deliberately not awaited: at login the shell's tray host is often not on the bus
    // yet, and startup shouldn't block for the retry window.
    unawaited(_connect());
  }

  static Future<void> setMenu(List<LinuxTrayMenuItem> menu) async {
    if (!Platform.isLinux) return;
    _menu = menu;
    await _client?.updateMenu(_buildMenu());
  }

  static Future<void> dispose() async {
    await _watcherSub?.cancel();
    _watcherSub = null;
    await _client?.close();
    _client = null;
    // The client won't close a bus it didn't create, so close ours explicitly.
    await _bus?.close();
    _bus = null;
  }

  /// The library registers with the watcher exactly once and never re-registers, so a tray
  /// host restart drops us until we ask again.
  static void _onNameOwnerChanged(DBusNameOwnerChangedEvent event) {
    if (event.name != _watcherName || event.newOwner == null) return;
    Logger.info('StatusNotifierWatcher appeared; re-registering tray item', tag: _tag);
    unawaited(_connect());
  }

  static Future<void> _connect() async {
    await _lock.synchronized(() async {
      if (_client == null) {
        final sni.StatusNotifierItemClient client = sni.StatusNotifierItemClient(
          id: 'bluebubbles',
          iconName: _iconName,
          title: _title,
          menu: _buildMenu(),
          onActivate: (_, _) async => await _onActivate?.call(),
          bus: _bus,
        );

        bool registered = false;
        try {
          await client.connect();
          registered = true;
        } catch (e) {
          // connect() is requestName + registerObject x2 + RegisterStatusNotifierItem.
          // Only that last call fails when no watcher is running, and the earlier steps
          // are not idempotent, so keep the client and let the retry loop below redo
          // just the registration.
          Logger.debug('Tray connect incomplete, watcher likely not up yet: $e', tag: _tag);
        }

        // connect() only guards its requestName with an assert, and asserts are stripped
        // from release builds. An unchecked loss here is a silently dead tray icon.
        if (!await _ownsItemName()) {
          Logger.error('Could not claim $_itemName; tray disabled', tag: _tag);
          await client.close();
          return;
        }

        _client = client;
        if (registered) {
          Logger.info('Tray item registered', tag: _tag);
          return;
        }
      }

      // The bus name and published objects are still ours; the new watcher just needs
      // to be told we exist.
      for (int attempt = 1; attempt <= _maxRetries; attempt++) {
        try {
          await _register();
          Logger.info('Tray item registered with watcher on attempt $attempt', tag: _tag);
          return;
        } catch (e, s) {
          if (attempt == _maxRetries) {
            Logger.error('Tray registration failed after $_maxRetries attempts', error: e, trace: s, tag: _tag);
            return;
          }
          await Future.delayed(_retryDelay);
        }
      }
    });
  }

  static Future<void> _register() async {
    await _bus!.callMethod(
      destination: _watcherName,
      path: DBusObjectPath('/StatusNotifierWatcher'),
      interface: _watcherName,
      name: 'RegisterStatusNotifierItem',
      values: [DBusString(_itemName)],
      replySignature: DBusSignature.empty,
    );
  }

  static Future<bool> _ownsItemName() async {
    final String? owner = await _bus!.getNameOwner(_itemName);
    return owner != null && owner == _bus!.uniqueName;
  }

  static sni.DBusMenuItem _buildMenu() {
    return sni.DBusMenuItem(
      children: _menu
          .map((e) => e.label == null
              ? sni.DBusMenuItem.separator()
              : sni.DBusMenuItem(label: e.label, onClicked: e.onClicked))
          .toList(),
    );
  }
}
