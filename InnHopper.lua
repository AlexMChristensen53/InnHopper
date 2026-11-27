-- InnHopper: core logic and main window.
-- Themes: Themes.lua. Settings: Options.lua. Setup guide: Setup.lua.

local ADDON, ns = ...

QuickTeleportDB = QuickTeleportDB or {}

local QT = { cache = {}, whispered = {}, requested = {} }
ns.QT = QT
QT.beacons = {}
QT.tab = "beacons"
QT.counts = { beacons = 0, players = 0 }

-- Debug logging; active only when Debug.lua is installed and enabled.
local function Dbg(text)
  if ns.Dbg then ns.Dbg(text) end
end
local ROWS = 10
local ROWS1 = 14      -- rows of the town list, which has no controls below it
local ROWS_MAX = 14
local ROW_H = 20
local TAB_H = 26
local HDR_H = 22
local DEFAULT_SCROLL = "Scroll of Liminal Passage" -- override with /ih scroll <name>
local WHO_COOLDOWN = 3

local WHISPER_BASE = "Hello there, fellow traveller! May I use your kind soul to teleport to you? If so please invite me once you are inside"
local OLD_DEFAULT = WHISPER_BASE .. " the warm and cozy Inn of {town}, {flavour}"
-- Placeholders: {town} {zone} {player} {flavour}
ns.WHISPER_DEFAULT = WHISPER_BASE .. " {flavour}"
local WHISPER_PLAIN = WHISPER_BASE .. " the inn of {town}!" -- fallback without flavour

ns.DEFAULTS = {
  theme = "vanilla",
  cols = { level = true, class = true, race = false, guild = false, zone = false },
  flavour = true,
  whisperCustom = false,
  whisperText = ns.WHISPER_DEFAULT,
  auto = true,
  minimap = true,
}

local DEST = ns.DEST

------------------------------------------------------------------
-- Settings (saved variables)
------------------------------------------------------------------
local function InitDB()
  QuickTeleportDB = QuickTeleportDB or {}
  local db = QuickTeleportDB
  for k, v in pairs(ns.DEFAULTS) do
    if db[k] == nil then
      if type(v) == "table" then
        local copy = {}
        for k2, v2 in pairs(v) do copy[k2] = v2 end
        db[k] = copy
      else
        db[k] = v
      end
    end
  end
  if db.whisperText == OLD_DEFAULT then db.whisperText = ns.WHISPER_DEFAULT end
  if type(db.cols) ~= "table" then db.cols = {} end
  if db.theme == "retail" then db.theme = "dark" end
  if db.theme == "polished" then db.theme = "alliance" end
  -- unknown themes fall back to vanilla below
  if not ns.THEMES[db.theme] then db.theme = "vanilla" end
end
ns.InitDB = InitDB

------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------
local function Msg(text)
  DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffInnHopper:|r " .. text)
end

local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata

local backdropTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil
local SendChat = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage

local function IsWide()
  return false
end

local function Hex(c)
  return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

local function SafeFont(obj, path, size)
  local ok = obj:SetFont(path, size, "")
  if not ok then obj:SetFont(STANDARD_TEXT_FONT, size, "") end
end

-- Town list sorting: "town", "zone" or "beacons". The beacon column exists only with the overview.
local function BeaconColumn()
  return ns.OverviewOn and ns.OverviewOn() or false
end

local function SortKey()
  local db = QuickTeleportDB
  local key = db and db.sortKey
  if key == "beacons" and not BeaconColumn() then key = nil end
  if key == "town" or key == "zone" or key == "beacons" then return key end
  return (db and db.zonesFirst == true) and "zone" or "town"
end

local function SortDesc()
  local db = QuickTeleportDB
  if db and db.sortDesc ~= nil then return db.sortDesc == true end
  return SortKey() == "beacons"
end

local function SetSort(key)
  if SortKey() == key then
    QuickTeleportDB.sortDesc = not SortDesc()
  else
    QuickTeleportDB.sortKey = key
    QuickTeleportDB.sortDesc = key == "beacons"
  end
end

local function GetDestList()
  local faction = UnitFactionGroup("player")
  local list = {}
  local src = DEST[faction]
  if src then
    for i = 1, #src do table.insert(list, src[i]) end
  end
  for i = 1, #DEST.Neutral do table.insert(list, DEST.Neutral[i]) end
  local key, desc = SortKey(), SortDesc()
  table.sort(list, function(a, b)
    if key == "beacons" then
      local ca, cb = ns.OverviewCount(a), ns.OverviewCount(b)
      if ca ~= cb then
        if desc then return ca > cb end
        return ca < cb
      end
    elseif key == "zone" then
      local za, zb = string.lower(a[2]), string.lower(b[2])
      if za ~= zb then
        if desc then return za > zb end
        return za < zb
      end
    else
      local ta, tb = string.lower(a[1]), string.lower(b[1])
      if ta ~= tb then
        if desc then return ta > tb end
        return ta < tb
      end
    end
    return string.lower(a[1]) < string.lower(b[1])
  end)
  return list
end

-- Whether a reported area matches the destination.
-- narrow: area contains the town name. wide: area equals the zone.
local function AreaMatches(area, dest, wide)
  if not area or area == "" then return false end
  local a = string.lower(area)
  if wide then return a == string.lower(dest[2]) end
  return string.find(a, string.lower(dest[1]), 1, true) ~= nil
end

local function CacheKey(dest, wide)
  return string.lower(dest[1]) .. (wide and "|zone" or "|town")
end

-- Known players at `dest`: guild, friends, last /who result.
-- Sample players for the setup guide preview (QT.demo).
local DEMO_PLAYERS = {
  { short = "Aldric",  level = 60, class = "Mage",    classFile = "MAGE",    race = "Human",     guild = "Crimson Order" },
  { short = "Brynja",  level = 58, class = "Priest",  classFile = "PRIEST",  race = "Dwarf",     guild = "Ironbound" },
  { short = "Cedric",  level = 52, class = "Warrior", classFile = "WARRIOR", race = "Gnome" },
  { short = "Dalia",   level = 47, class = "Rogue",   classFile = "ROGUE",   race = "Night Elf", guild = "Moonlit Blades" },
  { short = "Elowen",  level = 33, class = "Druid",   classFile = "DRUID",   race = "Night Elf", guild = "Moonlit Blades" },
}
local function DemoPlayers(dest)
  local out = {}
  for i, d in ipairs(DEMO_PLAYERS) do
    out[i] = { name = d.short, short = d.short, level = d.level, class = d.class, classFile = d.classFile,
               race = d.race, guild = d.guild, area = dest and dest[1] or "" }
  end
  return out
end

local function CollectPlayers(dest, wide)
  if QT.demo then return DemoPlayers(dest) end
  local out, seen = {}, {}
  local me = UnitName("player")

  local function add(fullName, level, class, area, race, guild, classFile)
    if not fullName then return end
    local short = Ambiguate(fullName, "short")
    if short == me then return end
    local key = string.lower(short)
    if seen[key] then return end
    seen[key] = true
    table.insert(out, { name = fullName, short = short, level = level, class = class, area = area,
                        race = race, guild = guild, classFile = classFile })
  end

  if IsInGuild() then
    local myGuild = GetGuildInfo("player")
    local n = GetNumGuildMembers()
    for i = 1, n do
      local name, _, _, level, class, z, _, _, online, _, classFile = GetGuildRosterInfo(i)
      if online and AreaMatches(z, dest, wide) then add(name, level, class, z, nil, myGuild, classFile) end
    end
  end

  if C_FriendList then
    local nf = C_FriendList.GetNumFriends()
    for i = 1, nf do
      local info = C_FriendList.GetFriendInfoByIndex(i)
      if info and info.connected and AreaMatches(info.area, dest, wide) then
        add(info.name, info.level, info.className, info.area)
      end
    end
  end

  local c = QT.cache[CacheKey(dest, wide)]
  if c and (GetTime() - c.time) < 300 then
    for name, d in pairs(c.data) do add(name, d.level, d.class, d.area, d.race, d.guild, d.classFile) end
  end

  table.sort(out, function(a, b) return string.lower(a.short) < string.lower(b.short) end)
  return out
