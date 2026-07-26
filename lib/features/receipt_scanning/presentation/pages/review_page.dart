// ignore_for_file: deprecated_member_use, deprecated_member_use_from_same_package, unused_local_variable, unnecessary_underscores, invalid_annotation_target, unused_element, non_constant_identifier_names, use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:io';


import '../../domain/entities/receipt.dart';
import '../providers/receipt_provider.dart';
import '../widgets/receipt_item_row.dart';
import '../../../../features/boxes/data/providers/boxes_provider.dart';

class ReviewPage extends ConsumerStatefulWidget {
  final Receipt receipt;
  const ReviewPage({super.key, required this.receipt});

  @override
  ConsumerState<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends ConsumerState<ReviewPage> {
  late TextEditingController _merchantController;
  late TextEditingController _totalController;
  late List<_UiReceiptItem> _items; 
  late DateTime _currentDate;
  
  bool _isTotalLocked = true;
  bool _isSaving = false;
  
  String _selectedCurrency = 'USD';
  String _selectedBoxId = 'main';

  Color get _accentColor => const Color(0xFF002FA7);
  Color get _destructiveColor => const Color(0xFFD4183D);
  Color _getBgColor(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? const Color(0xFF050505) : const Color(0xFFFAFAFA);
  Color _getCardColor(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0F0F0F) : Colors.white;
  Color _getBorderColor(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.06);
  Color _getMutedColor(BuildContext context) => const Color(0xFF737373);
  Color _getTextColor(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? const Color(0xFFF5F5F5) : const Color(0xFF1A1A1A);

  @override
  void initState() {
    super.initState();
    _merchantController = TextEditingController(text: widget.receipt.merchantName);
    _currentDate = widget.receipt.date;
    _items = widget.receipt.items.map((i) => _UiReceiptItem(const Uuid().v4(), i)).toList();
    _selectedCurrency = widget.receipt.currency;
    if (_selectedCurrency.isEmpty) _selectedCurrency = 'USD';
    
    _totalController = TextEditingController(text: widget.receipt.totalAmount.toStringAsFixed(2));
    _calculateTotal();
  }

  void _calculateTotal() {
    if (_isTotalLocked) {
      final sum = _items.fold(0.0, (prev, wrapper) => prev + wrapper.item.totalPrice);
      _totalController.text = sum.toStringAsFixed(2);
    }
  }

  void _updateItem(int index, ReceiptItem newItem) {
    setState(() {
      _items[index] = _UiReceiptItem(_items[index].id, newItem);
      _calculateTotal();
    });
  }
  
  void _deleteItem(int index) {
    setState(() {
      _items.removeAt(index);
      _calculateTotal();
    });
  }

  void _addItem() {
    setState(() {
      _items.add(_UiReceiptItem(const Uuid().v4(), const ReceiptItem(
        description: '',
        unitPrice: 0.0,
        quantity: 1,
        totalPrice: 0.0,
      )));
    });
  }

  Future<void> _saveReceipt() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final updatedReceipt = widget.receipt.copyWith(
        merchantName: _merchantController.text,
        totalAmount: double.tryParse(_totalController.text) ?? 0.0,
        date: _currentDate,
        currency: _selectedCurrency,
        items: _items.map((w) => w.item).toList(),
      );

      await ref.read(receiptListProvider.notifier).addReceipt(updatedReceipt);

      if (mounted) {
        context.go('/home');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: _destructiveColor),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final boxes = ref.watch(boxesProvider);
    final selectedBox = boxes.firstWhere(
      (b) => b.id == _selectedBoxId, 
      orElse: () => boxes.isNotEmpty ? boxes.first : throw StateError('No boxes available')
    );

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(color: Colors.white),
        actions: [
          IconButton(
            icon: Icon(Icons.delete_outline, color: _destructiveColor),
            onPressed: () {
               showDialog(
                 context: context, 
                 builder: (ctx) => AlertDialog(
                   backgroundColor: _getCardColor(context),
                   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                   title: Text('Delete Receipt?', style: GoogleFonts.spaceGrotesk(color: _getTextColor(context), fontWeight: FontWeight.bold)),
                   content: Text('This action cannot be undone.', style: GoogleFonts.spaceGrotesk(color: _getMutedColor(context))),
                   actions: [
                     TextButton(
                       child: Text('Cancel', style: GoogleFonts.spaceGrotesk(color: _getMutedColor(context))),
                       onPressed: () => Navigator.pop(ctx),
                     ),
                     TextButton(
                       child: Text('Delete', style: GoogleFonts.spaceGrotesk(color: _destructiveColor, fontWeight: FontWeight.bold)),
                       onPressed: () async {
                         Navigator.pop(ctx);
                         await ref.read(receiptListProvider.notifier).deleteReceipt(widget.receipt.id);
                         if (mounted) context.go('/home');
                       },
                     ),
                   ],
                 ),
               );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: widget.receipt.imagePath != null
                ? kIsWeb
                    ? Image.network(
                        widget.receipt.imagePath!,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        color: Colors.black.withOpacity(0.5),
                        colorBlendMode: BlendMode.darken,
                      )
                    : Image.file(
                        File(widget.receipt.imagePath!),
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        color: Colors.black.withOpacity(0.5),
                        colorBlendMode: BlendMode.darken,
                      )
                : Container(color: _getBgColor(context)),
          ),

          DraggableScrollableSheet(
            initialChildSize: 0.62,
            minChildSize: 0.45,
            maxChildSize: 0.95,
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: _getBgColor(context),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, spreadRadius: 5)
                  ],
                ),
                child: Column(
                  children: [
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 12, bottom: 8),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: _getMutedColor(context).withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    Expanded(
                      child: CustomScrollView(
                        controller: scrollController,
                        slivers: [
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      _buildCurrencySelector(context),
                                      const SizedBox(width: 8),
                                      _buildBoxSelector(context, boxes, selectedBox),
                                    ],
                                  ).animate().fadeIn().slideY(begin: 0.1),
                                  const SizedBox(height: 24),

                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _merchantController,
                                          style: GoogleFonts.spaceGrotesk(
                                            fontSize: 32,
                                            fontWeight: FontWeight.bold,
                                            color: _getTextColor(context),
                                          ),
                                          decoration: InputDecoration(
                                            border: InputBorder.none,
                                            hintText: 'Merchant',
                                            hintStyle: TextStyle(color: _getMutedColor(context)),
                                            isDense: true,
                                            contentPadding: EdgeInsets.zero,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: () async {
                                          final picked = await showDatePicker(
                                            context: context,
                                            initialDate: _currentDate,
                                            firstDate: DateTime(2000),
                                            lastDate: DateTime.now(),
                                          );
                                          if (picked != null) setState(() => _currentDate = picked);
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: _getCardColor(context),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: _getBorderColor(context)),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.calendar_today, size: 14, color: _getTextColor(context)),
                                              const SizedBox(width: 6),
                                              Text(
                                                DateFormat('dd MMM').format(_currentDate),
                                                style: GoogleFonts.spaceGrotesk(
                                                  color: _getTextColor(context),
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ).animate().fadeIn().slideY(begin: 0.1, delay: 50.ms),
                                  const SizedBox(height: 32),

                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'LINE ITEMS (${_items.length})',
                                        style: GoogleFonts.spaceGrotesk(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: _getMutedColor(context),
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      Text(
                                        'Logging to ${selectedBox.name}',
                                        style: GoogleFonts.spaceGrotesk(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: _accentColor,
                                        ),
                                      ),
                                    ],
                                  ).animate().fadeIn(delay: 100.ms),
                                  const SizedBox(height: 16),
                                ],
                              ),
                            ),
                          ),

                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 24.0),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  if (index == _items.length) {
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 8.0, bottom: 24.0),
                                      child: InkWell(
                                        onTap: _addItem,
                                        borderRadius: BorderRadius.circular(16),
                                        child: Container(
                                          padding: const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(
                                              color: _getBorderColor(context),
                                              style: BorderStyle.solid,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.add, color: _getMutedColor(context), size: 18),
                                              const SizedBox(width: 8),
                                              Text(
                                                'Add Line Item',
                                                style: GoogleFonts.spaceGrotesk(
                                                  color: _getMutedColor(context),
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ).animate().fadeIn(delay: 200.ms),
                                    );
                                  }

                                  final wrapper = _items[index];
                                  final item = wrapper.item;
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 16),
                                    clipBehavior: Clip.antiAlias,
                                    decoration: BoxDecoration(
                                      color: _getCardColor(context),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: _getBorderColor(context)),
                                    ),
                                    child: ReceiptItemRow(
                                      key: ValueKey(wrapper.id),
                                      item: item,
                                      onDelete: () => _deleteItem(index),
                                      onQuantityChanged: (val) {
                                        final q = int.tryParse(val) ?? 1;
                                        _updateItem(index, item.copyWith(quantity: q, totalPrice: q * item.unitPrice));
                                      },
                                      onDescriptionChanged: (val) {
                                        _updateItem(index, item.copyWith(description: val));
                                      },
                                      onTaxonomyChanged: (necessity, mainCat, subCat) {
                                        _updateItem(index, item.copyWith(
                                          necessity: necessity, 
                                          mainCategory: mainCat, 
                                          subCategory: subCat,
                                          category: subCat ?? mainCat,
                                        ));
                                      },
                                      onPriceChanged: (val) {
                                        final p = double.tryParse(val) ?? 0.0;
                                        _updateItem(index, item.copyWith(unitPrice: p, totalPrice: item.quantity * p));
                                      },
                                      onAssetChanged: (val) {
                                        _updateItem(index, item.copyWith(isAsset: val));
                                      },
                                    ),
                                  ).animate().fadeIn(delay: (150 + index * 50).ms).slideY(begin: 0.1);
                                },
                                childCount: _items.length + 1,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    Container(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                      decoration: BoxDecoration(
                        color: _getBgColor(context),
                        border: Border(top: BorderSide(color: _getBorderColor(context))),
                        boxShadow: [
                          BoxShadow(color: _getBgColor(context), offset: const Offset(0, -10), blurRadius: 10),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Total (${_items.length} Items)',
                                    style: GoogleFonts.spaceGrotesk(
                                      color: _getMutedColor(context),
                                      fontSize: 14,
                                    ),
                                  ),
                                  if (selectedBox.budget > 0)
                                    Text(
                                      'Budget Remaining: ${(selectedBox.budget - selectedBox.spent).toStringAsFixed(0)}',
                                      style: GoogleFonts.spaceGrotesk(
                                        color: _getMutedColor(context),
                                        fontSize: 12,
                                      ),
                                    ),
                                ],
                              ),
                              const Spacer(),
                              IconButton(
                                icon: Icon(
                                  _isTotalLocked ? Icons.lock : Icons.lock_open,
                                  color: _isTotalLocked ? _getMutedColor(context) : _accentColor,
                                  size: 18,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _isTotalLocked = !_isTotalLocked;
                                    if (_isTotalLocked) _calculateTotal();
                                  });
                                },
                              ),
                              SizedBox(
                                width: 120,
                                child: TextField(
                                  controller: _totalController,
                                  enabled: !_isTotalLocked,
                                  textAlign: TextAlign.right,
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: _isTotalLocked ? _getTextColor(context) : _accentColor,
                                  ),
                                  decoration: InputDecoration(
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                    prefixText: _selectedCurrency == 'USD' ? '\$' : _selectedCurrency == 'EUR' ? '€' : _selectedCurrency,
                                    prefixStyle: GoogleFonts.jetBrainsMono(
                                      fontSize: 24,
                                      color: _isTotalLocked ? _getTextColor(context) : _accentColor,
                                    ),
                                  ),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton(
                              onPressed: _isSaving ? null : _saveReceipt,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _accentColor,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: _isSaving 
                                  ? const SizedBox(
                                      width: 24, height: 24,
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                    )
                                  : Text(
                                      'Commit to ${selectedBox.name}',
                                      style: GoogleFonts.spaceGrotesk(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCurrencySelector(BuildContext context) {
    return PopupMenuButton<String>(
      initialValue: _selectedCurrency,
      onSelected: (val) => setState(() => _selectedCurrency = val),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: _getCardColor(context),
      itemBuilder: (context) => ['USD', 'EUR', 'GBP', 'JPY', 'CHF']
          .map((c) => PopupMenuItem(
                value: c,
                child: Text(c, style: GoogleFonts.spaceGrotesk(color: _getTextColor(context))),
              ))
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _getCardColor(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _getBorderColor(context)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.public, size: 14, color: _getTextColor(context)),
            const SizedBox(width: 6),
            Text(_selectedCurrency, style: GoogleFonts.spaceGrotesk(color: _getTextColor(context), fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down, size: 16, color: _getMutedColor(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildBoxSelector(BuildContext context, List<dynamic> boxes, dynamic selectedBox) {
    return PopupMenuButton<String>(
      initialValue: _selectedBoxId,
      onSelected: (val) {
        if (val == 'MANAGE') {
          context.push('/boxes');
        } else {
          setState(() => _selectedBoxId = val);
        }
      },
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: _getCardColor(context),
      itemBuilder: (context) {
        final items = boxes.map((b) => PopupMenuItem<String>(
          value: b.id,
          child: Row(
            children: [
              Container(
                width: 12, height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(b.color),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(b.name, style: GoogleFonts.spaceGrotesk(color: _getTextColor(context)))),
            ],
          ),
        )).toList();
        
        items.add(PopupMenuItem<String>(
          value: 'MANAGE',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Divider(color: _getBorderColor(context)),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text('Manage Boxes...', style: GoogleFonts.spaceGrotesk(color: _accentColor, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ));
        return items;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _getCardColor(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _getBorderColor(context)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selectedBox.icon == 'Briefcase' ? Icons.work : Icons.home, size: 14, color: _getTextColor(context)),
            const SizedBox(width: 6),
            Text(selectedBox.name, style: GoogleFonts.spaceGrotesk(color: _getTextColor(context), fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down, size: 16, color: _getMutedColor(context)),
          ],
        ),
      ),
    );
  }
}

class _UiReceiptItem {
  final String id;
  final ReceiptItem item;
  _UiReceiptItem(this.id, this.item);
}
