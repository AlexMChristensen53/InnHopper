-- "What's new" window, shown once per version that has an entry below.
-- Edit WHATS_NEW for each release: version, title and lines.
local ADDON, ns = ...

local WHATS_NEW = {
  version = "1.2.0",
  title = "InnHopper 1.2.0",
  lines = {
    "|cffffd200Beacons|r: Mark yourself as a beacon, when you walk into any major city or inn, other people will see you on the \"beacon\" list and know they can teleport to you. Switch it with the InnHopper button on your screen or in the settings.",
    "|cffffd200Beacon overview|r The town list shows how many beacons are available in each town.",
    "|cffffd200Leave the party after teleporting|r (settings, on by default).",
    "|cffffd200Town list|r: click Town, Zone or Beacons above the list to sort it.",
    "|cffffd200Commands|r: /ih opens the window, /ih help lists the rest.",
  },

}

local backdropTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil
local W = 400
local frame

local function Build()
  frame = CreateFrame("Frame", "InnHopperNews", UIParent, backdropTemplate)
  frame:SetWidth(W)
  frame:SetFrameStrata("DIALOG")
  frame:SetToplevel(true)
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function() frame:StartMoving() end)
  frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
  frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)

  local head = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  head:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -18)
  head:SetText("What's new")
  frame.title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -36)

  frame.body = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  frame.body:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -68)
  frame.body:SetWidth(W - 44)
  frame.body:SetJustifyH("LEFT")
  frame.body:SetJustifyV("TOP")
  frame.body:SetSpacing(4)

  local ok = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  ok:SetSize(100, 24)
  ok:SetPoint("BOTTOM", frame, "BOTTOM", 0, 22)
  ok:SetText(OKAY)
  ok:SetScript("OnClick", function() frame:Hide() end)

  tinsert(UISpecialFrames, "InnHopperNews")
  frame:Hide()
end

-- Shows the window. force = true ignores whether it was shown before.
function ns.ShowWhatsNew(force)
  if not frame then Build() end
  frame.title:SetText(WHATS_NEW.title)
  local text = {}
  for _, line in ipairs(WHATS_NEW.lines) do table.insert(text, "- " .. line) end
  frame.body:SetText(table.concat(text, "\n\n"))
  frame:SetHeight(68 + frame.body:GetStringHeight() + 64)
  frame:Show()
  if QuickTeleportDB then QuickTeleportDB.newsSeen = WHATS_NEW.version end
end

local function Due()
  local db = QuickTeleportDB
  if not db then return false end
  if db.newsSeen == WHATS_NEW.version then return false end
  if db.setupDone ~= true then
    -- New installation: the setup guide introduces everything.
    db.newsSeen = WHATS_NEW.version
    return false
  end
  return true
end

local function TryShow()
  if not Due() then return end
  if InCombatLockdown() then return false end
  local setup = _G["InnHopperSetup"]
  if setup and setup:IsShown() then return false end
  ns.ShowWhatsNew()
  return true
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_REGEN_ENABLED")
boot:SetScript("OnEvent", function(self, event)
  if event == "PLAYER_LOGIN" then
    C_Timer.After(6, function()
      if TryShow() == false then self.waiting = true end
    end)
  elseif self.waiting then
    if TryShow() ~= false then self.waiting = nil end
  end
end)
