# Composer popover checks

Use the packaged app with the server stopped. Leave the selected model and
reasoning level unchanged.

1. Open Model and thinking. Verify compact spacing between the effort label,
   model name and slider, with comfortable padding inside the popover.
2. Open Select model. With a short list, every row must fit without clipping.
   Back and Manage Models must remain outside the scrolling region.
3. With a long list, verify that the list scrolls inside a viewport no taller
   than 300 points and that the selected row is reachable.
4. Use Back, then reopen Select model. Verify that the viewport does not retain
   the first page's shorter height.
5. Verify that long names wrap to two lines and that hovering exposes the full
   name. Checkmarks must identify the current selection.
6. Navigate with arrow keys without activating a row. Dismiss with Escape and
   verify that the selected model remains unchanged.

`ModelPickerScrollViewTests` covers a compact parent proposal with three wrapped
rows and with a long list. These checks cover native popover resizing and focus.

## Conversation tool controls

The reported layout showed Tools, MCP and Plain Chat as three peer switches.
Plain Chat must instead read as an override of the two independent choices.

1. Open Tools & MCP. Plain Chat appears first with a caption describing its
   effect. A divider separates it from Tools and MCP.
2. In a fixture conversation, enable Tools and MCP together. Both remain on.
3. Turn on Plain Chat. Tools and MCP show their effective off state and become
   unavailable. Attached-folder search is also disabled.
4. Turn Plain Chat off. The prior Tools and MCP choices return. Agent restrictions
   still apply; a conversation cannot grant capabilities its agent forbids.
5. Verify the switch labels, help text, settings links and workspace path remain
   readable at the popover's fixed width. Dismiss without changing the user's
   saved choices when inspecting a real conversation.

`ChatToolPreferencesTests` and `ChatModeTogglesTests` cover resolution and
restoration independently of the popover layout.

## Primary action color

Use an idle interaction with an unsent draft. Keep the existing appearance and
accent settings. The enabled Send or Generate button must use the system accent,
with a contrasting arrow. The Stop state must use the same shared button style.
An empty draft must still disable submission. Repeat in light and dark fixture
profiles without changing the user's settings. Do not start inference to check
Stop; use a simulated running service.

The native glass fill needs a live window. Offscreen AppKit bitmap captures do
not include that fill, including for a standard prominent glass button.
