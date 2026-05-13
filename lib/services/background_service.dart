// lib/services/background_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:telephony/telephony.dart' as tel;

import '../models/sms_log.dart';
import 'storage_service.dart';

const int _kNotificationId = 9901;
const String _kChannelId = 'sms_gateway_channel';
const String _kChannelName = 'SMS Gateway Service';

// ─────────────────────────────────────────────
//  Initialise the background service
// ─────────────────────────────────────────────
Future<void> initBackgroundService() async {
  final service = FlutterBackgroundService();

  // Notification channel (Android 8+)
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    _kChannelId,
    _kChannelName,
    description: 'Keeps the SMS Gateway running',
    importance: Importance.low,
  );

  final FlutterLocalNotificationsPlugin notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  await notificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: _kChannelId,
      initialNotificationTitle: 'SMS Gateway Pro',
      initialNotificationContent: 'Server starting…',
      foregroundServiceNotificationId: _kNotificationId,
      foregroundServiceTypes: [AndroidForegroundType.dataSync],
      autoStartOnBoot: true,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
    ),
  );
}

// ─────────────────────────────────────────────
//  Entry point running in background isolate
// ─────────────────────────────────────────────
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // DartPluginRegistrant ensures plugins work in isolate
  DartPluginRegistrant.ensureInitialized();

  final FlutterLocalNotificationsPlugin notifications =
      FlutterLocalNotificationsPlugin();

  // Android-specific service controls
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((_) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((_) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((_) async {
    await service.stopSelf();
  });

  // ---- Start the Shelf HTTP server ----
  try {
    final port = await StorageService.getServerPort();
    await _startServer(service, notifications, port);
    _updateNotification(
      notifications,
      '🟢 Running on port $port',
      'Waiting for requests…',
    );
    service.invoke('serverStatus', {'running': true, 'port': port});
  } catch (e) {
    _updateNotification(notifications, '🔴 Server Error', e.toString());
    service.invoke('serverStatus', {'running': false, 'error': e.toString()});
  }

  // Heartbeat every 30 s to keep the service alive
  Timer.periodic(const Duration(seconds: 30), (_) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        _updateNotification(
          notifications,
          '🟢 SMS Gateway Pro – Running',
          'Last heartbeat: ${DateTime.now().toLocal().toString().substring(11, 19)}',
        );
      }
    }
    service.invoke('heartbeat', {'time': DateTime.now().toIso8601String()});
  });
}

// ─────────────────────────────────────────────
//  HTTP Server with Shelf
// ─────────────────────────────────────────────
Future<HttpServer> _startServer(
  ServiceInstance service,
  FlutterLocalNotificationsPlugin notifications,
  int port,
) async {
  final router = Router();

  // Health check
  router.get('/ping', (Request req) {
    return Response.ok(
      json.encode({'status': 'ok', 'service': 'SMS Gateway Pro'}),
      headers: {'content-type': 'application/json'},
    );
  });

  // Main SMS endpoint
  router.post('/send-sms', (Request req) async {
    return await _handleSendSms(req, service, notifications);
  });

  // 404 fallback
  router.all('/<path|.*>', (Request req) {
    return Response.notFound(
      json.encode({'error': 'Endpoint not found'}),
      headers: {'content-type': 'application/json'},
    );
  });

  final handler = const Pipeline()
      .addMiddleware(_corsMiddleware())
      .addMiddleware(logRequests())
      .addHandler(router.call);

  final server = await shelf_io.serve(
    handler,
    InternetAddress.anyIPv4,
    port,
  );
  server.autoCompress = true;
  return server;
}

