-- Tic-Tac-Toe for WADAMESH.
-- Start screen: play vs CPU, or play vs another player over the #tictactoe channel
-- (the channel must already exist on the device; the app never creates it).
--
-- Wire format, plain text on the channel, one post per message:
--   TTT <hostkey> - <m>        host opens a game; <m> is X's first move (1-9)
--   TTT <hostkey> <joinkey> <moves>
--                              every later post. <moves> is ALL moves so far
--                              (X plays 1st, 3rd.. and O 2nd, 4th..), so a later
--                              post repairs a lost one. The join post is the
--                              joiner's reply move, e.g. "51".
-- Keys are 16 random characters, one per player per game, so many games can share
-- the channel without mixing. They stop crosstalk; they are not anti-cheat, since
-- everything on a channel is readable.
-- A ".n" suffix (e.g. 513.1) is added by Resend so the mesh does not refuse the
-- post as a duplicate.
--
-- Speed: every post is sent the moment the API allows. The firmware enforces a 5 s
-- gap between posts and a budget of 3 in a row, then 1 a minute. That cap is the
-- limit; the open post carries the first move and the join post carries the reply,
-- so a game spends the fewest posts possible.

local ui, sys, mesh, timer = wada.ui, wada.sys, wada.mesh, wada.timer
local C = ui.colors
local clear = ui.clear or function() end
local fl = math.floor
local app = {}

local PAD = 6
local W, H = 240, 240
local CHAN_KEY = "tictactoe"
local FLOOR = 5050          -- ms between posts (API floor is 5 s)
local MAX_OPEN = 4
local ALPHA = "0123456789abcdefghijklmnopqrstuvwxyz"
local LINES = { {1,2,3}, {4,5,6}, {7,8,9}, {1,4,7}, {2,5,8}, {3,6,9}, {1,5,9}, {3,5,7} }

local my_name = nil
local g = nil               -- current game
local opens = {}            -- open games heard: {hkey, sender, chan, first}
local screen = "start"
local status_lbl, cells
local last_sig = nil
local last_send = -100000

local build_start, build_player, build_game

local function th(size) return ui.text_h and ui.text_h(size) or (size + 4) end
local function btn_h() return th(14) + 14 end
local function norm(s) return (tostring(s):lower():gsub("^#", "")) end

local function find_channel()
  local list = mesh.channels and mesh.channels() or {}
  for _, name in ipairs(list) do
    if norm(name) == CHAN_KEY then return name end
  end
end

