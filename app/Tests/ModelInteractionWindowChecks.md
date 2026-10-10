# Model selection and navigation checks

Use the packaged app with the server stopped. Inspect personal workspaces without
loading models, generating output, editing saved settings, or starting tasks.
Use an isolated fixture profile for model selections and draft changes.

1. Open Choose Model from a conversation, a generation page, Models, Agents,
   and Tasks. Check that the chooser opens in every destination and that Escape
   closes it without changing the selected model.
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
7. Verify Models, Agents, Tasks, all generation destinations, and terminal
   creation remain reachable. The session menu's Create submenu and the Tools
   menu must offer Image, Video, Audio & Music, and 3D.

`WorkspaceSplitViewTests` checks sidebar lifetime. `ModelPaletteTests` and
`ModelInteractionRouteTests` check model eligibility, capability routing, and the
setup gate. Media draft tests cover model changes without inference or disk output.
