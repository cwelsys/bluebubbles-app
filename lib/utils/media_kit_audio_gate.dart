import 'dart:async';
import 'dart:io';

import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

abstract class MediaKitAudioGate {
  static final Expando<_Gate> _gates = Expando('MediaKitAudioGate');

  static Future<void> suspend(Player? player) async {
    if (player == null) return;
    if (kIsWeb || !(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) return;
    final platform = player.platform;
    if (platform is! NativePlayer) return;

    var gate = _gates[player];
    if (gate == null) {
      gate = _Gate();
      _gates[player] = gate;
      gate.playing = player.stream.playing.listen((_) => _sync(player));
      gate.volume = player.stream.volume.listen((_) => _sync(player));
      gate.completed = player.stream.completed.listen((completed) {
        if (completed) suspend(player);
      });
    }
    if (gate.suspended) return;
    gate.suspended = true;
    await _setAudioOutput(platform, 'null');
  }

  static Future<void> resume(Player? player) async {
    if (player == null) return;
    final gate = _gates[player];
    if (gate == null || !gate.suspended) return;
    gate.suspended = false;

    final platform = player.platform;
    if (platform is! NativePlayer) return;
    await _setAudioOutput(platform, '');
  }

  static Future<void> resumeIfAudible(Player? player) async {
    if (player == null || player.state.volume <= 0) return;
    await resume(player);
  }

  static void _sync(Player player) {
    if (_gates[player] == null) return;
    if (player.state.playing && player.state.volume > 0) {
      unawaited(resume(player));
    } else if (player.state.volume <= 0) {
      unawaited(suspend(player));
    }
  }

  static Future<void> _setAudioOutput(NativePlayer platform, String ao) async {
    try {
      await platform.setProperty('ao', ao);
    } catch (e, s) {
      Logger.warn("Failed to set mpv ao='$ao'", error: e, trace: s, tag: 'MediaKitAudioGate');
    }
  }
}

class _Gate {
  bool suspended = false;
  StreamSubscription<bool>? playing;
  StreamSubscription<double>? volume;
  StreamSubscription<bool>? completed;
}
