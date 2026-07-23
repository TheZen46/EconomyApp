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

@HiveType(typeId: 11)
class InvoiceModel extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String invoiceNumber;

  @HiveField(2)
  String clientName;

  @HiveField(3)
  double amount;

  @HiveField(4)
  String status; // 'Draft' | 'Sent' | 'Settled' | 'Overdue'

  @HiveField(5)
  DateTime issuedDate;

  @HiveField(6)
  DateTime? dueDate;

  @HiveField(7)
  String notes;

  @HiveField(8)
  String currency;

  InvoiceModel({
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
    String? clientName,
    double? amount,
    String? status,
    DateTime? issuedDate,
    DateTime? dueDate,
    String? notes,
    String? currency,
  }) {
    return InvoiceModel(
      id: id,
      invoiceNumber: invoiceNumber,
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
}
