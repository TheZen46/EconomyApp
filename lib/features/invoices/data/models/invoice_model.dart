import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

part 'invoice_model.g.dart';

// Status constants
class InvoiceStatus {
  static const String draft = 'Draft';
  static const String sent = 'Sent';
  static const String settled = 'Settled';
  static const String overdue = 'Overdue';

  static const List<String> all = [draft, sent, settled, overdue];
}

@immutable
@HiveType(typeId: 11)
class InvoiceModel {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String invoiceNumber;

  @HiveField(2)
  final String clientName;

  @HiveField(3)
  final double amount;

  @HiveField(4)
  final String status; // 'Draft' | 'Sent' | 'Settled' | 'Overdue'

  @HiveField(5)
  final DateTime issuedDate;

  @HiveField(6)
  final DateTime? dueDate;

  @HiveField(7)
  final String notes;

  @HiveField(8)
  final String currency;

  @HiveField(9)
  final String? userId;

  @HiveField(10)
  final DateTime? createdAt;

  @HiveField(11)
  final DateTime? updatedAt;

  @HiveField(12)
  final DateTime? deletedAt;

  @HiveField(13)
  final int version;

  const InvoiceModel({
    required this.id,
    required this.invoiceNumber,
    required this.clientName,
    required this.amount,
    required this.status,
    required this.issuedDate,
    this.dueDate,
    this.notes = '',
    this.currency = 'USD',
    this.userId,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
    this.version = 1,
  });

  factory InvoiceModel.fromJson(Map<String, dynamic> json) {
    return InvoiceModel(
      id: json['id'] as String,
      invoiceNumber: json['invoice_number'] as String? ?? 'INV-001',
      clientName: json['client_name'] as String? ?? 'Unknown Client',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] as String? ?? InvoiceStatus.draft,
      issuedDate: json['issued_date'] != null
          ? DateTime.tryParse(json['issued_date'] as String) ?? DateTime.now()
          : DateTime.now(),
      dueDate: json['due_date'] != null ? DateTime.tryParse(json['due_date'] as String) : null,
      notes: json['notes'] as String? ?? '',
      currency: json['currency'] as String? ?? 'USD',
      userId: json['user_id'] as String?,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'] as String) : null,
      deletedAt: json['deleted_at'] != null ? DateTime.tryParse(json['deleted_at'] as String) : null,
      version: (json['version'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'invoice_number': invoiceNumber,
      'client_name': clientName,
      'amount': amount,
      'status': status,
      'issued_date': issuedDate.toUtc().toIso8601String(),
      'due_date': dueDate?.toUtc().toIso8601String(),
      'notes': notes,
      'currency': currency,
      'user_id': userId,
      'created_at': (createdAt ?? issuedDate).toUtc().toIso8601String(),
      'updated_at': (updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
      'deleted_at': deletedAt?.toUtc().toIso8601String(),
      'version': version,
    };
  }

  InvoiceModel copyWith({
    String? id,
    String? invoiceNumber,
    String? clientName,
    double? amount,
    String? status,
    DateTime? issuedDate,
    DateTime? dueDate,
    String? notes,
    String? currency,
    String? userId,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    int? version,
  }) {
    return InvoiceModel(
      id: id ?? this.id,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      clientName: clientName ?? this.clientName,
      amount: amount ?? this.amount,
      status: status ?? this.status,
      issuedDate: issuedDate ?? this.issuedDate,
      dueDate: dueDate ?? this.dueDate,
      notes: notes ?? this.notes,
      currency: currency ?? this.currency,
      userId: userId ?? this.userId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      version: version ?? this.version,
    );
  }

  bool get isOverdue {
    if (status == InvoiceStatus.settled) return false;
    if (dueDate == null) return false;
    return DateTime.now().isAfter(dueDate!);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InvoiceModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          invoiceNumber == other.invoiceNumber &&
          clientName == other.clientName &&
          amount == other.amount &&
          status == other.status &&
          issuedDate == other.issuedDate &&
          dueDate == other.dueDate &&
          notes == other.notes &&
          currency == other.currency &&
          userId == other.userId &&
          deletedAt == other.deletedAt &&
          version == other.version;

  @override
  int get hashCode =>
      id.hashCode ^
      invoiceNumber.hashCode ^
      clientName.hashCode ^
      amount.hashCode ^
      status.hashCode ^
      issuedDate.hashCode ^
      dueDate.hashCode ^
      notes.hashCode ^
      currency.hashCode ^
      userId.hashCode ^
      deletedAt.hashCode ^
      version.hashCode;
}
