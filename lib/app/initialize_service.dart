import 'dart:async';
import 'dart:ui';

import 'package:fhirant/app/signaling_server.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

Future<void> initializeService() async {
  const notificationChannelId = 'signaling_server';
  const notificationId = 1001;

  final service = FlutterBackgroundService();

  // Set up Android notification channel
  const channel = AndroidNotificationChannel(
    notificationChannelId, // id
    'Signaling Server', // title
    description: 'This channel is used by the signaling server.', // description
    importance: Importance.low,
  );

  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  // Configure the service
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      isForegroundMode: true,
      notificationChannelId: notificationChannelId,
      initialNotificationTitle: 'Signaling Server',
      initialNotificationContent: 'Running in the background.',
      foregroundServiceNotificationId: notificationId,
    ),
    iosConfiguration: IosConfiguration(
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
Future<void> onStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  final signalingServer = SignalingServer();
  await signalingServer.startServer();

  // Stop the server when instructed
  service.on('stopServer').listen((event) async {
    await signalingServer.stopServer();
    await service.stopSelf();
  });

  if (service is AndroidServiceInstance) {
    await service.setForegroundNotificationInfo(
      title: 'Signaling Server',
      content: 'Running in background...',
    );
  }

  // Keep the server alive
  Timer.periodic(const Duration(seconds: 10), (timer) {
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'Signaling Server',
        content: 'Running at ${DateTime.now()}',
      );
    }
  });
}