end

------------------------------------------------------------------
-- Whisper text (default or custom, with placeholders)
------------------------------------------------------------------
local function Tidy(s)
  s = string.gsub(s, "%s+", " ")
  s = string.gsub(s, "%s+([,!%.%?])", "%1")
  s = string.gsub(s, ",%s*$", "")
  s = string.gsub(s, "^%s+", "")
  s = string.gsub(s, "%s+$", "")
  return s
end

-- {flavour} = {flavour1}.
local function Fill(template, dest, player, useFlavour, pick)
  local s = template
  s = string.gsub(s, "{[Tt]own}", function() return dest[1] end)
  s = string.gsub(s, "{[Zz]one}", function() return dest[2] end)
  s = string.gsub(s, "{[Pp]layer}", function() return player or "" end)
  s = string.gsub(s, "{[Ff]lavou?r(%d?)}", function(n)
    if not useFlavour then return "" end
    local idx = pick or ((n == "") and 1 or tonumber(n))
    return dest[2 + idx] or dest[3] or ""
  end)
  return Tidy(s)
end

-- template and useFlavour are optional (used by the settings preview).
-- pick (1-3) forces one flavour line for all flavour placeholders; nil = per placeholder, or random if enabled.
function ns.BuildWhisper(dest, player, template, useFlavour, pick)
  local db = QuickTeleportDB
  local custom = db.whisperCustom and db.whisperText and string.gsub(db.whisperText, "%s", "") ~= ""
  if template == nil then template = custom and db.whisperText or ns.WHISPER_DEFAULT end
  if useFlavour == nil then useFlavour = db.flavour ~= false end
  local isDefault = (template == ns.WHISPER_DEFAULT)
  if pick == nil and useFlavour and db.randomFlavour then pick = math.random(3) end
  local msg = Fill(template, dest, player, useFlavour, pick)
  if isDefault and (not useFlavour or string.len(msg) > 255) then
    msg = Fill(WHISPER_PLAIN, dest, player, false)
  elseif string.len(msg) > 255 and useFlavour then
    msg = Fill(template, dest, player, false)
  end
  if string.len(msg) > 255 then msg = string.sub(msg, 1, 255) end
  return msg
end

------------------------------------------------------------------
-- Main window
------------------------------------------------------------------
local stage = 1
local currentDest = nil
local items = {}
local offset = 0
ns.GetState = function() return stage, currentDest and currentDest[1] end

local f = CreateFrame("Frame", "InnHopperFrame", UIParent, backdropTemplate)
ns.frame = f
-- Fixed height: the window keeps its size between the town list and the player list.
f:SetSize(370, ROWS * ROW_H + 192 + TAB_H)
f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
f:SetFrameStrata("HIGH")
f:SetToplevel(true)
f:SetMovable(true)
f:EnableMouse(true)
f:EnableMouseWheel(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", function() f:StartMoving() end)
f:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
f:Hide()
-- Escape handling through UISpecialFrames (no keyboard capture).
local function SetEscCloses(on)
  for i = #UISpecialFrames, 1, -1 do
    if UISpecialFrames[i] == "InnHopperFrame" then table.remove(UISpecialFrames, i) end
  end
  if on then table.insert(UISpecialFrames, "InnHopperFrame") end
end
SetEscCloses(true)

-- Moves the main window to the left edge while the settings are open.
function ns.MoveAside()
  SetEscCloses(false)
  if not QT.savedPoint then
    local p, rel, rp, x, y = f:GetPoint(1)
    QT.savedPoint = { p, rel, rp, x, y }
  end
  f:ClearAllPoints()
  f:SetPoint("LEFT", UIParent, "LEFT", 30, 0)
end
function ns.MoveBack()
  -- Deferred: re-adding during the game's Escape pass would close this window as well.
  if C_Timer and C_Timer.After then
    C_Timer.After(0.2, function() if not QT.savedPoint then SetEscCloses(true) end end)
  else
    SetEscCloses(true)
  end
  local sp = QT.savedPoint
  if not sp then return end
  QT.savedPoint = nil
  f:ClearAllPoints()
  f:SetPoint(sp[1], sp[2] or UIParent, sp[3], sp[4], sp[5])
end

-- Decoration (textures assigned by ApplyTheme)
local header = f:CreateTexture(nil, "ARTWORK", nil, -1)
local emblem = f:CreateTexture(nil, "BORDER")
local corners = {}
do
  local specs = {
    { "TOPLEFT", 3, -3, 0, 1, 0, 1 },
    { "TOPRIGHT", -3, -3, 1, 0, 0, 1 },
    { "BOTTOMLEFT", 3, 3, 0, 1, 1, 0 },
    { "BOTTOMRIGHT", -3, 3, 1, 0, 1, 0 },
  }
  for i, s in ipairs(specs) do
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetPoint(s[1], f, s[1], s[2], s[3])
    t:SetTexCoord(s[4], s[5], s[6], s[7])
    corners[i] = t
  end
end

-- Square header buttons (close, settings).
local function InitSquare(b)
  b.capL = b:CreateTexture(nil, "ARTWORK")
  b.capL:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  b.capL:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
  b.capR = b:CreateTexture(nil, "ARTWORK")
  b.capR:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
  b.capR:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  b.patch = b:CreateTexture(nil, "OVERLAY", nil, 1)   -- covers the X in the native close-button art
  b.patch:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.patch:Hide()
  b.icon = b:CreateTexture(nil, "OVERLAY", nil, 2)
  b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
  b:HookScript("OnMouseDown", function()
    b.icon:SetPoint("CENTER", b, "CENTER", 1, -1)
    if b.bgDown then b.capL:SetTexture(b.bgDown); b.capR:SetTexture(b.bgDown) end
  end)
  b:HookScript("OnMouseUp", function()
    b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
    if b.bgUp then b.capL:SetTexture(b.bgUp); b.capR:SetTexture(b.bgUp) end
  end)
end

local closeBtn = CreateFrame("Button", "InnHopperClose", f)
InitSquare(closeBtn)
closeBtn:SetScript("OnClick", function() f:Hide() end)

local gearBtn = CreateFrame("Button", "InnHopperGear", f)
InitSquare(gearBtn)
gearBtn:Hide() -- unused
gearBtn:SetScript("OnClick", function()
  if ns.OpenOptions then
    ns.MoveAside()
    ns.OpenOptions()
  else
    Msg("Options are not loaded.")
  end
end)

local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")

local instr = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
instr:SetPoint("TOP", f, "TOP", 0, -34)
instr:SetWidth(290)
instr:SetJustifyH("CENTER")

local status = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
status:SetPoint("BOTTOM", f, "BOTTOM", 0, 72)
status:SetWidth(290)
status:SetJustifyH("CENTER")

local eb = CreateFrame("EditBox", "InnHopperSearch", f, backdropTemplate)
eb:SetHeight(24)
eb:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -64)
eb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -20, -64)
eb:SetAutoFocus(false)
eb:SetFontObject(ChatFontNormal)
eb:SetTextInsets(6, 6, 0, 0)

local hint = eb:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
hint:SetPoint("LEFT", eb, "LEFT", 8, 0)

-- Themed push button (art assigned by ApplyTheme).
local themedButtons, themedChecks = {}, {}
local function MakeButton(name, w, h, text, template)
  local b = CreateFrame("Button", name, f, template)
  b:SetSize(w, h)
  b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.label:SetText(text)
  b:HookScript("OnMouseDown", function() b.label:SetPoint("CENTER", b, "CENTER", 1, -1) end)
  b:HookScript("OnMouseUp", function() b.label:SetPoint("CENTER", b, "CENTER", 0, 0) end)
  table.insert(themedButtons, b)
  return b
end

local function MakeCheck(name, text)
  local cb = CreateFrame("CheckButton", name, f)
  cb.label = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  cb.label:SetText(text)
  table.insert(themedChecks, cb)
  return cb
