# Changelog

Format based on [Keep a Changelog](https://keepachangelog.com). Versioning follows [Semantic Versioning](https://semver.org).

## [1.2.0]
### Added
- Beacon overview. The town list shows a Beacons column with the number of available beacons per town. Beacons announce themselves in a hidden channel, immediately when they become available and withdraw when they stop being available; viewers query every 10 seconds while the window is open. Always on; there is no setting for it.
- Sortable town list: click Town, Zone or Beacons above the list. The sort key and direction are saved.
- "Leave the party after teleporting" (on by default) in the settings and the setup guide.
- "What's new" window, shown once per version; `/ih new` reopens it.
- Beacon button: left click opens InnHopper, right click switches beacon mode, Shift + drag moves it.

### Changed
- Town list uses the full window height (13 rows) and the tabs span the full width.
- Warnings are shown lower on the screen in a separate message frame.
- Settings buttons use the button style of the selected theme.
- Beacon options list "On" before "Off". Setup guide texts shortened: explanations under tick boxes, macro and theme intros removed.
- The window is wider to fit the new columns.

### Removed
- Setting "Zones before towns"; the sort is chosen with the column headers.

## [1.1.0]
### Added
- Beacons (opt-in). A player with beacon mode on answers hidden requests from other InnHopper users and invites them to a party automatically until it is full. A beacon answers only while resting in an inn or city (not in a sleeping bag) and while its party has a free slot.
- Beacons tab next to the Players tab. Beacons among the listed players are detected with rate-limited hidden addon messages (up to 50 names per search, short-lived cache) and can be asked for an invite without a whisper.
- Beacon button with the addon icon: grey when beacon mode is off, coloured when on. Left click switches, Shift + left click moves it. Its position is saved.
- Confirmation dialog when beacon mode is switched on, with a "Remember my choice" option and a "Without auto-invite" button.
- Beacon settings: mode, auto-invite, confirmation dialog, button visibility.
- Beacon step in the setup guide.
- Teleport button pulses after a party was joined through a beacon request.
- Setting "Zones before towns" for the town list order.
- `/ih` as the main command, `/ih help` for a command list.

### Changed
- Settings page redesigned: fixed header and scrollable sections.
- Town search matches the start of the sorted field only (town name, or zone name with "Zones before towns"). Zones are sorted alphabetically.
- Setup guide and settings texts use the `/ih` commands.

### Removed
- Informational chat messages (whisper sent, invite accepted, teleport accepted, no invite received).
- Button tooltips and their setting. The beacon button keeps a short usage hint.

## [1.0.0]
### Added
- Searchable list of inn towns for both factions.
- Player lookup per town via `/who`, guild roster and friends list.
- Whisper request for a party invite with a configurable message: placeholders `{town}`, `{zone}`, `{player}`, `{flavour1}`-`{flavour3}`, random flavour option, 255 character check.
- Teleport button using the Scroll of Liminal Passage, with scroll count.
- Optional auto-accept for party invites and summons.
- Selectable player list columns: level, class, race, guild, location. Class-coloured names.
- Themes: Vanilla (default), Dark, Alliance, Horde.
- Settings page (Interface > AddOns > InnHopper, `/tp options`).
- First-start setup guide (`/tp setup`) with live preview.
- Minimap button (right-click: settings, left-drag: reposition) and DataBroker launcher.
- Action bar macro generator with `#showtooltip`.
- Optional button tooltips.
- Slash commands: `/tp`, `/teleport`, `/innhopper`.
