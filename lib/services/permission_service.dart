import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

class PermissionService {
  PermissionService._();

  static const _channel = MethodChannel('wakewise/system_permissions');

  static Future<Map<String, bool>> checkAll() async {
    final result = <String, bool>{
      'notifications': (await ph.Permission.notification.status).isGranted,
    };
    if (Platform.isAndroid) {
      result['exactAlarm'] =
          (await ph.Permission.scheduleExactAlarm.status).isGranted;
      result['batteryOptimization'] =
          (await ph.Permission.ignoreBatteryOptimizations.status).isGranted;
      result['fullScreenIntent'] = await fullScreenIntentGranted();
    }
    return result;
  }

  static Future<Map<String, bool>> requestOnboardingPermissions() async {
    final result = <String, bool>{};
    result['notifications'] =
        (await ph.Permission.notification.request()).isGranted;
    if (Platform.isAndroid) {
      result['exactAlarm'] =
          (await ph.Permission.scheduleExactAlarm.request()).isGranted;
      result['fullScreenIntent'] = await requestFullScreenIntent();
      result['batteryOptimization'] =
          (await ph.Permission.ignoreBatteryOptimizations.request()).isGranted;
    }
    return result;
  }

  static Future<bool> ensureNotificationPermission() async {
    if ((await ph.Permission.notification.status).isGranted) return true;
    return (await ph.Permission.notification.request()).isGranted;
  }

  static Future<bool> ensureExactAlarmPermission() async {
    if (!Platform.isAndroid) return true;
    if ((await ph.Permission.scheduleExactAlarm.status).isGranted) return true;
    return (await ph.Permission.scheduleExactAlarm.request()).isGranted;
  }

  static Future<bool> fullScreenIntentGranted() async {
    if (!Platform.isAndroid) return true;
    return await _channel.invokeMethod<bool>('canUseFullScreenIntent') ?? false;
  }

  static Future<bool> requestFullScreenIntent() async {
    if (!Platform.isAndroid) return true;
    if (await fullScreenIntentGranted()) return true;
    await _channel.invokeMethod<void>('requestFullScreenIntent');
    return fullScreenIntentGranted();
  }

  static Future<bool> ensureBatteryOptimizationExemption() async {
    if (!Platform.isAndroid) return true;
    if ((await ph.Permission.ignoreBatteryOptimizations.status).isGranted) {
      return true;
    }
    return (await ph.Permission.ignoreBatteryOptimizations.request()).isGranted;
  }

  static Future<bool> ensureMotionPermission() async {
    if (!Platform.isAndroid) return true;
    if ((await ph.Permission.activityRecognition.status).isGranted) {
      return true;
    }
    return (await ph.Permission.activityRecognition.request()).isGranted;
  }

  static Future<bool> requestPermission(String permission) async {
    switch (permission) {
      case 'notifications':
        return ensureNotificationPermission();
      case 'exactAlarm':
        return ensureExactAlarmPermission();
      case 'fullScreenIntent':
        return requestFullScreenIntent();
      case 'batteryOptimization':
        return ensureBatteryOptimizationExemption();
      default:
        throw ArgumentError.value(
          permission,
          'permission',
          'Unknown permission',
        );
    }
  }

  static Future<bool> openSystemSettings() => ph.openAppSettings();
}
