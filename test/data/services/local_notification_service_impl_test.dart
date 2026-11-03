import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qayd/data/services/local_notification_service_impl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NotificationCall {
  const _NotificationCall({
    required this.id,
    required this.title,
    required this.body,
    required this.details,
    required this.payload,
  });

  final int id;
  final String? title;
  final String? body;
  final NotificationDetails? details;
  final String? payload;
}

class _RecordingNotificationGateway implements LocalNotificationGateway {
  InitializationSettings? initializationSettings;
  DidReceiveNotificationResponseCallback? onResponse;
  final calls = <_NotificationCall>[];

  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
  }) async {
    initializationSettings = settings;
    onResponse = onDidReceiveNotificationResponse;
    return true;
  }

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails,
    String? payload,
  }) async {
    calls.add(
      _NotificationCall(
        id: id,
        title: title,
        body: body,
        details: notificationDetails,
        payload: payload,
      ),
    );
  }
}

void main() {
  late SharedPreferences preferences;
  late _RecordingNotificationGateway gateway;
  late LocalNotificationServiceImpl service;
  var permissionRequests = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'notif_peer_activity': true,
      'notif_self_activity': true,
      'notif_sound_enabled': false,
      'notif_vibration_enabled': false,
    });
    preferences = await SharedPreferences.getInstance();
    gateway = _RecordingNotificationGateway();
    permissionRequests = 0;
    service = LocalNotificationServiceImpl(
      preferences,
      plugin: gateway,
      requestNotificationPermission: () async {
        permissionRequests++;
        return PermissionStatus.granted;
      },
    );
  });

  test(
    'initializes the v22 plugin settings and requests permission once',
    () async {
      await service.initialize();

      expect(permissionRequests, 1);
      expect(gateway.initializationSettings, isNotNull);
      expect(
        gateway.initializationSettings!.android!.defaultIcon,
        '@mipmap/ic_launcher',
      );
      expect(
        gateway.initializationSettings!.iOS!.requestAlertPermission,
        isTrue,
      );
      expect(gateway.onResponse, isNotNull);
    },
  );

  test(
    'forwards tapped notification payload through the response stream',
    () async {
      await service.initialize();
      final tapped = expectLater(
        service.onNotificationTap,
        emits('voucher:123'),
      );

      gateway.onResponse!(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          id: 123,
          payload: 'voucher:123',
        ),
      );

      await tapped;
    },
  );

  test(
    'important notification retains its high-priority financial channel',
    () async {
      await service.showImportantNotification(
        title: 'Incoming claim',
        body: 'A new claim needs review.',
        payload: 'claim-123',
      );

      expect(gateway.calls, hasLength(1));
      final call = gateway.calls.single;
      expect(call.title, 'Incoming claim');
      expect(call.body, 'A new claim needs review.');
      expect(call.payload, 'claim-123');
      expect(call.id, inInclusiveRange(0, 99999));

      final android = call.details!.android!;
      expect(android.channelId, 'qayd_important_channel');
      expect(android.importance, Importance.max);
      expect(android.priority, Priority.high);
      expect(android.playSound, isFalse);
      expect(android.enableVibration, isFalse);
      expect(call.details!.iOS!.presentAlert, isTrue);
      expect(call.details!.iOS!.presentSound, isFalse);
      expect(
        call.details!.iOS!.interruptionLevel,
        InterruptionLevel.timeSensitive,
      );
    },
  );

  test(
    'local notification honors the self-activity preference and defaults',
    () async {
      await preferences.setBool('notif_self_activity', false);
      await service.showLocalNotification(
        title: 'Hidden local notice',
        body: 'The preference is disabled.',
      );
      expect(gateway.calls, isEmpty);

      await preferences.setBool('notif_self_activity', true);
      await service.showLocalNotification(
        title: 'Local notice',
        body: 'The preference is enabled.',
      );

      expect(gateway.calls, hasLength(1));
      final call = gateway.calls.single;
      expect(call.title, 'Local notice');
      expect(call.details!.android!.channelId, 'qayd_default_channel');
      expect(call.details!.android!.playSound, isFalse);
      expect(call.details!.android!.enableVibration, isFalse);
    },
  );

  test(
    'important notification respects disabled peer-activity preference',
    () async {
      await preferences.setBool('notif_peer_activity', false);

      await service.showImportantNotification(
        title: 'Suppressed claim',
        body: 'Peer activity is disabled.',
      );

      expect(gateway.calls, isEmpty);
    },
  );

  test(
    'sound and vibration default to enabled when no preference is stored',
    () async {
      await preferences.remove('notif_sound_enabled');
      await preferences.remove('notif_vibration_enabled');

      await service.showLocalNotification(
        title: 'Defaults',
        body: 'Preferences absent.',
      );

      expect(gateway.calls.single.details!.android!.playSound, isTrue);
      expect(gateway.calls.single.details!.android!.enableVibration, isTrue);
    },
  );
}
