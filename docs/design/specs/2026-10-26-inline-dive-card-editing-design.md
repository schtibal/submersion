# Edit notes, buddies and equipment on the dive detail page

Issue: #2976.
Mockup: [assets/2026-10-26-inline-dive-card-editing-mockup.html](assets/2026-10-26-inline-dive-card-editing-mockup.html).

## Intent

Changing a dive's notes, buddies or equipment today means opening the full
dive editor, expanding the right group and scrolling to the field. A diver who
is looking at a dive and notices something missing should be able to fix it on
the card they are looking at.

## Goals

- The Notes, Buddies and Equipment cards on the dive detail page each gain an
  edit mode of their own.
- Buddies and Equipment also gain an Add action that works without entering
  edit mode.
- Saving a card writes only that card's data, so it cannot overwrite a field
  of the dive that changed elsewhere (another device, the full editor) while
  the card was open.

## Non-goals

- No other card becomes editable (cylinders, sightings, conditions, and so on).
- No change to the full dive editor's behaviour.
- No change to the buddy selection sheet, the role selector or the equipment
  picker sheet themselves; the cards reuse them as they are.

## Anti-goals

- Nothing a diver does in a card's edit mode reaches the database before they
  press Save. Cancel leaves the dive exactly as it was.
- A dive with no notes or no buddies must still show its empty state as today
  when not editing. (A dive with no equipment used to show no Equipment card
  at all; it now shows the card with an empty line, since Add has to be
  reachable there.)

## Behaviour

### Shared

1. A card in view mode shows its action icons at the right of its header.
2. Pressing the card's Edit icon enters edit mode: the Edit icon is replaced by
   a **Cancel** text button and a **Save** filled button, matching the app's
   dialogs. The card is outlined in the primary colour while editing.
3. Save writes the draft, leaves edit mode and shows the saved values. If the
   write fails, the card stays in edit mode with the draft intact and a
   snackbar reports the error.
4. Cancel discards the draft and leaves edit mode.
5. While Save runs, both buttons are disabled.
6. One card edits at a time: while one is open, the other cards' Add and
   Edit icons are disabled.
7. Leaving the page (back), opening the full editor, or stepping to the
   previous or next dive while the open card's draft differs from what is
   saved asks first, with the editor's own discard dialog.

### Notes

1. View: an Edit (pencil) icon at the top right of the header.
2. Edit: an outlined, multi-line text field holding the notes. It is at least
   eight lines tall and grows with its text. A grip at its bottom-right corner
   drags it taller, for more visible rows than its text needs.
3. Save writes the notes text, unchanged (no trimming).

### Buddies

1. View: an Add (plus) icon and an Edit (pencil) icon at the top right, after
   the buddy count.
2. Add, from view mode: opens the same buddy selection sheet the full editor
   uses, with the dive's current buddies selected. Done in the sheet saves the
   resulting list straight away; closing the sheet without Done changes
   nothing.
3. Edit: each buddy row trades its chevron for a pencil and an X. The Me row
   shows only the pencil, with the X slot left empty so the icons line up.
   In view mode Me appears only when the dive has a role of the diver's
   own; in edit mode it is always there (reading "Set my role" when empty),
   as the full editor's Me chip is.
   - The pencil opens the role selector for that person, as tapping a chip
     does in the full editor. Me's selector allows no role, as it does there;
     a buddy left with no role becomes "Buddy", as there.
   - The X removes that buddy from the draft.
   - The Add icon stays in the header in edit mode; buddies picked there join
     the draft instead of saving.
   - Rows do not navigate to the buddy page while editing.
4. Save writes the buddy list with their roles, and the diver's own roles,
   only the parts that changed.
5. A dive that has no linked buddies but legacy free-text buddy names keeps
   showing the legacy section in view mode as today. Add and Edit both work
   there; edit mode lists only linked buddies, as the full editor does.

### Equipment

1. View: an Add (plus) icon and an Edit (pencil) icon between the existing
   arrange (sort) icon and the collapse chevron. Pressing either also expands
   a collapsed card.
2. Add, from view mode: opens the same multi-select equipment picker the full
   editor uses (spare gear hidden, retired gear offered). Confirming saves the
   picked gear straight away, an assembly bringing its parts exactly as the
   full editor does.
3. Edit: each row trades its chevron for an X. An assembly's X removes it with
   its parts; a part's X removes only that part; a set chip's X removes the
   set's gear, all as in the full editor. Rows do not get a pencil: a piece of
   gear on a dive has nothing to edit. The arrange icon and the check-in chips
   are hidden while editing, and rows do not navigate.
   - The Add icon stays in the header; gear picked there joins the draft.
4. Save writes the dive's gear links only.

## Data

- **Notes:** a new `DiveRepository.setNotes(diveId, notes)` writes the
  `notes` column and `updated_at`, marks the dive pending for sync and
  notifies listeners, as `setSite` does.
- **Diver roles:** a new `DiveRepository.setDiverRoles(diveId, roleIds)`
  writes the primary role to `dives.diver_role` and the full set through the
  existing role-link writer, the way `updateDive` does.
- **Buddies:** the existing `BuddyRepository.setBuddiesForDive`.
- **Gear:** a new `DiveRepository.setDiveGear(diveId, links)` reusing the
  existing gear-diff writer, so unchanged links keep their rows.

Each card invalidates the providers the full editor invalidates for the same
data, through helpers shared with the editor where the editor already has the
list.

## Testing

- Repository tests for the three new methods: the column(s) written, the
  dive marked pending, other columns untouched.
- A widget test per card: icons in view mode, entering edit mode, Cancel
  restoring the original, Save calling the repository with the draft, the Me
  row having no X, Add saving straight away from view mode.
