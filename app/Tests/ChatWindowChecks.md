# Main window title and toolbar checks

Use the packaged app with the server stopped. Do not rename, branch, delete or
send anything in personal conversations during layout checks.

1. Open an existing conversation. Verify that the native title bar shows its
   subject and that a long title truncates without moving the toolbar actions.
2. Check an agent conversation. A named subject should be the window title;
   an unnamed conversation should use its agent's name.
3. Click Rename in the title bar. Verify the name dialog has the correct value
   and Cancel leaves it unchanged. Branch Chat belongs to the More menu and
   must be unavailable for an empty conversation or while its turn is running.
4. Switch to Models, Tasks, Agents and an existing terminal. Verify the
   destination title and native toolbar material remain consistent, with no
   conversation actions left over in another destination.
5. Collapse and restore the sidebar. Check traffic lights, sidebar toggle,
   title and action placement at the narrowest supported window width.
6. Inspect sidebar groups and selection. Group collapse, row ordering and
   multi-selection must still behave as before; do not reorder personal data
   during a read-only check.
   New opens one empty interaction directly. New, Models, Agents and Tasks
   form one group above every session section, including agent conversations and
   custom groups. Sessions has no launcher button or menu. A custom group's
   heading uses the same plain text style as Sessions. Its context menu creates
   a chat in the group; it has no competing folder icon or inline plus button.
   Session selection uses a neutral highlight, including while the sidebar
   has keyboard focus. Move between sessions with the keyboard and verify
   that focus and selection remain visible.
7. Verify that model selection appears in the input dock. Open its model list
   and verify that chat and media models identify their capabilities. A media
   selection keeps the same transcript and editor without generating output.
   Choose MiniMax-H3, then choose a chat model from the same control. Both choices
   must retain the conversation and shared draft without changing the page layout.
8. Open Tools & MCP. Verify that Tools, MCP, and Plain Chat are switches and
   remain left aligned. Plain Chat disables both tool switches. Dismiss without
   changing a personal conversation's saved settings.

Use an isolated fixture profile to activate Branch. Verify the new conversation
ends at the latest complete boundary, keeps its settings and leaves the source
unchanged. `ChatWindowPresentationTests` covers title and eligibility rules;
`ChatForkTests` covers the copied transcript and settings.

## Growing session history

1. In an isolated fixture profile, open a sidebar with at least 40 sessions.
   At its top, verify New, Models, Agents and Tasks together, followed by
   the session sections. These rows must remain before the history.
2. Resize the window to its minimum height. Return the sidebar to its top.
   Verify that the management rows are visible without scrolling past sessions.
3. Open the app's menu-bar Code control. Verify that the existing host and
   sandbox terminal choices remain available; do not start a terminal.
4. In the fixture profile, open a custom group's context menu and choose New
   Chat in Group. Verify that it creates one empty chat within the group.

## Direct conversation actions

1. Verify that New, Models, Agents and Tasks form one sidebar group without an
   intervening heading.
2. Open a saved chat. The title bar exposes Rename, Move to Group and Delete
   using standard symbols, with Branch Chat in the overflow menu.
3. Open Rename and cancel. Open Move to Group and inspect existing groups and
   New Group, then dismiss it. Open Delete and cancel its confirmation.
   Each action must target the visible chat and preserve its content on Cancel.
4. In an isolated fixture, create a group from the title bar, move the chat into
   an existing group and back to Sessions. Verify sidebar selection follows the
   same chat and the group assignment persists.
