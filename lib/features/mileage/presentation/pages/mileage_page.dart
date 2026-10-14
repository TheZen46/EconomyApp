import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/constants/app_constants.dart';
import 'package:t_aidy/features/mileage/domain/mileage_engine.dart';
import '../../../boxes/data/providers/boxes_provider.dart';
import '../../../receipt_scanning/presentation/providers/receipt_provider.dart';

/// Interactive Mileage Logbook HUD and trip tracker for business travel tax deductions.
class MileagePage extends ConsumerStatefulWidget {
  const MileagePage({super.key});

  @override
  ConsumerState<MileagePage> createState() => _MileagePageState();
}

class _MileagePageState extends ConsumerState<MileagePage> {
  MileageRatePreset _selectedRatePreset = kMileageRatePresets.first;
  String _selectedBoxFilter = 'all';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isPrivacy = ref.watch(privacyModeProvider);

    final trips = ref.watch(mileageTripsProvider);
    final boxes = ref.watch(boxesProvider);
    final summary = ref.watch(mileageSummaryProvider);

    final filteredTrips = trips.where((t) {
      if (_selectedBoxFilter == 'all') return true;
      return t.boxId == _selectedBoxFilter;
    }).toList();

    final cardColor = isDark ? colorScheme.surfaceContainerHighest : Colors.white;
    final borderColor = colorScheme.outline.withAlpha(isDark ? 50 : 30);
    final textColor = colorScheme.onSurface;
    final mutedTextColor = colorScheme.onSurfaceVariant;
    final accentColor = colorScheme.primary;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Mileage & Travel Log',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            tooltip: 'Log New Trip',
            icon: const Icon(Icons.add_road),
            onPressed: () => _showAddTripModal(context),
          ),
          IconButton(
            tooltip: 'Statutory Rate Presets',
            icon: const Icon(Icons.tune),
            onPressed: () => _showRatePresetsModal(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddTripModal(context),
        icon: const Icon(Icons.add),
        label: Text('Log Trip', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
      ),
      body: CustomScrollView(
        slivers: [
          // Hero Summary Card
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [accentColor.withOpacity(0.35), colorScheme.secondary.withOpacity(0.18)]
                        : [accentColor.withOpacity(0.85), colorScheme.secondary.withOpacity(0.85)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: accentColor.withOpacity(0.2),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'TOTAL MILEAGE DEDUCTION',
                          style: GoogleFonts.spaceGrotesk(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.5,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${summary.tripCount} Trips',
                            style: GoogleFonts.jetBrainsMono(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppConstants.privacyMask('\$${summary.totalDeductibleAmount.toStringAsFixed(2)}', isPrivacy: isPrivacy),
                      style: GoogleFonts.jetBrainsMono(
                        color: Colors.white,
                        fontSize: 38,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('RECORDED DISTANCE', style: GoogleFonts.spaceGrotesk(fontSize: 9, color: Colors.white70, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 2),
                                Text(
                                  '${summary.totalDistanceMiles.toStringAsFixed(1)} mi (${summary.totalDistanceKm.toStringAsFixed(1)} km)',
                                  style: GoogleFonts.jetBrainsMono(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                          Container(width: 1, height: 26, color: Colors.white24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('ACTIVE RATE', style: GoogleFonts.spaceGrotesk(fontSize: 9, color: Colors.white70, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 2),
                                Text(
                                  '\$${_selectedRatePreset.ratePerUnit.toStringAsFixed(2)} / ${_selectedRatePreset.unit.name == 'miles' ? 'mi' : 'km'}',
                                  style: GoogleFonts.jetBrainsMono(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF6EE7B7)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ).animate().fade(duration: 300.ms).slideY(begin: 0.05, end: 0),
            ),
          ),

          // Box Filter Chips
          SliverToBoxAdapter(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('All Boxes'),
                    selected: _selectedBoxFilter == 'all',
                    onSelected: (val) => setState(() => _selectedBoxFilter = 'all'),
                  ),
                  const SizedBox(width: 8),
                  ...boxes.map((b) {
                    final isSelected = _selectedBoxFilter == b.id;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        avatar: Icon(Icons.inventory_2_outlined, size: 14, color: isSelected ? Colors.white : colorScheme.primary),
                        label: Text(b.name),
                        selected: isSelected,
                        onSelected: (val) => setState(() => _selectedBoxFilter = b.id),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),

          // Trips List Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'RECORDED LOGS',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: mutedTextColor,
                    ),
                  ),
                  Text('${filteredTrips.length} entries', style: GoogleFonts.spaceGrotesk(fontSize: 12, color: mutedTextColor)),
                ],
              ),
            ),
          ),

          // Trips Content
          if (filteredTrips.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.directions_car_outlined, size: 56, color: mutedTextColor.withOpacity(0.4)),
                    const SizedBox(height: 12),
                    Text(
                      'No mileage trips logged',
                      style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w600, color: textColor),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Log business drives to claim standard statutory mileage deductions.',
                      style: GoogleFonts.spaceGrotesk(fontSize: 12, color: mutedTextColor),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 80),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final trip = filteredTrips[index];
                    final box = boxes.cast().firstWhere((b) => b.id == trip.boxId, orElse: () => null);

                    return Dismissible(
                      key: Key(trip.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        decoration: BoxDecoration(
                          color: Colors.red.shade400,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.delete_outline, color: Colors.white),
                      ),
                      onDismissed: (_) => ref.read(mileageTripsProvider.notifier).removeTrip(trip.id),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderColor),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: colorScheme.primary.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(Icons.directions_car, color: colorScheme.primary, size: 22),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    trip.purpose,
                                    style: GoogleFonts.spaceGrotesk(fontSize: 14, fontWeight: FontWeight.bold, color: textColor),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${trip.startLocation} → ${trip.endLocation}',
                                    style: GoogleFonts.spaceGrotesk(fontSize: 12, color: mutedTextColor),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      if (box != null) ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: colorScheme.secondary.withOpacity(0.12),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            box.name,
                                            style: GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.bold, color: colorScheme.secondary),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                      ],
                                      Text(
                                        '${trip.date.year}-${trip.date.month.toString().padLeft(2, '0')}-${trip.date.day.toString().padLeft(2, '0')}',
                                        style: GoogleFonts.jetBrainsMono(fontSize: 10, color: mutedTextColor),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  AppConstants.privacyMask('\$${trip.totalDeductible.toStringAsFixed(2)}', isPrivacy: isPrivacy),
                                  style: GoogleFonts.jetBrainsMono(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF10B981)),
                                ),
                                Text(
                                  '${trip.distance.toStringAsFixed(1)} ${trip.unit.name == 'miles' ? 'mi' : 'km'}',
                                  style: GoogleFonts.jetBrainsMono(fontSize: 11, color: mutedTextColor),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  childCount: filteredTrips.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showAddTripModal(BuildContext context) async {
    final purposeCtrl = TextEditingController();
    final startCtrl = TextEditingController(text: 'Office HQ');
    final endCtrl = TextEditingController();
    final distCtrl = TextEditingController(text: '15');
    String? selectedBox;
    final boxes = ref.read(boxesProvider);

    try {
      await showModalBottomSheet(
        context: context,
        backgroundColor: Theme.of(context).colorScheme.surface,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Log Business Trip', style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: purposeCtrl,
                    decoration: const InputDecoration(labelText: 'Trip Purpose (e.g. Client Meeting)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: startCtrl,
                          decoration: const InputDecoration(labelText: 'Start Origin', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: endCtrl,
                          decoration: const InputDecoration(labelText: 'Destination', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: distCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Distance (${_selectedRatePreset.unit.name})',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: selectedBox,
                          decoration: const InputDecoration(labelText: 'Assign to Box', border: OutlineInputBorder()),
                          items: boxes.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name))).toList(),
                          onChanged: (val) => setModalState(() => selectedBox = val),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      final dist = double.tryParse(distCtrl.text) ?? 0.0;
                      if (dist > 0 && purposeCtrl.text.isNotEmpty) {
                        final newTrip = MileageTrip(
                          id: const Uuid().v4(),
                          date: DateTime.now(),
                          purpose: purposeCtrl.text,
                          startLocation: startCtrl.text.isEmpty ? 'Origin' : startCtrl.text,
                          endLocation: endCtrl.text.isEmpty ? 'Destination' : endCtrl.text,
                          distance: dist,
                          unit: _selectedRatePreset.unit,
                          ratePerUnit: _selectedRatePreset.ratePerUnit,
                          boxId: selectedBox,
                        );
                        ref.read(mileageTripsProvider.notifier).addTrip(newTrip);
                        Navigator.pop(ctx);
                      }
                    },
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: const Text('Save Mileage Record'),
                  ),
                ],
              ),
            );
          },
        ),
      );
    } finally {
      purposeCtrl.dispose();
      startCtrl.dispose();
      endCtrl.dispose();
      distCtrl.dispose();
    }
  }

  void _showRatePresetsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Statutory Mileage Presets', style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...kMileageRatePresets.map((preset) {
              final isSelected = _selectedRatePreset.id == preset.id;
              return ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                selected: isSelected,
                title: Text(preset.name, style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600)),
                subtitle: Text('${preset.jurisdiction} • \$${preset.ratePerUnit}/${preset.unit.name == 'miles' ? 'mi' : 'km'}'),
                trailing: isSelected ? const Icon(Icons.check_circle, color: Color(0xFF10B981)) : null,
                onTap: () {
                  setState(() => _selectedRatePreset = preset);
                  Navigator.pop(ctx);
                },
              );
            }),
          ],
        ),
      ),
    );
  }
}
