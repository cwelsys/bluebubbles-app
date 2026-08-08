import 'package:bluebubbles/services/backend/interfaces/chat_interface.dart';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';

// ignore: non_constant_identifier_names
TypingIndicatorService get TypingIndicatorSvc => GetIt.I<TypingIndicatorService>();

class TypingIndicatorService extends GetxController {
  String? _activeTypingChatGuid;
  final Map<String, RxBool> _remoteTyping = {};

  bool get isTyping => _activeTypingChatGuid != null;

  /// Whether the other party is typing in [chatGuid]. Keyed by guid and owned by
  /// this singleton so observers keep a stable [RxBool] across [ChatState] and
  /// [ConversationViewController] rebuilds.
  RxBool remoteTyping(String chatGuid) => _remoteTyping.putIfAbsent(chatGuid, () => false.obs);

  void setRemoteTyping(String chatGuid, bool typing) {
    final state = remoteTyping(chatGuid);
    if (state.value != typing) state.value = typing;
  }

  void clearRemoteTyping(String chatGuid) => _remoteTyping.remove(chatGuid);

  void clearAllRemoteTyping() {
    for (final state in _remoteTyping.values) {
      if (state.value) state.value = false;
    }
  }

  Future<void> startTyping(String chatGuid) async {
    _activeTypingChatGuid = chatGuid;
    await ChatInterface.startTyping(chatGuid: chatGuid);
  }

  Future<void> stopTyping(String chatGuid) async {
    if (_activeTypingChatGuid == chatGuid) _activeTypingChatGuid = null;
    await ChatInterface.stopTyping(chatGuid: chatGuid);
  }

  /// Stops the active typing indicator for any chat.
  /// Called by LifecycleService before the app backgrounds.
  /// Must complete before GlobalIsolate.drainAndStop() is invoked so the
  /// HTTP request has a chance to succeed.
  Future<void> stopAllTyping() async {
    if (_activeTypingChatGuid == null) return;
    final guid = _activeTypingChatGuid!;
    _activeTypingChatGuid = null;
    await ChatInterface.stopTyping(chatGuid: guid);
  }
}
