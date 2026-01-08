import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

enum LayoutMode { rsvpOnly, splitView, ebookOnly }

/// Controls panel for RSVP reader
class RSVPControlsPanel extends StatelessWidget {
  final double wpm;
  final bool longWordDelay;
  final bool isPlaying;
  final bool hasWords;
  final bool showLayoutButtons;
  final LayoutMode layoutMode;
  final ValueChanged<double> onWpmChanged;
  final ValueChanged<bool> onLongWordDelayChanged;
  final VoidCallback? onPlayPause;
  final ValueChanged<LayoutMode> onLayoutModeChanged;

  const RSVPControlsPanel({
    super.key,
    required this.wpm,
    required this.longWordDelay,
    required this.isPlaying,
    required this.hasWords,
    required this.showLayoutButtons,
    required this.layoutMode,
    required this.onWpmChanged,
    required this.onLongWordDelayChanged,
    this.onPlayPause,
    required this.onLayoutModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Layout mode buttons (only if EPUB loaded)
          if (showLayoutButtons) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLayoutModeButton(
                  context: context,
                  icon: Icons.speed,
                  label: 'Speed Reader',
                  mode: LayoutMode.rsvpOnly,
                ),
                const SizedBox(width: 8),
                _buildLayoutModeButton(
                  context: context,
                  icon: Icons.view_column,
                  label: 'Split',
                  mode: LayoutMode.splitView,
                ),
                const SizedBox(width: 8),
                // Reader mode disabled on web due to epub_view library limitations
                Tooltip(
                  message: kIsWeb
                      ? 'Reader-Modus nicht verfügbar im Web'
                      : 'Vollbild E-Book Reader',
                  child: _buildLayoutModeButton(
                    context: context,
                    icon: Icons.book,
                    label: 'Reader',
                    mode: LayoutMode.ebookOnly,
                    enabled: !kIsWeb,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          // Settings: WPM & Long Words
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Geschwindigkeit",
                      style: TextStyle(color: Colors.grey),
                    ),
                    Row(
                      children: [
                        Text(
                          "${wpm.round()}",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        Expanded(
                          child: Slider(
                            value: wpm,
                            min: 60,
                            max: 1200,
                            onChanged: onWpmChanged,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Column(
                children: [
                  const Text(
                    "Länger stoppen bei langen Worten",
                    style: TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                  Switch(
                    value: longWordDelay,
                    onChanged: onLongWordDelayChanged,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Play Button
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed: hasWords ? onPlayPause : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: isPlaying ? 0 : 4,
              ),
              child: Text(
                isPlaying ? "Pausieren" : "Starten",
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLayoutModeButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required LayoutMode mode,
    bool enabled = true,
  }) {
    final isSelected = layoutMode == mode;
    final isDisabled = !enabled;

    return OutlinedButton.icon(
      onPressed: isDisabled ? null : () => onLayoutModeChanged(mode),
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: isDisabled
            ? Colors.grey[600]
            : isSelected
            ? Theme.of(context).colorScheme.primary
            : Colors.grey,
        side: BorderSide(
          color: isDisabled
              ? Colors.grey[800]!
              : isSelected
              ? Theme.of(context).colorScheme.primary
              : Colors.grey[700]!,
          width: isSelected && !isDisabled ? 2 : 1,
        ),
        backgroundColor: isDisabled
            ? Colors.grey[900]
            : isSelected
            ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
            : Colors.transparent,
      ),
    );
  }
}