end

local backBtn = MakeButton("InnHopperBack", 80, 24, "< Back")
backBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 14)

local whoBtn = MakeButton("InnHopperWho", 80, 24, "Refresh")
whoBtn:SetPoint("LEFT", backBtn, "RIGHT", 6, 0)

-- Secure button: item use goes through a macro.
local useBtn = MakeButton("InnHopperUse", 100, 24, "Teleport", "SecureActionButtonTemplate")
useBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 14)
useBtn:RegisterForClicks("AnyUp", "AnyDown")
useBtn:SetAttribute("type", "macro")
ns.useBtn = useBtn


local function IsAuto()
  return QuickTeleportDB.auto ~= false
end

local autoCB = MakeCheck("InnHopperAuto", "Auto-accept")
autoCB:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 42)
autoCB:SetScript("OnClick", function()
  QuickTeleportDB.auto = autoCB:GetChecked() and true or false
end)
local function ShortLower(name)
  return string.lower(Ambiguate(name or "", "short"))
end

-- Party members are targeted by unit id; "/target Name" only works for nearby players.
local function FindPartyUnit()
  local n = GetNumSubgroupMembers()
  if QT.lastTarget then
    local want = ShortLower(QT.lastTarget)
    for i = 1, n do
      local u = "party" .. i
      if UnitExists(u) and ShortLower(UnitName(u)) == want then return u end
    end
  end
  if n == 1 then return "party1" end
  return nil
end

local function BuildMacro()
  local text = "/use " .. (QuickTeleportDB.scroll or DEFAULT_SCROLL)
  local unit = FindPartyUnit()
  if unit then text = "/target " .. unit .. "\n" .. text end
  return text
end

local function UpdateUseMacro()
  if InCombatLockdown() then return end
  useBtn:SetAttribute("macrotext", (IsInGroup() and not QT.demo) and BuildMacro() or "")
end

-- Warnings appear above the screen centre, below the default error text at the top.
local warnFrame = CreateFrame("MessageFrame", "InnHopperWarning", UIParent)
warnFrame:SetSize(640, 40)
warnFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
warnFrame:SetFrameStrata("DIALOG")
warnFrame:SetInsertMode("TOP")
warnFrame:SetFading(true)
warnFrame:SetTimeVisible(3)
warnFrame:SetFadeDuration(1)
warnFrame:SetFontObject(ErrorFont or GameFontNormalLarge)
warnFrame:EnableMouse(false)

local function Warn(text)
  local now = GetTime()
  if QT.lastWarn and (now - QT.lastWarn) < 0.6 then return end -- click fires on key down and up
  QT.lastWarn = now
  warnFrame:AddMessage(text, 1, 0.1, 0.1, 1)
  Msg("|cffff5555" .. text .. "|r")
end

-- Runs before the secure macro; blocks the use if teleporting is not possible.
useBtn:HookScript("PreClick", function()
  if InCombatLockdown() then return end
  if not IsInGroup() then
    useBtn:SetAttribute("macrotext", "")
    Warn("You are not in a party yet - ask a player for an invite first.")
    return
  end
  if not IsResting() then
    useBtn:SetAttribute("macrotext", "")
    Warn("You are currently not within city limits or inside an Inn.")
    return
  end
  local macro = BuildMacro()
  useBtn:SetAttribute("macrotext", macro)
  Dbg("Teleport pressed, macro: " .. string.gsub(macro, "\n", " | "))
  QT.teleportTime = GetTime()
  QT.glowDone = true
end)

-- Marks the Teleport button while the scroll can be used right now by pulsing its highlight.
local glowOn = false

local function SetGlow(on)
  if on == glowOn then return end
  glowOn = on
  local tex = useBtn:GetHighlightTexture()
  if on then
    useBtn:LockHighlight()
    if tex then
      if not tex.pulse then
        local group = tex:CreateAnimationGroup()
        group:SetLooping("BOUNCE")
        local alpha = group:CreateAnimation("Alpha")
        if alpha.SetFromAlpha then
          alpha:SetFromAlpha(1)
          alpha:SetToAlpha(0.2)
        else
          alpha:SetChange(-0.8)
        end
        alpha:SetDuration(0.7)
        tex.pulse = group
      end
      tex.pulse:Play()
    end
  else
    if tex and tex.pulse then tex.pulse:Stop() end
    useBtn:UnlockHighlight()
  end
end

local rows = {}
local Refresh

-- Column headers of the town list; clicking one sorts by that column.
local headers = {}
local function MakeHeader(key, label, x, w, right)
  local b = CreateFrame("Button", nil, f)
  b:SetSize(w, 18)
  b:SetPoint("TOPLEFT", f, "TOPLEFT", x, -92)
  b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  b.text = b:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  b.text:SetPoint(right and "RIGHT" or "LEFT", b, right and "RIGHT" or "LEFT", right and -6 or 0, 0)
  b.key, b.label = key, label
  b:SetScript("OnClick", function()
    SetSort(key)
    offset = 0
    Refresh()
  end)
  b:Hide()
  table.insert(headers, b)
  return b
end
MakeHeader("town", "Town", 24, 138)
MakeHeader("zone", "Zone", 168, 104)
MakeHeader("beacons", "Beacons", 280, 50, true)

local tabBeacons = MakeButton("InnHopperTabBeacons", 162, 22, "Beacons")
tabBeacons:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -92)
tabBeacons:Hide()
tabBeacons:SetScript("OnClick", function()
  QT.tab = "beacons"
  offset = 0
  Refresh()
end)

local tabPlayers = MakeButton("InnHopperTabPlayers", 162, 22, "Players")
tabPlayers:SetPoint("TOPRIGHT", f, "TOPRIGHT", -20, -92)
tabPlayers:Hide()
tabPlayers:SetScript("OnClick", function()
  QT.tab = "players"
  offset = 0
  Refresh()
end)

local sb = CreateFrame("Slider", "InnHopperScroll", f)
sb:SetOrientation("VERTICAL")
sb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -94)
sb:SetSize(16, ROWS * ROW_H)
sb:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
local sbTrack = sb:CreateTexture(nil, "BACKGROUND")
sbTrack:SetAllPoints()
sbTrack:SetColorTexture(0, 0, 0, 0.35)
sb:SetMinMaxValues(0, 0)
sb:SetValueStep(1)
if sb.SetObeyStepOnDrag then sb:SetObeyStepOnDrag(true) end
sb:SetValue(0)
sb:Hide()
sb:SetScript("OnValueChanged", function(_, v)
  if QT.sbBusy then return end
  local nv = math.floor(v + 0.5)
  if nv ~= offset then
    offset = nv
    Refresh()
  end
end)

------------------------------------------------------------------
-- Theme
------------------------------------------------------------------
local function Tint(tex, c)
  if not tex then return end
  if c then tex:SetVertexColor(c[1], c[2], c[3], c[4] or 1) else tex:SetVertexColor(1, 1, 1, 1) end
end

local function SetCoords(tex, coords)
  if not tex then return end
  if coords then tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4]) else tex:SetTexCoord(0, 1, 0, 1) end
end

local function StyleIconButton(b, set, tint, size, anchorFn)
  b:SetSize(size, size)
  b:SetNormalTexture(set.normal)
  b:SetPushedTexture(set.pushed or set.normal)
  b:SetHighlightTexture(set.hi or set.normal)
  b:GetNormalTexture():SetAlpha(1)
  b:GetPushedTexture():SetAlpha(1)
  Tint(b:GetNormalTexture(), tint)
  Tint(b:GetPushedTexture(), tint)
  local h = b:GetHighlightTexture()
  if h then h:SetBlendMode("ADD"); Tint(h, tint) end
  b:ClearAllPoints()
  anchorFn()
end

