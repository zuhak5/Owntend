part of '../../../../main.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<SearchResult> _results = const [];
  bool _loading = false;
  bool _indexReady = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_scheduleSearch);
    unawaited(_rebuildIndex());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_scheduleSearch);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _rebuildIndex() async {
    try {
      await ref.read(searchRepositoryProvider).rebuildIndex();
      _indexReady = true;
    } catch (_) {
      // Search still renders its explicit error when a user queries.
    }
  }

  void _scheduleSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      unawaited(_runSearch(_controller.text));
    });
  }

  Future<void> _runSearch(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty) {
      if (mounted) {
        setState(() {
          _results = const [];
          _error = null;
          _loading = false;
        });
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = ref.read(searchRepositoryProvider);
      if (!_indexReady) {
        await repository.rebuildIndex();
        _indexReady = true;
      }
      final results = await repository.search(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _failureMessage(context, error);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = _controller.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.search)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(
              HkSpacing.gutter,
              HkSpacing.xs,
              HkSpacing.gutter,
              HkSpacing.bottomAction,
            ),
            children: [
              TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Symbols.search_rounded),
                  suffixIcon: hasQuery
                      ? IconButton(
                          tooltip: context.l10n.clearSearch,
                          onPressed: () => _controller.clear(),
                          icon: const Icon(Symbols.close_rounded),
                        )
                      : null,
                  labelText: context.l10n.searchRoomsItemsTasksNotes,
                ),
                onSubmitted: _runSearch,
              ),
              if (_loading) ...[
                const SizedBox(height: HkSpacing.sm),
                const LinearProgressIndicator(),
              ],
              if (_error != null) ...[
                const SizedBox(height: HkSpacing.sm),
                ErrorPanel(message: _error!),
              ],
              if (_results.isNotEmpty) ...[
                const SizedBox(height: HkSpacing.sm),
                const HkNativeAdCard(placement: 'search'),
              ],
              if (_results.isEmpty) const SizedBox(height: HkSpacing.sm),
              if (!hasQuery)
                hk_ui.PremiumEmptyState(
                  icon: Symbols.manage_search_rounded,
                  title: context.l10n.searchYourHome,
                  body: context.l10n.findAllHomeContent,
                )
              else if (!_loading && _results.isEmpty && _error == null)
                hk_ui.PremiumEmptyState(
                  icon: Symbols.search_off_rounded,
                  illustrationTone: hk_ui.HkIllustrationTone.neutral,
                  title: context.l10n.noResults,
                  body: context.l10n.tryAnotherSearchTerm,
                )
              else
                for (final result in _results)
                  hk_ui.PremiumCard(
                    margin: const EdgeInsets.only(bottom: HkSpacing.xs),
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(_searchResultIcon(result.entityType)),
                      title: Text(_searchResultTitle(context, result)),
                      subtitle: Text(
                        _searchResultSubtitle(context, result),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Symbols.chevron_right_rounded),
                      onTap: () => _openSearchResult(context, result),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _searchResultIcon(String type) {
  return switch (type) {
    'area' => Symbols.home_work_rounded,
    'room' => Symbols.meeting_room_rounded,
    'asset' => Symbols.inventory_2_rounded,
    'plan' => Symbols.task_alt_rounded,
    'tag' => Symbols.sell_rounded,
    'category' => Symbols.category_rounded,
    _ => Symbols.search_rounded,
  };
}

String _searchResultTitle(BuildContext context, SearchResult result) {
  if (result.entityType == 'category') {
    final category = appCategoryById[result.entityId];
    if (category != null) {
      return _categoryLabel(context, category);
    }
  }
  return result.title;
}

String _searchResultSubtitle(BuildContext context, SearchResult result) {
  final type = switch (result.entityType) {
    'area' => context.l10n.area,
    'room' => context.l10n.room,
    'asset' => context.l10n.item,
    'plan' => context.l10n.task,
    'tag' => context.l10n.tag,
    'category' => context.l10n.category,
    _ => context.l10n.result,
  };
  final snippet = result.entityType == 'category' ? '' : result.snippet.trim();
  return snippet.isEmpty
      ? type
      : context.l10n.searchResultWithSnippet(type, snippet);
}

void _openSearchResult(BuildContext context, SearchResult result) {
  switch (result.entityType) {
    case 'room':
      context.push('/assets/room/${result.entityId}');
    case 'asset':
      context.push('/assets/thing/${result.entityId}');
    case 'plan':
      context.push('/maintenance/${result.entityId}');
    default:
      context.push('/assets');
  }
}
