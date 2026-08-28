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
  });

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
          currency == other.currency;

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
      currency.hashCode;
}
