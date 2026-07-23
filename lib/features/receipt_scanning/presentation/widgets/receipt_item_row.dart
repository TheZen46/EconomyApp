// ignore_for_file: deprecated_member_use, deprecated_member_use_from_same_package, unused_local_variable, unnecessary_underscores, invalid_annotation_target, unused_element, non_constant_identifier_names, use_build_context_synchronously
import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/receipt.dart';
import '../../../../core/constants/taxonomy_constants.dart';
import '../../../../core/utils/string_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../settings/presentation/providers/taxonomy_provider.dart';

class ReceiptItemRow extends ConsumerWidget {
  final ReceiptItem item;
  final VoidCallback onDelete;
  final Function(String) onDescriptionChanged;
  final Function(ItemNecessity, String?, String?) onTaxonomyChanged; // New combined callback
  final Function(String) onPriceChanged;
  final Function(String) onQuantityChanged;
  final ValueChanged<bool> onAssetChanged;

  const ReceiptItemRow({
    super.key,
    required this.item,
    required this.onDelete,
    required this.onDescriptionChanged,
    required this.onTaxonomyChanged,
    required this.onPriceChanged,
    required this.onQuantityChanged,
    required this.onAssetChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: key ?? ValueKey(item),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppTheme.error,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: GestureDetector(
        onLongPress: () {
          onAssetChanged(!item.isAsset);
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(!item.isAsset ? 'Marked as Asset (Vault) 🛡️' : 'Removed from Vault'),
            duration: const Duration(milliseconds: 1500),
            backgroundColor: !item.isAsset ? AppTheme.secondary : Colors.grey,
          ));
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          decoration: BoxDecoration(
            color: item.isAsset ? AppTheme.secondary.withAlpha(25) : AppTheme.surface.withAlpha(76),
            border: Border(bottom: BorderSide(color: Colors.white.withAlpha(12))),
          ),
          child: Row(
            children: [
              // Necessity Indicator (Click to Cycle)
              GestureDetector(
                onTap: () {
                  // Cycle: Essential -> Discretional -> Junk -> Unknown -> Essential
                  final nextIndex = (item.necessity.index + 1) % ItemNecessity.values.length;
                  final next = ItemNecessity.values[nextIndex];
                  onTaxonomyChanged(next, item.mainCategory, item.subCategory);
                },
                child: Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _getNecessityColor(item.necessity),
                    border: Border.all(color: Colors.white24, width: 1),
                  ),
                ),
              ),

              // Quantity (Neon Green)
              SizedBox(
                width: 30,
                child: TextFormField(
                  initialValue: '${item.quantity}x',
                  style: const TextStyle(color: AppTheme.secondary, fontWeight: FontWeight.bold, fontSize: 13),
                  decoration: const InputDecoration(border: InputBorder.none, isDense: true),
                  keyboardType: TextInputType.number,
                  onChanged: (val) => onQuantityChanged(val.replaceAll('x', '')),
                ),
              ),
              const SizedBox(width: 8),
              
              // Description & Taxonomy Subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      initialValue: item.description,
                      style: const TextStyle(color: AppTheme.textMain, fontSize: 14),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        hintText: 'Item description',
                        hintStyle: TextStyle(color: AppTheme.textDim),
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: onDescriptionChanged,
                    ),
                    // Taxonomy Picker
                    GestureDetector(
                      onTap: () => _showCategoryPicker(context, ref),
                      child: Row(
                        children: [
                          Text(
                            _getCategoryText(),
                            style: TextStyle(
                              color: item.mainCategory == null ? AppTheme.textDim.withAlpha(127) : AppTheme.primary,
                              fontSize: 11,
                            ),
                          ),
                          if (item.isAsset) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.shield, color: AppTheme.secondary, size: 12),
                            const SizedBox(width: 2),
                            const Text('Vault', style: TextStyle(color: AppTheme.secondary, fontSize: 10, fontWeight: FontWeight.bold)),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Price
              SizedBox(
                width: 70,
                child: TextFormField(
                  initialValue: item.unitPrice.toStringAsFixed(2),
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: AppTheme.textDim, fontSize: 13),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    prefixText: '€',
                    prefixStyle: TextStyle(color: AppTheme.textDim, fontSize: 12),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: onPriceChanged,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  String _getCategoryText() {
    if (item.subCategory != null && item.subCategory!.isNotEmpty) {
      return item.subCategory!;
    }
    if (item.mainCategory != null && item.mainCategory!.isNotEmpty) {
      return item.mainCategory!;
    }
    return '+ Check Category';
  }

  Color _getNecessityColor(ItemNecessity n) {
    switch (n) {
      case ItemNecessity.essential: return Colors.greenAccent;
      case ItemNecessity.discretional: return Colors.amberAccent;
      case ItemNecessity.junk: return Colors.redAccent;
      case ItemNecessity.unknown: return Colors.grey;
    }
  }

  void _showCategoryPicker(BuildContext context, WidgetRef ref) {
    // Read the current dynamic hierarchy from the provider
    final hierarchy = ref.read(taxonomyProvider);
    
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.85,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text('Select Category', style: TextStyle(color: AppTheme.textMain, fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 16),
                
                Expanded(
                  child: SearchWidget(
                    hierarchy: hierarchy,
                    onSelect: (necessity, main, sub) {
                      Navigator.pop(ctx);
                      onTaxonomyChanged(necessity, main, sub);
                    },
                  ),
                ),
              ],
            ),
          );
        }
      ),
    );
  }
}

