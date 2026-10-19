# AZPC minimap menu (Forever addon 0.2.56)

The minimap icon uses the player's supplied gold/teal AZPC diamond emblem,
encoded as a 32px palette/rectangle image and rendered once with native textures.
No additional files or launcher upgrade are needed. The full wordmark is omitted
so the emblem remains legible at minimap size. No textures are recreated on click
or refresh, and there is no idle OnUpdate handler.

Click either mouse button to open Crafting, Sync Status, Getting Started or Hide
minimap icon. Crafting uses the existing planner and its Auction House requirement;
the menu does not open the Auction House, perform scans or purchase anything.
Escape/close dismisses the menu. It clamps to the screen.

Drag with the left button to move around the minimap. The angle and hidden state
persist in AZPCForeverDB.minimap without altering captured history. Cursor position
respects the minimap's effective UI scale. OnUpdate exists only during dragging.
Dragging suppresses the release click briefly, avoiding accidental menu opens.

- `/azpcf minimap show` restores the icon.
- `/azpcf minimap hide` hides it.
- `/azpcf minimap reset` restores the default angle and shows the icon.
- `/azpcf minimap` toggles visibility.

Existing slash commands continue through their previous handlers. Panel actions
and menu opening are deferred to the user after combat, and there are no capture,
mailbox, cost calculation, recipe or auction transaction changes.
