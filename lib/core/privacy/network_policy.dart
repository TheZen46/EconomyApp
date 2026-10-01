import 'package:hive/hive.dart';

/// Isolation mode: one switch that keeps all data on this device.
///
/// While it is on, the cloud paths of the app consult [isCloudAllowed] and do
/// nothing: SyncManager (outbox push and delta pull), SyncService (training
/// and Google Drive uploads), SyncEngine (replication), WebhookService, the
/// Gemini AI service and over-the-air model updates. Work that would have been
/// sent stays queued locally until isolation mode is turned off. Signing in,
/// which the user starts explicitly, is not blocked.
///
/// This is separate from the privacy mode of the dashboard, which only masks
/// figures on screen.
class NetworkPolicy {
  NetworkPolicy._();

  /// Settings key of the isolation mode switch.
  static const String isolationModeKey = 'network_isolation_enabled';

  /// Whether isolation mode is on.
  static bool isIsolated(Box? settingsBox) {
    try {
      return settingsBox?.get(isolationModeKey, defaultValue: false) as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Whether cloud requests are allowed, that is, isolation mode is off.
  static bool isCloudAllowed(Box? settingsBox) => !isIsolated(settingsBox);
}
