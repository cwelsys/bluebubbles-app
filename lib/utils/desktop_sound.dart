import 'dart:async';

import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:media_kit/media_kit.dart';

Future<void> playDesktopSound(String path, {required double volume, String tag = 'DesktopSound'}) async {
  final player = Player();
  var disposed = false;

  Future<void> release() async {
    if (disposed) return;
    disposed = true;
    await player.dispose();
  }

  unawaited(player.stream.completed.firstWhere((completed) => completed, orElse: () => false).then((_) async {
    await Future.delayed(const Duration(milliseconds: 500));
    await release();
  }));

  try {
    await player.setVolume(volume);
    await player.open(Media(path));
  } catch (e, s) {
    Logger.error('Failed to play sound at $path', error: e, trace: s, tag: tag);
    await release();
  }
}
