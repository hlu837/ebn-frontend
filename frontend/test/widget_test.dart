import 'package:flutter_test/flutter_test.dart';

import 'package:onsite_demo/services/notification_service.dart';

void main() {
  group('notification routing', () {
    test('chat notifications route to chat, not the claim flow', () {
      final chatNotification = AppNotification(
        id: 'n1',
        kind: AppNotificationKind.chatMessage,
        title: 'New message from Visitor',
        body: 'hello',
        isRead: false,
        relatedId: 'thread-123',
        createdAt: DateTime(2024, 1, 1),
      );

      expect(notificationDestination(chatNotification),
          NotificationDestination.chat);
    });

    test('dispatch notifications still route to the claim flow', () {
      final dispatchNotification = AppNotification(
        id: 'n2',
        kind: AppNotificationKind.newDispatch,
        title: 'New dispatch',
        body: 'A lead is ready',
        isRead: false,
        relatedId: 'req-456',
        createdAt: DateTime(2024, 1, 1),
      );

      expect(notificationDestination(dispatchNotification),
          NotificationDestination.dispatch);
    });
  });
}