class SearchWidget extends StatefulWidget {
  final Map<String, Map<String, List<TaxonomyItem>>> hierarchy;
  final Function(ItemNecessity, String, String) onSelect;
  const SearchWidget({super.key, required this.hierarchy, required this.onSelect});

  @override
  State<SearchWidget> createState() => _SearchWidgetState();
}

class _SearchWidgetState extends State<SearchWidget> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    bool isSearching = _query.isNotEmpty;
    
    return Column(
      children: [
        TextField(
          autofocus: false,
          style: const TextStyle(color: AppTheme.textMain),
          decoration: InputDecoration(
            hintText: 'Search category...',
            hintStyle: const TextStyle(color: AppTheme.textDim),
            prefixIcon: const Icon(Icons.search, color: AppTheme.textDim),
            filled: true,
            fillColor: Colors.white.withAlpha(12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            isDense: true,
          ),
          onChanged: (val) => setState(() => _query = val),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: isSearching ? _buildSearchResults() : _buildHierarchy(),
        ),
      ],
    );
  }

  Widget _buildSearchResults() {
    // Flatten and Filter
    final List<Map<String, dynamic>> matches = [];
    
    for (var mainEntry in widget.hierarchy.entries) {
      for (var subEntry in mainEntry.value.entries) {
        for (var item in subEntry.value) {
          if (StringUtils.fuzzyMatch(_query, item.name)) {
            matches.add({
              'main': mainEntry.key,
              'sub': subEntry.key,
              'item': item,
            });
          }
        }
      }
    }


    if (matches.isEmpty) {
      return const Center(child: Text('No matches found', style: TextStyle(color: AppTheme.textDim)));
    }

    return ListView.builder(
      itemCount: matches.length,
      itemBuilder: (context, index) {
        final m = matches[index];
        final taxItem = m['item'] as TaxonomyItem;
        return ListTile(
          title: Text(taxItem.name, style: const TextStyle(color: AppTheme.textMain)),
          subtitle: Text('${m['main']} > ${m['sub']}', style: const TextStyle(color: AppTheme.textDim, fontSize: 12)),
          trailing: _NecessityDot(necessity: _parseNecessity(taxItem.defaultNecessity)),
          onTap: () => widget.onSelect(_parseNecessity(taxItem.defaultNecessity), m['main'], m['sub']),
        );
      },
    );
  }

  Widget _buildHierarchy() {
    return ListView(
      children: widget.hierarchy.entries.map((mainEntry) {
        return Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            title: Text(mainEntry.key, style: const TextStyle(color: AppTheme.textMain, fontWeight: FontWeight.bold)),
            collapsedIconColor: AppTheme.textDim,
            iconColor: AppTheme.primary,
            children: mainEntry.value.entries.map((subEntry) {
              return ExpansionTile(
                title: Text(subEntry.key, style: const TextStyle(color: AppTheme.textMain, fontSize: 14)),
                collapsedIconColor: AppTheme.textDim,
                iconColor: AppTheme.secondary,
                children: subEntry.value.map((taxItem) {
                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.only(left: 32, right: 16),
                    title: Text(taxItem.name, style: const TextStyle(color: AppTheme.textDim)),
                    trailing: _NecessityDot(necessity: _parseNecessity(taxItem.defaultNecessity)),
                    onTap: () => widget.onSelect(_parseNecessity(taxItem.defaultNecessity), mainEntry.key, subEntry.key),
                  );
                }).toList(),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }

  ItemNecessity _parseNecessity(String val) {
    try {
      return ItemNecessity.values.firstWhere((e) => e.name == val);
    } catch (_) {
      return ItemNecessity.unknown;
    }
  }
}

class _NecessityDot extends StatelessWidget {
  final ItemNecessity necessity;
  const _NecessityDot({required this.necessity});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8, height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _getColor(),
      ),
    );
  }

  Color _getColor() {
    switch (necessity) {
      case ItemNecessity.essential: return Colors.greenAccent;
      case ItemNecessity.discretional: return Colors.amberAccent;
      case ItemNecessity.junk: return Colors.redAccent;
      case ItemNecessity.unknown: return Colors.grey;
    }
  }
}