local function DoApplyTheme(T)
  local function try(name, fn)
    local ok, err = pcall(fn)
    if not ok then Msg("|cffff5555Theme problem in " .. name .. " (" .. T.name .. "):|r " .. tostring(err)) end
  end
  local fn, sz, col = T.fonts, T.sizes, T.colors
  try("frame", function()
    local fr = T.frame
    f:SetBackdrop({
      bgFile = fr.bg, edgeFile = fr.edge, tile = fr.tile, tileSize = fr.tileSize,
      edgeSize = fr.edgeSize, insets = fr.insets,
    })
    f:SetBackdropColor(fr.bgColor[1], fr.bgColor[2], fr.bgColor[3], fr.bgColor[4])
    f:SetBackdropBorderColor(fr.edgeColor[1], fr.edgeColor[2], fr.edgeColor[3], fr.edgeColor[4])

  end)
  try("header plate", function()
    local h = T.decor.header
    if h then
      header:SetTexture(h.tex); header:SetSize(h.w, h.h)
      header:ClearAllPoints(); header:SetPoint("TOP", f, "TOP", 0, h.y)
      header:Show()
    else
      header:Hide()
    end
    local c = T.decor.corner
    for _, t in ipairs(corners) do
      if c then t:SetTexture(c.tex); t:SetSize(c.size, c.size); t:Show() else t:Hide() end
    end
    local e = T.decor.emblem
    if e then
      emblem:SetTexture(e.tex); emblem:SetSize(e.size, e.size); emblem:SetAlpha(e.alpha)
      emblem:ClearAllPoints()
      if e.icon then
        emblem:SetDrawLayer("OVERLAY")
        emblem:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -14)
        emblem:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      else
        emblem:SetDrawLayer("BORDER")
        emblem:SetPoint("CENTER", f, "CENTER", 0, -8)
        emblem:SetTexCoord(0, 1, 0, 1)
      end
      emblem:Show()
    else
      emblem:Hide()
    end
  end)

  try("close + settings buttons", function()
    local cl, g = T.close, T.gear
    local function StyleSquare(b, spec, placeFn)
      if spec.bg then
        b:SetSize(spec.btnSize, spec.btnSize)
        b.bgUp, b.bgDown = spec.bg.up, spec.bg.down
        local half = spec.btnSize / 2
        if spec.bg.single then
          -- single square texture
          b.capL:SetTexture(spec.bg.up); b.capL:SetWidth(spec.btnSize); b.capL:SetTexCoord(0, 1, 0, 1)
          b.capL:Show(); b.capR:Hide()
        else
          b.capL:SetTexture(spec.bg.up); b.capL:SetWidth(half); b.capL:SetTexCoord(0, 0.09375, 0, 0.6875)
          b.capR:SetTexture(spec.bg.up); b.capR:SetWidth(half); b.capR:SetTexCoord(0.53125, 0.625, 0, 0.6875)
          b.capL:Show(); b.capR:Show()
        end
        local nt, pt = b:GetNormalTexture(), b:GetPushedTexture()
        if nt then nt:SetAlpha(0) end
        if pt then pt:SetAlpha(0) end
        b:SetHighlightTexture(spec.bg.hi)
        local hl = b:GetHighlightTexture()
        SetCoords(hl, spec.bg.coords)
        if hl then hl:SetBlendMode("ADD") end
        b.patch:Hide()
        b.icon:SetTexture(spec.tex); b.icon:SetSize(spec.size, spec.size); Tint(b.icon, spec.tint); b.icon:Show()
        b:ClearAllPoints(); placeFn()
      elseif spec.native then
        -- native close-button art with an icon over a patch
        b.capL:Hide(); b.capR:Hide()
        b.bgUp, b.bgDown = nil, nil
        StyleIconButton(b, spec.native, nil, spec.btnSize, placeFn)
        local pc = spec.patch
        b.patch:SetTexture(spec.patchTex); b.patch:SetVertexColor(pc[1], pc[2], pc[3], 1)
        b.patch:SetSize(spec.patchSize, spec.patchSize); b.patch:Show()
        b.icon:SetTexture(spec.tex); b.icon:SetSize(spec.size, spec.size); Tint(b.icon, spec.tint); b.icon:Show()
      else
        b.capL:Hide(); b.capR:Hide(); b.icon:Hide(); b.patch:Hide()
        b.bgUp, b.bgDown = nil, nil
        StyleIconButton(b, spec.set, spec.tint, spec.size, placeFn)
      end
    end
    StyleSquare(closeBtn, cl.bg and cl or { set = cl, tint = cl.tint, size = cl.size }, function()
      closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", cl.x, cl.y)
    end)
    StyleSquare(gearBtn, (g.bg or g.native) and g or { set = { normal = g.tex, pushed = g.tex, hi = g.tex }, tint = g.tint, size = g.size }, function()
      if g.x then
        gearBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", g.x, g.y)
      else
        gearBtn:SetPoint("RIGHT", closeBtn, "LEFT", cl.gearGap, 0)
      end
    end)
  end)

  try("fonts + colours", function()
    SafeFont(title, fn.title, sz.title)
    title:SetTextColor(col.title[1], col.title[2], col.title[3])
    title:ClearAllPoints()
      local h = T.decor.header
      if h then
        -- anchored to the header plate
        title:SetPoint("TOP", header, "TOP", 0, h.titleOffset or -(h.h / 2 - 7))
      else
        title:SetPoint("TOP", f, "TOP", 0, T.titleY)
      end
    SafeFont(instr, fn.text, sz.text)
    instr:SetTextColor(col.instr[1], col.instr[2], col.instr[3])
    SafeFont(status, fn.text, sz.small)
    status:SetTextColor(col.status[1], col.status[2], col.status[3])
    SafeFont(hint, fn.text, sz.small)
    hint:SetTextColor(col.hint[1], col.hint[2], col.hint[3])
    SafeFont(eb, fn.text, sz.text)
    eb:SetTextColor(col.text[1], col.text[2], col.text[3])
  end)

  try("search box", function()
    local ed = T.editbox
    eb:SetBackdrop({ bgFile = ed.bg, edgeFile = ed.edge, tile = ed.tile, tileSize = ed.tileSize,
                     edgeSize = ed.edgeSize, insets = ed.insets })
    eb:SetBackdropColor(ed.bgColor[1], ed.bgColor[2], ed.bgColor[3], ed.bgColor[4])
    eb:SetBackdropBorderColor(ed.edgeColor[1], ed.edgeColor[2], ed.edgeColor[3], ed.edgeColor[4])
  end)

  try("push buttons", function()
    local bt = T.button
    for _, b in ipairs(themedButtons) do
      b:SetNormalTexture(bt.up); b:SetPushedTexture(bt.down); b:SetHighlightTexture(bt.hi)
      SetCoords(b:GetNormalTexture(), bt.coords)
      SetCoords(b:GetPushedTexture(), bt.coords)
      local hl = b:GetHighlightTexture()
      SetCoords(hl, bt.coords)
      if hl then hl:SetBlendMode("ADD") end
      SafeFont(b.label, fn.text, sz.text)
      b.label:SetTextColor(col.btnText[1], col.btnText[2], col.btnText[3])
    end
  end)

  try("check boxes", function()
    local ck = T.check
    for _, cb in ipairs(themedChecks) do
      cb:SetSize(ck.size, ck.size)
      cb:SetNormalTexture(ck.box); cb:SetPushedTexture(ck.pushed)
      cb:SetHighlightTexture(ck.hi); cb:SetCheckedTexture(ck.mark)
      Tint(cb:GetNormalTexture(), ck.tint)
      Tint(cb:GetPushedTexture(), ck.tint)
      Tint(cb:GetCheckedTexture(), ck.markTint or ck.tint)
      local hl = cb:GetHighlightTexture()
      if hl then hl:SetBlendMode("ADD") end
      SafeFont(cb.label, fn.text, sz.small)
      cb.label:SetTextColor(col.text[1], col.text[2], col.text[3])
    end
  end)

  try("scroll bar", function()
    local k = T.knob
    sb:SetThumbTexture(k.tex)
    local th = sb:GetThumbTexture()
    th:SetSize(k.w, k.h)
    SetCoords(th, k.coords)
    Tint(th, k.tint)
    sbTrack:SetColorTexture(k.track[1], k.track[2], k.track[3], k.track[4])
  end)

  try("list rows", function()
    local rh = T.rowHi
    for _, row in ipairs(rows) do
      row:SetHighlightTexture(rh.tex)
      local ht = row:GetHighlightTexture()
      Tint(ht, rh.color)
      ht:SetBlendMode(rh.tex == "Interface\\QuestFrame\\UI-QuestTitleHighlight" and "ADD" or "BLEND")
      SafeFont(row.text, fn.text, sz.text)
      row.text:SetTextColor(col.text[1], col.text[2], col.text[3])
      SafeFont(row.zone, fn.text, sz.text)
      SafeFont(row.count, fn.text, sz.text)
    end
  end)

