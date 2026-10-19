# First-time setup (Forever addon 0.2.55)

Open `/azpcf setup` for a movable, dismissible Getting Started checklist using the
same native style as Sync Status. New players receive one prompt after login,
deferred during combat. Existing account history suppresses the automatic prompt.
Later, close and Escape persist dismissal per character/realm/region; the command
always reopens it. No launcher or watcher update is required for this release.

Progress reads existing character identity, per-profession recipe records and
confirmed bag/bank observations. Profession and bank steps are optional. Gathering
skills without recipes are excluded; if profession enumeration is unavailable,
the checklist gives instructions instead of claiming all professions are captured.
Use Refresh checklist after opening professions or the banker. No background
history scanning, capture hooks or cost rebuilds are introduced.

Connection status reports only a previously acknowledged upload from this PC.
The first-upload step requires a loaded watcher acknowledgement at or after setup
began, and explicitly tells the user to check their character on My Trades. It
cannot independently verify which character/batch reached the website or whether
a previous credential is currently valid. Status updates load at login/reload.

Reload to Save requires a user click and is blocked in combat. Onboarding writes
only its own SavedVariables metadata; recipes, trades and costs are not modified.
