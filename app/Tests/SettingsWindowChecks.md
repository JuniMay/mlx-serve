# Settings window regression checks

Run these checks in the packaged macOS app. The Swift unit tests cover settings
selection, search matching and reset scope. These checks cover the native window
layout. Keep the server stopped and leave saved setting values unchanged.

## Category layout

1. Open Settings at its default 900 × 700 point size.
2. Select Memory and scroll to the top.
3. Select General.
4. Verify that the sidebar search field and General row remain below the toolbar.
5. Verify that General's toolbar title and Start server row are fully visible.
6. Verify that the reset caption and button remain inside the window's bottom edge,
   with comfortable bottom spacing and the button aligned to the form's right inset.
7. Select About MLX-Serve, Memory, and General in that order. Repeat checks 4–6.
8. Scroll Memory to the bottom, then select General. Repeat checks 4–6.
9. Resize the window toward its minimum size. Verify that the form scrolls,
   that the first and last controls remain reachable, and that the reset caption
   wraps without pushing either column upward or the button against the corner.
10. Restore the window size and verify the same layout again.

The sidebar's top position must stay stable when categories change. A category
must not move either column outside the window. Repeat in light and dark
appearance when those configurations are available.

## Search and help

1. Search for `--max-resident-mem`.
2. Verify that Model memory cap appears even though the flag is in its full help.
3. Verify that Memory is its only section heading and that All parameters and
   the drafter explanation are absent. There must be no empty cards or gaps
   left by hidden sections above the result.
4. Open its information button and verify that the explanation is readable.
5. Dismiss the help and search for `resets`. Only the global reset footer should
   remain; unrelated section headings and All parameters must be absent.
6. Search for `General`. Its category heading and matching rows should appear without unrelated
   headings, generation controls, or the reset footer.
7. Search for `temperature`. Verify that matching rows remain reachable and that
   no All parameters control can change parameters hidden by the search.
8. Search for `unmatchablesettingsquery`. Verify that the no-results message
   appears without section headings, empty cards, or generation controls.
9. Clear the search and select Generation Defaults. Verify that its introduction,
   All parameters control, and parameter rows return. Leave all values unchanged.
10. Select General. Verify that its first row and the sidebar search field remain
    visible.

## Help placement and control alignment

1. Select General. Verify that each information button sits beside its option
   name, on the first text baseline, rather than after the option's control.
2. Compare switches in rows with and without information buttons. Their trailing
   edges must align, including the startup options.
3. Open an information button. Verify that its complete explanation is readable
   and that closing the popover does not change the option value.
4. Repeat the alignment check in Memory and LAN Sharing with sliders and switches.
   Compare memory-reserve in Memory and KV quantization in Cache: their
   visible right edges must align despite differently sized selected labels.
   Check the same menu alignment in General, Server, Engines and Appearance. Voice menus in the leading custom groups should stay left aligned.
   In Appearance, verify that Color Mode shows every segment in full and keeps
   its right edge clear of the card's rounded corner.
5. Narrow the window until a long option name wraps. Verify that its information
   button remains beside the first line, the caption stays below the name, and
   the control remains reachable without overlapping either.

## Settings hierarchy and saved preferences

1. Verify that selected categories display their title only in the toolbar.
   Search results must include category headings when showing multiple sections.
2. Open Tools & MCP. Check that the switches lead their labels, including the
   global Tools and MCP switches. Workspace tool choices and memory/task features
   must have distinct groups; no row should float in the middle of a section.
3. Open Providers. Add an unsaved provider. Verify that each editor row has two
   columns: the option name and its editor. Placeholder text must appear inside
   the editor, not as a third column. Repeat at minimum window width. Do not save
   the blank entry or change existing credentials or provider configuration.
4. Open Server. Context size must show Auto as an explicit menu choice, retain
   a custom saved value, and display the active server limit separately.
5. Verify that Cache owns KV and prefix-cache controls, and Performance groups
   Neural Engine settings under hardware acceleration.
6. Open Generation Defaults. Verify that saved per-model thinking preferences can be
   read and that reset controls are clearly associated with their model. Use
   unit tests or an isolated fixture profile to change them.
7. Open About. Bundled engines and dependencies must remain readable and links
   must identify their destination. There must be no active update controls.
