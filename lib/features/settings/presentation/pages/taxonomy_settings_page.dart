import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/constants/taxonomy_constants.dart';
import '../providers/taxonomy_provider.dart';
import '../../../receipt_scanning/domain/entities/receipt.dart';

class TaxonomySettingsPage extends ConsumerWidget {
  const TaxonomySettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch dynamic hierarchy
    final hierarchy = ref.watch(taxonomyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Taxonomy Settings'),
        actions: [
            IconButton(
              icon: const Icon(Icons.restore),
              tooltip: 'Reset to Defaults',
              onPressed: () {
                _confirmReset(context, ref);
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: hierarchy.entries.map((mainEntry) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.surface.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  title: Text(mainEntry.key, style: const TextStyle(color: AppTheme.textMain, fontWeight: FontWeight.bold)),
                  iconColor: AppTheme.primary,
                  collapsedIconColor: AppTheme.textDim,
                  children: mainEntry.value.entries.map((subEntry) {
                    return ExpansionTile(
                      title: Text(subEntry.key, style: const TextStyle(color: AppTheme.textMain, fontSize: 15)),
                      iconColor: AppTheme.secondary,
                      collapsedIconColor: AppTheme.textDim,
                      trailing: IconButton(
                        icon: const Icon(Icons.add_circle_outline, size: 20), 
                        color: AppTheme.secondary,
                        onPressed: () => _showAddItemDialog(context, ref, mainEntry.key, subEntry.key),
                      ),
                      children: subEntry.value.map((item) {
                        return ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                          title: Text(item.name, style: const TextStyle(color: AppTheme.textDim)),
                          trailing: _NecessityToggle(
                            current: _parseNecessity(item.defaultNecessity),
                            onChanged: (newVal) {
                                ref.read(taxonomyProvider.notifier).updateItemNecessity(
                                  mainEntry.key, 
                                  subEntry.key, 
                                  item.name, 
                                  newVal.name,
                                );
                            },
                          ),
                        );
                      }).toList(),
                    );
                  }).toList(),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  ItemNecessity _parseNecessity(String val) {
    try {
      return ItemNecessity.values.firstWhere((e) => e.name == val);
    } catch (_) {
      return ItemNecessity.unknown;
    }
  }

  void _confirmReset(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Reset Taxonomy?', style: TextStyle(color: AppTheme.textMain)),
        content: const Text('This will revert all categories and necessities to the system defaults. Existing receipts won\'t change.', style: TextStyle(color: AppTheme.textDim)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
             onPressed: () {
               ref.read(taxonomyProvider.notifier).resetDefaults();
               Navigator.pop(ctx);
             },
             child: const Text('Reset', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      )
    );
  }

  void _showAddItemDialog(BuildContext context, WidgetRef ref, String main, String sub) {
    final nameController = TextEditingController();
    ItemNecessity selectedNecessity = ItemNecessity.discretional;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AppTheme.surface,
            title: Text('Add to $sub', style: const TextStyle(color: AppTheme.textMain)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  style: const TextStyle(color: AppTheme.textMain),
                  decoration: const InputDecoration(
                    labelText: 'Item Name',
                    labelStyle: TextStyle(color: AppTheme.textDim),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.textDim)),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('Necessity: ', style: TextStyle(color: AppTheme.textDim)),
                    const SizedBox(width: 8),
                    _NecessityToggle(
                      current: selectedNecessity,
                      onChanged: (val) => setDialogState(() => selectedNecessity = val),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              TextButton(
                onPressed: () {
                  if (nameController.text.isNotEmpty) {
                    ref.read(taxonomyProvider.notifier).addItem(main, sub, nameController.text, selectedNecessity.name);
                    Navigator.pop(ctx);
                  }
                },
                child: const Text('Add'),
              ),
            ],
          );
        }
      ),
    );
  }
}

class _NecessityToggle extends StatelessWidget {
  final ItemNecessity current;
  final Function(ItemNecessity) onChanged;

  const _NecessityToggle({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        final nextIndex = (current.index + 1) % ItemNecessity.values.length;
        onChanged(ItemNecessity.values[nextIndex]);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
           color: _getColor(current).withOpacity(0.2),
           borderRadius: BorderRadius.circular(12),
           border: Border.all(color: _getColor(current)),
        ),
        child: Text(
          current.name.toUpperCase(),
          style: TextStyle(color: _getColor(current), fontSize: 10, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Color _getColor(ItemNecessity n) {
    switch (n) {
      case ItemNecessity.essential: return Colors.greenAccent;
      case ItemNecessity.discretional: return Colors.amberAccent;
      case ItemNecessity.junk: return Colors.redAccent;
      case ItemNecessity.unknown: return Colors.grey;
    }
  }
}
