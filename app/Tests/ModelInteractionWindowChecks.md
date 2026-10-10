# Model selection and navigation checks

Use the packaged app with the server stopped. Inspect personal workspaces without
loading models, generating output, editing saved settings, or starting tasks.
Use an isolated fixture profile for model selections and draft changes.

1. Press Command-L from a conversation, a generation page, Models, Agents,
   and Tasks. Check that the model chooser opens in every destination and that
   Escape closes it without changing the selected model.
2. Check available chat, image, video, voice, music, sound, and 3D models.
   Each row must identify its interaction. Search must match the interaction
   as well as the model name. Drafters, embeddings, incomplete downloads, and
   voice-mode-only models must not appear as standalone interactions.
3. In a fixture profile, choose each model type. Chat models must open chat;
   media models must open their matching workspace with that exact preset.
   Voice, Music, and Sound Effects must open their respective audio tabs.
   Decision models must open Decisions. Selection must not generate output.
4. Enter a draft and attach a fixture file in a generation workspace. Choose
   another compatible model in the same modality. Verify the draft and attachment
   remain, the selected model changes, and unsupported inputs remain unavailable.
5. With only a ready image model in a fixture library, launch the main window.
   Choose Model must remain accessible without a chat-model download. A library
   containing only dependencies or unresolved media presets still needs setup.
6. Scroll the sidebar and resize it. Visit chat, media, Models, Agents, Tasks,
   and an existing terminal. The main sidebar must retain its width and scroll
   position. Agents and Tasks add their secondary lists only within the main pane.
7. Click New in the sidebar. A fresh conversation must open directly. Open its
   model control and select a model in the fixture profile; the model must route
   to its supported interaction. Verify Models, Agents, and Tasks remain in the
   sidebar and terminal creation remains available from the Sessions menu.

`WorkspaceSplitViewTests` checks sidebar lifetime. `ModelPaletteTests` and
`ModelInteractionRouteTests` check model eligibility, capability routing, and the
setup gate. Media draft tests cover model changes without inference or disk output.

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
