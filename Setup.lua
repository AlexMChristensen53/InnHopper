-- InnHopper setup guide (first start and /ih setup).
-- Shows the main window with sample players next to a step panel.
local ADDON, ns = ...

local backdropTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil
local function DB() return QuickTeleportDB end

local W, H = 380, 340
local wiz, steps, stepFrames, stepNo = nil, {}, {}, 1

local function Check(parent, text, x, y)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetSize(26, 26)
  cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  cb.label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  cb.label:SetText(text)
  return cb
end

local function Note(parent, text, x, y, w, template)
  local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlightSmall")
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  fs:SetWidth(w or 340)
  fs:SetJustifyH("LEFT")
  fs:SetJustifyV("TOP")
  fs:SetText(text)
  return fs
end

local function Button(parent, text, w, x, y)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, 24)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  b:SetText(text)
  return b
end

------------------------------------------------------------------
-- Steps: title, text, build(parent) returning a loader for saved values.
------------------------------------------------------------------

-- 1. Player list
steps[1] = {
  title = "Player list",
  text = "Choose what is shown next to each player's name in the list. Names are always shown. Watch the InnHopper window change as you tick.",
  build = function(p)
    local defs = {
      { "level", "Level" }, { "class", "Class" }, { "race", "Race" },
      { "guild", "Guild" }, { "zone", "Location (city / zone)" },
    }
    local checks = {}
    for i, d in ipairs(defs) do
      local cb = Check(p, d[2], 4, -(i - 1) * 28)
      cb:SetScript("OnClick", function()
        DB().cols = DB().cols or {}
        DB().cols[d[1]] = cb:GetChecked() and true or false
        if ns.RefreshMain then ns.RefreshMain() end
      end)
      checks[d[1]] = cb
    end
    return function()
      local cols = DB().cols or {}
      for k, cb in pairs(checks) do cb:SetChecked(cols[k] and true or false) end
    end
  end,
}

-- 2. Whisper message
steps[2] = {
  height = 450,
  title = "Whisper message",
  text = "This is what InnHopper whispers to a player to ask for a party invite.",
  build = function(p)
    local defCB = Check(p, "Use the default message", 4, 0)
    local ownCB = Check(p, "Write my own message", 4, -26)

    local box = CreateFrame("EditBox", nil, p, backdropTemplate)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontNormal)
    box:SetSize(336, 58)
    box:SetPoint("TOPLEFT", p, "TOPLEFT", 6, -58)
    box:SetTextInsets(6, 6, 6, 6)
    box:SetMaxLetters(500)
    box:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    box:SetBackdropColor(0, 0, 0, 0.6)
    local help = Note(p, "You can use {town} {zone} {player} {flavour1} {flavour2} {flavour3}", 6, -120, 336, "GameFontDisableSmall")
    help:SetHeight(26)
    local preview = Note(p, "", 6, -140, 336)
    preview:SetHeight(70)

    local more
    local function Update()
      local own = DB().whisperCustom and true or false
      defCB:SetChecked(not own)
      ownCB:SetChecked(own)
      box:SetShown(own)
      help:SetShown(own)
      local template = own and (box:GetText() or "") or ns.WHISPER_DEFAULT
      local town = (ns.FindTown and ns.FindTown("Booty Bay")) or ns.DEST.Neutral[1]
      local msg = ns.BuildWhisper(town, "Name", template, DB().flavour ~= false)
      preview:ClearAllPoints()
      preview:SetPoint("TOPLEFT", p, "TOPLEFT", 6, own and -152 or -66)
      preview:SetText("|cffffd200Example (" .. town[1] .. "):|r " .. msg .. "\n|cff888888" .. #msg .. " / 255 characters|r")
      if more then
        local top = own and 152 or 66
        more:ClearAllPoints()
        more:SetPoint("TOPLEFT", p, "TOPLEFT", 4, -(top + (preview:GetStringHeight() or 40) + 14))
      end
    end
    local function SetOwn(own)
      DB().whisperCustom = own
      if own and (not DB().whisperText or string.gsub(DB().whisperText, "%s", "") == "") then
        DB().whisperText = ns.WHISPER_DEFAULT
      end
      box:SetText(DB().whisperText or ns.WHISPER_DEFAULT)
      Update()
    end
    defCB:SetScript("OnClick", function() SetOwn(false) end)
    ownCB:SetScript("OnClick", function() SetOwn(true) end)
    box:SetScript("OnTextChanged", function(_, user)
      local t = box:GetText() or ""
      if string.find(t, "\n") then box:SetText((string.gsub(t, "[\r\n]+", " "))) return end
      if user then DB().whisperText = t end
      Update()
    end)
    box:SetScript("OnEscapePressed", function() box:ClearFocus() end)
    box:SetScript("OnEnterPressed", function() box:ClearFocus() end)
    more = Note(p, "More whisper options (flavour text, random flavour) are in the settings: /ih options", 4, -246, 340, "GameFontDisableSmall")
    return function()
      box:SetText(DB().whisperText or ns.WHISPER_DEFAULT)
      Update()
    end
  end,
}

