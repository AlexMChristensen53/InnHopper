-- InnHopper themes: colours, fonts, frame and widget art.
-- "vanilla" and "dark" use game art; the others use Textures/ (tools/make_textures.py).
local ADDON, ns = ...

local TEX = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\"
local WHITE = "Interface\\Buttons\\WHITE8x8"

local function tex(name) return TEX .. name .. ".tga" end

local FRIZ = "Fonts\\FRIZQT__.TTF"
local ARIAL = "Fonts\\ARIALN.TTF"
local MORPH = "Fonts\\MORPHEUS.TTF"
local SKURRI = "Fonts\\SKURRI.TTF"

-- Shared builder for themes with their own artwork.
local function customTheme(o)
  local f = o.family
  return {
    id = o.id,
    name = o.name,
    fonts = o.fonts,
    sizes = o.sizes or { title = 14, text = 11, small = 10 },
    colors = o.colors,
    titleY = -11,
    frame = {
      bg = tex("bg_" .. f), edge = WHITE, tile = false, edgeSize = 2,
      insets = { left = 2, right = 2, top = 2, bottom = 2 },
      bgColor = { 1, 1, 1, 1 }, edgeColor = o.edge,
    },
    decor = {
      header = { tex = tex("header_" .. f), w = 256, h = 32, y = -2, fill = 0.75, maxW = 300 },
      corner = { tex = tex("corner_" .. f), size = 40, ox = 0, oy = 0 },
      emblem = o.emblem,
    },
    editbox = {
      bg = WHITE, edge = WHITE, tile = false, edgeSize = 1,
      insets = { left = 1, right = 1, top = 1, bottom = 1 },
      bgColor = o.editBg, edgeColor = o.editEdge,
    },
    button = { up = tex("btn_" .. f .. "_up"), down = tex("btn_" .. f .. "_down"), hi = tex("btn_" .. f .. "_hi") },
    close = { normal = tex("close_x"), pushed = tex("close_x"), hi = tex("close_x"), tint = o.icon, size = 20, x = -8, y = -8, gearGap = -4 },
    gear = { tex = tex("gear"), tint = o.icon, size = 22 },
    check = { box = tex("check_box"), pushed = tex("check_box"), hi = tex("check_box"), mark = tex("check_mark"), tint = o.icon, size = 22 },
    knob = { tex = tex("knob"), w = 14, h = 28, tint = o.icon, track = o.track },
    rowHi = { tex = WHITE, color = o.rowHi },
  }
end

local THEMES = {}

-- ---------------------------------------------------------------- Vanilla (default)
THEMES.vanilla = {
  id = "vanilla",
  name = "Vanilla (2004)",
  fonts = { title = FRIZ, text = FRIZ },   -- Friz Quadrata
  sizes = { title = 13, text = 11, small = 10 },
  colors = {
    title = { 1, 0.82, 0 }, text = { 1, 1, 1 }, muted = { 0.6, 0.6, 0.6 },
    instr = { 1, 1, 1 }, status = { 1, 0.82, 0 }, hint = { 0.5, 0.5, 0.5 }, btnText = { 1, 0.82, 0 },
  },
  titleY = -3,
  frame = {
    bg = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edge = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
    bgColor = { 1, 1, 1, 1 }, edgeColor = { 1, 1, 1, 1 },
  },
  decor = {
    header = { tex = "Interface\\DialogFrame\\UI-DialogBox-Header", w = 256, h = 64, y = 12, fill = 0.62, maxW = 320, titleOffset = -14 },
  },
  editbox = {
    bg = "Interface\\Tooltips\\UI-Tooltip-Background", edge = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
    bgColor = { 0, 0, 0, 0.6 }, edgeColor = { 1, 1, 1, 1 },
  },
  button = {
    up = "Interface\\Buttons\\UI-Panel-Button-Up",
    down = "Interface\\Buttons\\UI-Panel-Button-Down",
    hi = "Interface\\Buttons\\UI-Panel-Button-Highlight",
    coords = { 0, 0.625, 0, 0.6875 },
  },
  close = {
    normal = "Interface\\Buttons\\UI-Panel-MinimizeButton-Up",
    pushed = "Interface\\Buttons\\UI-Panel-MinimizeButton-Down",
    hi = "Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight",
    size = 32, x = -4, y = -4, gearGap = 8,
  },
  -- settings button: close-button art with a cogwheel over a patch
  gear = {
    tex = tex("gear_gold"), size = 16, btnSize = 40, patchTex = tex("patch_dot"), patchSize = 22,
    patch = { 0.30, 0.0, 0.0 },
    native = {
      normal = "Interface\\Buttons\\UI-Panel-MinimizeButton-Up",
      pushed = "Interface\\Buttons\\UI-Panel-MinimizeButton-Down",
      hi = "Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight",
    },
  },
  check = {
    box = "Interface\\Buttons\\UI-CheckBox-Up", pushed = "Interface\\Buttons\\UI-CheckBox-Down",
    hi = "Interface\\Buttons\\UI-CheckBox-Highlight", mark = "Interface\\Buttons\\UI-CheckBox-Check",
    size = 26,
  },
  knob = { tex = "Interface\\Buttons\\UI-ScrollBar-Knob", w = 18, h = 24, coords = { 0.20, 0.80, 0.125, 0.875 }, track = { 0, 0, 0, 0.35 } },
  rowHi = { tex = "Interface\\QuestFrame\\UI-QuestTitleHighlight", color = { 1, 1, 1, 1 } },
}

