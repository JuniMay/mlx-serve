# Composer popover checks

Use the packaged app with the server stopped. Leave the selected model and
reasoning level unchanged.

1. Open Model and thinking. Verify compact spacing between the effort label,
   model name and slider, with comfortable padding inside the popover.
2. Open Select model. With a short list, every row must fit without clipping.
   Back and Manage Models must remain outside the scrolling region.
3. With a long list, verify that the list scrolls inside a viewport no taller
   than 300 points and that the selected row is reachable.
4. Use Back, then reopen Select model. Verify that the viewport does not retain
   the first page's shorter height.
5. Verify that long names wrap to two lines and that hovering exposes the full
   name. Checkmarks must identify the current selection.
6. Navigate with arrow keys without activating a row. Dismiss with Escape and
   verify that the selected model remains unchanged.

`ModelPickerScrollViewTests` covers a compact parent proposal with three wrapped
rows and with a long list. These checks cover native popover resizing and focus.
