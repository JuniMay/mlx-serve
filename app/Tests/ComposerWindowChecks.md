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

Plain Chat overrides the independent Tools and MCP choices.

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
6. Tools describes attached-folder search as part of its scope. Turning Tools off
   disables that search even while MCP stays on. Reset Tool Choices appears only
   for saved overrides and explains that it restores Tools & MCP Settings choices.

`ChatToolPreferencesTests` and `ChatModeTogglesTests` cover resolution and
restoration independently of the popover layout.

## Dock control appearance and spacing

Use an idle interaction with an unsent draft. Keep the existing appearance and
accent settings. Send, Generate and Stop use the same neutral glass button style.
Keep visible gaps between attachments, model controls, voice and the action.
The controls must not fuse into an outlined strip or change the dock's surface
when switching between chat and media models. Inspect both full and narrow widths.
An empty draft must still disable submission. Repeat in light and dark fixture
profiles without changing the user's settings. Do not start inference to check
Stop; use a simulated running service.

`ComposerControlsLayoutTests` checks measured gaps and horizontal bounds. Native
glass fill needs a live window; offscreen AppKit captures omit that fill.

## Expanded draft and native surface

1. Open a conversation with no generation running. Record its model and draft.
2. Enter a disposable multiline draft. The native editor grows to its compact
   limit. Its overflow scrolls within the text area using the system-preferred native scrollbar.
3. Once the draft fills several lines, Expand message appears inside the dock.
   Activate it. The same editor fills the conversation pane; the sidebar and
   conversation title remain visible. No sheet or second editor opens.
4. Select text and undo an edit before and after expanding. The draft, selection,
   undo history, attachments, model and tool choices must be preserved.
5. Use Reduce message or Escape to return to the dock. Return and Shift-Return
   retain their chat/media behavior. Clear the disposable draft and restore the
   recorded draft without sending it.
6. Verify that the floating dock uses the system Liquid Glass material, with one
   outer shape and no opaque editor rectangle. Respect Reduce Transparency.
