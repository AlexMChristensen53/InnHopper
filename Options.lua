-- InnHopper settings page (Interface > AddOns > InnHopper, /ih options).
local ADDON, ns = ...

local backdropTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil
local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata

local panel = CreateFrame("Frame", "InnHopperOptionsPanel", UIParent)
panel.name = "InnHopper"
panel:Hide()

local function DB() return QuickTeleportDB end

-- Layout: fixed header, scrolling body made of framed sections.
local scroll = CreateFrame("ScrollFrame", "InnHopperOptScroll", panel, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -72)
scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 8)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(560, 812)
scroll:SetScrollChild(content)
scroll:SetScript("OnSizeChanged", function(_, w) if w and w > 0 then content:SetWidth(w) end end)

local SECTION_BACKDROP = {
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

-- Creates a framed section at the given offset (top is negative) with a title and divider.
local function Section(title, top, height)
  local f = CreateFrame("Frame", nil, content, backdropTemplate)
  f:SetPoint("TOPLEFT", content, "TOPLEFT", 6, top)
  f:SetPoint("TOPRIGHT", content, "TOPRIGHT", -6, top)
  f:SetHeight(height)
  if f.SetBackdrop then
    f:SetBackdrop(SECTION_BACKDROP)
    f:SetBackdropColor(0, 0, 0, 0.35)
    f:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.8)
  end
  local t = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  t:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -8)
  t:SetText(title)
  local line = f:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(1, 1, 1, 0.12)
  line:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -24)
  line:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -24)
  line:SetHeight(1)
  return f
end

Section("Appearance", 0, 70)
Section("Player list", -80, 104)
Section("Whisper message", -194, 256)
Section("Behaviour", -460, 104)
Section("Beacons", -574, 150)
Section("Shortcuts", -734, 66)

local refreshers = {}
local function OnRefresh(fn) table.insert(refreshers, fn) end

local function Label(text, template, x, y, parent)
  local p = parent or content
  local fs = p:CreateFontString(nil, "ARTWORK", template or "GameFontNormal")
  fs:SetPoint("TOPLEFT", p, "TOPLEFT", x, y)
  fs:SetJustifyH("LEFT")
  fs:SetText(text)
  return fs
end

local function Check(name, text, x, y)
  local cb = CreateFrame("CheckButton", name, content, "UICheckButtonTemplate")
  cb:SetSize(24, 24)
  cb:SetPoint("TOPLEFT", content, "TOPLEFT", x, y)
  local t = _G[name .. "Text"]
  if t then t:SetText(text) end
  return cb
end

local function Button(name, text, w, x, y)
  local b = CreateFrame("Button", name, content, "UIPanelButtonTemplate")
  b:SetSize(w, 24)
  b:SetPoint("TOPLEFT", content, "TOPLEFT", x, y)
  b:SetText(text)
  return b
end

------------------------------------------------------------------
-- Heading
------------------------------------------------------------------
local head = Label("InnHopper", "GameFontNormalLarge", 16, -16, panel)
local ver = Label("", "GameFontHighlightSmall", 0, 0, panel)
ver:ClearAllPoints()
ver:SetPoint("BOTTOMLEFT", head, "BOTTOMRIGHT", 8, 1)
local sub = Label("Teleport between inns with the Scroll of Liminal Passage.", "GameFontHighlightSmall", 16, -42, panel)
local headLine = panel:CreateTexture(nil, "ARTWORK")
headLine:SetColorTexture(1, 1, 1, 0.2)
headLine:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -64)
headLine:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -64)
headLine:SetHeight(1)

