# Transcript window checks

Use existing conversations with the server stopped. Do not send messages,
change tools, delete messages, or create branches during layout checks.

1. Inspect collapsed Thinking and tool headers with the pointer elsewhere.
   Both use secondary gray text and a chevron beside the label. Hover and press
   each header; its text and chevron darken. Move the pointer away and check
   that the quiet style returns. The whole header button toggles its details.
2. Expand a long thinking block. The header and actions belong to the same card
   as the content. The card opens without an animated height change. Content
   scrolls inside a frame no taller than 240 points. Scrolling
   that frame must not move the conversation while more content remains in that
   direction. Collapse and reopen it; the header's position in the window must
   not shift. Check while following the newest content and while reading history.
3. Choose Enlarge. The same card grows within the conversation without opening
   a sheet or replacing its content. Its header retains Copy and a Reduce
   control. Check both ends and text selection. Copy returns the complete text,
   including content outside the viewport. Reduce restores the 240-point cap
   and leaves the disclosure expanded. Native scroll indicators appear while
   scrolling and follow the system's scroll-bar preference.
   Also begin with the conversation at the top and a visible thinking header.
   Scroll inside its reader, then choose Enlarge and Reduce. The header and
   outer conversation offset must stay in place; the inner reading position
   must remain unchanged.
4. Repeat with tool arguments/results and a plan in an isolated fixture. Long
   output must remain available. Plan approval buttons stay outside scrolling.
   Use fixture callbacks to check that Enlarge and process Stop buttons invoke
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
   enlarged cards: all follow the selected text size. Code and tool identifiers
   may use a monospaced face. Table text also follows the selected size. Restore
   the original appearance and text size after fixture checks.

`TranscriptDetailTypographyTests`, `TranscriptDisclosureTests`,
`TranscriptDetailViewportTests`, `TranscriptReaderPositionTests`, `MarkdownPresentationTests`,
`MarkdownBlockBoundaryTests` and `ChatColumnMetricsTests` cover the corresponding
geometry, content and state rules without loading a model.

Regression fixture: a completed thinking block with 4,000 lines must keep all
text in one read-only native text view. Opening it must not lay out one giant
SwiftUI Text before presenting the bounded viewport. Verify that the integrated card and its scroll position remain when changing
its size.
