# Original User Request

## Initial Request — 2026-07-18T14:46:22Z

# Teamwork Project Prompt — Draft

> Status: Step 9 — Ready for launch
> Goal: Fix all remaining Flutter UI bugs to match Figma React export exactly.

Fix the remaining layout overflow bugs in the Flutter app's dashboard grid, and implement the complex interactive animations for the header (e.g., the expanding search bar with omni-filters) exactly as they appear in the React `header.tsx` Figma export.

Working directory: f:\testing\antigrav_test\t_aidy
Integrity mode: development

## Requirements

### R1. Fix Widget Visibility (Grid Layout)
The first 3 or 4 widgets in the responsive grid (Monthly Runway, Tax Nest, Pulse) are currently cut off or overflowing. Fix the `Wrap` or `LayoutBuilder` constraints in `home_page.dart` so all widgets are fully visible and scale correctly without clipping.

### R2. Implement Complex Header Interactions
The current Flutter `AppBar` just uses static icon buttons. You must implement the interactive state from `header.tsx`:
- When the Search icon is clicked, the search bar should animate and expand (from 40% to 100% width) replacing the title, complete with the text input field and the omni-filter chips ('Everything', 'Merchants', 'Invoices', 'Vault Assets').
- Ensure the "tAIdy" title is properly positioned on the top left of the bar as in the design.
- Implement the "Edit Layout" toggle interaction.

### R3. Polish All Interactables
Review all 8 widgets and ensure their buttons, hover states, and tap animations match the original React components. 

## Acceptance Criteria

### Layout Integrity
- [ ] Running the app on a medium or large screen displays all grid widgets fully without any overflow exceptions or clipping.

### Header Fidelity
- [ ] Tapping the search icon triggers an animated expansion of a search input field.
- [ ] The expanded search field contains the 4 filter chips exactly as designed in `header.tsx`.
- [ ] Tapping the close (X) button dismisses the search bar and restores the "tAIdy" title.