end

function ns.ApplyTheme(id)
  local T = ns.THEMES[id or QuickTeleportDB.theme] or ns.THEMES.vanilla
  QT.theme = T
  local ok, err = pcall(DoApplyTheme, T)
  if not ok then
    Msg("|cffff5555Theme problem (" .. T.name .. "):|r " .. tostring(err))
  end
  if Refresh then Refresh() end
end

------------------------------------------------------------------
-- List contents
------------------------------------------------------------------
-- True when beacons are shown: real (non-demo) lists only.
local function BeaconsOn()
  return not QT.demo and ns.BeaconScan ~= nil
end

-- Matches when the text starts with the query.
local function StartsWith(query, text)
  return string.find(string.lower(text or ""), query, 1, true) == 1
end

local function BuildItems()
  local q = string.lower(eb:GetText() or "")
  items = {}
  if stage == 1 then
    local list = GetDestList()
    local field = SortKey() == "zone" and 2 or 1
    for i = 1, #list do
      local d = list[i]
      if q == "" or StartsWith(q, d[field]) then
        table.insert(items, d)
      end
    end
  else
    local list = CollectPlayers(currentDest, IsWide())
    local beaconsOn = BeaconsOn()
    local nb, np = 0, 0
    for i = 1, #list do
      local p = list[i]
      local isBeacon = beaconsOn and QT.beacons[string.lower(p.short)] and true or false
      if isBeacon then nb = nb + 1 else np = np + 1 end
      local onTab = not beaconsOn or (QT.tab == "beacons") == isBeacon
      if onTab and (q == "" or StartsWith(q, p.short)) then
        table.insert(items, p)
      end
    end
    QT.counts.beacons, QT.counts.players = nb, np
  end
end

local function ClassHex(p)
  local cc = p.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[p.classFile]
  if cc then return Hex({ cc.r, cc.g, cc.b }) end
  return ""
end

local function RowText(p)
  local T = QT.theme or ns.THEMES.vanilla
  local cols = QuickTeleportDB.cols or {}
  local muted = Hex(T.colors.muted)
  local parts = {}
  local lc = {}
  if cols.level and p.level then table.insert(lc, "Lv " .. p.level) end
  if cols.class and p.class then table.insert(lc, p.class) end
  if #lc > 0 then table.insert(parts, table.concat(lc, " ")) end
  if cols.race and p.race and p.race ~= "" then table.insert(parts, p.race) end
  if (cols.zone or IsWide()) and p.area and p.area ~= "" then table.insert(parts, p.area) end
  if cols.guild and p.guild and p.guild ~= "" then table.insert(parts, "<" .. p.guild .. ">") end
  local ch = ClassHex(p)
  local name = (ch ~= "" and (ch .. p.short .. "|r") or p.short)
  local s = name
  if #parts > 0 then s = s .. "  " .. muted .. table.concat(parts, " - ") .. "|r" end
  local key = string.lower(p.short)
  if QT.whispered[key] then
    s = s .. "  |cffffff00(whispered)|r"
  elseif QT.requested[key] then
    s = s .. "  |cffffff00(requested)|r"
  end
  return s
end

local function GetInstruction()
  if QT.demo then return "Click a player's name to ask them for a party invite." end
  if stage == 1 then
    return "Where do you want to go?\nClick a town below, or type to search."
  end
  if IsInGroup() then
    if not IsResting() then
      return "You are in a party! Walk into a city or inn first,\nthen press |cff00ff00Teleport|r"
    end
    return "You are in a party!\nPress |cff00ff00Teleport|r to use your scroll."
  end
  if QT.pending then
    return (QT.pendingRequest and "Request sent!" or "Whisper sent!") .. " Accept their party invite,\nthen press |cff00ff00Teleport|r"
  end
  return "Click a player's name to ask them for a party invite."
end

local function GetStatus(total)
  if stage == 1 then
    if total == 0 then return "No matches." end
    return ""
  end
  local c = QT.cache[CacheKey(currentDest, IsWide())]
  if QT.searching then
    return "Searching for players in " .. currentDest[1] .. "..."
  end
  if BeaconsOn() and QT.tab == "beacons" and (QT.counts.beacons + QT.counts.players) > 0 then
    if total > 0 then
      return total .. " beacon(s) in " .. currentDest[1]
    end
    if QT.beaconScanning then return "Checking for beacons..." end
    if (eb:GetText() or "") ~= "" then return "No beacons match your search." end
    return "No beacons found. Open the Players tab to ask someone directly."
  end
  if total > 0 then
    return total .. " player(s) in " .. currentDest[1]
  end
  if QT.timedOut then
    return "The server is slow to answer. Press Refresh to try again."
  end
  if QT.tooSoon then
    return "You searched a moment ago - wait a few seconds, then press Refresh."
  end
  if c and c.total and c.total > 0 and c.kept == 0 and not IsWide() then
    return "Players were found, but none of them are in " .. currentDest[1] .. " itself right now."
  end
  if c then
    return "Nobody found in " .. currentDest[1] .. " right now. Press Refresh again in a little while."
  end
  return "Searching..."
end

-- Scales the title font and header plate to fit the title.
local function FitTitle()
  local T = QT.theme or ns.THEMES.vanilla
  local h = T.decor.header
  local size = T.sizes.title
  SafeFont(title, T.fonts.title, size)
  local w = title:GetStringWidth() or 0
  local fill = (h and h.fill) or 1
  local maxW = (h and h.maxW) or 190
  local maxText = h and (fill * maxW - 30) or maxW
  if w > maxText and w > 0 then
    size = math.max(8, math.floor(size * maxText / w))
    SafeFont(title, T.fonts.title, size)
    w = title:GetStringWidth() or 0
  end
  if h then header:SetWidth(math.min(maxW, math.max(h.w, (w + 30) / fill))) end
end

-- Teleport button label with the scroll count; the font shrinks to fit.
local function UpdateUseCount()
  local T = QT.theme or ns.THEMES.vanilla
  local name = QuickTeleportDB.scroll or DEFAULT_SCROLL
  local n = 0
  if C_Item and C_Item.GetItemCount then n = C_Item.GetItemCount(name) or 0
  elseif GetItemCount then n = GetItemCount(name) or 0 end
  local label = useBtn.label
  label:SetText("Teleport (" .. n .. ")")
  if not IsInGroup() then QT.glowDone = false end
  SetGlow(QT.pulseReady == true and stage == 2 and IsInGroup() and IsResting() and n > 0 and not QT.glowDone)
  local size = T.sizes.text
  SafeFont(label, T.fonts.text, size)
  local w = label:GetStringWidth() or 0
  if w > 88 then SafeFont(label, T.fonts.text, math.max(8, math.floor(size * 88 / w))) end
end

-- Moves the list down and grows the window while the tab row is visible.
local function LayoutList(shift)
  if QT.layoutShift == shift then return end
  if InCombatLockdown() then return end
  QT.layoutShift = shift
  sb:ClearAllPoints()
  sb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -94 - shift)
  for i = 1, ROWS_MAX do
    rows[i]:ClearAllPoints()
    rows[i]:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -94 - shift - (i - 1) * ROW_H)
  end
end

