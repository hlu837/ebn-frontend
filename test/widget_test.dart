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

    test(
        'new dispatch notifications should auto-open the countdown claim alert',
        () {
      final dispatchNotification = AppNotification(
        id: 'n3',
        kind: AppNotificationKind.newDispatch,
        title: 'New order request nearby',
        body: 'A lead is ready',
        isRead: false,
        relatedId: 'req-789',
        createdAt: DateTime(2024, 1, 1),
      );

      expect(shouldAutoOpenDispatchAlert(dispatchNotification), isTrue);
      expect(
        shouldAutoOpenDispatchAlert(
            dispatchNotification.copyWith(isRead: true)),
        isTrue,
      );
    });

    test(
        'notifications without a request id should not auto-open the claim alert',
        () {
      final systemNotification = AppNotification(
        id: 'n4',
        kind: AppNotificationKind.system,
        title: 'General update',
        body: 'Something happened',
        isRead: false,
        relatedId: null,
        createdAt: DateTime(2024, 1, 1),
      );

      expect(shouldAutoOpenDispatchAlert(systemNotification), isFalse);
    });
  });
}
