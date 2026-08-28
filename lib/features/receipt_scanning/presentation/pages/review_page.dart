import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';


import '../../domain/entities/receipt.dart';
import '../providers/receipt_provider.dart';
import '../widgets/receipt_item_row.dart';
import '../widgets/universal_receipt_image.dart';
import '../../../../features/boxes/data/providers/boxes_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/theme_notifier.dart';
import '../../../../core/utils/error_handler.dart';

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
  Color _getBgColor(BuildContext context) => Theme.of(context).scaffoldBackgroundColor;
  Color _getCardColor(BuildContext context) => Theme.of(context).colorScheme.surface;
  Color _getBorderColor(BuildContext context) => Theme.of(context).colorScheme.outline;
  Color _getMutedColor(BuildContext context) => Theme.of(context).colorScheme.onSurfaceVariant;
  Color _getTextColor(BuildContext context) => Theme.of(context).colorScheme.onSurface;

  Color get _accentColor => AppColors.accent;
  Color get _destructiveColor => AppColors.destructive;

  @override
  void initState() {
    super.initState();
    _merchantController = TextEditingController(text: widget.receipt.merchantName);
    _currentDate = widget.receipt.date;
    _items = widget.receipt.items.map((i) => _UiReceiptItem(const Uuid().v4(), i)).toList();
    _selectedCurrency = widget.receipt.currency;
    if (_selectedCurrency.isEmpty) _selectedCurrency = 'USD';
    _selectedBoxId = widget.receipt.boxId ?? ref.read(activeBoxIdProvider);
    
    _totalController = TextEditingController(text: widget.receipt.totalAmount.toStringAsFixed(2));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(isBalatroThemeProvider.notifier).checkTrigger(widget.receipt.totalAmount);
      for (final item in widget.receipt.items) {
        ref.read(isBalatroThemeProvider.notifier).checkTrigger(item.unitPrice);
        ref.read(isBalatroThemeProvider.notifier).checkTrigger(item.totalPrice);
      }
    });
  }

  void _calculateTotal() {
    final sum = _items.fold(0.0, (prev, wrapper) => prev + wrapper.item.totalPrice);
    if (_isTotalLocked) {
      _totalController.text = sum.toStringAsFixed(2);
    }
    ref.read(isBalatroThemeProvider.notifier).checkTrigger(sum);
    ref.read(isBalatroThemeProvider.notifier).checkTrigger(_totalController.text);
  }

  void _updateItem(int index, ReceiptItem newItem) {
    final triggeredPrice = ref.read(isBalatroThemeProvider.notifier).checkTrigger(newItem.unitPrice) ||
                           ref.read(isBalatroThemeProvider.notifier).checkTrigger(newItem.totalPrice) ||
                           ref.read(isBalatroThemeProvider.notifier).checkTrigger(newItem.description);

    final sanitizedItem = triggeredPrice
        ? newItem.copyWith(unitPrice: 0.0, totalPrice: 0.0)
        : newItem;

    setState(() {
      _items[index] = _UiReceiptItem(_items[index].id, sanitizedItem);
      _calculateTotal();
    });

    if (triggeredPrice && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("🃏 Balatro Reality Engaged! +500 XP Awarded! Value sanitized to protect database."),
          backgroundColor: Color(0xFFFF3333),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 4),
        ),
      );
    }
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
        items: _items.map((w) => w.item.copyWith(boxId: _selectedBoxId)).toList(),
        boxId: _selectedBoxId,
      );

      await ref.read(receiptListProvider.notifier).addReceipt(updatedReceipt);

      if (mounted) {
        context.go('/home');
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showErrorSnackBar(
          context: context,
          error: e,
          actionLabel: 'Retry',
          onAction: _saveReceipt,
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
                         if (!context.mounted) return;
                         context.go('/home');
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
            child: UniversalReceiptImage(
              imagePath: widget.receipt.imagePath,
              receiptId: widget.receipt.id,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              color: Colors.black.withOpacity(0.5),
              colorBlendMode: BlendMode.darken,
              errorBuilder: (context, error, stackTrace) => Container(
                color: _getBgColor(context),
                alignment: Alignment.center,
                child: Icon(
                  Icons.receipt_long_outlined,
                  size: 64,
                  color: _getMutedColor(context).withOpacity(0.25),
                ),
              ),
            ),
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
                                        final newQty = int.tryParse(val) ?? 1;
                                        _updateItem(index, item.copyWith(
                                          quantity: newQty,
                                          totalPrice: item.unitPrice * newQty,
                                        ));
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
                                        final newPrice = double.tryParse(val) ?? 0.0;
                                        _updateItem(index, item.copyWith(
                                          unitPrice: newPrice,
                                          totalPrice: newPrice * item.quantity,
                                        ));
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