-- 3. Auto-accept
steps[3] = {
  title = "Auto-accept",
  text = "InnHopper can accept the party invite from the player you whispered, and the teleport pop-up after you press Teleport, so you don't have to click them yourself.",
  build = function(p)
    local cb = Check(p, "Auto-accept party invites and the teleport pop-up", 4, 0)
    cb:SetScript("OnClick", function()
      DB().auto = cb:GetChecked() and true or false
      if ns.RefreshMain then ns.RefreshMain() end
    end)
    Note(p, "The same tick box is at the bottom of the InnHopper window. It only reacts to players you whispered yourself.", 4, -40, 340)
    return function() cb:SetChecked(DB().auto ~= false) end
  end,
}

-- 4. Beacon mode
steps[4] = {
  height = 350,
  title = "Beacon mode",
  text = "Mark yourself as a beacon for other InnHoppers, letting them know they can teleport to you.",
  build = function(p)
    local defs = {
      { "off", "Off", "Your character never answers requests. Recommended if you are unsure." },
      { "on", "On", "Answers requests whenever you are resting in an inn or a city. Players who ask to join are invited to your party automatically until it is full." },
    }
    local checks = {}
    local function Refresh()
      local mode = ns.GetBeaconMode()
      for id, cb in pairs(checks) do cb:SetChecked(id == mode) end
    end
    ns.OnBeaconChange(Refresh)
    local y = 0
    for _, d in ipairs(defs) do
      local cb = Check(p, d[2], 4, y)
      cb:SetScript("OnClick", function()
        if ns.RequestBeaconMode then ns.RequestBeaconMode(d[1], Refresh) end
        Refresh()
      end)
      checks[d[1]] = cb
      local note = Note(p, d[3], 34, y - 24, 308)
      y = y - 26 - math.ceil(#d[3] / 50) * 12 - 8
    end
    Note(p, "Switching on asks for confirmation. You can also switch with the InnHopper button on your screen: grey is off, coloured is on.", 4, y - 4, 340, "GameFontDisableSmall")
    return Refresh
  end,
}

-- 5. Macro
steps[5] = {
  title = "Action bar macro",
  text = "InnHopper can add a macro to your General macro list that opens the window with /ih and shows how many scrolls you have left. Drag it to your action bar and give it a keybind if you like.",
  build = function(p)
    local icon = p:CreateTexture(nil, "ARTWORK")
    icon:SetSize(40, 40)
    icon:SetPoint("TOPLEFT", p, "TOPLEFT", 6, 0)
    icon:SetTexture("Interface\\Icons\\Spell_Arcane_Blink")
    Note(p, "InnHopper\n|cff888888/ih|r", 54, -6, 200, "GameFontNormal")
    local btn = Button(p, "Create macro", 140, 6, -58)
    btn:SetScript("OnClick", function() if ns.CreateMacro then ns.CreateMacro() end end)
    Note(p, "Not interested? Just press Next. You can create it later in the settings (/ih options).", 4, -96, 340)
    return function() end
  end,
}

-- 6. Theme
steps[6] = {
  title = "Theme",
  text = "Pick a look for the InnHopper window. It changes right away, so you can see it on the left.",
  build = function(p)
    local buttons = {}
    for i, id in ipairs(ns.THEME_ORDER) do
      local T = ns.THEMES[id]
      local b = Button(p, T.name, 200, 6, -(i - 1) * 30)
      b:SetScript("OnClick", function()
        DB().theme = id
        ns.ApplyTheme(id)
        for _, o in ipairs(buttons) do o.mark:SetShown(o.id == id) end
      end)
      b.id = id
      b.mark = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      b.mark:SetPoint("LEFT", b, "RIGHT", 8, 0)
      b.mark:SetText("<- selected")
      buttons[i] = b
    end
    return function()
      local cur = DB().theme or "vanilla"
      for _, o in ipairs(buttons) do o.mark:SetShown(o.id == cur) end
    end
  end,
}

------------------------------------------------------------------
-- The panel
------------------------------------------------------------------
local function Finish(skipped)
  DB().setupDone = true
  if wiz then wiz:Hide() end
  if ns.SetDemo then ns.SetDemo(false) end
  if ns.frame then ns.frame:Hide() end
  C_Timer.After(0.2, function() if ns.SetEscCloses then ns.SetEscCloses(true) end end)
  StaticPopupDialogs["INNHOPPER_SETUP_DONE"] = StaticPopupDialogs["INNHOPPER_SETUP_DONE"] or {
    text = "%s",
    button1 = OKAY,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
  }
  StaticPopup_Show("INNHOPPER_SETUP_DONE",
    "|cffffd200InnHopper " .. (skipped and "setup skipped" or "setup finished") .. "|r\n\n" ..
    "Open the window any time with |cffffff00/ih|r or the minimap button.\n\n" ..
    "Run this guide again with |cffffff00/ih setup|r.\n\n" ..
    "All settings: |cffffff00/ih options|r, or Interface -> AddOns -> InnHopper.")
end

local function ShowStep(n)
  stepNo = n
  local st = steps[n]
  wiz.title:SetText(st.title)
  wiz.count:SetText("Step " .. n .. " of " .. #steps)
  wiz.text:SetText(st.text)
  for i, fr in ipairs(stepFrames) do fr:SetShown(i == n) end
  stepFrames[n].load()
  wiz:SetHeight(st.height or H)
  wiz.back:SetEnabled(n > 1)
  wiz.next:SetText(n == #steps and "Finish" or "Next")
  -- the preview window must be open
  if ns.frame and not ns.frame:IsShown() then
    ns.frame:Show()
    if ns.SetDemo then ns.SetDemo(true) end
  end
end

local function Build()
  wiz = CreateFrame("Frame", "InnHopperSetup", UIParent, backdropTemplate)
  wiz:SetSize(W, H)
  wiz:SetFrameStrata("HIGH")
  wiz:SetToplevel(true)
  wiz:SetClampedToScreen(true)
  wiz:SetMovable(true)
  wiz:EnableMouse(true)
  wiz:RegisterForDrag("LeftButton")
  wiz:SetScript("OnDragStart", function() wiz:StartMoving() end)
  wiz:SetScript("OnDragStop", function() wiz:StopMovingOrSizing() end)
  wiz:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })

  wiz.head = wiz:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  wiz.head:SetPoint("TOPLEFT", wiz, "TOPLEFT", 22, -18)
  wiz.head:SetText("InnHopper setup")
  wiz.count = wiz:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  wiz.count:SetPoint("TOPRIGHT", wiz, "TOPRIGHT", -24, -18)
  wiz.title = wiz:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  wiz.title:SetPoint("TOPLEFT", wiz, "TOPLEFT", 22, -38)
  wiz.text = wiz:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  wiz.text:SetPoint("TOPLEFT", wiz, "TOPLEFT", 22, -66)
  wiz.text:SetWidth(W - 44)
  wiz.text:SetJustifyH("LEFT")
  wiz.text:SetJustifyV("TOP")
  wiz.text:SetHeight(58)

  for i, st in ipairs(steps) do
    local fr = CreateFrame("Frame", nil, wiz)
    fr:SetPoint("TOPLEFT", wiz, "TOPLEFT", 20, -130)
    fr:SetPoint("BOTTOMRIGHT", wiz, "BOTTOMRIGHT", -20, 54)
    fr.load = st.build(fr)
    fr:Hide()
    stepFrames[i] = fr
  end

  wiz.skip = Button(wiz, "Skip setup", 90, 20, -(H - 44))
  wiz.skip:SetScript("OnClick", function() Finish(true) end)
  wiz.back = Button(wiz, "Back", 70, W - 20 - 70 - 6 - 80, -(H - 44))
  wiz.back:SetScript("OnClick", function() if stepNo > 1 then ShowStep(stepNo - 1) end end)
  wiz.next = Button(wiz, "Next", 80, W - 20 - 80, -(H - 44))
  wiz.next:SetScript("OnClick", function()
    if stepNo >= #steps then Finish(false) else ShowStep(stepNo + 1) end
  end)
  for _, b in ipairs({ wiz.skip, wiz.back, wiz.next }) do
    local _, _, _, x = b:GetPoint(1)
    b:ClearAllPoints()
    b:SetPoint("BOTTOMLEFT", wiz, "BOTTOMLEFT", x, 22)
  end
  wiz:Hide()
end

function ns.StartSetup()
  if not wiz then Build() end
  if InCombatLockdown() then
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffInnHopper:|r Setup will start when combat ends. Or type |cffffff00/ih setup|r later.")
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function(self) self:UnregisterAllEvents(); ns.StartSetup() end)
    return
  end
  if ns.CloseOptions then ns.CloseOptions() end
  wiz:ClearAllPoints()
  wiz:SetPoint("TOPLEFT", ns.frame, "TOPRIGHT", 14, 0)
  if ns.SetEscCloses then ns.SetEscCloses(false) end
  ns.frame:Show()
  if ns.SetDemo then ns.SetDemo(true) end
  wiz:Show()
  ShowStep(1)
end
