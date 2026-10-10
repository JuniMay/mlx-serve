# Main window title and toolbar checks

Use the packaged app with the server stopped. Do not rename, branch, delete or
send anything in personal conversations during layout checks.

1. Open an existing conversation. Verify that the native title bar shows its
   subject and that a long title truncates without moving the toolbar actions.
2. Check an agent conversation. A named subject should be the window title;
   an unnamed conversation should use its agent's name.
3. Open the conversation actions menu. Rename must open the existing name
   dialog with the correct value; Cancel must leave it unchanged. Branch must
   be unavailable for an empty conversation or while its turn is running.
4. Switch to Models, Create, Tasks, Agents and an existing terminal. Verify the
   destination title and native toolbar material remain consistent, with no
   conversation actions left over in another destination.
5. Collapse and restore the sidebar. Check traffic lights, sidebar toggle,
   title and action placement at the narrowest supported window width.
6. Inspect sidebar groups and selection. Group collapse, row ordering and
   multi-selection must still behave as before; do not reorder personal data
   during a read-only check.
   The New menu sits above Sessions and opens the existing creation actions.
   Its icon stays visible in light and dark appearances. Models, Agents and
   Tasks appear under Manage. Opening New keeps the current session selected.
   Accessibility exposes New as one control, without repeating its title for
   the icon and chevron.

Use an isolated fixture profile to activate Branch. Verify the new conversation
ends at the latest complete boundary, keeps its settings and leaves the source
unchanged. `ChatWindowPresentationTests` covers title and eligibility rules;
`ChatForkTests` covers the copied transcript and settings.
