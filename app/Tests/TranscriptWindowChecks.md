# Transcript window checks

Use existing conversations with the server stopped. Do not send messages,
change tools, delete messages, or create branches during layout checks.

1. Inspect collapsed Thinking and tool headers with the pointer elsewhere.
   Both use secondary gray text and a chevron beside the label. Hover and press
   each header; its text and chevron darken. Move the pointer away and check
   that the quiet style returns. The whole header button toggles its details.
2. Expand a long thinking block. The header stays in place outside the details
   frame. Content scrolls inside a frame no taller than 240 points. Scrolling
   that frame must not move the conversation while more content remains in that
   direction. Collapse and reopen it; the header's alignment must not shift.
3. Open its Reader. Check the beginning and end, text selection, Close and
   Escape. The reader must fit within the presenting window. Copy returns the
   complete text, including content outside the inline viewport. Opening and
   closing the Reader must leave the disclosure expanded.
4. Repeat with tool arguments/results and a plan in an isolated fixture. Long
   output must remain available. Plan approval buttons stay outside scrolling.
   Use fixture callbacks to check that Reader and process Stop buttons invoke
   only their own actions and leave expansion unchanged. Check both a single
   tool and a group of tools with process controls. Do not approve or stop a
   real run.
5. Compare code blocks, thinking/tool frames, user bubbles and the composer.
   Custom reading surfaces use the shared continuous corner shape. The
   transcript and composer share horizontal boundaries at narrow and wide widths.
6. Inspect paragraphs, nested bullets, numbered lists crossing 9 to 10, quotes,
   tables, inline formulas and adjacent display formulas. Lists align by depth;
   unrelated lists do not shift each other. Tables keep readable row spacing
   and wrap within the reading column. Display formulas have consistent gaps
   and scroll horizontally when wide. Select and copy prose spanning a table.
7. Check the same fixture at every transcript text size and both appearances.
   Compare normal conversation text with expanded Thinking, tool details and
   their Readers: all follow the selected text size. Code and tool identifiers
   may use a monospaced face. Table text also follows the selected size. Restore
   the original appearance and text size after fixture checks.

`TranscriptDetailTypographyTests`, `TranscriptDisclosureTests`,
`TranscriptDetailViewportTests`, `MarkdownPresentationTests`,
`MarkdownBlockBoundaryTests` and `ChatColumnMetricsTests` cover the corresponding
geometry, content and state rules without loading a model.
