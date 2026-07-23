import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../data/models/invoice_model.dart';
import '../../data/providers/invoices_provider.dart';

class CreateInvoiceSheet extends ConsumerStatefulWidget {
  const CreateInvoiceSheet({super.key});

  @override
  ConsumerState<CreateInvoiceSheet> createState() => _CreateInvoiceSheetState();
}

class _CreateInvoiceSheetState extends ConsumerState<CreateInvoiceSheet> {
  final _formKey = GlobalKey<FormState>();
  final _clientNameController = TextEditingController();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  
  String _currency = 'USD';
  String _status = InvoiceStatus.draft;
  DateTime _issuedDate = DateTime.now();
  DateTime? _dueDate;

  void _save() async {
    if (!_formKey.currentState!.validate()) return;
    
    final amount = double.tryParse(_amountController.text) ?? 0.0;
    
    await ref.read(invoicesProvider.notifier).create(
      clientName: _clientNameController.text,
      amount: amount,
      status: _status,
      issuedDate: _issuedDate,
      dueDate: _dueDate,
      notes: _notesController.text,
      currency: _currency,
    );
    
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _clientNameController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F0F0F) : const Color(0xFFFFFFFF);
    final borderCol = isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04);
    final textCol = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF1A1A1A);
    final accent = const Color(0xFF002FA7);

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: borderCol),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'New Invoice',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: textCol,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Invoice number auto-generated on save',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 14,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
              ),
              const SizedBox(height: 24),
              
              TextFormField(
                controller: _clientNameController,
                style: GoogleFonts.spaceGrotesk(color: textCol),
                decoration: InputDecoration(
                  labelText: 'Client Name',
                  labelStyle: GoogleFonts.spaceGrotesk(color: isDark ? Colors.white54 : Colors.black54),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: borderCol),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: borderCol),
                  ),
                ),
                validator: (val) => val == null || val.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _amountController,
                      style: GoogleFonts.jetBrainsMono(color: textCol),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Amount',
                        labelStyle: GoogleFonts.spaceGrotesk(color: isDark ? Colors.white54 : Colors.black54),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: borderCol),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: borderCol),
                        ),
                      ),
                      validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 1,
                    child: DropdownButtonFormField<String>(
                      value: _currency,
                      dropdownColor: bg,
                      style: GoogleFonts.spaceGrotesk(color: textCol),
                      decoration: InputDecoration(
                        labelText: 'Currency',
                        labelStyle: GoogleFonts.spaceGrotesk(color: isDark ? Colors.white54 : Colors.black54),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: borderCol),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: borderCol),
                        ),
                      ),
                      items: ['USD', 'EUR', 'GBP'].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _currency = v);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Segmented Control for Status
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderCol),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _status = InvoiceStatus.draft),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: _status == InvoiceStatus.draft ? accent : Colors.transparent,
                            borderRadius: const BorderRadius.horizontal(left: Radius.circular(11)),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Draft',
                            style: GoogleFonts.spaceGrotesk(
                              color: _status == InvoiceStatus.draft ? Colors.white : textCol,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _status = InvoiceStatus.sent),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: _status == InvoiceStatus.sent ? accent : Colors.transparent,
                            borderRadius: const BorderRadius.horizontal(right: Radius.circular(11)),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Sent',
                            style: GoogleFonts.spaceGrotesk(
                              color: _status == InvoiceStatus.sent ? Colors.white : textCol,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final dt = await showDatePicker(
                          context: context,
                          initialDate: _issuedDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (dt != null) setState(() => _issuedDate = dt);
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Issue Date',
                          labelStyle: GoogleFonts.spaceGrotesk(color: isDark ? Colors.white54 : Colors.black54),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: borderCol),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: borderCol),
                          ),
                        ),
                        child: Text(
                          DateFormat.yMd().format(_issuedDate),
                          style: GoogleFonts.jetBrainsMono(color: textCol),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final dt = await showDatePicker(
                          context: context,
                          initialDate: _dueDate ?? _issuedDate.add(const Duration(days: 30)),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (dt != null) setState(() => _dueDate = dt);
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Due Date',
                          labelStyle: GoogleFonts.spaceGrotesk(color: isDark ? Colors.white54 : Colors.black54),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: borderCol),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: borderCol),
                          ),
                        ),
                        child: Text(
                          _dueDate != null ? DateFormat.yMd().format(_dueDate!) : 'Optional',
                          style: GoogleFonts.jetBrainsMono(color: _dueDate != null ? textCol : (isDark ? Colors.white54 : Colors.black54)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _notesController,
                style: GoogleFonts.spaceGrotesk(color: textCol),
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Notes (Optional)',
                  labelStyle: GoogleFonts.spaceGrotesk(color: isDark ? Colors.white54 : Colors.black54),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: borderCol),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: borderCol),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Save Invoice', style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
