import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/receipt.dart';
import '../../../../core/constants/taxonomy_constants.dart';
import '../../../../core/utils/string_utils.dart';
import '../../../settings/presentation/providers/taxonomy_provider.dart';

class ReceiptItemRow extends ConsumerWidget {
  final ReceiptItem item;
  final VoidCallback onDelete;
  final Function(String) onDescriptionChanged;
  final Function(ItemNecessity, String?, String?) onTaxonomyChanged;
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
            backgroundColor: !item.isAsset ? const Color(0xFF10B981) : Colors.grey,
          ));
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          decoration: BoxDecoration(
            color: item.isAsset ? const Color(0xFF10B981).withOpacity(0.08) : Colors.transparent,
            border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Quantity Badge Input
                  Container(
                    width: 48,
                    height: 32,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.accent.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: TextFormField(
                      initialValue: '${item.quantity}',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.jetBrainsMono(
                        color: AppColors.accent,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        suffixText: '×',
                        suffixStyle: GoogleFonts.jetBrainsMono(
                          color: AppColors.accent.withOpacity(0.7),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (val) => onQuantityChanged(val.replaceAll(RegExp(r'[^0-9]'), '')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  
                  // Description
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          initialValue: item.description,
                          style: GoogleFonts.spaceGrotesk(color: AppTheme.textMain, fontSize: 14, fontWeight: FontWeight.w500),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            hintText: 'Item description',
                            hintStyle: TextStyle(color: AppTheme.textDim),
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: onDescriptionChanged,
                        ),
                        // Taxonomy Subtitle
                        GestureDetector(
                          onTap: () => _showCategoryPicker(context, ref),
                          child: Row(
                            children: [
                              Text(
                                _getCategoryText(),
                                style: TextStyle(
                                  color: item.mainCategory == null ? AppTheme.textDim.withOpacity(0.6) : AppColors.accent,
                                  fontSize: 11,
                                ),
                              ),
                              if (item.isAsset) ...[
                                const SizedBox(width: 6),
                                const Icon(Icons.shield, color: Color(0xFF10B981), size: 12),
                                const SizedBox(width: 2),
                                const Text('Vault Asset', style: TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold)),
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
                    width: 76,
                    child: TextFormField(
                      initialValue: item.unitPrice.toStringAsFixed(2),
                      textAlign: TextAlign.right,
                      style: GoogleFonts.jetBrainsMono(color: AppTheme.textMain, fontSize: 13, fontWeight: FontWeight.w600),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        prefixText: '\$ ',
                        prefixStyle: TextStyle(color: AppTheme.textDim, fontSize: 12),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: onPriceChanged,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              
              // ─── 3-Tier Necessity Interactive Pill Selector ──────────────
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _buildNecessityChip(
                    context,
                    necessity: ItemNecessity.essential,
                    label: 'Essential',
                    icon: Icons.shield_outlined,
                    color: const Color(0xFF10B981),
                  ),
                  _buildNecessityChip(
                    context,
                    necessity: ItemNecessity.discretional,
                    label: 'Discretional',
                    icon: Icons.auto_awesome_outlined,
                    color: const Color(0xFF0891B2),
                  ),
                  _buildNecessityChip(
                    context,
                    necessity: ItemNecessity.junk,
                    label: 'Junk',
                    icon: Icons.local_fire_department_outlined,
                    color: const Color(0xFFEC4899),
                  ),
                  // Digital Vault Toggle Chip
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onAssetChanged(!item.isAsset),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: item.isAsset ? const Color(0xFF10B981).withOpacity(0.18) : Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: item.isAsset ? const Color(0xFF10B981) : Colors.white.withOpacity(0.1),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            item.isAsset ? Icons.verified_user : Icons.verified_user_outlined,
                            size: 11,
                            color: item.isAsset ? const Color(0xFF10B981) : AppTheme.textDim,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            item.isAsset ? 'Vault [Active]' : '+ Vault',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 10,
                              fontWeight: item.isAsset ? FontWeight.bold : FontWeight.normal,
                              color: item.isAsset ? const Color(0xFF10B981) : AppTheme.textDim,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNecessityChip(
    BuildContext context, {
    required ItemNecessity necessity,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = item.necessity == necessity;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => onTaxonomyChanged(necessity, item.mainCategory, item.subCategory),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.2) : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.white.withOpacity(0.08),
            width: isSelected ? 1.2 : 1,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: color.withOpacity(0.3), blurRadius: 6)]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: isSelected ? color : AppTheme.textDim),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? color : AppTheme.textDim,
              ),
            ),
          ],
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

  void _showCategoryPicker(BuildContext context, WidgetRef ref) {
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
            fillColor: Colors.white.withOpacity(0.05),
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
      case ItemNecessity.essential: return const Color(0xFF10B981);
      case ItemNecessity.discretional: return const Color(0xFF0891B2);
      case ItemNecessity.junk: return const Color(0xFFEC4899);
      case ItemNecessity.unknown: return Colors.grey;
    }
  }
}
