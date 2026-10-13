import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:submersion/features/media/data/media_cache_settings.dart';
import 'package:submersion/features/settings/presentation/providers/media_cache_settings_provider.dart';
import 'package:submersion/l10n/l10n_extension.dart';

/// A cache size as the sliders show it: whole megabytes below a gigabyte,
/// whole gigabytes from there. Every stop is one or the other.
///
/// The suffixes are not localized, as nowhere else in the app (see
/// `formatBytes`), and a byte is not one of the diver's unit settings.
String formatMediaCacheSize(int mb) =>
    mb >= 1024 ? '${mb ~/ 1024} GB' : '$mb MB';

/// The two media cache sizes (issue #3337): decoded images in memory, and
/// thumbnails on disk. Each is a slider over fixed stops.
class MediaCacheSettingsCard extends ConsumerWidget {
  const MediaCacheSettingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(mediaCacheSettingsProvider);
    final notifier = ref.read(mediaCacheSettingsProvider.notifier);

    return Card(
      child: Column(
        children: [
          _CacheSizeSlider(
            sliderKey: const ValueKey('media_memory_cache_slider'),
            icon: Icons.memory_outlined,
            title: l10n.settings_mediaCache_memory_title,
            subtitle: l10n.settings_mediaCache_memory_subtitle,
            steps: kMemoryCacheStepsMb,
            valueMb: settings.memoryCacheMb,
            onChanged: notifier.setMemoryCacheMb,
          ),
          const Divider(height: 1),
          _CacheSizeSlider(
            sliderKey: const ValueKey('media_disk_cache_slider'),
            icon: Icons.sd_storage_outlined,
            title: l10n.settings_mediaCache_disk_title,
            subtitle: l10n.settings_mediaCache_disk_subtitle,
            steps: kDiskCacheStepsMb,
            valueMb: settings.diskCacheMb,
            onChanged: notifier.setDiskCacheMb,
            trailing: IconButton.outlined(
              key: const ValueKey('media_disk_cache_empty_button'),
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: l10n.settings_mediaCache_disk_empty,
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final emptied = await notifier.emptyDiskCache();
                messenger
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(
                      content: Text(
                        emptied
                            ? l10n.settings_mediaCache_disk_emptied
                            : l10n.settings_mediaCache_disk_emptyFailed,
                      ),
                    ),
                  );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CacheSizeSlider extends StatelessWidget {
  const _CacheSizeSlider({
    required this.sliderKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.steps,
    required this.valueMb,
    required this.onChanged,
    this.trailing,
  });

  final Key sliderKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final List<int> steps;
  final int valueMb;
  final Future<void> Function(int mb) onChanged;

  /// Shown to the right of the slider.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = formatMediaCacheSize(valueMb);
    // The slider runs over stop indices, not megabytes: the stops double,
    // so equal megabytes would crowd the small sizes into one end.
    final index = steps.indexOf(valueMb).clamp(0, steps.length - 1);

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: Icon(icon),
            title: Text(title),
            subtitle: Text(subtitle),
            trailing: Text(size, style: theme.textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: Slider(
                    key: sliderKey,
                    min: 0,
                    max: (steps.length - 1).toDouble(),
                    divisions: steps.length - 1,
                    value: index.toDouble(),
                    label: size,
                    semanticFormatterCallback: (value) =>
                        formatMediaCacheSize(steps[value.round()]),
                    onChanged: (value) => onChanged(steps[value.round()]),
                  ),
                ),
                if (trailing != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: trailing,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
