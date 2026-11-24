# InnHopper development

## Layout
```
InnHopper/               addon folder and repository root
  InnHopper.toc          metadata, version, file list
  Data.lua               town data
  Themes.lua             theme definitions
  InnHopper.lua          core logic and main window
  Options.lua            settings page
  Setup.lua              first-start setup guide
  Debug.lua              developer commands (excluded from releases)
  Textures/              addon art
  .pkgmeta               packager settings
  Developer stuff/       excluded from releases
    release.ps1          local release zip
    CHANGELOG.md
    DEVELOPING.md
    tools/
```

## Workflow
1. Link the addon folder into the game once (Windows):
   `mklink /J "<WoW>\_forever_\Interface\AddOns\InnHopper" "<path to InnHopper>"`
2. Edit, then `/reload`. Changes to the `.toc` or new files require a full restart.
3. `/console scriptErrors 1` displays Lua errors.

## Developer commands (require Debug.lua)
| Command | Function |
|---|---|
| `/innhopper debug` | Toggle debug output |
| `/innhopper state` | Print current state |
| `/innhopper frames` | List frames listening for who results |
| `/innhopper version` | Print version |

## Release
1. Update `## Version:` in `InnHopper.toc` and add an entry to `CHANGELOG.md`.
2. Commit and push.
3. `git tag vX.Y.Z` and `git push origin vX.Y.Z`. The CurseForge packager builds the release from the tag.
4. `release.ps1` builds a local zip without `Developer stuff` and `Debug.lua`.

## Themes and textures
- `Themes.lua` defines all themes. Add a table and register its id in `ns.THEME_ORDER`.
- `tools/make_textures.py` (Python, Pillow) generates the TGA files in `Textures/`.