local function RefreshInner()
  local showTabs = stage == 2 and BeaconsOn()
  local showHeader = stage == 1 and not QT.demo
  LayoutList(showHeader and HDR_H or (showTabs and TAB_H or 0))
  BuildItems()
  local T = QT.theme or ns.THEMES.vanilla
  local total = #items
  local rowsVisible = showHeader and ROWS1 or ROWS
  sb:SetHeight(rowsVisible * ROW_H)
  local maxOffset = total - rowsVisible
  if maxOffset < 0 then maxOffset = 0 end
  if offset > maxOffset then offset = maxOffset end
  if offset < 0 then offset = 0 end

  QT.sbBusy = true
  sb:SetMinMaxValues(0, maxOffset)
  sb:SetValue(offset)
  QT.sbBusy = false
  sb:SetShown(maxOffset > 0)

  local beaconCol = stage == 1 and BeaconColumn()
  for i = 1, ROWS_MAX do
    local it = (i <= rowsVisible) and items[i + offset] or nil
    local row = rows[i]
    if it then
      row.item = it
      if stage == 1 then
        row.text:SetWidth(138)
        row.text:SetText(it[1])
        row.zone:ClearAllPoints()
        row.zone:SetPoint("LEFT", row, "LEFT", 150, 0)
        row.zone:SetWidth(beaconCol and 104 or 160)
        row.zone:SetText(Hex(T.colors.muted) .. it[2] .. "|r")
        row.zone:Show()
        if beaconCol then
          local n = ns.OverviewCount(it)
          row.count:SetText(n > 0 and ("|cffffff00" .. (n > 50 and "50+" or n) .. "|r") or (Hex(T.colors.muted) .. "-|r"))
        end
        row.count:SetShown(beaconCol)
      else
        row.text:SetWidth(306)
        row.text:SetText(RowText(it))
        row.zone:Hide()
        row.count:Hide()
      end
      row:Show()
    else
      row.item = nil
      row:Hide()
    end
  end

  if stage == 1 then
    title:SetText("InnHopper")
    hint:SetText(SortKey() == "zone" and "Search zone..." or "Search town...")
  else
    title:SetText(currentDest[1])
    hint:SetText("Search player name...")
  end
  FitTitle()
  if (eb:GetText() or "") == "" then hint:Show() else hint:Hide() end
  instr:SetText(GetInstruction())
  status:SetText(GetStatus(total))

  local sortKey, sortDesc = SortKey(), SortDesc()
  for _, h in ipairs(headers) do
    local visible = showHeader and (h.key ~= "beacons" or BeaconColumn())
    h:SetShown(visible)
    if visible then
      h.text:SetText(h.label .. (sortKey == h.key and (sortDesc and " v" or " ^") or ""))
    end
  end
  headers[2]:SetWidth(BeaconColumn() and 104 or 160)

  tabBeacons:SetShown(showTabs)
  tabPlayers:SetShown(showTabs)
  if showTabs then
    tabBeacons.label:SetText("Beacons (" .. QT.counts.beacons .. ")")
    tabPlayers.label:SetText("Players (" .. QT.counts.players .. ")")
    if QT.tab == "beacons" then
      tabBeacons:LockHighlight()
      tabPlayers:UnlockHighlight()
    else
      tabPlayers:LockHighlight()
      tabBeacons:UnlockHighlight()
    end
  end

  autoCB:SetShown(stage == 2)
  autoCB:SetChecked(IsAuto())
  if not InCombatLockdown() then
    backBtn:SetShown(stage == 2)
    whoBtn:SetShown(stage == 2)
    useBtn:SetShown(stage == 2)
  end
  useBtn:SetAlpha(IsInGroup() and 1 or 0.45)
  UpdateUseCount()
end
-- Display errors are reported once in chat.
local lastDisplayError
Refresh = function()
  local ok, err = pcall(RefreshInner)
  if not ok and err ~= lastDisplayError then
    lastDisplayError = err
    Msg("|cffff5555Display problem:|r " .. tostring(err))
  end
end
ns.RefreshMain = function() Refresh() end
ns.GetStage = function() return stage end

-- Suppresses the default who window by unregistering other WHO_LIST_UPDATE listeners during a search.
local function SuppressWhoWindows()
  QT.suppressed = QT.suppressed or {}
  if #QT.suppressed > 0 then return end
  local fr = EnumerateFrames()
  while fr do
    if fr ~= QT.evFrame then
      local ok, registered = pcall(fr.IsEventRegistered, fr, "WHO_LIST_UPDATE")
      -- frames returning secret values cannot be tested and are skipped
      if ok and not (issecretvalue and issecretvalue(registered)) and registered then
        fr:UnregisterEvent("WHO_LIST_UPDATE")
        table.insert(QT.suppressed, fr)
        Dbg("window suppressed: " .. (fr:GetName() or "unnamed frame"))
      end
    end
    fr = EnumerateFrames(fr)
  end
end

local function RestoreWhoWindows()
  local list = QT.suppressed
  if not list then return end
  QT.suppressed = {}
  for i = 1, #list do
    list[i]:RegisterEvent("WHO_LIST_UPDATE")
  end
end

-- Sends /who "<town>" and keeps matching players.
-- Must be called directly from a click or key press (hardware event), and SendWho must come first.
local function SendSearch()
  if not currentDest then return end
  local now = GetTime()
  if QT.lastWho and (now - QT.lastWho) < WHO_COOLDOWN then
    QT.tooSoon = true
    return
  end
  QT.tooSoon = false
  QT.timedOut = false
  QT.lastWho = now
  QT.whoDest = currentDest
  QT.whoWide = false
  QT.searching = true
  local q = '"' .. currentDest[1] .. '"'
  local id = (QT.whoId or 0) + 1
  QT.whoId = id
  C_FriendList.SetWhoToUi(true)
  C_FriendList.SendWho(q)
  Dbg("sent /who " .. q)
  -- the result arrives later; the who window is suppressed after sending
  local ok, err = pcall(SuppressWhoWindows)
  if not ok then Dbg("could not silence who window: " .. tostring(err)) end
  local d = currentDest
  C_Timer.After(6, function()
    if QT.whoId == id then RestoreWhoWindows() end
    if QT.searching and QT.whoDest == d then
      QT.searching = false
      QT.timedOut = true
      if f:IsShown() then Refresh() end
    end
  end)
end

local function StartWho()
  if QT.demo then return end
  local ok, err = pcall(SendSearch)
  if not ok then
    QT.searching = false
    Msg("|cffff5555Search problem:|r " .. tostring(err))
  end
  Refresh()
end

-- Queries the players of the current list for beacons. Results arrive one by one.
local function StartBeaconScan()
  if not BeaconsOn() or stage ~= 2 or not currentDest then return end
  local list = CollectPlayers(currentDest, IsWide())
  local names = {}
  for i = 1, #list do names[i] = list[i].name end
  local dest = currentDest
  QT.beaconScanning = true
  local started = ns.BeaconScan(names, function(name, found, auto)
    if found and currentDest == dest then
      QT.beacons[ShortLower(name)] = { auto = auto == true }
      if f:IsShown() then Refresh() end
    end
  end, function(stats)
    if currentDest == dest then
      QT.beaconScanning = false
      QT.beaconSkipped = stats.skipped
      if f:IsShown() then Refresh() end
    end
  end)
  if not started then QT.beaconScanning = false end
end

local function EnterStage2(dest)
  stage = 2
  currentDest = dest
  offset = 0
  QT.beacons = {}
  QT.beaconSkipped = 0
  QT.beaconScanning = false
  QT.tab = "beacons"
  if ns.BeaconScanCancel then ns.BeaconScanCancel() end
  local ok, err = pcall(SendSearch)
  if not ok then
    QT.searching = false
    Msg("|cffff5555Search problem:|r " .. tostring(err))
  end
  eb:SetText("")
  if QT.tooSoon then StartBeaconScan() end
  Refresh()
end

local function EnterStage1()
  if QT.demo then return end
  stage = 1
  currentDest = nil
  offset = 0
  QT.searching = false
  QT.beaconScanning = false
  if ns.BeaconScanCancel then ns.BeaconScanCancel() end
  eb:SetText("")
  Refresh()
