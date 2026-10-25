import 'package:submersion/core/providers/provider.dart';

/// The dive detail cards that edit in place (issue #2976).
enum InlineEditCard { notes, buddies, equipment }

/// The card currently in edit mode on one dive's detail page, and whether
/// its draft differs from what is saved.
class InlineEditSession {
  const InlineEditSession({required this.card, this.dirty = false});

  final InlineEditCard card;
  final bool dirty;

  InlineEditSession copyWith({bool? dirty}) =>
      InlineEditSession(card: card, dirty: dirty ?? this.dirty);
}

/// One card edits at a time: while one is open the others' actions are
/// disabled, and the page guards leaving while the open one is dirty.
class InlineEditNotifier extends StateNotifier<InlineEditSession?> {
  InlineEditNotifier() : super(null);

  /// Opens [card] for editing. False when another card is already open.
  bool begin(InlineEditCard card) {
    final current = state;
    if (current != null && current.card != card) return false;
    state = InlineEditSession(card: card);
    return true;
  }

  void setDirty(InlineEditCard card, bool dirty) {
    final current = state;
    if (current == null || current.card != card || current.dirty == dirty) {
      return;
    }
    state = current.copyWith(dirty: dirty);
  }

  void end(InlineEditCard card) {
    if (state?.card == card) state = null;
  }
}

/// Keyed by dive id, so the master-detail pane opening another dive starts
/// with no card open.
final inlineEditNotifierProvider = StateNotifierProvider.autoDispose
    .family<InlineEditNotifier, InlineEditSession?, String>(
      (ref, diveId) => InlineEditNotifier(),
    );