------------------------------------------------------------------
-- Theme (custom dropdown)
------------------------------------------------------------------
local dd = CreateFrame("Button", "InnHopperThemeDropdown", content, backdropTemplate)
dd:SetSize(220, 24)
dd:SetPoint("TOPLEFT", content, "TOPLEFT", 20, -36)
dd:SetBackdrop({
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
dd:SetBackdropColor(0, 0, 0, 0.8)
dd.text = dd:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
dd.text:SetPoint("LEFT", dd, "LEFT", 10, 0)
dd.arrow = dd:CreateFontString(nil, "ARTWORK", "GameFontNormal")
dd.arrow:SetPoint("RIGHT", dd, "RIGHT", -8, 0)
dd.arrow:SetText("v")
dd:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

local themeNote = Label("", "GameFontHighlightSmall", 250, -41)

local list = CreateFrame("Frame", nil, panel, backdropTemplate)
list:SetFrameStrata("DIALOG")
list:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, 0)
list:SetBackdrop({
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
list:SetBackdropColor(0, 0, 0, 0.95)
list:Hide()

local themeItems = {}
local function UpdateThemeText()
  local T = ns.THEMES[DB().theme] or ns.THEMES.vanilla
  dd.text:SetText(T.name)
  themeNote:SetText(T.id == "vanilla" and "(default)" or "")
  for _, it in ipairs(themeItems) do
    it.mark:SetShown(it.id == T.id)
  end
end

local function PickTheme(id)
  DB().theme = id
  ns.ApplyTheme(id)
  UpdateThemeText()
  list:Hide()
end

do
  local order = ns.THEME_ORDER
  list:SetSize(220, 8 + #order * 22)
  for i, id in ipairs(order) do
    local T = ns.THEMES[id]
    local b = CreateFrame("Button", nil, list)
    b:SetSize(204, 22)
    b:SetPoint("TOPLEFT", list, "TOPLEFT", 8, -4 - (i - 1) * 22)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    b.text = b:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    b.text:SetPoint("LEFT", b, "LEFT", 6, 0)
    b.text:SetText(T.name .. (id == "vanilla" and "  |cff888888(default)|r" or ""))
    b.mark = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    b.mark:SetPoint("RIGHT", b, "RIGHT", -6, 0)
    b.mark:SetText("*")
    b.id = id
    b:SetScript("OnClick", function() PickTheme(id) end)
    themeItems[i] = b
  end
end

dd:SetScript("OnClick", function()
  if list:IsShown() then list:Hide() else list:Show() end
end)
panel:SetScript("OnHide", function()
  list:Hide()
  if ns.MoveBack then ns.MoveBack() end
end)

------------------------------------------------------------------
-- Player list info
------------------------------------------------------------------
Label("The player's name is always shown. Everything comes from the game's /who search.", "GameFontHighlightSmall", 20, -112)

local colDefs = {
  { "level", "Level" },
  { "class", "Class" },
  { "race", "Race" },
  { "guild", "Guild" },
  { "zone", "City / location" },
}
local colChecks = {}
for i, d in ipairs(colDefs) do
  local col = (i - 1) % 3
  local row = math.floor((i - 1) / 3)
  local cb = Check("InnHopperOpt_" .. d[1], d[2], 20 + col * 150, -128 - row * 26)
  cb:SetScript("OnClick", function()
    DB().cols = DB().cols or {}
    DB().cols[d[1]] = cb:GetChecked() and true or false
    if ns.RefreshMain then ns.RefreshMain() end
  end)
  colChecks[d[1]] = cb
end

------------------------------------------------------------------
-- Whisper message
------------------------------------------------------------------
local customCB = Check("InnHopperOpt_custom", "Use my own message", 20, -222)

local box = CreateFrame("EditBox", "InnHopperOptMessage", content, backdropTemplate)
box:SetMultiLine(true)
box:SetAutoFocus(false)
box:SetFontObject(ChatFontNormal)
box:SetSize(440, 64)
box:SetPoint("TOPLEFT", content, "TOPLEFT", 22, -252)
box:SetTextInsets(6, 6, 6, 6)
box:SetMaxLetters(500)
box:SetBackdrop({
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
box:SetBackdropColor(0, 0, 0, 0.6)

local help = Label("Placeholders:  {town}  {zone}  {player}  {flavour1}  {flavour2}  {flavour3}", "GameFontHighlightSmall", 22, -350)
local counter = Label("", "GameFontHighlightSmall", 22, -366)
local preview = Label("", "GameFontHighlightSmall", 22, -386)
preview:SetWidth(440)
preview:SetJustifyV("TOP")
preview:SetHeight(48)

local flavourCB = Check("InnHopperOpt_flavour", "Include flavour text", 250, -222)

local resetBtn = Button("InnHopperOptReset", "Reset to default", 120, 20, -320)

local townBtn = Button("InnHopperOptTown", "Preview town", 170, 146, -320)
local randCB = Check("InnHopperOpt_random", "Random flavour", 322, -319)

function ns.FindTown(name)
  if not name then return nil end
  for _, tbl in pairs({ ns.DEST.Alliance, ns.DEST.Horde, ns.DEST.Neutral }) do
    for i = 1, #tbl do if tbl[i][1] == name then return tbl[i] end end
  end
end

local townList = CreateFrame("Frame", nil, panel, backdropTemplate)
townList:SetFrameStrata("DIALOG")
townList:SetSize(230, 250)
townList:SetPoint("BOTTOMLEFT", townBtn, "TOPLEFT", 0, 2)
townList:SetBackdrop({
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
townList:SetBackdropColor(0, 0, 0, 0.95)
townList:Hide()
local townNames = {}
for _, tbl in pairs({ ns.DEST.Alliance, ns.DEST.Horde, ns.DEST.Neutral }) do
  for i = 1, #tbl do table.insert(townNames, tbl[i][1]) end
end
table.sort(townNames)
local townScroll = CreateFrame("ScrollFrame", "InnHopperTownScroll", townList, "UIPanelScrollFrameTemplate")
townScroll:SetPoint("TOPLEFT", townList, "TOPLEFT", 8, -8)
townScroll:SetPoint("BOTTOMRIGHT", townList, "BOTTOMRIGHT", -28, 8)
local townContent = CreateFrame("Frame", nil, townScroll)
townContent:SetSize(190, #townNames * 20)
townScroll:SetScrollChild(townContent)
local UpdatePreview
for i, name in ipairs(townNames) do
  local b = CreateFrame("Button", nil, townContent)
  b:SetSize(190, 20)
  b:SetPoint("TOPLEFT", townContent, "TOPLEFT", 0, -(i - 1) * 20)
  b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  local t = b:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  t:SetPoint("LEFT", b, "LEFT", 6, 0)
  t:SetText(name)
  b:SetScript("OnClick", function()
    DB().previewTown = name
    townList:Hide()
    UpdatePreview()
  end)
end
townBtn:SetScript("OnClick", function()
  if townList:IsShown() then townList:Hide() else townList:Show() end
end)
panel:HookScript("OnHide", function() townList:Hide() end)

-- Longest message any town can produce with the current text (255 limit).
UpdatePreview = function()
  local db = DB()
  local text = box:GetText() or ""
  local useCustom = db.whisperCustom
  local template = useCustom and text or ns.WHISPER_DEFAULT
  local flav = db.flavour ~= false
  local rand = db.randomFlavour and flav
  local longest, longestDest, longestPick = 0, nil, nil
  local function scan(tbl)
    for i = 1, #tbl do
      for p = (rand and 1 or 0), (rand and 3 or 0) do
        local pk = (p > 0) and p or nil
        local m = ns.BuildWhisper(tbl[i], "Name", template, flav, pk)
        if #m > longest then longest, longestDest, longestPick = #m, tbl[i], pk end
      end
    end
  end
  scan(ns.DEST.Alliance); scan(ns.DEST.Horde); scan(ns.DEST.Neutral)
  -- raw length for the longest town, before automatic shortening
  local raw = 0
  if useCustom then
    local dest = longestDest or ns.DEST.Neutral[1]
    local s = text
    s = string.gsub(s, "{[Tt]own}", function() return dest[1] end)
    s = string.gsub(s, "{[Zz]one}", function() return dest[2] end)
    s = string.gsub(s, "{[Pp]layer}", "Name")
    s = string.gsub(s, "{[Ff]lavou?r(%d?)}", function(n)
      if not flav then return "" end
      return dest[2 + (longestPick or ((n == "") and 1 or tonumber(n)))] or ""
    end)
    raw = #s
  end
  if useCustom and raw > 255 then
    counter:SetText("|cffff5555Too long for some towns (" .. raw .. " / 255).|r InnHopper will shorten it automatically.")
  else
    counter:SetText("Longest possible message: " .. longest .. " / 255 characters")
  end
  local sample = ns.FindTown(db.previewTown) or ns.DEST.Neutral[1]
  townBtn:SetText("Preview town: " .. sample[1])
  preview:SetText("Preview (" .. sample[1] .. (rand and ", one of 3 flavours picked at random" or "") .. "): "
    .. ns.BuildWhisper(sample, "Name", template, flav))
  box:SetAlpha(useCustom and 1 or 0.5)
end

box:SetScript("OnTextChanged", function(_, user)
  local t = box:GetText() or ""
  if string.find(t, "\n") then
    box:SetText((string.gsub(t, "[\r\n]+", " ")))
    return
  end
  if user then DB().whisperText = t end
  UpdatePreview()
end)
box:SetScript("OnEscapePressed", function() box:ClearFocus() end)
box:SetScript("OnEnterPressed", function() box:ClearFocus() end)

customCB:SetScript("OnClick", function()
  DB().whisperCustom = customCB:GetChecked() and true or false
  UpdatePreview()
end)
randCB:SetScript("OnClick", function()
  DB().randomFlavour = randCB:GetChecked() and true or false
  UpdatePreview()
end)
flavourCB:SetScript("OnClick", function()
  DB().flavour = flavourCB:GetChecked() and true or false
  UpdatePreview()
end)
resetBtn:SetScript("OnClick", function()
  DB().whisperText = ns.WHISPER_DEFAULT
  box:SetText(ns.WHISPER_DEFAULT)
  UpdatePreview()
end)

------------------------------------------------------------------
-- Behaviour
------------------------------------------------------------------
local autoCB = Check("InnHopperOpt_auto", "Auto-accept party invites and the teleport pop-up", 20, -490)
autoCB:SetScript("OnClick", function() DB().auto = autoCB:GetChecked() and true or false end)

local zonesCB = Check("InnHopperOpt_zonesFirst", "Zones before towns", 20, -538)
zonesCB:SetScript("OnClick", function()
  DB().zonesFirst = zonesCB:GetChecked() and true or false
  if ns.RefreshMain then ns.RefreshMain() end
end)

local miniCB = Check("InnHopperOpt_minimap", "Show minimap button", 20, -514)
miniCB:SetScript("OnClick", function()
  DB().minimap = miniCB:GetChecked() and true or false
  if ns.ApplyMinimap then ns.ApplyMinimap() end
end)

------------------------------------------------------------------
-- Beacon (right of Behaviour)
------------------------------------------------------------------
local beaconNote = Label("Mark yourself as a beacon for other InnHoppers, letting them know they can teleport to you", "GameFontHighlightSmall", 20, -600)
beaconNote:SetWidth(520)
beaconNote:SetJustifyV("TOP")

local beaconChecks = {}
local aiCB, confirmCB, shownCB
local function RefreshBeacon()
  local mode = ns.GetBeaconMode and ns.GetBeaconMode() or "off"
  for id, cb in pairs(beaconChecks) do cb:SetChecked(id == mode) end
  if aiCB then
    aiCB:SetChecked(not ns.GetBeaconAutoInvite or ns.GetBeaconAutoInvite())
    aiCB:SetEnabled(mode ~= "off")
  end
  if confirmCB then confirmCB:SetChecked(ns.GetBeaconConfirm()) end
  if shownCB then shownCB:SetChecked(ns.GetBeaconButtonShown()) end
end

for i, d in ipairs({ { "off", "Off" }, { "on", "On" } }) do
  local cb = Check("InnHopperOpt_beacon" .. d[1], d[2], 20 + (i - 1) * 70, -626)
  cb:SetScript("OnClick", function()
    if ns.RequestBeaconMode then ns.RequestBeaconMode(d[1], RefreshBeacon) end
    RefreshBeacon()
  end)
  beaconChecks[d[1]] = cb
end

aiCB = Check("InnHopperOpt_beaconinvite", "Auto-invite", 20, -650)
aiCB:SetScript("OnClick", function()
  if ns.SetBeaconAutoInvite then ns.SetBeaconAutoInvite(aiCB:GetChecked()) end
  RefreshBeacon()
end)

confirmCB = Check("InnHopperOpt_beaconconfirm", "Confirm before switching on", 20, -674)
confirmCB:SetScript("OnClick", function()
  ns.SetBeaconConfirm(confirmCB:GetChecked())
end)

shownCB = Check("InnHopperOpt_beaconshown", "Show beacon button", 20, -698)
shownCB:SetScript("OnClick", function()
  ns.SetBeaconButtonShown(shownCB:GetChecked())
end)

ns.OnBeaconChange(RefreshBeacon)

local openBtn = Button("InnHopperOptOpen", "Open InnHopper", 130, 20, -766)
openBtn:SetScript("OnClick", function()
  if ns.frame and not ns.frame:IsShown() then ns.frame:Show() end
end)

------------------------------------------------------------------
-- Action bar macro (General macros)
------------------------------------------------------------------
local MACRO_NAME = "InnHopper"

local function Say(text)
  DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffInnHopper:|r " .. text)
end

local function FindGeneralMacro()
  local maxAccount = MAX_ACCOUNT_MACROS or 120
  for i = 1, maxAccount do
    local name = GetMacroInfo(i)
    if name == MACRO_NAME then return i end
  end
  return nil
end

local function CreateOpenMacro()
  if InCombatLockdown() then
    Say("|cffff5555You cannot create a macro during combat.|r")
    return
  end
  if FindGeneralMacro() then
    Say("The |cffffff00" .. MACRO_NAME .. "|r macro already exists. Type |cffffff00/macro|r, open the General Macros tab and drag it to your action bar.")
    return
  end
  local numAccount = GetNumMacros()
  if numAccount >= (MAX_ACCOUNT_MACROS or 120) then
    Say("|cffff5555Your General macro list is full.|r Delete one in /macro and try again.")
    return
  end
  -- #showtooltip displays the scroll icon and count on the action bar button
  local scroll = (DB() and DB().scroll) or "Scroll of Liminal Passage"
  local body = "#showtooltip " .. scroll .. "\n/ih"
  local ok = pcall(CreateMacro, MACRO_NAME, "Spell_Arcane_Blink", body, false)
  if not ok or not FindGeneralMacro() then
    ok = pcall(CreateMacro, MACRO_NAME, 134400, body, false) -- question-mark icon fallback
  end
  if FindGeneralMacro() then
    Say("Macro created. Type |cffffff00/macro|r, open the General Macros tab, and drag |cffffff00" .. MACRO_NAME .. "|r to your action bar. Right-click the action bar button to give it a keybind.")
  else
    Say("|cffff5555Could not create the macro.|r You can make one yourself in /macro with the text: #showtooltip Scroll of Liminal Passage, then /ih on the next line")
  end
end

ns.CreateMacro = CreateOpenMacro

local macroBtn = Button("InnHopperOptMacro", "Create macro", 130, 160, -766)
macroBtn:SetScript("OnClick", CreateOpenMacro)

------------------------------------------------------------------
-- Load saved values when the page is shown
------------------------------------------------------------------
local function LoadAll()
  if ns.InitDB then ns.InitDB() end
  local db = DB()
  ver:SetText("v" .. (GetMeta and GetMeta(ADDON, "Version") or "?"))
  UpdateThemeText()
  for key, cb in pairs(colChecks) do cb:SetChecked(db.cols and db.cols[key] and true or false) end
  customCB:SetChecked(db.whisperCustom and true or false)
  flavourCB:SetChecked(db.flavour ~= false)
  randCB:SetChecked(db.randomFlavour and true or false)
  box:SetText(db.whisperText or ns.WHISPER_DEFAULT)
  autoCB:SetChecked(db.auto ~= false)
  miniCB:SetChecked(db.minimap ~= false)
  zonesCB:SetChecked(db.zonesFirst == true)
  RefreshBeacon()
  UpdatePreview()
end
panel:SetScript("OnShow", function(...)
  if ns.MoveAside then ns.MoveAside() end
  LoadAll(...)
end)

-- Canvas page callbacks
panel.OnCommit = function() end
panel.OnDefault = function() end
panel.OnRefresh = function() end

------------------------------------------------------------------
-- Register with the game options window
------------------------------------------------------------------
local category
if Settings and Settings.RegisterCanvasLayoutCategory then
  category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
  Settings.RegisterAddOnCategory(category)
elseif InterfaceOptions_AddCategory then
  InterfaceOptions_AddCategory(panel)
end

function ns.OpenOptions()
  if category and Settings and Settings.OpenToCategory then
    local id = category.GetID and category:GetID() or category.ID
    Settings.OpenToCategory(id)
  elseif InterfaceOptionsFrame_OpenToCategory then
    InterfaceOptionsFrame_OpenToCategory(panel) -- called twice; the first call can open the wrong page
    InterfaceOptionsFrame_OpenToCategory(panel)
  else
    print("InnHopper: could not find the game's options window.")
  end
end
