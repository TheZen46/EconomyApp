import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'dart:io';

import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/receipt.dart';
import '../providers/receipt_provider.dart';
import '../widgets/receipt_item_row.dart';

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
  // late String _currentCategory; // Removed
  late DateTime _currentDate;
  
  bool _isTotalLocked = true; // Auto-calc mode
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _merchantController = TextEditingController(text: widget.receipt.merchantName);
    // _currentCategory = widget.receipt.category;
    _currentDate = widget.receipt.date;
    _items = widget.receipt.items.map((i) => _UiReceiptItem(const Uuid().v4(), i)).toList();
    
    // Initialize controller first
    _totalController = TextEditingController(text: widget.receipt.totalAmount.toStringAsFixed(2));
    
    // Then calculate (which might update it if locked)
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
        items: _items.map((w) => w.item).toList(),
      );

      // Use the notifier so it refreshes the list automatically
      await ref.read(receiptListProvider.notifier).addReceipt(updatedReceipt);

      if (mounted) {
        context.go('/home');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.error),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false, // Prevent image squashing and sheet conflict
      backgroundColor: Colors.black, // Background for image
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppTheme.error),
            onPressed: () {
               showDialog(
                 context: context, 
                 builder: (ctx) => AlertDialog(
                   backgroundColor: AppTheme.surface,
                   title: const Text('Delete Receipt?', style: TextStyle(color: AppTheme.textMain)),
                   content: const Text('This action cannot be undone.', style: TextStyle(color: AppTheme.textDim)),
                   actions: [
                     TextButton(
                       child: const Text('Cancel', style: TextStyle(color: AppTheme.textDim)),
                       onPressed: () => Navigator.pop(ctx),
                     ),
                     TextButton(
                       child: const Text('Delete', style: TextStyle(color: AppTheme.error)),
                       onPressed: () async {
                         Navigator.pop(ctx); // Close dialog
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
          // 1. Image Layer (Full Screen behind sheet)
          Positioned.fill(
            child: widget.receipt.imagePath != null
                ? InteractiveViewer(
                    minScale: 1.0,
                    maxScale: 4.0,
                    child: Image.file(
                      File(widget.receipt.imagePath!),
                      fit: BoxFit.contain,
                      alignment: Alignment.topCenter,
                    ),
                  )
                : const Center(child: Icon(Icons.image_not_supported, color: Colors.white)),
          ),

          // 2. Draggable Sheet
          DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.45, // Increased to prevent overflow of fixed footer/header
            maxChildSize: 0.95,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 20, spreadRadius: 5)],
                ),
                child: Column(
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 12, bottom: 8),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // Header (Merchant, Date, Category)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _merchantController,
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: AppTheme.textMain, 
                              fontWeight: FontWeight.bold
                            ),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              hintText: 'Merchant Name',
                              hintStyle: TextStyle(color: AppTheme.textDim),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              // Date Pill
                              InkWell(
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
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    DateFormat('dd MMM yyyy').format(_currentDate),
                                    style: const TextStyle(color: AppTheme.textDim, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                              /*
                              const Spacer(),
                              // Category Dropdown Removed
                              */
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Colors.white10),

                    // List Items
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: _items.length + 1, // +1 for Add Button
                        itemBuilder: (context, index) {
                          if (index == _items.length) {
                             // Footer Add Button
                             return Padding(
                               padding: const EdgeInsets.all(16.0),
                               child: OutlinedButton.icon(
                                 onPressed: _addItem, 
                                 icon: const Icon(Icons.add, size: 18),
                                 label: const Text('Add Missing Item'),
                                 style: OutlinedButton.styleFrom(
                                   foregroundColor: AppTheme.textDim,
                                   side: BorderSide(color: AppTheme.textDim.withOpacity(0.3), style: BorderStyle.solid), // Dashed border not native, solid for now
                                   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                 ),
                               ),
                             );
                          }
                          
                          final wrapper = _items[index];
                              final item = wrapper.item;
                              return ReceiptItemRow(
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
                                     category: subCat ?? mainCat, // Legacy compat
                                   ));
                                },
                                onPriceChanged: (val) {
                                  final p = double.tryParse(val) ?? 0.0;
                                  _updateItem(index, item.copyWith(unitPrice: p, totalPrice: item.quantity * p));
                                },
                                onAssetChanged: (val) {
                                  _updateItem(index, item.copyWith(isAsset: val));
                                },
                              );
                        },
                      ),
                    ),

                    // Total & Save Footer
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Text('Total', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppTheme.textDim)),
                              const Spacer(),
                              // Lock Icon
                              IconButton(
                                icon: Icon(
                                  _isTotalLocked ? Icons.lock : Icons.lock_open,
                                  color: _isTotalLocked ? AppTheme.textDim : AppTheme.secondary,
                                  size: 18,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _isTotalLocked = !_isTotalLocked;
                                    if (_isTotalLocked) _calculateTotal(); // Re-calc on lock
                                  });
                                },
                              ),
                              // Total Input
                              SizedBox(
                                width: 100,
                                child: TextField(
                                  controller: _totalController,
                                  enabled: !_isTotalLocked,
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontSize: 24, 
                                    fontWeight: FontWeight.bold,
                                    color: _isTotalLocked ? AppTheme.textMain : AppTheme.secondary, // Blue when manual
                                  ),
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    prefixText: 'â‚¬',
                                  ),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _isSaving ? null : _saveReceipt,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primary,
                                foregroundColor: AppTheme.background,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: _isSaving 
                                  ? const CircularProgressIndicator(color: AppTheme.background)
                                  : const Text('Save Receipt', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
}

class _UiReceiptItem {
  final String id;
  final ReceiptItem item;
  _UiReceiptItem(this.id, this.item);
}
