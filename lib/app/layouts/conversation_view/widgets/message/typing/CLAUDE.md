# widgets/message/typing/ — Typing Indicator

## Files
| File | Purpose |
|------|---------|
| `typing_indicator.dart` | Animated three-dot typing bubble shown when a participant is composing; driven by socket events |
| `typing_clipper.dart` | `CustomClipper` that shapes the typing bubble's rounded tail |

## Lifecycle
`TypingIndicator` appears at the bottom of the message list when `TypingIndicatorSvc.remoteTyping(guid)`
is true. `ActionHandler` sets it when the server sends a `typing-indicator` socket event.

The flag is owned by `TypingIndicatorService`, not by `ChatState` or `ConversationViewController` —
conversation list tiles read it per chat, and routing it through `cvc()` used to construct a full
`ConversationViewController` (DB-backed `chat.handles`, focus nodes, keyboard subscription) for every
rendered tile. `ConversationViewController.showTypingIndicator` remains as a delegating getter.

## Animation
Uses a staggered `AnimationController` to bounce each of the three dots at offset intervals. Auto-disposes when hidden.

## Related
- `TypingIndicatorService`: `lib/services/ui/typing_indicator_service.dart`
- Socket events: `lib/services/network/socket_service.dart`