// ─────────────────────────────────────────────
//  Handle POST /send-sms
// ─────────────────────────────────────────────
Future<Response> _handleSendSms(
  Request req,
  ServiceInstance service,
  FlutterLocalNotificationsPlugin notifications,
) async {
  try {
    // 1. Validate API Key
    final apiKey = await StorageService.getApiKey();
    final headerKey = req.headers['x-api-key'] ??
        req.headers['authorization']?.replaceFirst('Bearer ', '');

    if (headerKey == null || headerKey.trim() != apiKey.trim()) {
      return Response(
        401,
        body: json.encode({'error': 'Unauthorized – invalid API key'}),
        headers: {'content-type': 'application/json'},
      );
    }

    // 2. Parse body
    final body = await req.readAsString();
    Map<String, dynamic> data;
    try {
      data = json.decode(body);
    } catch (_) {
      return Response(
        400,
        body: json.encode({'error': 'Invalid JSON body'}),
        headers: {'content-type': 'application/json'},
      );
    }

    final phone = (data['phone'] ?? '').toString().trim();
    final message = (data['message'] ?? '').toString().trim();

    if (phone.isEmpty) {
      return Response(
        400,
        body: json.encode({'error': 'Field "phone" is required'}),
        headers: {'content-type': 'application/json'},
      );
    }
    if (message.isEmpty) {
      return Response(
        400,
        body: json.encode({'error': 'Field "message" is required'}),
        headers: {'content-type': 'application/json'},
      );
    }

    // Basic phone validation
    final phoneRegex = RegExp(r'^\+?[0-9]{7,15}$');
    if (!phoneRegex.hasMatch(phone)) {
      return _logAndRespond(
        service: service,
        phone: phone,
        message: message,
        status: SmsStatus.failed,
        errorMsg: 'Invalid phone number format',
        httpStatus: 400,
      );
    }

    // 3. Send SMS via Telephony
    final telephony = tel.Telephony.instance;
    bool smsSent = false;
    String? smsError;

    try {
      await telephony.sendSms(
        to: phone,
        message: message,
        isMultipart: message.length > 160,
        statusListener: (status) {
          // Status handled via callback – we optimistically report success
        },
      );
      smsSent = true;
    } catch (e) {
      smsError = e.toString();
      smsSent = false;
    }

    return _logAndRespond(
      service: service,
      phone: phone,
      message: message,
      status: smsSent ? SmsStatus.success : SmsStatus.failed,
      errorMsg: smsError,
      httpStatus: smsSent ? 200 : 500,
    );
  } catch (e) {
    return Response(
      500,
      body: json.encode({'error': 'Internal server error: $e'}),
      headers: {'content-type': 'application/json'},
    );
  }
}

Future<Response> _logAndRespond({
  required ServiceInstance service,
  required String phone,
  required String message,
  required SmsStatus status,
  String? errorMsg,
  required int httpStatus,
}) async {
  final log = SmsLog(
    id: DateTime.now().millisecondsSinceEpoch.toString(),
    phone: phone,
    message: message,
    timestamp: DateTime.now(),
    status: status,
    errorMessage: errorMsg,
  );

  await StorageService.addLog(log);
  service.invoke('newLog', log.toMap());

  final responseBody = {
    'success': status == SmsStatus.success,
    'phone': phone,
    'timestamp': log.timestamp.toIso8601String(),
    if (errorMsg != null) 'error': errorMsg,
  };

  return Response(
    httpStatus,
    body: json.encode(responseBody),
    headers: {'content-type': 'application/json'},
  );
}

// ─────────────────────────────────────────────
//  Helpers
// ─────────────────────────────────────────────
void _updateNotification(
  FlutterLocalNotificationsPlugin plugin,
  String title,
  String body,
) {
  plugin.show(
    _kNotificationId,
    title,
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        _kChannelId,
        _kChannelName,
        channelDescription: 'Keeps the SMS Gateway running',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        autoCancel: false,
        icon: '@mipmap/ic_launcher',
      ),
    ),
  );
}

Middleware _corsMiddleware() {
  return (Handler innerHandler) {
    return (Request request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: _corsHeaders);
      }
      final response = await innerHandler(request);
      return response.change(headers: _corsHeaders);
    };
  };
}

const Map<String, String> _corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, X-API-Key, Authorization',
};