-- ---------------------------------------------------------------- Dark
THEMES.dark = {
  id = "dark",
  name = "Dark",
  fonts = { title = FRIZ, text = ARIAL },
  sizes = { title = 14, text = 12, small = 11 },
  colors = {
    title = { 1, 0.82, 0 }, text = { 0.95, 0.95, 0.95 }, muted = { 0.55, 0.55, 0.6 },
    instr = { 0.95, 0.95, 0.95 }, status = { 0.95, 0.95, 0.95 }, hint = { 0.5, 0.5, 0.55 }, btnText = { 0.95, 0.95, 0.95 },
  },
  titleY = -14,
  frame = {
    bg = WHITE, edge = WHITE, tile = false, edgeSize = 2,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
    bgColor = { 0.06, 0.06, 0.07, 0.96 }, edgeColor = { 0.35, 0.35, 0.38, 1 },
  },
  decor = {},
  editbox = {
    bg = WHITE, edge = WHITE, tile = false, edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
    bgColor = { 0.1, 0.1, 0.11, 1 }, edgeColor = { 0.3, 0.3, 0.33, 1 },
  },
  button = { up = tex("btn_dark_up"), down = tex("btn_dark_down"), hi = tex("btn_dark_hi") },
  close = { normal = tex("close_x"), pushed = tex("close_x"), hi = tex("close_x"), tint = { 0.8, 0.8, 0.8 }, size = 20, x = -8, y = -8, gearGap = -4 },
  gear = { tex = tex("gear"), tint = { 0.8, 0.8, 0.8 }, size = 22 },
  check = { box = tex("check_box"), pushed = tex("check_box"), hi = tex("check_box"), mark = tex("check_mark"), tint = { 0.55, 0.55, 0.6 }, markTint = { 1, 1, 1 }, size = 22 },
  knob = { tex = tex("knob"), w = 14, h = 28, tint = { 0.6, 0.6, 0.65 }, track = { 1, 1, 1, 0.06 } },
  rowHi = { tex = WHITE, color = { 1, 0.82, 0, 0.12 } },
}

-- ---------------------------------------------------------------- Alliance
THEMES.alliance = customTheme({
  id = "alliance", name = "Alliance", family = "alliance",
  fonts = { title = FRIZ, text = ARIAL }, sizes = { title = 14, text = 12, small = 11 },
  colors = {
    title = { 0.95, 0.88, 0.65 }, text = { 0.93, 0.95, 1 }, muted = { 0.55, 0.62, 0.75 },
    instr = { 0.8, 0.85, 0.95 }, status = { 0.85, 0.75, 0.5 }, hint = { 0.5, 0.55, 0.65 }, btnText = { 1, 0.95, 0.8 },
  },
  edge = { 0.78, 0.66, 0.35, 1 }, editBg = { 0.04, 0.06, 0.10, 0.9 }, editEdge = { 0.78, 0.66, 0.35, 0.9 },
  icon = { 0.9, 0.8, 0.5 }, track = { 0, 0, 0, 0.4 }, rowHi = { 0.78, 0.66, 0.35, 0.22 },
})

-- ---------------------------------------------------------------- Horde
THEMES.horde = customTheme({
  id = "horde", name = "Horde", family = "horde",
  fonts = { title = FRIZ, text = ARIAL }, sizes = { title = 14, text = 12, small = 11 },
  colors = {
    title = { 0.95, 0.88, 0.65 }, text = { 1, 0.95, 0.94 }, muted = { 0.75, 0.58, 0.58 },
    instr = { 0.95, 0.85, 0.85 }, status = { 0.85, 0.75, 0.5 }, hint = { 0.65, 0.5, 0.5 }, btnText = { 1, 0.95, 0.8 },
  },
  edge = { 0.78, 0.66, 0.35, 1 }, editBg = { 0.10, 0.04, 0.05, 0.9 }, editEdge = { 0.78, 0.66, 0.35, 0.9 },
  icon = { 0.9, 0.8, 0.5 }, track = { 0, 0, 0, 0.4 }, rowHi = { 0.78, 0.66, 0.35, 0.22 },
})

ns.THEMES = THEMES
ns.THEME_ORDER = { "vanilla", "dark", "alliance", "horde" }