end

local function WhisperPlayer(p)
  SendChat(ns.BuildWhisper(currentDest, p.short), "WHISPER", nil, p.name)
  QT.whispered[string.lower(p.short)] = GetTime()
  QT.pending = currentDest
  QT.pendingRequest = false
  QT.awaitBeacon = nil
  QT.lastTarget = p.name
  UpdateUseMacro()
  Refresh()
end

-- Asks a beacon for a party invite with a hidden request instead of a whisper.
local function RequestBeacon(p)
  if not ns.BeaconJoin(p.name) then
    WhisperPlayer(p)
    return
  end
  local key = string.lower(p.short)
  local stamp = GetTime()
  QT.requested[key] = stamp
  QT.pending = currentDest
  QT.pendingRequest = true
  QT.awaitBeacon = stamp
  QT.lastTarget = p.name
  UpdateUseMacro()
  Refresh()
end

local function Activate(it)
  if QT.demo then return end
  if stage == 1 then
    EnterStage2(it)
    return
  end
  local entry = QT.beacons[string.lower(it.short)]
  if type(entry) == "table" and entry.auto then
    RequestBeacon(it)
  else
    WhisperPlayer(it)
  end
end

for i = 1, ROWS_MAX do
  local row = CreateFrame("Button", "InnHopperRow" .. i, f)
  row:SetSize(316, ROW_H)
  row:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -94 - (i - 1) * ROW_H)
  row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  row.text:SetPoint("LEFT", row, "LEFT", 6, 0)
  row.text:SetWidth(306)
  row.text:SetJustifyH("LEFT")
  if row.text.SetWordWrap then row.text:SetWordWrap(false) end
  row.zone = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  row.zone:SetJustifyH("LEFT")
  if row.zone.SetWordWrap then row.zone:SetWordWrap(false) end
  row.zone:Hide()
  row.count = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  row.count:SetPoint("RIGHT", row, "RIGHT", -6, 0)
  row.count:SetWidth(44)
  row.count:SetJustifyH("RIGHT")
  row.count:Hide()
  row:SetScript("OnClick", function()
    if row.item then Activate(row.item) end
  end)
  row:SetScript("OnEnter", function()
    if stage == 2 and row.item then
      local p = row.item
      GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
      GameTooltip:SetText(p.short, 1, 1, 1)
      local line = {}
      if p.level then table.insert(line, "Level " .. p.level) end
      if p.race and p.race ~= "" then table.insert(line, p.race) end
      if p.class then table.insert(line, p.class) end
      if #line > 0 then GameTooltip:AddLine(table.concat(line, " "), 0.8, 0.8, 0.8) end
      if p.area and p.area ~= "" then GameTooltip:AddLine(p.area, 0.6, 0.6, 0.6) end
      if p.guild and p.guild ~= "" then GameTooltip:AddLine("<" .. p.guild .. ">", 0.4, 1, 0.4) end
      if QT.beacons[string.lower(p.short)] then GameTooltip:AddLine("Beacon", 0.4, 0.8, 1) end
      local entry = QT.beacons[string.lower(p.short)]
      if type(entry) == "table" and entry.auto then
        GameTooltip:AddLine("Click to ask this beacon for a party invite", 1, 0.82, 0)
      else
        GameTooltip:AddLine("Click to whisper and ask for a party invite", 1, 0.82, 0)
      end
      GameTooltip:Show()
    end
  end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  rows[i] = row
end

f:SetScript("OnMouseWheel", function(_, delta)
  if delta > 0 then offset = offset - 3 else offset = offset + 3 end
  Refresh()
end)

eb:SetScript("OnTextChanged", function()
  offset = 0
  Refresh()
end)
eb:SetScript("OnEnterPressed", function()
  if items[1] then Activate(items[1]) end
end)
eb:SetScript("OnEscapePressed", function()
  eb:ClearFocus()
  f:Hide()
end)

backBtn:SetScript("OnClick", function() EnterStage1() end)
whoBtn:SetScript("OnClick", function() StartWho(true) end)

f:HookScript("OnHide", function()
  QT.beaconScanning = false
  if ns.BeaconScanCancel then ns.BeaconScanCancel() end
end)

f:SetScript("OnShow", function()
  if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
  stage = 1
  currentDest = nil
  offset = 0
  QT.searching = false
  eb:SetText("")
  Refresh()
end)

function QT.Toggle()
  if f:IsShown() then f:Hide() else f:Show() end
end
ns.Toggle = QT.Toggle

-- Setup guide support: sample data, no game interaction.
function ns.SetDemo(on)
  QT.demo = on and true or false
  offset = 0
  QT.searching = false
  if QT.demo then
    stage = 2
    for _, d in ipairs(DEST.Neutral) do if d[1] == "Booty Bay" then currentDest = d end end
    currentDest = currentDest or DEST.Neutral[1]
  else
    stage = 1
    currentDest = nil
  end
  eb:SetText("")
  UpdateUseMacro()
  Refresh()
end
ns.SetEscCloses = SetEscCloses
ns.ApplyTheme("vanilla") -- replaced at PLAYER_LOGIN

------------------------------------------------------------------
-- Minimap button
------------------------------------------------------------------
local btn = CreateFrame("Button", "InnHopperMinimapButton", Minimap)
btn:SetSize(31, 31)
btn:SetFrameStrata("MEDIUM")
btn:SetFrameLevel(8)
btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
btn:RegisterForDrag("LeftButton")
btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local icon = btn:CreateTexture(nil, "BACKGROUND")
icon:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\Textures\\logo")
icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
icon:SetSize(20, 20)
icon:SetPoint("CENTER", btn, "CENTER", 0, 0)

local border = btn:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetSize(52, 52)
border:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)

local function PlaceButton()
  local a = math.rad(QuickTeleportDB.angle or 200)
  btn:ClearAllPoints()
  btn:SetPoint("CENTER", Minimap, "CENTER", 80 * math.cos(a), 80 * math.sin(a))
end

-- DataBroker launcher. The library is provided by other addons, so registration happens at login.
function ns.RegisterBroker()
  if ns.broker then return end
  local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
  if not LDB then return end
  ns.broker = LDB:NewDataObject("InnHopper", {
    type = "launcher",
    text = "InnHopper",
    icon = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\logo",
    OnClick = function(_, button)
      if button == "RightButton" then
        if ns.OpenOptions then ns.MoveAside(); ns.OpenOptions() end
      else
        QT.Toggle()
      end
    end,
    OnTooltipShow = function(tt)
      tt:AddLine("InnHopper")
      tt:AddLine("Left-click: open InnHopper", 1, 1, 1)
      tt:AddLine("Right-click: settings", 1, 1, 1)
    end,
  })
end

function ns.ApplyMinimap()
  if QuickTeleportDB.minimap == false then btn:Hide() else btn:Show() end
end

btn:SetScript("OnClick", function(_, button)
  if button == "RightButton" then
    if ns.OpenOptions then ns.MoveAside(); ns.OpenOptions() end
  else
    QT.Toggle()
  end
end)
btn:SetScript("OnDragStart", function()
  btn:SetScript("OnUpdate", function()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local s = Minimap:GetEffectiveScale()
    px, py = px / s, py / s
    QuickTeleportDB.angle = math.deg(math.atan2(py - my, px - mx))
    PlaceButton()
  end)
end)
btn:SetScript("OnDragStop", function() btn:SetScript("OnUpdate", nil) end)
btn:SetScript("OnEnter", function()
  GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
  GameTooltip:SetText("InnHopper")
  GameTooltip:AddLine("Left-click: open InnHopper", 1, 1, 1)
  GameTooltip:AddLine("Right-click: settings", 1, 1, 1)
  GameTooltip:AddLine("Hold left-click and drag: move button", 0.7, 0.7, 0.7)
  GameTooltip:Show()
end)
btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
PlaceButton()