local function new_key()
  local t = {}
  for i = 1, 16 do
    local k = sys.random(1, #ALPHA)
    t[i] = ALPHA:sub(k, k)
  end
  return table.concat(t)
end

-- ---- game logic --------------------------------------------------------------

local function evaluate(moves)
  local b = {}
  for i, c in ipairs(moves) do
    b[c] = (i % 2 == 1) and "X" or "O"
  end
  local win
  for _, l in ipairs(LINES) do
    local a = b[l[1]]
    if a and a == b[l[2]] and a == b[l[3]] then
      win = { winner = a, line = l }
      break
    end
  end
  return b, win
end

local function is_over()
  local _, win = evaluate(g.moves)
  return (win ~= nil) or #g.moves >= 9
end

-- "519" -> {5,1,9}, or nil if impossible (repeat, or a move after a win)
local function parse_moves(s)
  local mv, seen = {}, {}
  for ch in s:gmatch("%d") do
    local c = tonumber(ch)
    if c < 1 or seen[c] or #mv >= 9 then return nil end
    if #mv > 0 then
      local _, w = evaluate(mv)
      if w then return nil end
    end
    seen[c] = true
    mv[#mv + 1] = c
  end
  return mv
end

local function my_turn()
  local mover = (#g.moves % 2 == 0) and "X" or "O"
  return mover == g.me
end

local function cpu_choose(b, me, opp)
  local function find(mark)
    for _, l in ipairs(LINES) do
      local n, empty = 0, nil
      for _, c in ipairs(l) do
        if b[c] == mark then n = n + 1 elseif not b[c] then empty = c end
      end
      if n == 2 and empty then return empty end
    end
  end
  local m = find(me) or find(opp)
  if m then return m end
  if not b[5] then return 5 end
  local free, corners = {}, {}
  for i = 1, 9 do
    if not b[i] then
      free[#free + 1] = i
      if i == 1 or i == 3 or i == 7 or i == 9 then corners[#corners + 1] = i end
    end
  end
  local pool = #corners > 0 and corners or free
  return pool[sys.random(1, #pool)]
end

-- ---- screen refresh ----------------------------------------------------------

local function ready_at()
  return math.max(g.next_try or 0, last_send + FLOOR)
end

local function status_text()
  local _, win = evaluate(g.moves)
  local net = g.mode == "net"
  local who = g.mode == "cpu" and "CPU" or (g.opp_name or "opponent")
  local t
  if win then
    t = (win.winner == g.me) and "You win!" or (who .. " wins")
  elseif #g.moves >= 9 then
    t = "Draw"
  elseif net and g.taken then
    t = "Game taken by another player"
  elseif net and g.me == "X" and #g.moves == 0 then
    t = "Pick your first move to open the game"
  elseif net and g.me == "X" and not g.jkey then
    t = "Waiting for an opponent to join..."
  elseif my_turn() then
    t = "Your turn (" .. g.me .. ")"
  else
    t = "Waiting for " .. who .. "..."
  end
  if net then
    t = "#" .. g.hkey:sub(1, 6) .. "  " .. t
    if g.err then
      t = t .. "\n" .. g.err
    elseif g.pending then
      local wait = math.ceil((ready_at() - sys.millis()) / 1000)
      if wait > 0 then t = t .. "\nSending in " .. wait .. "s..." else t = t .. "\nSending..." end
    end
  end
  return t
end

local function refresh()
  if screen ~= "game" or not g or not status_lbl or not cells then return end
  local st = status_text()
  local sig = st .. "|" .. table.concat(g.moves)
  if sig == last_sig then return end
  last_sig = sig
  status_lbl:set(st)
  local b = evaluate(g.moves)
  for i = 1, 9 do
    local mark = b[i]
    cells[i]:set(mark or " ")
    cells[i]:color(mark == "X" and C.accent or (mark == "O" and C.good or C.sub))
  end
end

-- ---- sending -----------------------------------------------------------------

local function build_text()
  return "TTT " .. g.hkey .. " " .. (g.jkey or "-") .. " " .. table.concat(g.moves)
         .. (g.sfx and ("." .. g.sfx) or "")
end

local function try_send(now)
  if not g or g.mode ~= "net" or not g.pending or g.taken then return end
  if now < ready_at() then return end
  if not mesh.send then
    g.pending = false
    g.err = "No channel support on this board"
    return
  end
  local ok, err, wait = mesh.send(g.chan, build_text())
  if ok then
    last_send = now
    g.pending, g.sfx, g.err = false, nil, nil
  elseif err == "too fast" then
    g.next_try = now + 200
  elseif err == "rate limited" then
    g.next_try = now + (tonumber(wait) or 60) * 1000
  elseif err == "duplicate" then
    g.resend = (g.resend or 0) + 1
    g.sfx = g.resend
    g.next_try = now
  elseif err == "denied" or err == "permission denied" then
    g.pending = false
    g.err = "Permission denied. Resend asks again"
  else
    g.err = "Not sent: " .. tostring(err)
    g.next_try = now + 15000
  end
  refresh()
end

local function resend()
  if not g or g.mode ~= "net" or g.taken then return end
  if #g.moves == 0 or (g.me == "O" and #g.moves < 2) then return end
  g.resend = (g.resend or 0) + 1
  g.sfx = g.resend
  g.pending = true
  g.next_try = 0
  g.err = nil
  try_send(sys.millis())
  refresh()
end

-- ---- playing -----------------------------------------------------------------

local function play_cell(i)
  if not g or g.taken then return end
  local b = evaluate(g.moves)
  if is_over() or b[i] then return end
  if not my_turn() then sys.toast("Not your turn", 1200) return end
  g.moves[#g.moves + 1] = i
  if g.mode == "net" then
    g.pending = true
    g.next_try = 0
    g.err = nil
    try_send(sys.millis())
  elseif not is_over() then
    local this = g
    timer.after(450, function()
      if g ~= this or is_over() then return end
      local bb = evaluate(g.moves)
      g.moves[#g.moves + 1] = cpu_choose(bb, "O", "X")
      if is_over() then sys.beep() end
      refresh()
    end)
  end
  refresh()
end

local function start_cpu()
  g = { mode = "cpu", me = "X", moves = {} }
  build_game()
end

local function start_host()
  local ch = find_channel()
  if not ch then build_player() return end
  g = { mode = "net", hkey = new_key(), me = "X", chan = ch, moves = {}, pending = false, next_try = 0 }
  build_game()
end

local function join_game(o)
  for i = #opens, 1, -1 do
    if opens[i].hkey == o.hkey then table.remove(opens, i) end
  end
  g = {
    mode = "net", hkey = o.hkey, jkey = new_key(), me = "O", chan = o.chan,
    opp_name = o.sender, moves = { o.first }, pending = false, next_try = 0,
  }
  build_game()
end

-- ---- screens -----------------------------------------------------------------

build_game = function()
  screen = "game"
  last_sig = nil
  clear()
  ui.scroll(false)
  local bh = btn_h()
  local land = W >= H + 100
  local side, bx, by, px, pwid
  if land then
    side = H - 2 * PAD
    bx, by = PAD, PAD
    px = PAD + side + PAD
    pwid = W - px - PAD
  else
    local top = PAD + 3 * th(12) + 4
    side = math.min(W - 2 * PAD, H - top - bh - 2 * PAD)
    bx = fl((W - side) / 2)
    by = top
    px = PAD
    pwid = W - 2 * PAD
  end

  status_lbl = ui.label("", px, PAD, 12, C.text)
  status_lbl:width(pwid)

  local gap = 3
  local cell = fl((side - 2 * gap) / 3)
  cells = {}
  for i = 1, 9 do
    local r = fl((i - 1) / 3)
    local c = (i - 1) % 3
    local idx = i
    cells[i] = ui.button(" ", bx + c * (cell + gap), by + r * (cell + gap), cell, cell,
                         function() play_cell(idx) end)
  end

  local net = g.mode == "net"
  local y = H - bh - PAD
  if land then
    ui.button("Menu", px, y, pwid, bh, function() build_start() end)
    if net then ui.button("Resend", px, y - bh - 4, pwid, bh, resend) end
  elseif net then
    local half = fl((pwid - PAD) / 2)
    ui.button("Menu", px, y, half, bh, function() build_start() end)
    ui.button("Resend", px + half + PAD, y, half, bh, resend)
  else
    ui.button("Menu", px, y, pwid, bh, function() build_start() end)
  end
  refresh()
end

build_start = function()
  screen = "start"
  status_lbl, cells = nil, nil
  clear()
  ui.scroll(true)
  local bw, bh = W - 2 * PAD, btn_h()
  local y = PAD
  ui.label("Tic-Tac-Toe", PAD, y, 16, C.text)
  y = y + th(16) + 4
  ui.label("Choose a mode", PAD, y, 12, C.sub)
  y = y + th(12) + 8

  if g and g.mode == "net" and not is_over() and not g.taken then
    ui.button("Resume player game", PAD, y, bw, bh, function() build_game() end)
    y = y + bh + 4
  end
  ui.button("Play vs CPU", PAD, y, bw, bh, start_cpu)
  y = y + bh + 4
  ui.button("Play vs Player", PAD, y, bw, bh, function() build_player() end)
end

build_player = function()
  screen = "player"
  status_lbl, cells = nil, nil
  clear()
  ui.scroll(true)
  local bw, bh = W - 2 * PAD, btn_h()
  local y = PAD
  ui.label("Play vs Player", PAD, y, 16, C.text)
  y = y + th(16) + 8

  local ch = mesh.send and find_channel()
  if not mesh.send then
    local l = ui.label("Player games need a board with the extended app SDK.", PAD, y, 12, C.sub)
    l:width(bw)
    y = y + 3 * th(12) + 8
  elseif not ch then
    local l = ui.label("Add a channel named #tictactoe to this device first, then open this screen again. The app does not create it.",
                       PAD, y, 12, C.text)
    l:width(bw)
    y = y + 5 * th(12) + 8
  else
    ui.button("Host a game", PAD, y, bw, bh, start_host)
    y = y + bh + 4
    if #opens > 0 then
      ui.label("Open games heard:", PAD, y, 12, C.sub)
      y = y + th(12) + 4
      for _, o in ipairs(opens) do
        ui.button("Join " .. o.sender .. "  #" .. o.hkey:sub(1, 6), PAD, y, bw, bh,
                  function() join_game(o) end)
        y = y + bh + 4
      end
    else
      local l = ui.label("No open games heard yet. They show up here while this screen is open.",
                         PAD, y, 12, C.sub)
      l:width(bw)
      y = y + 3 * th(12) + 4
    end
    local hint = ui.label("Each move is a channel post. The mesh allows 3 quick posts, then about 1 a minute.",
                          PAD, y + 4, 12, C.sub)
    hint:width(bw)
    y = y + 4 + 3 * th(12) + 4
  end
  ui.button("Back", PAD, y + 4, bw, bh, function() build_start() end)
end

-- ---- lifecycle ---------------------------------------------------------------

function app.on_message(m)
  if type(m.text) ~= "string" then return end
  local H_, J, rest = m.text:match("TTT (%w+) (%S+) (%S+)")
  if not H_ or #H_ ~= 16 then return end
  local digits = rest:match("^(%d+)%.?%d*$")
  if not digits then return end
  if m.channel and norm(m.channel) ~= CHAN_KEY then return end
  local sender = tostring(m.sender or "?")
  if my_name and sender == my_name then return end
  local mv = parse_moves(digits)
  if not mv or #mv == 0 then return end

  if J == "-" then
    -- an open game: host's first move
    if #mv ~= 1 then return end
    if g and g.hkey == H_ then return end
    for i = #opens, 1, -1 do
      if opens[i].hkey == H_ then table.remove(opens, i) end
    end
    table.insert(opens, 1, { hkey = H_, sender = sender, chan = m.channel or find_channel(), first = mv[1] })
    while #opens > MAX_OPEN do table.remove(opens) end
    if screen == "player" then build_player() end
    return
  end

  if #J ~= 16 or not J:match("^%w+$") then return end

  -- a join post means the game is taken: stop offering it
  local removed = false
  for i = #opens, 1, -1 do
    if opens[i].hkey == H_ then table.remove(opens, i); removed = true end
  end
  if removed and screen == "player" then build_player() end

  if not g or g.mode ~= "net" or g.hkey ~= H_ then return end

  if g.me == "X" then
    if not g.jkey then
      -- first join wins: it must be 2 moves, starting with our first move
      if #mv == 2 and #g.moves == 1 and mv[1] == g.moves[1] then
        g.jkey, g.opp_name, g.moves = J, sender, mv
        g.pending, g.err = false, nil
        sys.beep()
        refresh()
      end
      return
    end
    if J ~= g.jkey then return end
  else
    if J ~= g.jkey then
      -- someone else's join got there first
      if #mv >= 2 and not g.taken then
        g.taken = true
        g.pending = false
        refresh()
      end
      return
    end
  end

  if g.opp_name and sender ~= "?" and sender ~= g.opp_name then return end
  if #mv ~= #g.moves + 1 then return end
  for i, c in ipairs(g.moves) do
    if mv[i] ~= c then return end
  end
  local mark = (#mv % 2 == 1) and "X" or "O"
  if mark == g.me then return end
  g.moves = mv
  sys.beep()
  refresh()
end

function app.on_input(ev)
  if ev.type == "key" and screen == "game" and ev.key and ev.key:match("^[1-9]$") then
    play_cell(tonumber(ev.key))
  end
end

function app.on_tick()
  if screen == "game" and g then
    try_send(sys.millis())
    refresh()
  end
end

function app.on_open(w, h)
  W, H = w, h
  local me = mesh.self and mesh.self()
  my_name = me and me.name or nil
  timer.every(200)
  build_start()
end

function app.on_close() end

return app
