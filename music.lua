-- ============================================================
--  CC Music Player · 背景音乐播放器      CC: Tweaked / CraftOS
-- ------------------------------------------------------------
--  · 播放 /music 目录里的 .dfpwm 文件
--  · mp3 / flac / aac 不能直接播放: 先用电脑上的 tools/convert.js
--    (或 convert.bat) 转成 .dfpwm, 放进电脑的 /music 目录
--  · 键盘: ↑↓ 选歌  回车 播放  空格 停止  ←→ 上一首/下一首
--          +/- 音量  r 重新扫描
--  · 显示屏(触摸): 点歌名 = 播放, 再点一次 = 停止
--          底部 [上首] [停止] [下首]
--  · 开机自动按顺序循环播放歌单(见下面配置)
--
--  扬声器: 直接贴在电脑旁边, 或者用有线调制解调器+线缆接到各处
-- ============================================================


-- ====================== ① 配置 ======================
local CONFIG = {
    lang = "zh",          -- "zh" 中文 / "en" 英文
    title = "MUSIC",      -- 停止时表头显示的字

    -- 显示屏的外设名; 写 "monitor_5" 或只写 "5" 都行; nil = 自动找第一块
    monitorName = nil,

    -- 开机自动从第一首开始播放
    autoplay = true,
    -- 歌单播完自动从头再来(autoplay 开着才有效)
    loopPlaylist = true,
    -- 随机播放(会覆盖顺序)
    shuffle = false,
    -- 初始音量 0.0 ~ 3.0
    volume = 1.5,
    -- 每次读多少字节 DFPWM(16KB ≈ 2.7 秒)
    chunk = 16 * 1024,
    -- 音乐目录(电脑文件夹里)
    musicDir = "/music",
}


-- ====================== ② 文字 ======================
local TEXT = {
    zh = {
        hintKeys = "回 车 播  空 格 停",
        hintTap  = "点 歌 名 播 放",
        none     = "没 有 歌 曲",
        noSpeaker= "没 有 扬 声 器",
        needConv = "(转)",
        vol      = "音 量",
        prev     = "上首",
        stop     = "停止",
        next     = "下首",
        play     = "播放中",
        paused   = "已停止",
        sSong    = "首",
        sPrev    = "上",
        sStop    = "停",
        sNext    = "下",
    },
    en = {
        hintKeys = "ENTER PLAY  SPACE STOP",
        hintTap  = "TAP A SONG",
        none     = "NO SONGS",
        noSpeaker= "NO SPEAKER",
        needConv = "(cvt)",
        vol      = "VOL",
        prev     = "PREV",
        stop     = "STOP",
        next     = "NEXT",
        play     = "PLAYING",
        paused   = "STOPPED",
        sSong    = "",
        sPrev    = "<",
        sStop    = "#",
        sNext    = ">",
    },
}

local function T(key)
    local t = TEXT[CONFIG.lang] or TEXT.zh
    return t[key] or key
end


-- ====================== ③ 字符宽度 ======================
-- (和点餐机一样的处理: 每个汉字按 2 格排, 后面补一个空格)
local wideNative = false

local WIDE = {
    { 0x1100, 0x115F }, { 0x2E80, 0x303E }, { 0x3041, 0x33FF },
    { 0x3400, 0x4DBF }, { 0x4E00, 0x9FFF }, { 0xA000, 0xA4CF },
    { 0xAC00, 0xD7A3 }, { 0xF900, 0xFAFF }, { 0xFE30, 0xFE4F },
    { 0xFF00, 0xFF60 }, { 0xFFE0, 0xFFE6 },
}

local function isWide(cp)
    if cp >= 0x20000 then return true end
    for i = 1, #WIDE do
        local r = WIDE[i]
        if cp >= r[1] and cp <= r[2] then return true end
    end
    return false
end

