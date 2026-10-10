# Generation workspace regression checks

Use the packaged app with the server stopped. Do not download or load a model,
start generation, record audio, or change saved input values. Inspect existing
conditional sections only when the selected model exposes them.

1. Open Image, Video, Audio → Voice, Music and Sound, then 3D from Tools.
   The result occupies the main canvas, with an input dock below it. Model
   configuration and technical parameters start closed. The prompt, selected
   model and Generate action remain visible without scrolling the page.
   The Audio type toolbar menu must visibly name the current family, including
   before the menu opens. Switch between Voice, Music and Sound Effects, verify
   the title and selected checkmark match the displayed workspace, then restore
   the original family. An arrow-only control fails this check even if
   accessibility reports the selected name.
2. Open the model popover, inspect its model names and download state, then
   dismiss without choosing or downloading. Open the attachment popover where
   supported. References, first/last frames, source audio and voice inputs must
   remain reachable; a short popover must not leave a large empty region.
3. Open Generation settings. Verify quality, dimensions, duration, sampler,
   adapters and residency controls that the selected model supports. Close it
   again. Input and result remain present, with no lost draft or reset state.
4. At narrow and wide window sizes, check the dock controls for clipping and
   overlap. Controls wrap when needed. Long prompts scroll inside a bounded
   input area so the result remains visible. Use a fixture profile to verify
   long-input growth, shrinkage and draft retention across model selection.
5. Verify unavailable-model and required-input explanations remain visible
   beside the disabled action. On Music, retain the required-lyrics rule. On
   3D, retain the source-image requirement. Do not generate to test these states.
6. Inspect existing output, progress and errors. File names, players, history,
   save and Finder actions remain reachable. Do not play or delete outputs.
7. Open Choose Model (⌘L). Search available models by name or capability and
   dismiss. In an isolated fixture, select each local model capability and
   verify its matching workspace opens without starting media generation.
   Select another model of the same capability and confirm its draft survives.
8. Verify keyboard focus reaches enabled fields, popovers and the inspector.
   Escape dismisses popovers. Repeat in an isolated light/dark fixture and
   restore the original window size and open panels after inspection.

`GenerationWorkspaceTests` checks the hosted layout and bounded input.
Model-route tests check capability selection; media service and request tests
cover the generation behavior independently of this layout check.
