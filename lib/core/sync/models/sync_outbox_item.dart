import 'package:hive/hive.dart';

part 'sync_outbox_item.g.dart';

/// Represents a local mutation queued for synchronization to Supabase.
@HiveType(typeId: 12)
class SyncOutboxItem extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String entityType; // 'receipt' | 'receipt_item' | 'box' | 'invoice' | 'asset' | 'taxonomy' | 'profile'

  @HiveField(2)
  final String entityId;

  @HiveField(3)
  final String mutationType; // 'insert' | 'update' | 'delete'

  @HiveField(4)
  final Map<String, dynamic> payload;

  @HiveField(5)
  final DateTime timestamp;

  @HiveField(6)
  int retryCount;

  @HiveField(7)
  String status; // 'pending' | 'processing' | 'synced' | 'failed' | 'permanently_failed'

  @HiveField(8)
  String? errorMessage;

  @HiveField(9)
  DateTime? lastAttemptAt;

  SyncOutboxItem({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.mutationType,
    required this.payload,
    DateTime? timestamp,
    this.retryCount = 0,
    this.status = 'pending',
    this.errorMessage,
    this.lastAttemptAt,
  }) : timestamp = timestamp ?? DateTime.now();

  factory SyncOutboxItem.fromJson(Map<String, dynamic> json) {
    return SyncOutboxItem(
      id: json['id'] as String,
      entityType: json['entity_type'] as String,
      entityId: json['entity_id'] as String,
      mutationType: json['mutation_type'] as String,
      payload: Map<String, dynamic>.from(json['payload'] as Map),
      timestamp: DateTime.parse(json['timestamp'] as String),
      retryCount: (json['retry_count'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? 'pending',
      errorMessage: json['error_message'] as String?,
      lastAttemptAt: json['last_attempt_at'] != null
          ? DateTime.parse(json['last_attempt_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entity_type': entityType,
      'entity_id': entityId,
      'mutation_type': mutationType,
      'payload': payload,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'retry_count': retryCount,
      'status': status,
      'error_message': errorMessage,
      'last_attempt_at': lastAttemptAt?.toUtc().toIso8601String(),
    };
  }
}
