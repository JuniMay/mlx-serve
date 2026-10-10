# Model selection and navigation checks

Use the packaged app with the server stopped. Inspect personal workspaces without
loading models, generating output, editing saved settings, or starting tasks.
Use an isolated fixture profile for model selections and draft changes.

1. Press Command-L from the interaction page, Models, Agents,
   and Tasks. Check that the model chooser opens in every destination and that
   Escape closes it without changing the selected model.
2. Check available chat, image, video, voice, music, sound, and 3D models.
   Each row must identify its interaction. Search must match the interaction
   as well as the model name. Drafters, embeddings, incomplete downloads, and
   voice-mode-only models must not appear as standalone interactions.
3. In a fixture profile, choose each model type. Chat and media models must keep
   the same transcript and input editor mounted with that exact model selected.
   The page must not change its geometry or animate to another destination.
   Return from MiniMax-H3 to a chat model using the same dock model selector.
   Decision models remain in Models and open Decisions there. They must not appear
   in the interaction dock's model selector. Selection must not generate output.
4. Enter a draft and attach a fixture file. Switch from chat to video, to image,
   and back to chat. Verify that the shared prompt and transcript remain. Open
   each capability's attachments and parameters; its saved inputs must remain
   available, with unsupported controls hidden or disabled.
5. With only a ready image model in a fixture library, launch the main window.
   Choose Model must remain accessible without a chat-model download. A library
   containing only dependencies or unresolved media presets still needs setup.
6. Scroll the sidebar and resize it. Visit interactions, Models, Agents, Tasks,
   and an existing terminal. The main sidebar must retain its width and scroll
   position. Agents and Tasks add their secondary lists only within the main pane.
7. Click New in the sidebar. A fresh conversation must open directly. Open its
   model control and select a model in the fixture profile; the selection must
   keep the interaction page and offer its supported controls. Verify Models,
   Agents and Tasks appear under Manage above the session sections. Terminal
   creation remains available from the app's menu-bar Code control.

`WorkspaceSplitViewTests` checks sidebar lifetime. `ModelPaletteTests` and
`ModelInteractionRouteTests` check model eligibility, capability routing, and the
setup gate. `InteractionSelectionTests` checks in-page model changes. Media draft
tests cover model changes without inference or disk output.

## My Models action alignment

1. Open My Models with chat and media models visible. Compare rows showing Use,
   Selected, and any currently loaded status without activating the buttons.
2. Verify the primary actions share a column. Update, model settings, deletion
   or lock, and Reveal in Finder must each retain their own aligned icon slot.
   An unavailable action leaves an empty slot, with no disabled placeholder icon.
3. Check that Size on Disk aligns with the size values. Resize the window and
   verify that model names truncate before the action cells overlap or move.
4. In a fixture profile with a simulated active transfer, verify progress and
   percentage fit in the primary cell. Cancel occupies the deletion slot, and
   settings and Reveal in Finder remain aligned with completed rows. Do not
   start a real download for this check.

`ModelRowActionsTests` covers download cancellation eligibility, deletion locks,
and confirmation text. Native control placement requires these live-window checks.
