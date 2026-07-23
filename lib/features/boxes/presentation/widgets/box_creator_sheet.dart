import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/providers/boxes_provider.dart';

class BoxCreatorSheet extends ConsumerStatefulWidget {
  final String? editBoxId;

  const BoxCreatorSheet({Key? key, this.editBoxId}) : super(key: key);

  @override
  ConsumerState<BoxCreatorSheet> createState() => _BoxCreatorSheetState();
}

class _BoxCreatorSheetState extends ConsumerState<BoxCreatorSheet> {
  final _formKey = GlobalKey<FormState>();
  
  late TextEditingController _nameController;
  late TextEditingController _budgetController;
  
  String _currency = 'USD';
  int _selectedColor = const Color(0xFF002FA7).value;
  String _selectedIcon = 'Home';
  bool _autoCategorize = false;
  bool _isPrivate = false;

  final List<String> _currencies = ['USD', 'EUR', 'GBP', 'JPY', 'CHF'];
  final List<Color> _colors = const [
    Color(0xFF002FA7),
    Color(0xFF1A1A1A),
    Color(0xFFA3A3A3),
    Color(0xFFD4183D),
    Color(0xFF16A34A),
    Color(0xFF9333EA),
    Color(0xFFEA580C),
    Color(0xFF0891B2),
  ];
  
  final Map<String, IconData> _icons = {
    'Home': Icons.home_outlined,
    'Briefcase': Icons.work_outline,
    'Plane': Icons.flight_takeoff,
    'Target': Icons.track_changes,
    'Activity': Icons.local_activity_outlined,
  };

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _budgetController = TextEditingController(text: '0');

    if (widget.editBoxId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final box = ref.read(boxesProvider.notifier).findById(widget.editBoxId!);
        if (box != null) {
          setState(() {
            _nameController.text = box.name;
            _budgetController.text = box.budget.toStringAsFixed(0);
            _currency = box.currency;
            _selectedColor = box.color;
            _selectedIcon = box.icon ?? 'Home';
            _autoCategorize = box.autoCategorize;
            _isPrivate = box.isPrivate;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    
    final name = _nameController.text.trim();
    final budget = double.tryParse(_budgetController.text.trim()) ?? 0.0;
    
    final notifier = ref.read(boxesProvider.notifier);
    
    if (widget.editBoxId != null) {
      final existing = notifier.findById(widget.editBoxId!);
      if (existing != null) {
        notifier.updateBox(
          widget.editBoxId!,
          existing.copyWith(
            name: name,
            budget: budget,
            currency: _currency,
            color: _selectedColor,
            icon: _selectedIcon,
            autoCategorize: _autoCategorize,
            isPrivate: _isPrivate,
          ),
        );
      }
    } else {
      notifier.createNew(
        name: name,
        budget: budget,
        currency: _currency,
        color: Color(_selectedColor),
        icon: _selectedIcon,
        autoCategorize: _autoCategorize,
        isPrivate: _isPrivate,
      );
    }
    
    Navigator.of(context).pop();
  }

  void _delete() {
    if (widget.editBoxId == null || widget.editBoxId == 'main') return;
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Box?'),
        content: const Text('Are you sure you want to delete this box? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              ref.read(boxesProvider.notifier).deleteBox(widget.editBoxId!);
              Navigator.of(ctx).pop(); // pop dialog
              Navigator.of(context).pop(); // pop sheet
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F0F0F) : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
        ),
      ),
      padding: EdgeInsets.only(
        top: 24,
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                widget.editBoxId != null ? 'Edit Box' : 'Create New Box',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 24),
              
              // Name
              TextFormField(
                controller: _nameController,
                style: GoogleFonts.spaceGrotesk(color: isDark ? Colors.white : Colors.black),
                decoration: InputDecoration(
                  labelText: 'Box Name',
                  labelStyle: GoogleFonts.spaceGrotesk(color: isDark ? Colors.white54 : Colors.black54),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFFAFAFA),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (val) => val == null || val.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              
              // Budget & Currency
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _budgetController,
                      keyboardType: TextInputType.number,
                      style: GoogleFonts.jetbrainsMono(color: isDark ? Colors.white : Colors.black),
                      decoration: InputDecoration(
                        labelText: 'Budget (0 = Unlimited)',
                        labelStyle: GoogleFonts.spaceGrotesk(color: isDark ? Colors.white54 : Colors.black54),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFFAFAFA),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      validator: (val) => val == null || double.tryParse(val) == null ? 'Invalid number' : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 1,
                    child: DropdownButtonFormField<String>(
                      value: _currency,
                      dropdownColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                      style: GoogleFonts.jetbrainsMono(color: isDark ? Colors.white : Colors.black),
                      decoration: InputDecoration(
                        labelText: 'Currency',
                        labelStyle: GoogleFonts.spaceGrotesk(color: isDark ? Colors.white54 : Colors.black54),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFFAFAFA),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      items: _currencies.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _currency = val);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              // Color Picker
              Text('Color Accent', style: GoogleFonts.spaceGrotesk(color: isDark ? Colors.white70 : Colors.black87, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _colors.map((c) {
                  final isSelected = _selectedColor == c.value;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedColor = c.value),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: isSelected ? Border.all(color: isDark ? Colors.white : Colors.black, width: 3) : null,
                      ),
                      child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // Icon Picker
              Text('Icon', style: GoogleFonts.spaceGrotesk(color: isDark ? Colors.white70 : Colors.black87, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _icons.entries.map((entry) {
                  final isSelected = _selectedIcon == entry.key;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedIcon = entry.key),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF002FA7) : (isDark ? const Color(0xFF1A1A1A) : const Color(0xFFFAFAFA)),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? Colors.transparent : (isDark ? Colors.white12 : Colors.black12),
                        ),
                      ),
                      child: Icon(
                        entry.value,
                        color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // Toggles
              SwitchListTile(
                value: _autoCategorize,
                onChanged: (val) => setState(() => _autoCategorize = val),
                title: Text('Auto-categorize receipts', style: GoogleFonts.spaceGrotesk(color: isDark ? Colors.white : Colors.black)),
                activeColor: const Color(0xFF002FA7),
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                value: _isPrivate,
                onChanged: (val) => setState(() => _isPrivate = val),
                title: Text('Private Box (requires auth)', style: GoogleFonts.spaceGrotesk(color: isDark ? Colors.white : Colors.black)),
                activeColor: const Color(0xFF002FA7),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 32),

              // Actions
              Row(
                children: [
                  if (widget.editBoxId != null && widget.editBoxId != 'main') ...[
                    IconButton(
                      onPressed: _delete,
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.red.withOpacity(0.1),
                        padding: const EdgeInsets.all(16),
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF002FA7),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        'Save Box',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
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
}
