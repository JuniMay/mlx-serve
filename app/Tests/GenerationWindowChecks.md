# Media interaction regression checks

Use the packaged app with the server stopped. Do not download or load a model,
start generation, record audio, or change personal saved inputs. Use an isolated
fixture profile for draft editing, model switching and simulated progress.

1. Open a conversation with existing messages and a draft. Select MiniMax-H3
   from the dock model list. The transcript, draft, editor and sidebar must remain
   in place. Select a chat model from the same list and verify the same state.
   Repeat for image, speech, music, sound and 3D. There is one interaction page;
   changing capability must not replace it with a result canvas or another dock.
2. Open the attachment and generation-settings popovers. Verify the selected
   model's references, first/last frames, source audio, voice controls, lyrics,
   quality, dimensions, duration, sampler and adapters remain reachable where
   supported. Verify labels, fields and scrolling stay within the popover at each
   supported text size. Close the popovers and verify that the transcript and prompt have
   not moved or reset. Reference inputs remain when returning to the same model
   family. Do not record or download to test a control.
3. In a fixture profile, enter a long prompt, resize the window and reopen the
   popovers. The shared editor must grow to its cap, scroll thereafter and reflow
   without additional typing. Transcript and dock edges remain aligned at narrow
   and wide sizes. Controls must not overlap or clip.
4. For media models, Return inserts a newline and Command-Return invokes the
   enabled Generate action. Test submission with a fake service. Reference
   markers replace the selected text and leave the caret after the marker.
   Escape dismisses the active popover. Test keyboard editing only in a fixture.
5. Verify disabled-action explanations for missing models and required inputs.
   Music retains the required-lyrics rule; 3D retains the source-image rule.
   Selecting a model alone must not start generation or add a transcript entry.
   Dismiss a simulated memory confirmation and verify no prompt is recorded.
6. Start a fake video generation, then select a chat model. Progress and Stop
   remain available in the original conversation. Switch to another conversation;
   it must not show that generation. Complete the fake service and return to the
   original conversation. Its saved transcript must contain the prompt and video.
   Repeat with failure and cancellation. No late service event may add a second
   result after the run has ended.
   While a fixture adapter download is pending, a second conversation must not
   replace the reservation or gain a Stop button for it. Cancel the pending run,
   then finish the fake download. Its callback must not start generation. Confirm
   a speech request with partial dictation records the finalized request text.
7. Inspect existing output attachments. Images, audio, video and 3D files keep
   their previews and Open or Reveal in Finder actions. Missing files show a
   notice. Generated outputs remain referenced after saving and reopening the
   fixture conversation. Do not play or delete personal output files.
8. Verify the generation parameters retain access to earlier output files and
   their output folder. Files created before transcript tracking must remain
   reachable without being assigned to an unrelated conversation.

`MediaInteractionHistoryTests` checks session ownership, delayed start, output
persistence, cancellation and failures with fake phase events.
`InteractionSelectionTests` checks in-page model switching. `GrowingTextEditorTests`
checks native geometry, selection, keyboard handling and width-dependent reflow.
Media service and request tests cover generation behavior independently of layout.
