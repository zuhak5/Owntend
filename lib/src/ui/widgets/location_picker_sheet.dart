import '../components.dart' as hk_ui;
import '../presentation_support.dart';

class LocationPickerSheet extends ConsumerStatefulWidget {
  const LocationPickerSheet({super.key});

  @override
  ConsumerState<LocationPickerSheet> createState() =>
      _LocationPickerSheetState();
}

class _LocationPickerSheetState extends ConsumerState<LocationPickerSheet> {
  final _controller = TextEditingController();
  Future<List<HomeLocation>>? _results;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim();
    return EditorSheetFrame(
      title: context.l10n.homeLocation,
      saveLabel: context.l10n.search,
      saveEnabled: query.isNotEmpty,
      onCancel: () => Navigator.of(context).pop(),
      onSave: () => _search(_controller.text),
      child: Column(
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Symbols.search_rounded),
              labelText: context.l10n.cityOrZip,
            ),
            onSubmitted: _search,
          ),
          const SizedBox(height: HkSpacing.md),
          FutureBuilder<List<HomeLocation>>(
            future: _results,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                );
              }
              if (snapshot.hasError) {
                return hk_ui.PremiumEmptyState(
                  icon: Symbols.cloud_off_rounded,
                  title: context.l10n.somethingWentWrongPleaseTryAgain,
                  body: '',
                  illustrationTone: hk_ui.HkIllustrationTone.danger,
                  action: FilledButton(
                    onPressed: () => _search(_controller.text),
                    child: Text(context.l10n.retry),
                  ),
                );
              }
              final results = snapshot.data ?? const <HomeLocation>[];
              if (results.isEmpty) {
                return hk_ui.PremiumEmptyState(
                  icon: Symbols.location_on_rounded,
                  title: context.l10n.searchForALocation,
                  body: context.l10n.weatherContextImprovesOutdoorTasks,
                );
              }
              return Column(
                children: [
                  for (final location in results)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Symbols.location_on_rounded),
                      title: Text(location.label),
                      subtitle: Text(
                        bidiIsolate(
                          context,
                          '${location.latitude.toStringAsFixed(2)}, ${location.longitude.toStringAsFixed(2)}',
                        ),
                      ),
                      onTap: () => Navigator.of(context).pop(location),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  void _search(String query) {
    setState(() {
      _results = ref.read(weatherRepositoryProvider).searchLocations(query);
    });
  }
}
