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
   Check the same menu alignment in General, Server, Engines, Appearance, and
   Voice. Voice engine, system voice, Kokoro, and clone-clip controls must use the
   trailing column, with descriptions under their names in the label column.
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
3. Open Providers. Verify that Nearby Macs is a built-in source with a discovery
   switch and restart guidance. Verify that LAN Sharing contains publishing
   controls and no discovery switch. Open the Nearby Macs reset confirmation;
   it must name discovery and preserve configured chat services. Cancel it.
   Add an unsaved chat-service provider. Verify that each editor row has two
   columns: the option name and its editor. Placeholder text must appear inside
   the editor, not as a third column. Repeat at minimum window width. Do not save
   the blank entry or change existing credentials or provider configuration.
4. Open Server. Context size must show Auto as an explicit menu choice, retain
   a custom saved value, and display the active server limit separately.
5. Verify that Cache uses separate native cards for prompt preparation, RAM
   conversation cache, SSD conversation cache, and applicable GGUF cache settings.
   Engines must use the same card style without a second frame inside each card.
   Search for a setting in one card; empty cards and headings must disappear.
   Performance has separate native cards for execution controls and Neural Engine
   acceleration. Each card has its own heading and description.
6. Open Generation Defaults. Verify that saved per-model thinking preferences can be
   read and that reset controls are clearly associated with their model. Use
   unit tests or an isolated fixture profile to change them.
7. Open About. Bundled engines and dependencies must remain readable and links
   must identify their destination. There must be no active update controls.

## Captions, help, and disclosure motion

1. Compare Model Folders, Server, Cache, Performance, Engines, and Voice. Each option
   has one short caption in its label column. In Model Folders, long paths and
   Choose, Reset, and Clear controls remain in the trailing column; the caption
   must wrap in the label column instead of crossing beneath those controls. Its full explanation opens from the information
   button beside the name. Dynamic cautions and resource costs stay readable.
2. Open Disable vision help. It must describe model-dependent memory savings and
   image-input support without promising a fixed memory reduction.
3. Expand and collapse a Tools group. Its controls must appear directly below
   its label with a brief transition, keeping the state and focus intact.
4. Repeat with Reduce Motion enabled in an isolated fixture or test profile.
   The controls must remain fully usable without expansion animation. Keep the
   user's system accessibility preferences unchanged.

Design references: [Offering help](https://developer.apple.com/design/human-interface-guidelines/offering-help),
[Layout](https://developer.apple.com/design/human-interface-guidelines/layout),
[Boxes](https://developer.apple.com/design/human-interface-guidelines/boxes),
[Disclosure controls](https://developer.apple.com/design/human-interface-guidelines/disclosure-controls),
and [Motion](https://developer.apple.com/design/human-interface-guidelines/motion).

## Generation parameter controls

1. Open Generation Defaults. Verify that each parameter has one trailing control
   column. Its named mode menu comes before the numeric value, with the slider
   below both. The mode menu must not float in a third column beside the slider.
2. Open Temperature's mode menu. It must name Model default, Custom value, and
   Override client value. Dismiss it without changing the saved value.
   In an isolated profile, select each choice and verify that the numeric field
   and slider enable for Custom value and Override client value, and disable
   for the inherited source. Reopen the menu to verify the selected choice.
   Changing Custom value to Override client value must preserve the value.
3. Open the per-model generation settings and an editable agent's sampling
   settings. Their controls must use the same layout. The inherited choice must
   name its source. Agent settings must not offer Override client value.
4. Compare inherited, custom, forced, and mixed states in an isolated fixture.
   The controls must keep stable widths, reserve the numeric value's space, and
   show the slider's endpoints directly below its track. At the 620-point model
   sheet width, every label and control must remain inside the sheet.

## Voice controls

1. Inspect Voice engine, System voice, Kokoro voice, and Voice clone clip in an
   isolated settings profile. Their explanations must stay beneath their names
   and their controls must use the shared trailing column.
2. With local fixture download states, inspect Kokoro's Download, progress with
   Cancel, and error with Retry controls at the minimum settings width. All
   controls and status text must remain inside the trailing column. Use fixture
   data; do not download a model to check layout.
3. Verify that a long clip name truncates without moving Choose file, Record,
   and Remove outside the column. Leave the user's clip and voice unchanged.

## Compound row accessibility

1. Inspect Model Folders with VoiceOver or the native accessibility tree. The
   folder paths must expose their text. Choose default model folder, Choose
   additional model folder, Reset, and Clear must retain distinct button names.
2. Inspect Kokoro and Voice clone clip in an isolated profile. The voice picker,
   Play voice sample, Choose voice clip, Record, and Remove voice clip controls
   must each expose their own name. The row title must not replace child names.
3. Compare a simple switch or menu row. Its control must still expose the option
   name. Inspect labels without changing saved values or starting playback.
4. Inspect saved model-thinking rows. The effort picker and reset action must
   identify their action and model separately; Reset must not expose only a model ID.
5. Generation Defaults must show one section introduction explaining client
   defaults, model-rule precedence, and application to the next request.
6. In Voice, Wake phrase appears once on the left. Choose a wake phrase must
   appear only as an empty field's placeholder. The field keeps its Wake phrase
   accessibility name and preserves any saved phrase.

## Settings group scope and separators

1. Open LAN Sharing. Its privacy note must appear under the sharing option in
   the label column. It must remain visible before sharing is enabled and remain
   searchable by Privacy. A section introduction describes the whole category;
   the privacy consequence belongs beside the control that enables it.
2. Open Providers. Reset Nearby Macs belongs inside the Nearby Macs card, below
   discovery. It must not appear below Chat Services as a category-wide reset.
   Open its confirmation and verify that only discovery is turned off. Chat
   services, LAN publishing, the sharing name, and shared-model choices are kept.
   Cancel without changing settings. Search for Reset Nearby Macs and verify
   that the action remains associated with its group.
3. Open Generation Defaults. Adjacent parameter rows must have the same subtle
   horizontal separators as other Settings rows. Search for one parameter:
   no divider should remain above or below a single result. Clearing the search
   restores separators without changing parameter values.