------------------------------------------------------------------
-- Slash commands + events
------------------------------------------------------------------
SLASH_INNHOPPER1 = "/ih"
SLASH_INNHOPPER2 = "/innhopper"
-- Legacy aliases kept for macros created by earlier versions.
SLASH_INNHOPPER3 = "/tp"
SLASH_INNHOPPER4 = "/teleport"
SlashCmdList["INNHOPPER"] = function(msg)
  msg = msg or ""
  local name = string.match(msg, "^[Ss][Cc][Rr][Oo][Ll][Ll]%s+(.+)")
  if name then
    QuickTeleportDB.scroll = name
    UpdateUseMacro()
    Msg("Scroll item set to '" .. name .. "'")
  elseif string.lower(msg) == "options" or string.lower(msg) == "config" or string.lower(msg) == "settings" then
    if ns.OpenOptions then ns.MoveAside(); ns.OpenOptions() end
  elseif string.lower(msg) == "setup" then
    if ns.StartSetup then ns.StartSetup() end
  elseif string.lower(msg) == "help" then
    Msg("commands")
    DEFAULT_CHAT_FRAME:AddMessage("  |cffffff00/ih|r  open or close the window")
    DEFAULT_CHAT_FRAME:AddMessage("  |cffffff00/ih options|r  open the settings")
    DEFAULT_CHAT_FRAME:AddMessage("  |cffffff00/ih setup|r  run the setup guide")
    DEFAULT_CHAT_FRAME:AddMessage("  |cffffff00/ih scroll <item>|r  set the scroll item")
    DEFAULT_CHAT_FRAME:AddMessage("  |cffffff00/ih new|r  show what's new")
    DEFAULT_CHAT_FRAME:AddMessage("  |cffffff00/ih version|r  show the version")
    DEFAULT_CHAT_FRAME:AddMessage("  |cffffff00/innhopper|r  works the same as /ih")
  elseif string.lower(msg) == "new" then
    if ns.ShowWhatsNew then ns.ShowWhatsNew(true) end
  elseif string.lower(msg) == "version" then
    Msg("version " .. (GetMeta and GetMeta(ADDON, "Version") or "unknown"))
  elseif ns.Command and ns.Command(string.lower(msg)) then
    -- handled by Debug.lua
  else
    QT.Toggle()
  end
end

local ev = CreateFrame("Frame")
QT.evFrame = ev
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("WHO_LIST_UPDATE")
ev:RegisterEvent("GUILD_ROSTER_UPDATE")
ev:RegisterEvent("FRIENDLIST_UPDATE")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("PLAYER_UPDATE_RESTING")
ev:RegisterEvent("PARTY_INVITE_REQUEST")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:RegisterEvent("CONFIRM_SUMMON")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(_, name, arg1)
  if name == "PLAYER_LOGIN" then
    InitDB()
    ns.ApplyTheme(QuickTeleportDB.theme)
    PlaceButton()
    ns.ApplyMinimap()
    pcall(ns.RegisterBroker)
    UpdateUseMacro()
    if not QuickTeleportDB.setupDone then
      C_Timer.After(3, function() if ns.StartSetup then ns.StartSetup() end end)
    end
  elseif name == "PLAYER_REGEN_ENABLED" then
    UpdateUseMacro()
    if f:IsShown() then Refresh() end
  elseif name == "WHO_LIST_UPDATE" then
    if (QT.searching or QT.timedOut) and QT.whoDest then
      local dest, wide = QT.whoDest, QT.whoWide
      local num = C_FriendList.GetNumWhoResults()
      local data, kept = {}, 0
      for i = 1, num do
        local info = C_FriendList.GetWhoInfo(i)
        local hidden = issecretvalue and (issecretvalue(info and info.area) or issecretvalue(info and info.fullName))
        if info and not hidden and info.fullName and AreaMatches(info.area, dest, wide) then
          data[info.fullName] = { level = info.level, class = info.classStr, area = info.area,
                                  race = info.raceStr, guild = info.fullGuildName, classFile = info.filename }
          kept = kept + 1
        end
      end
      QT.cache[CacheKey(dest, wide)] = { time = GetTime(), data = data, total = num, kept = kept }
      Dbg("who answered: " .. num .. " returned, " .. kept .. " matched the " .. (wide and "zone" or "town"))
      QT.searching = false
      QT.timedOut = false
      local id = QT.whoId
      C_Timer.After(0.3, function()
        if QT.whoId == id then RestoreWhoWindows() end
      end)
      if f:IsShown() then
        StartBeaconScan()
        Refresh()
      end
    end
  elseif name == "GUILD_ROSTER_UPDATE" or name == "FRIENDLIST_UPDATE" then
    if f:IsShown() and stage == 2 then Refresh() end
  elseif name == "GROUP_ROSTER_UPDATE" then
    if IsInGroup() then
      -- The Teleport pulse is reserved for a party joined through a beacon request.
      if QT.awaitBeacon and (GetTime() - QT.awaitBeacon) < 120 and QT.lastTarget then
        local want = ShortLower(QT.lastTarget)
        for i = 1, GetNumSubgroupMembers() do
          local u = "party" .. i
          if UnitExists(u) and ShortLower(UnitName(u) or "") == want then
            QT.pulseReady = true
            QT.awaitBeacon = nil
            break
          end
        end
      end
      QT.pending = nil
    else
      QT.pulseReady = false
    end
    UpdateUseMacro()
    if f:IsShown() then Refresh() end
  elseif name == "BAG_UPDATE_DELAYED" then
    if f:IsShown() then UpdateUseCount() end
  elseif name == "PLAYER_UPDATE_RESTING" then
    if f:IsShown() then Refresh() end
  elseif name == "PARTY_INVITE_REQUEST" then
    Dbg("party invite from " .. tostring(arg1))
    -- Accept only invites from players whispered within the last 5 minutes.
    if IsAuto() and arg1 then
      local k = ShortLower(arg1)
      local t = math.max(QT.whispered[k] or 0, QT.requested[k] or 0)
      if t > 0 and (GetTime() - t) < 300 then
        local accept = AcceptGroup or (C_PartyInfo and C_PartyInfo.AcceptInvite)
        if accept then
          accept()
          StaticPopup_Hide("PARTY_INVITE")
        end
      end
    end
  elseif name == "PLAYER_ENTERING_WORLD" then
    -- Leaves the party once the teleport has landed (opt-in).
    local armed = QT.leaveArmed
    QT.leaveArmed = nil
    if armed and (GetTime() - armed) < 120 and QuickTeleportDB.leaveAfter ~= false then
      C_Timer.After(2, function()
        if IsInGroup() then
          local leave = (C_PartyInfo and C_PartyInfo.LeaveParty) or LeaveParty
          if leave then leave() end
        end
      end)
    end
  elseif name == "CONFIRM_SUMMON" then
    Dbg("summon pop-up received")
    -- Arms leaving the party for the arrival that follows a summon requested with Teleport.
    if QuickTeleportDB.leaveAfter ~= false and QT.teleportTime and (GetTime() - QT.teleportTime) < 120 then
      local getSummoner = (C_SummonInfo and C_SummonInfo.GetSummonConfirmSummoner) or GetSummonConfirmSummoner
      local summoner = getSummoner and getSummoner() or nil
      if not (summoner and QT.lastTarget and ShortLower(summoner) ~= ShortLower(QT.lastTarget)) then
        QT.leaveArmed = GetTime()
      end
    end
    -- Accept only summons following a Teleport press within the last 2 minutes.
    if IsAuto() and QT.teleportTime and (GetTime() - QT.teleportTime) < 120 then
      local getSummoner = (C_SummonInfo and C_SummonInfo.GetSummonConfirmSummoner) or GetSummonConfirmSummoner
      local summoner = getSummoner and getSummoner() or nil
      if summoner and QT.lastTarget and ShortLower(summoner) ~= ShortLower(QT.lastTarget) then
        return
      end
      local confirm = (C_SummonInfo and C_SummonInfo.ConfirmSummon) or ConfirmSummon
      if confirm then
        confirm()
        QT.teleportTime = nil
      end
    end
  end
end)
