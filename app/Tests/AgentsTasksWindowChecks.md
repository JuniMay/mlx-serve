# Agents and Tasks window checks

Use the packaged app with the server stopped. Do not start a chat or a task,
preview a voice, change saved settings, or delete any data during layout checks.

1. Switch from a conversation to Agents, then Tasks. Each destination must show
   exactly one native toolbar title, with its actions available separately.
   The main sidebar must retain its width, selection behavior and scroll position
   across these destinations; only the main pane adds a secondary list.
   Open Agents and select a built-in starter. Check that both list sections,
   selection, names, availability text and the chat buttons remain readable.
   Move between starter rows with the arrow keys without activating a chat.
2. Open and dismiss Create New Agent. Verify that starter types and Blank agent
   remain available without creating an agent.
3. Check the name, description, prompt and identity sections. Built-in fields
   must remain read-only, Duplicate available and Delete absent. Expand and
   collapse More options using both its label and disclosure triangle.
4. Narrow the window. Verify that field labels, voice/model menus, prompt
   actions and Start Chat stay inside the detail pane. Do not activate them.
5. Open Tasks. Check the empty state or task list, schedule and autonomy labels.
   Inspect available run history without starting, approving or deleting runs.
   Run, Enabled, Edit and Delete must remain distinct at narrow widths.
6. Open New Task, expand Options, inspect the schedule presets and labeled
   controls, then Cancel. Do not save or create a task. Verify that Escape
   cancels, and that all content is reachable by scrolling and keyboard focus.
7. Repeat the visual checks in light and dark appearance and with long names.
   Use an isolated fixture profile for any editing, submission or run-state
   checks; do not exercise those actions on personal agents or tasks.

These checks cover native selection, focus, disclosure and layout. Existing
agent-resolution and task-scheduler tests cover their underlying behavior.