local function decodeAt(s, i)
    local b = s:byte(i)
    if not b then return nil, 1 end
    if b < 0x80 then return b, 1 end
    if b < 0xE0 then
        local b2 = s:byte(i + 1) or 0
        return (b - 0xC0) * 0x40 + (b2 - 0x80), 2
    elseif b < 0xF0 then
        local b2, b3 = s:byte(i + 1) or 0, s:byte(i + 2) or 0
        return (b - 0xE0) * 0x1000 + (b2 - 0x80) * 0x40 + (b3 - 0x80), 3
    end
    local b2, b3, b4 = s:byte(i + 1) or 0, s:byte(i + 2) or 0, s:byte(i + 3) or 0
    return (b - 0xF0) * 0x40000 + (b2 - 0x80) * 0x1000 + (b3 - 0x80) * 0x40 + (b4 - 0x80), 4
end

local function clen(s)
    s = tostring(s)
    local c, i = 0, 1
    while i <= #s do
        local cp, n = decodeAt(s, i)
        if not cp then break end
        c = c + (isWide(cp) and 2 or 1)
        i = i + n
    end
    return c
end

local function fit(s, maxW)
    s = tostring(s)
    if maxW <= 0 then return "" end
    local out, c, i = {}, 0, 1
    while i <= #s do
        local cp, n = decodeAt(s, i)
        if not cp then break end
        local w = isWide(cp) and 2 or 1
        if c + w > maxW then break end
        local ch = string.sub(s, i, i + n - 1)
        if w == 2 and not wideNative then
            out[#out + 1] = ch .. " "
        else
            out[#out + 1] = ch
        end
        c = c + w
        i = i + n
    end
    return table.concat(out)
end

local function wide(s)
    return fit(tostring(s), 4096)
end

local function chars(s)
    s = tostring(s)
    local n, i = 0, 1
    while i <= #s do
        local _, len = decodeAt(s, i)
        i = i + len
        n = n + 1
    end
    return n
end

local function cut(s, maxCells)
    s = tostring(s)
    local i, n = 1, 0
    while i <= #s and n < maxCells do
        local _, len = decodeAt(s, i)
        i = i + len
        n = n + 1
    end
    return string.sub(s, 1, i - 1)
end

local function center(s, w)
    s = tostring(s)
    local n = clen(s)
    if n >= w then return fit(s, w) end
    local left = math.floor((w - n) / 2)
    local right = w - n - left
    if left < 0 then left = 0 end
    if right < 0 then right = 0 end
    return string.rep(" ", left) .. fit(s, n) .. string.rep(" ", right)
end

local function detectWide(scr)
    wideNative = false
    pcall(function()
        local sx, sy = scr.getCursorPos()
        scr.setCursorPos(1, 1)
        scr.write("汉")
        local nx = scr.getCursorPos()
        scr.setCursorPos(sx, sy)
        if type(nx) == "number" and nx - 1 == 2 then wideNative = true end
    end)
    return wideNative
end


-- ====================== ④ 状态 ======================
local P = {
    songs = {},        -- { file, name, size, ok }
    cur = nil,         -- 正在播放的歌(下标)
    playing = false,
    handle = nil,
    decoder = nil,
    ended = false,     -- 文件读完了
    pending = nil,     -- 等待送进扬声器的 chunk
    volume = 1.5,
    speakers = {},
    msg = nil,         -- 界面底部临时提示
    msgUntil = 0,
    tick = nil,        -- 心跳定时器(卡住时补喂)
}

local UI = {
    scr = term, mon = nil, name = nil,
    w = 51, h = 19, touch = false, onTerm = true,
    sel = 1, offset = 0, rows = {}, hit = {},
}

local okReq, dfpwm = pcall(require, "cc.audio.dfpwm")
if not okReq then dfpwm = nil end


-- ====================== ⑤ 外设 ======================
local function hasType(name, want)
    local ok, t = pcall(peripheral.getType, name)
    if not ok then return false end
    if type(t) == "table" then
        for _, v in ipairs(t) do
            if v == want then return true end
        end
        return false
    end
    return t == want
end

local function allNames()
    local out, seen = {}, {}
    local function add(n)
        if type(n) == "string" and not seen[n] then
            seen[n] = true
            out[#out + 1] = n
        end
    end

    local ok, locals = pcall(peripheral.getNames)
    if not ok or type(locals) ~= "table" then locals = {} end
    for _, n in ipairs(locals) do add(n) end
    for _, n in ipairs(locals) do
        if hasType(n, "modem") then
            local okm, m = pcall(peripheral.wrap, n)
            if okm and m and type(m.getNamesRemote) == "function" then
                local okr, remote = pcall(m.getNamesRemote)
                if okr and type(remote) == "table" then
                    for _, r in ipairs(remote) do add(r) end
                end
            end
        end
    end
    return out
end

local function findSpeakers()
    local out = {}
    local names = allNames()
    table.sort(names)
    for _, name in ipairs(names) do
        if hasType(name, "speaker") then
            out[#out + 1] = name
        end
    end
    return out
end

local function findMonitor()
    local names = allNames()
    table.sort(names)
    local want = CONFIG.monitorName
    if want then
        for _, name in ipairs(names) do
            if hasType(name, "monitor") and (name == want or name == "monitor_" .. want) then
                local ok, mon = pcall(peripheral.wrap, name)
                if ok and mon then return name, mon end
            end
        end
    end
    for _, name in ipairs(names) do
        if hasType(name, "monitor") then
            local ok, mon = pcall(peripheral.wrap, name)
            if ok and mon then return name, mon end
        end
    end
    return nil, nil
end

local function monSize(mon, scale)
    pcall(mon.setTextScale, scale)
    local ok, w, h = pcall(mon.getSize)
    if ok and type(w) == "number" and type(h) == "number" then
        return w, h
    end
    return 0, 0
end

local function pickScale(mon)
    local w, h = monSize(mon, 1)
    if w >= 14 and h >= 5 then return 1 end
    w, h = monSize(mon, 0.5)
    if w >= 14 and h >= 5 then return 0.5 end
    return 1
end

local function setupScreen()
    local name, mon = findMonitor()
    UI.name, UI.mon = name, mon
    if mon then
        UI.onTerm = false
        pcall(mon.setTextScale, pickScale(mon))
        local ok, w, h = pcall(mon.getSize)
        if ok and type(w) == "number" then UI.w, UI.h = w, h end
        UI.scr = mon
        local okc, isColor = pcall(mon.isColor)
        UI.touch = okc and isColor == true
    else
        UI.onTerm = true
        UI.scr = term
        local ok, w, h = pcall(term.getSize)
        if ok then UI.w, UI.h = w, h end
        UI.touch = false
    end
    detectWide(UI.scr)
end


-- ====================== ⑥ 歌单 ======================
local function fmtSize(n)
    n = tonumber(n) or 0
    if n >= 1024 * 1024 then
        return string.format("%.1fM", n / 1048576)
    elseif n >= 1024 then
        return string.format("%.0fK", n / 1024)
    end
    return n .. "B"
end

local AUDIO_EXT = {
    mp3 = true, flac = true, aac = true, wav = true,
    ogg = true, m4a = true, wma = true, opus = true, dfpwm = true,
}

-- music/names.txt: 每行 "文件名=显示名" (等号后面随便写, 支持中文)
local function loadNames()
    local map = {}
    pcall(function()
        local path = CONFIG.musicDir .. "/names.txt"
        if not fs.exists(path) then return end
        local h = fs.open(path, "r")
        if not h then return end
        local txt = h.readAll() or ""
        h.close()
        for line in string.gmatch(txt, "[^\r\n]+") do
            if not string.match(line, "^%s*#") then
                local k, v = string.match(line, "^([^=]+)=(.+)$")
                if k and v then
                    k = string.gsub(k, "^%s+", "")
                    k = string.gsub(k, "%s+$", "")
                    map[k] = v
                end
            end
        end
    end)
    return map
end

local function scanSongs()
    local nameMap = loadNames()
    local prevCur = P.cur and P.songs[P.cur] and P.songs[P.cur].file
    local prevSel = UI.sel and P.songs[UI.sel] and P.songs[UI.sel].file

    local out = {}
    pcall(function()
        local names = fs.list(CONFIG.musicDir)
        for _, n in ipairs(names) do
            local ext = string.lower(string.match(n, "%.([%w]+)$") or "")
            if AUDIO_EXT[ext] then
                local path = CONFIG.musicDir .. "/" .. n
                local size = 0
                pcall(function() size = fs.getSize(path) end)
                local ok = (ext == "dfpwm")
                local base = string.match(n, "^(.*)%.[%w]+$") or n
                local label = nameMap[base] or (ok and base or n)
                out[#out + 1] = { file = path, name = n, label = label, size = size, ok = ok }
            end
        end
    end)

    -- 按显示名排序(不区分大小写)
    table.sort(out, function(a, b)
        local ka = string.lower(tostring(a.label))
        local kb = string.lower(tostring(b.label))
        if ka == kb then return a.name < b.name end
        return ka < kb
    end)

    P.songs = out

    -- 重新扫描后, 用文件名找回正在播放/选中的那首
    local function findIdx(file)
        if not file then return nil end
        for i, s in ipairs(out) do
            if s.file == file then return i end
        end
        return nil
    end
    if prevCur then P.cur = findIdx(prevCur) end
    UI.sel = (prevSel and findIdx(prevSel)) or 1
    if UI.sel > #out then UI.sel = #out end
    if UI.sel < 1 then UI.sel = 1 end
    return out
end


-- ====================== ⑦ 播放 ======================
local function stopSong()
    for _, s in ipairs(P.speakers) do
        pcall(function() peripheral.call(s, "stop") end)
    end
    if P.handle then
        pcall(function() P.handle.close() end)
    end
    P.handle = nil
    P.decoder = nil
    P.cur = nil
    P.playing = false
    P.ended = false
    P.pending = nil
end

local function sendPending()
    if not P.pending then return end
    for _, s in ipairs(P.speakers) do
        if not P.pending.done[s] then
            local ok, acc = pcall(function()
                return peripheral.call(s, "playAudio", P.pending.pcm, P.volume)
            end)
            if ok and acc ~= false then
                P.pending.done[s] = true
            end
        end
    end
    local all = true
    for _, s in ipairs(P.speakers) do
        if not P.pending.done[s] then
            all = false
            break
        end
    end
    if all then P.pending = nil end
end

local function feedSpeaker()
    -- 一次最多喂 4 块, 不递归: 防止某些情况下把整个文件一口气读进来
    local guard = 0
    while P.playing and not P.ended and not P.pending and guard < 4 do
        guard = guard + 1
        local chunk = P.handle.read(CONFIG.chunk)
        if not chunk then
            P.ended = true
            break
        end
        local okPcm, pcm = pcall(P.decoder, chunk)
        if not okPcm then
            P.msg = "解码失败"
            P.msgUntil = os.clock() + 3
            stopSong()
            return
        end
        P.pending = { pcm = pcm, done = {} }
        sendPending()
    end
end

local function openSong(idx)
    local song = P.songs[idx]
    if not song or not song.ok or not dfpwm then return false end
    if #P.speakers == 0 then return false end
    stopSong()
    local ok, h = pcall(fs.open, song.file, "rb")
    if not ok or not h then
        P.msg = "打不开: " .. tostring(song.label or song.name)
        P.msgUntil = os.clock() + 3
        return false
    end
    P.handle = h
    P.decoder = dfpwm.make_decoder()
    P.cur = idx
    P.playing = true
    P.ended = false
    feedSpeaker()
    if not P.tick then P.tick = os.startTimer(0.5) end
    return true
end

local function nextPlayable(afterIdx)
    for i = 1, #P.songs do
        local idx = (afterIdx + i - 1) % #P.songs + 1
        if P.songs[idx].ok then return idx end
    end
    return nil
end

local function prevPlayable(beforeIdx)
    for i = 1, #P.songs do
        local idx = (beforeIdx - i + #P.songs - 1) % #P.songs + 1
        if P.songs[idx].ok then return idx end
    end
    return nil
end

local function pickShuffle()
    if #P.songs <= 1 then return nil end
    local pool = {}
    for i, s in ipairs(P.songs) do
        if s.ok and i ~= P.cur then pool[#pool + 1] = i end
    end
    if #pool == 0 then return nil end
    return pool[math.random(#pool)]
end

local function nextSong()
    local idx = CONFIG.shuffle and pickShuffle() or nextPlayable(P.cur or 0)
    if idx then openSong(idx) else stopSong() end
end

local function prevSong()
    if CONFIG.shuffle then
        local idx = pickShuffle()
        if idx then openSong(idx) end
        return
    end
    local idx = prevPlayable(P.cur or 1)
    if idx then openSong(idx) end
end

local function onSongEnd()
    if not CONFIG.autoplay then
        stopSong()
        return
    end
    local idx = CONFIG.shuffle and pickShuffle() or nextPlayable(P.cur or 0)
    if not idx then
        stopSong()
        return
    end
    if not CONFIG.shuffle and not CONFIG.loopPlaylist and idx <= (P.cur or 0) then
        stopSong()
        return
    end
    openSong(idx)
end

local function setVolume(delta)
    P.volume = P.volume + delta
    if P.volume > 3 then P.volume = 3 end
    if P.volume < 0 then P.volume = 0 end
end


-- ====================== ⑧ 界面 ======================
local function blank()
    UI.hit = {}
    UI.scr.setBackgroundColor(colors.black)
    UI.scr.clear()
    UI.scr.setCursorPos(1, 1)
end

local function fillRow(y, bg)
    if y < 1 or y > UI.h then return end
    UI.scr.setBackgroundColor(bg)
    UI.scr.setCursorPos(1, y)
    UI.scr.clearLine()
end

local function fillPart(y, width, bg)
    if y < 1 or y > UI.h or width < 1 then return end
    local n = math.min(width, UI.w)
    UI.scr.setBackgroundColor(bg)
    UI.scr.setCursorPos(1, y)
    UI.scr.write(string.rep(" ", n))
end

local function put(x, y, text, fg, bg)
    if text == nil or text == "" then return end
    if y < 1 or y > UI.h then return end
    if x < 1 then x = 1 end
    if x > UI.w then return end
    local t = cut(text, UI.w - x + 1)
    if t == "" then return end
    UI.scr.setBackgroundColor(bg or colors.black)
    UI.scr.setTextColor(fg or colors.white)
    UI.scr.setCursorPos(x, y)
    UI.scr.write(t)
end

local function rowsInfo()
    local headerRows = (UI.h >= 6) and 2 or 1
    local listTop = headerRows + 1
    local rowsH = math.max(1, UI.h - listTop)
    return listTop, rowsH
end

local function drawMusic()
    blank()
    local w, h = UI.w, UI.h
    local songs = P.songs
    local n = #songs

    local listTop, rowsH = rowsInfo()
    UI.listTop, UI.rowsH = listTop, rowsH

    -- 头部: 播放时显示歌名, 停止时显示店名
    fillRow(1, colors.orange)
    local headTxt = CONFIG.title
    if P.playing and P.cur and songs[P.cur] then
        headTxt = "♪ " .. tostring(songs[P.cur].label or songs[P.cur].name)
    end
    put(1, 1, center(headTxt, w), colors.white, colors.orange)
    if listTop >= 3 then
        local state = P.playing and T("play") or T("paused")
        local info = n .. T("sSong") .. " " .. string.format("%.1f", P.volume) .. " " .. state
        put(1, 2, center(info, w), colors.lightGray, colors.black)
    end

    if n == 0 then
        put(1, listTop, center(T("none"), w), colors.gray, colors.black)
    else
        local maxOff = math.max(0, n - rowsH)
        if UI.offset > maxOff then UI.offset = maxOff end
        if UI.offset < 0 then UI.offset = 0 end

        UI.rows = {}
        for i = 1, rowsH do
            local song = songs[UI.offset + i]
            local y = listTop + i - 1
            if song then
                local isPlay = (UI.offset + i == P.cur)
                local isSel = (UI.offset + i == UI.sel)
                local bg = colors.black
                local fg = colors.white
                if isPlay then
                    bg = colors.green
                    fg = colors.black
                elseif isSel then
                    bg = colors.lightGray
                    fg = colors.black
                elseif not song.ok then
                    fg = colors.gray
                end

                fillPart(y, w - 1, bg)
                UI.rows[i] = y

                local mark = " "
                if isPlay then mark = "*" elseif isSel then mark = ">" end
                put(1, y, mark, fg, bg)

                local sizeTxt = fmtSize(song.size)
                local tag = song.ok and "" or T("needConv")
                local display = song.label or song.name
                local nameW = (w - 1) - 2 - clen(sizeTxt) - clen(tag) - 2
                if nameW < 3 then nameW = 3 end
                local line = fit(display, nameW)
                if tag ~= "" then line = line .. " " .. tag end
                put(2, y, line, fg, bg)
                put(w - clen(sizeTxt), y, sizeTxt, fg, bg)
            else
                fillPart(y, w - 1, colors.black)
            end
        end

        -- 右边滑条
        local trackH = rowsH
        if trackH > 0 then
            local thumbH = math.max(1, math.floor(trackH * trackH / math.max(1, n)))
            if thumbH > trackH then thumbH = trackH end
            local thumbTop = 0
            if maxOff > 0 then
                thumbTop = math.floor((UI.offset / maxOff) * (trackH - thumbH) + 0.5)
            end
            for i = 0, trackH - 1 do
                local onThumb = (i >= thumbTop) and (i < thumbTop + thumbH)
                UI.scr.setBackgroundColor(onThumb and colors.lightGray or colors.gray)
                UI.scr.setCursorPos(w, listTop + i)
                UI.scr.write(" ")
            end
        end
    end

    -- 底部
    if P.msg and os.clock() < (P.msgUntil or 0) then
        put(1, h, center(P.msg, w), colors.red, colors.black)
    elseif #P.speakers == 0 then
        put(1, h, center(T("noSpeaker"), w), colors.red, colors.black)
    elseif UI.touch then
        local prevB = fit("[" .. T("prev") .. "]", 4096)
        local stopB = fit("[" .. T("stop") .. "]", 4096)
        local nextB = fit("[" .. T("next") .. "]", 4096)
        if chars(prevB) + chars(stopB) + chars(nextB) + 2 > w then
            prevB = fit("[" .. T("sPrev") .. "]", 4096)
            stopB = fit("[" .. T("sStop") .. "]", 4096)
            nextB = fit("[" .. T("sNext") .. "]", 4096)
        end
        local pw, sw, nw = chars(prevB), chars(stopB), chars(nextB)
        local total = pw + sw + nw + 2
        local x = math.floor((w - total) / 2) + 1
        if x < 1 then x = 1 end
        put(x, h, prevB, colors.black, colors.lime)
        UI.hit[#UI.hit + 1] = { x1 = x, y1 = h, x2 = x + pw - 1, y2 = h, act = "prev" }
        x = x + pw + 1
        put(x, h, stopB, colors.white, colors.red)
        UI.hit[#UI.hit + 1] = { x1 = x, y1 = h, x2 = x + sw - 1, y2 = h, act = "stop" }
        x = x + sw + 1
        put(x, h, nextB, colors.black, colors.lime)
        UI.hit[#UI.hit + 1] = { x1 = x, y1 = h, x2 = x + nw - 1, y2 = h, act = "next" }
    else
        put(1, h, center(T("hintKeys"), w), colors.gray, colors.black)
    end
end


-- ====================== ⑨ 输入 ======================
local function scrollTo(y)
    local listTop, rowsH = rowsInfo()
    local maxOff = math.max(0, #P.songs - rowsH)
    if maxOff <= 0 then return end
    local rel = (y - listTop) / math.max(1, rowsH - 1)
    if rel < 0 then rel = 0 elseif rel > 1 then rel = 1 end
    UI.offset = math.floor(rel * maxOff + 0.5)
end

local function touch(x, y)
    local listTop, rowsH = rowsInfo()
    if y == UI.h then
        for _, b in ipairs(UI.hit) do
            if x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2 then
                if b.act == "prev" then
                    prevSong()
                elseif b.act == "stop" then
                    stopSong()
                elseif b.act == "next" then
                    nextSong()
                end
                return
            end
        end
        return
    end
    if y >= listTop and y <= listTop + rowsH - 1 then
        if x >= UI.w then
            scrollTo(y)
            return
        end
        local idx = UI.offset + (y - listTop) + 1
        local song = P.songs[idx]
        if not song then return end
        UI.sel = idx
        if song.ok then
            if P.cur == idx then
                stopSong()
            else
                openSong(idx)
            end
        end
    end
end

local function key(k)
    local n = #P.songs
    local _, rowsH = rowsInfo()
    if k == keys.up then
        if n > 0 then
            UI.sel = UI.sel - 1
            if UI.sel < 1 then UI.sel = n end
            if UI.sel <= UI.offset then UI.offset = UI.sel - 1 end
            if UI.sel > UI.offset + rowsH then UI.offset = UI.sel - rowsH end
        end
    elseif k == keys.down then
        if n > 0 then
            UI.sel = UI.sel + 1
            if UI.sel > n then UI.sel = 1 end
            if UI.sel <= UI.offset then UI.offset = UI.sel - 1 end
            if UI.sel > UI.offset + rowsH then UI.offset = UI.sel - rowsH end
        end
    elseif k == keys.enter or k == keys.numPadEnter then
        local song = P.songs[UI.sel]
        if song then
            if song.ok then
                if P.cur == UI.sel then
                    stopSong()
                else
                    openSong(UI.sel)
                end
            end
        end
    elseif k == keys.space then
        stopSong()
    elseif k == keys.left then
        prevSong()
    elseif k == keys.right then
        nextSong()
    elseif k == keys.equals then
        setVolume(0.5)
    elseif k == keys.minus then
        setVolume(-0.5)
    elseif k == keys.r then
        scanSongs()
    end
end


-- ====================== ⑩ 主循环 ======================
local function log(text)
    if UI.onTerm then return end
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.lightGray)
    term.write(wide(tostring(text)) .. "\n")
end

local function boot()
    if UI.onTerm then return end
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.white)
    term.write(wide(CONFIG.title) .. "  music player\n")
    term.setTextColor(colors.lightGray)
    term.write("screen: " .. tostring(UI.name) .. "  songs: " .. #P.songs .. "  speakers: " .. #P.speakers .. "\n")
    if not dfpwm then
        term.setTextColor(colors.red)
        term.write("WARN: cc.audio.dfpwm 不可用\n")
    end
    if #P.speakers == 0 then
        term.setTextColor(colors.red)
        term.write("WARN: 没有找到扬声器\n")
    end
    term.setTextColor(colors.lightGray)
    term.write("--------------------------------\n")
end

-- 心跳: 万一 speaker_audio_empty 事件漏了, 这里补喂, 免得卡住
local function onTick(id)
    if P.tick == id then P.tick = nil end
    if P.playing and not P.pending and not P.ended then
        feedSpeaker()
    end
    if P.playing and not P.tick then
        P.tick = os.startTimer(0.5)
    end
end

local function main()
    P.volume = tonumber(CONFIG.volume) or 1.5
    setupScreen()
    scanSongs()
    P.speakers = findSpeakers()
    boot()

    if CONFIG.autoplay then
        local idx = nextPlayable(0)
        if idx then
            openSong(idx)
            log("autoplay: " .. P.songs[idx].name)
        end
    end

    while true do
        drawMusic()
        local e, p1, p2, p3 = os.pullEvent()

        if e == "speaker_audio_empty" then
            sendPending()
            if not P.pending then
                if P.playing and P.ended then
                    onSongEnd()
                elseif P.playing then
                    feedSpeaker()
                end
            end
        elseif e == "timer" then
            onTick(p1)
        elseif e == "monitor_touch" then
            if p1 == UI.name then touch(p2, p3) end
        elseif e == "key" then
            key(p1)
        elseif e == "monitor_resize" or e == "term_resize" then
            setupScreen()
        elseif e == "peripheral" or e == "peripheral_detach" then
            P.speakers = findSpeakers()
            setupScreen()
        end
    end
end


-- ====================== ⑪ 入口 ======================
local ok, err = pcall(main)
stopSong()
if not ok then
    local msg = tostring(err)
    if not string.find(msg, "Terminated") then
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.red)
        term.write("music.lua error: " .. msg .. "\n")
    end
end
