import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:universal_io/io.dart';

class TahoeChatGuidMigration {
  static const String _tag = 'TahoeChatGuidMigration';
  static const Set<String> _servicePrefixes = {'iMessage', 'SMS', 'RCS', 'any'};

  static bool get isPending =>
      !kIsWeb && SettingsSvc.serverDetails.isMinTahoe && !PrefsSvc.server.hasMigratedTahoeChatGuids();

  static String? anyGuidFor(String guid) {
    int sep = guid.indexOf(';-;');
    if (sep == -1) sep = guid.indexOf(';+;');
    if (sep == -1 || !_servicePrefixes.contains(guid.substring(0, sep))) return null;
    return 'any${guid.substring(sep)}';
  }

  static Future<bool> migrateIfNeeded() async {
    if (!isPending) return false;

    final Map<String, String> renamed = {};
    try {
      Database.runInTransaction(TxMode.write, () {
        final Map<String, List<Chat>> groups = {};
        for (final chat in Database.chats.getAll()) {
          final target = anyGuidFor(chat.guid);
          if (target != null) groups.putIfAbsent(target, () => []).add(chat);
        }

        for (final MapEntry(key: guid, value: chats) in groups.entries) {
          if (chats.length == 1 && chats.first.guid == guid) continue;
          for (final oldGuid in _mergeInto(guid, chats)) {
            renamed[oldGuid] = guid;
          }
        }
      });
    } catch (e, s) {
      Logger.error("Failed to migrate chats to Tahoe GUIDs", error: e, trace: s, tag: _tag);
      return false;
    }

    for (final MapEntry(key: oldGuid, value: newGuid) in renamed.entries) {
      await _copyChatFolder(FilesystemSvc.avatarsPath, oldGuid, newGuid);
      await _copyChatFolder(FilesystemSvc.customBackgroundsPath, oldGuid, newGuid);
    }

    final lastOpened = PrefsSvc.messaging.getLastOpenedChat();
    if (lastOpened != null && renamed.containsKey(lastOpened)) {
      await PrefsSvc.messaging.setLastOpenedChat(renamed[lastOpened]!);
    }

    await PrefsSvc.server.markTahoeChatGuidsMigrated();
    Logger.info("Moved ${renamed.length} chats to Tahoe GUIDs", tag: _tag);
    return renamed.isNotEmpty;
  }

  static List<String> _mergeInto(String guid, List<Chat> chats) {
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    chats.sort((a, b) => (b.dbOnlyLatestMessageDate ?? epoch).compareTo(a.dbOnlyLatestMessageDate ?? epoch));
    final survivor = chats.firstWhereOrNull((c) => c.guid == guid) ?? chats.first;
    final others = chats.where((c) => !identical(c, survivor)).toList();
    final oldGuids = [
      if (survivor.guid != guid) survivor.guid,
      ...others.map((c) => c.guid),
    ];

    for (final other in others) {
      _absorb(survivor, other);

      final query = Database.messages.query(Message_.chat.equals(other.id!)).build();
      final messages = query.find();
      query.close();
      for (final message in messages) {
        message.chat.target = survivor;
      }
      Database.messages.putMany(messages);

      for (final group in other.customGroups) {
        group.chats.removeWhere((c) => c.id == other.id);
        if (!group.chats.any((c) => c.id == survivor.id)) group.chats.add(survivor);
        group.chats.applyToDb();
      }

      Database.chats.remove(other.id!);
    }

    survivor.guid = guid;
    Database.chats.put(survivor);
    return oldGuids;
  }

  static void _absorb(Chat into, Chat from) {
    final fromLatest = from.dbOnlyLatestMessageDate;
    final intoLatest = into.dbOnlyLatestMessageDate;
    if (from.dbLatestMessage.target != null &&
        fromLatest != null &&
        (intoLatest == null || fromLatest.isAfter(intoLatest))) {
      into.dbLatestMessage.target = from.dbLatestMessage.target;
      into.dbOnlyLatestMessageDate = fromLatest;
    }

    if (from.isPinned == true && into.isPinned != true) {
      into.isPinned = true;
      into.pinIndex = from.pinIndex;
    }
    into.isArchived = (into.isArchived ?? false) && (from.isArchived ?? false);
    into.hasUnreadMessage = (into.hasUnreadMessage ?? false) || (from.hasUnreadMessage ?? false);
    if (into.dateDeleted == null || from.dateDeleted == null) into.dateDeleted = null;
    into.lockChatName = into.lockChatName || from.lockChatName;
    into.lockChatIcon = into.lockChatIcon || from.lockChatIcon;

    if (into.muteType == null && from.muteType != null) {
      into.muteType = from.muteType;
      into.muteArgs = from.muteArgs;
    }
    if (into.customThemeLight == null && into.customThemeDark == null) {
      into.customThemeLight = from.customThemeLight;
      into.customThemeDark = from.customThemeDark;
    }
    if (into.wallpaperType == null) {
      into.wallpaperType = from.wallpaperType;
      into.dynamicWallpaperId = from.dynamicWallpaperId;
      into.dynamicWallpaperConfig = from.dynamicWallpaperConfig;
    }
    if (isNullOrEmpty(into.textFieldText)) into.textFieldText = from.textFieldText;
    if (into.textFieldAttachments.isEmpty) into.textFieldAttachments = [...from.textFieldAttachments];

    into.displayName ??= from.displayName;
    into.customAvatarPath ??= from.customAvatarPath;
    into.customBackgroundPath ??= from.customBackgroundPath;
    into.autoSendReadReceipts ??= from.autoSendReadReceipts;
    into.autoSendTypingIndicators ??= from.autoSendTypingIndicators;
    into.lastReadMessageGuid ??= from.lastReadMessageGuid;
    into.chatIdentifier ??= from.chatIdentifier;
    into.style ??= from.style;

    if (into.handles.isEmpty) into.handles.addAll(from.handles);
  }

  static Future<void> _copyChatFolder(String root, String oldGuid, String newGuid) async {
    final source = Directory(join(root, FilesystemService.sanitizeGuid(oldGuid)));
    final destination = Directory(join(root, FilesystemService.sanitizeGuid(newGuid)));
    if (!await source.exists() || await destination.exists()) return;

    try {
      await destination.create(recursive: true);
      await for (final entity in source.list()) {
        if (entity is File) await entity.copy(join(destination.path, basename(entity.path)));
      }
    } on FileSystemException catch (e, s) {
      Logger.warn("Failed to copy ${source.path} to ${destination.path}", error: e, trace: s, tag: _tag);
    }
  }
}
