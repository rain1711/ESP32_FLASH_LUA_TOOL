--GUIMODE=1  --用于识别GUI程序还是print程序
local PATH = "0:/H7-TOOL/Lua/ESP"
local CFG = {
    UART_PORT = 1,
    BAUD = 921600,
    EN_PIN = 2, -- D2
    BOOT_PIN = 3, -- D3
    TVCC_VOLT = 3.3,
    BLOCK_SIZE = 4096,
    FLASH_SIZE = 0x400000,
    SYNC_TRIALS = 5
}
local BAUD_LIST = {115200, 230400, 460800, 921600, 1500000}
local CHIP_LIST = {
    "Auto",
    "ESP32",
    "ESP32-S2",
    "ESP32-C3",
    "ESP32-S3",
    "ESP32-C2",
    "ESP32-C6",
    "ESP32-H2",
    "ESP32-C5",
    "ESP32-C61",
    "ESP32-P4",
    "ESP8266"
}
local CHIPS = {
    ["ESP8266"] = {enc = false, attach = "8266"},
    ["ESP32"] = {enc = false, attach = "spi"},
    ["ESP32-S2"] = {enc = true, attach = "spi"},
    ["ESP32-C3"] = {enc = true, attach = "spi"},
    ["ESP32-S3"] = {enc = true, attach = "spi"},
    ["ESP32-C2"] = {enc = true, attach = "spi"},
    ["ESP32-C6"] = {enc = true, attach = "spi"},
    ["ESP32-H2"] = {enc = true, attach = "spi"},
    ["ESP32-C5"] = {enc = true, attach = "spi"},
    ["ESP32-C61"] = {enc = true, attach = "spi"},
    ["ESP32-P4"] = {enc = true, attach = "spi"}
}
local MAGIC = {
    [0xfff0c101] = "ESP8266",
    [0x00f01d83] = "ESP32",
    [0x000007c6] = "ESP32-S2",
    [0x6921506f] = "ESP32-C3",
    [0x1b31506f] = "ESP32-C3",
    [0x4881606f] = "ESP32-C3",
    [0x4361606f] = "ESP32-C3",
    [0x00000009] = "ESP32-S3",
    [0x6f51306f] = "ESP32-C2",
    [0x7c41a06f] = "ESP32-C2",
    [0x0c21e06f] = "ESP32-C2",
    [0x1101406f] = "ESP32-C5",
    [0x5fd1406f] = "ESP32-C5",
    [0xd7b73e80] = "ESP32-H2",
    [0x2ce0806f] = "ESP32-C6",
    [0x7211606f] = "ESP32-C61"
}
local MAGIC_P4_REG = 0x500d0000
local MAGIC_P4_MASK = 0x7FFFFFF
local MAGIC_P4_VAL = 0x2207202
local CMD = {
    FLASH_BEGIN = 0x02,
    FLASH_DATA = 0x03,
    FLASH_END = 0x04,
    MEM_BEGIN = 0x05,
    MEM_END = 0x06,
    MEM_DATA = 0x07,
    SYNC = 0x08,
    WRITE_REG = 0x09,
    READ_REG = 0x0a,
    SPI_SET_PARAMS = 0x0b,
    SPI_ATTACH = 0x0d,
    SPI_FLASH_MD5 = 0x13
}
local KEY = {UP = 1, DOWN = 8, OK = 15, CANCEL = 22, HOME = 29}
local C = {
    BG = 0xFFFF,
    TEXT = 0x0000,
    TITLE_BG = 0x001F,
    TITLE_TEXT = 0xFFFF,
    HL = 0xFFE0,
    HL_TEXT = 0x0000,
    LINE = 0xCE59,
    PROG = 0x9F53,
    STATUS = 0x0000,
    GRAY = 0x8410,
    OK = 0x07E0,
    ERR = 0xF800
}
local OFFSET_PRESETS = {0x00000, 0x01000, 0x08000, 0x0E000, 0x10000, 0x100000, 0x200000, 0x300000, 0x400000}
local SCREEN_W = 240
local function le16(v)
    return string.char(v & 0xFF, (v >> 8) & 0xFF)
end
local function le32(v)
    return string.char(v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF)
end
local function tohex(v)
    return string.format("0x%X", v)
end
local function xor8(s)
    local c = 0xEF
    for i = 1, #s do
        c = (c ~ string.byte(s, i)) & 0xFF
    end
    return c
end
local function slip_encode(s)
    local out = ""
    for i = 1, #s do
        local b = string.byte(s, i)
        if b == 0xC0 then
            out = out .. "\xDB\xDC"
        elseif b == 0xDB then
            out = out .. "\xDB\xDD"
        else
            out = out .. string.char(b)
        end
    end
    return out
end
local function slip_decode(s)
    local out, i = "", 1
    while i <= #s do
        local b = string.byte(s, i)
        if b == 0xDB then
            local n = string.byte(s, i + 1)
            if n == 0xDC then
                out = out .. "\xC0"
            elseif n == 0xDD then
                out = out .. "\xDB"
            else
                return nil, "bad escape"
            end
            i = i + 2
        else
            out = out .. string.char(b)
            i = i + 1
        end
    end
    return out
end
local function now_ms()
    local ok, v = pcall(get_runtime)
    if ok and v then
        return v
    end
    return os.clock() * 1000
end
local state
local update_progress
local function is_manual()
    return state.reset_mode == "manual"
end
local ESP = {}
ESP.__index = ESP
function ESP.new(port, baud)
    local self = setmetatable({}, ESP)
    self.port, self.baud, self.rawbuf, self.target = port, baud, "", "Auto"
    self:apply_target()
    return self
end
function ESP.apply_target(self)
    local c = CHIPS[self.target] or {enc = true, attach = "spi"}
    self.encryption_field, self.attach_method, self.block_size = c.enc, c.attach, CFG.BLOCK_SIZE
end
function ESP.fill_raw(self, t)
    t = math.max(1, math.floor(t or 0))
    local len, str = uart_recive(self.port, 200, t, 10)
    if len and len > 0 and str then
        self.rawbuf = self.rawbuf .. str
        if #self.rawbuf > 8192 then
            self.rawbuf = string.sub(self.rawbuf, -4096)
        end
    end
end
function ESP.extract_packet(self)
    local buf = self.rawbuf
    local i = string.find(buf, "\xC0", 1, true)
    if not i then
        return nil
    end
    local start = i
    while start <= #buf and string.byte(buf, start) == 0xC0 do
        start = start + 1
    end
    if start > #buf then
        self.rawbuf = ""
        return nil
    end
    local j = string.find(buf, "\xC0", start, true)
    if not j then
        return nil
    end
    local raw = string.sub(buf, start, j - 1)
    self.rawbuf = string.sub(buf, j + 1)
    return slip_decode(raw)
end
function ESP.parse_packet(self, pkt)
    if not pkt or #pkt < 10 then
        return nil
    end
    return {
        direction = string.byte(pkt, 1),
        command = string.byte(pkt, 2),
        size = string.byte(pkt, 3) | (string.byte(pkt, 4) << 8),
        value = string.byte(pkt, 5) | (string.byte(pkt, 6) << 8) | (string.byte(pkt, 7) << 16) |
            (string.byte(pkt, 8) << 24),
        failed = string.byte(pkt, #pkt - 1),
        error = string.byte(pkt, #pkt),
        resp_data = string.sub(pkt, 9, #pkt - 2)
    }
end
function ESP.read_packet(self, timeout)
    local deadline = now_ms() + timeout
    while true do
        local raw = self:extract_packet()
        if raw then
            local p = self:parse_packet(raw)
            if p then
                return p
            end
        end
        if now_ms() >= deadline then
            return nil
        end
        local t = math.floor(deadline - now_ms())
        if t > 500 then
            t = 500
        end
        self:fill_raw(t)
    end
end
function ESP.send_frame(self, cmd, payload, data)
    data = data or ""
    local checksum = 0
    if #data > 0 then
        checksum = xor8(data)
    end
    local header = string.char(0x00, cmd) .. le16(#payload + #data) .. le32(checksum)
    self.rawbuf = ""
    uart_send(self.port, "\xC0" .. slip_encode(header .. payload .. data) .. "\xC0")
end
function ESP.send_command(self, cmd, payload, data, timeout)
    self:send_frame(cmd, payload, data)
    timeout = timeout or 5000
    local deadline = now_ms() + timeout
    while true do
        local remain = deadline - now_ms()
        if remain <= 0 then
            return nil, "no matching resp"
        end
        local pkt = self:read_packet(remain)
        if not pkt then
            return nil, "timeout"
        end
        if pkt.direction == 0x01 and pkt.command == cmd then
            if pkt.failed ~= 0 then
                return nil, "ERR" .. pkt.error
            end
            return pkt
        end
    end
end
function ESP.enter_bootloader(self)
    if is_manual() then
        print("手动模式：跳过自动复位，直接SYNC（请确认板子已在下载模式）")
        if state then state.status = "直接SYNC..." end
        if update_progress then update_progress(0, "手动模式：直接SYNC") end
        return
    end
    print("开始进入下载模式...")
    if CFG.EN_PIN > 0 then
        gpio_cfg(CFG.EN_PIN, 1)
        gpio_write(CFG.EN_PIN, 1)
    end
    if CFG.BOOT_PIN > 0 then
        gpio_cfg(CFG.BOOT_PIN, 1)
        gpio_write(CFG.BOOT_PIN, 1)
    end
    delayms(50)
    if CFG.BOOT_PIN > 0 then
        gpio_write(CFG.BOOT_PIN, 0)
    end
    if CFG.EN_PIN > 0 then
        gpio_write(CFG.EN_PIN, 0)
    end
    delayms(50)
    if CFG.EN_PIN > 0 then
        gpio_write(CFG.EN_PIN, 1)
    end
    delayms(50)
    if CFG.BOOT_PIN > 0 then
        gpio_write(CFG.BOOT_PIN, 1)
    end
    delayms(100)
end
function ESP.release_pins(self)
    if is_manual() then
        print("手动模式:请手动复位")
        if state then state.status = "完成,手动复位" end
        if update_progress then update_progress(100, "完成,手动复位") end
        return
    end
    if CFG.BOOT_PIN > 0 then
        gpio_write(CFG.BOOT_PIN, 1)
    end
    if CFG.EN_PIN > 0 then
        gpio_write(CFG.EN_PIN, 0)
        delayms(50)
        gpio_write(CFG.EN_PIN, 1)
    end
end
function ESP.sync(self)
    local seq = "\x07\x07\x12\x20" .. string.rep("\x55", 32)
    self:send_frame(CMD.SYNC, seq)
    for attempt = 1, CFG.SYNC_TRIALS do
        print("SYNC try " .. attempt)
        local ok = false
        for _ = 1, 8 do
            local pkt = self:read_packet(400)
            if pkt and pkt.direction == 0x01 and pkt.command == CMD.SYNC and pkt.failed == 0 then
                ok = true
                break
            end
        end
        if ok then
            print("SYNC OK")
            return true
        end
        delayms(120)
        self:send_frame(CMD.SYNC, seq)
    end
    print("SYNC 握手失败，请检查接线，或者降低波特率")
    return false
end
function ESP.detect_chip(self)
    local chip_name = nil
    print("读芯片寄存器...")
    local pkt = self:send_command(CMD.READ_REG, le32(0x40001000), nil, 4000)
    if pkt and pkt.value then
        print(string.format("magic=0x%08X", pkt.value))
        chip_name = MAGIC[pkt.value]
    else
    end
    if not chip_name then
        local p4 = self:send_command(CMD.READ_REG, le32(MAGIC_P4_REG), nil, 4000)
        if p4 and p4.value then
            if (p4.value & MAGIC_P4_MASK) == MAGIC_P4_VAL then
                chip_name = "ESP32-P4"
            end
        else
        end
    end
    if chip_name then
        self.target = chip_name
        self:apply_target()
        print("成功识别到芯片: " .. chip_name)
        return chip_name
    end
    print("芯片识别失败，未找到匹配的芯片型号！")
    return nil
end
function ESP.spi_attach(self)
    print("SPI ATTACH")
    if self.attach_method == "8266" then
        return self:send_command(CMD.FLASH_BEGIN, le32(0) .. le32(0) .. le32(0) .. le32(0), nil, 5000)
    else
        return self:send_command(CMD.SPI_ATTACH, le32(0) .. le32(0), nil, 5000)
    end
end
function ESP.spi_set_params(self)
    print("SPI SET PARAMS")
    return self:send_command(
        CMD.SPI_SET_PARAMS,
        le32(0) .. le32(CFG.FLASH_SIZE) .. le32(0x10000) .. le32(0x1000) .. le32(0x100) .. le32(0xFFFF),
        nil,
        5000
    )
end
function ESP.flash_begin(self, offset, erase_size, block_size, num_blocks)
    print(string.format("BEGIN off=0x%X n=%d", offset, num_blocks))
    local payload =
        le32(erase_size) ..
        le32(num_blocks) .. le32(block_size) .. le32(offset) .. (self.encryption_field and le32(0) or "")
    return self:send_command(CMD.FLASH_BEGIN, payload, nil, 30000)
end
function ESP.flash_data(self, seq, data)
    return self:send_command(CMD.FLASH_DATA, le32(#data) .. le32(seq) .. le32(0) .. le32(0), data, 20000)
end
function ESP.flash_md5(self, offset, size)
    local pkt = self:send_command(
        CMD.SPI_FLASH_MD5, le32(offset) .. le32(size) .. le32(0) .. le32(0), nil, 15000
    )
    if not pkt then return nil end
    local d = pkt.resp_data or ""
    if #d >= 34 then d = string.sub(d, 1, 32) end -- 去掉 ROM 的 4 状态字节对齐余量
    if #d == 32 then return d end
    if #d == 18 then -- stub 风格：16 raw + 2 状态，已在 parse 中剥离，此处兜底转 hex
        return (string.gsub(string.sub(d, 1, 16), ".",
            function(c) return string.format("%02x", string.byte(c)) end))
    end
    return nil
end
local MD5_S = {7,12,17,22, 5,9,14,20, 4,11,16,23, 6,10,15,21}
local MD5_K = {}
for i = 1, 64 do MD5_K[i] = math.floor(2^32 * math.abs(math.sin(i))) & 0xFFFFFFFF end
local function md5_lrot(x, n) return ((x << n) | (x >> (32 - n))) & 0xFFFFFFFF end
local function md5_new()
    return {a = 0x67452301, b = 0xEFCDAB89, c = 0x98BADCFE, d = 0x10325476, buf = "", total = 0}
end
local function md5_block(st, blk)
    local M = {}
    for i = 0, 15 do
        local b1, b2, b3, b4 = string.byte(blk, i * 4 + 1, i * 4 + 4)
        M[i + 1] = ((b1 or 0) | ((b2 or 0) << 8) | ((b3 or 0) << 16) | ((b4 or 0) << 24)) & 0xFFFFFFFF
    end
    local A, B, C, D = st.a, st.b, st.c, st.d
    for i = 1, 64 do
        local F, g
        if i <= 16 then F = (B & C) | ((~B) & D); g = i
        elseif i <= 32 then F = (D & B) | ((~D) & C); g = (5 * (i - 1) + 1) % 16 + 1
        elseif i <= 48 then F = B ~ C ~ D; g = (3 * (i - 1) + 5) % 16 + 1
        else F = C ~ (B | (~D)); g = (7 * (i - 1)) % 16 + 1 end
        F = (F + A + MD5_K[i] + M[g]) & 0xFFFFFFFF
        A = D; D = C; C = B
        local r = MD5_S[math.floor((i - 1) / 16) * 4 + ((i - 1) % 4) + 1]
        B = (B + md5_lrot(F, r)) & 0xFFFFFFFF
    end
    st.a = (st.a + A) & 0xFFFFFFFF; st.b = (st.b + B) & 0xFFFFFFFF
    st.c = (st.c + C) & 0xFFFFFFFF; st.d = (st.d + D) & 0xFFFFFFFF
end
local function md5_update(st, chunk)
    st.total = st.total + #chunk
    local data = st.buf .. chunk
    local pos = 1
    while #data - pos + 1 >= 64 do
        md5_block(st, string.sub(data, pos, pos + 63))
        pos = pos + 64
    end
    st.buf = string.sub(data, pos)
end
local function md5_finish(st)
    local bitlen = st.total * 8
    local pad = "\x80"
    local r = (st.total + 1) % 64
    local need = (r <= 56) and (56 - r) or (56 + 64 - r)
    pad = pad .. string.rep("\x00", need)
    for _ = 1, 8 do pad = pad .. string.char(bitlen & 0xFF); bitlen = bitlen >> 8 end
    md5_update(st, pad)
    st.buf = ""
    local function wh(w)
        return string.format("%02x%02x%02x%02x", w & 0xFF, (w >> 8) & 0xFF, (w >> 16) & 0xFF, (w >> 24) & 0xFF)
    end
    return wh(st.a) .. wh(st.b) .. wh(st.c) .. wh(st.d)
end
local function md5_of_file(job)
    local path, size = job.path, job.fsize
    if not job.exist or not size or size <= 0 then return nil end
    local st = md5_new()
    local off = 0
    while off < size do
        local n = math.min(4096, size - off)
        local len, bin = f_read(path, off, n)
        if not len or len <= 0 or not bin then return nil end
        md5_update(st, string.sub(bin, 1, len))
        bin = nil
        off = off + len
    end
    return md5_finish(st)
end
function ESP.verify_all(self, jobs, on_progress)
    for i, job in ipairs(jobs) do
        local fsize = job.fsize
        if on_progress then on_progress(nil, string.format("校验 %d/%d %s", i, #jobs, job.name)) end
        local expect = md5_of_file(job)
        local got = self:flash_md5(job.offset, fsize)
        if not expect or not got then return false, "校验失败:" .. job.name end
        if string.lower(expect) ~= string.lower(got) then
            return false, string.format("MD5不一致:%s 本地%s 片上%s", job.name, expect, got)
        end
    end
    return true
end
local function calc_erase_8266(offset, image_size)
    local num_sectors = math.ceil(image_size / 4096)
    local head_sectors = 16 - (math.floor(offset / 4096) % 16)
    if num_sectors <= head_sectors then
        return math.floor((num_sectors + 1) / 2) * 4096
    else
        return (num_sectors - head_sectors) * 4096
    end
end
function ESP.flash_one(self, job, on_progress, idx, total)
    local fsize = job.fsize
    if not job.exist or not fsize or fsize <= 0 then
        return false, "缺文件: " .. job.name
    end
    local bs = (self.target == "ESP8266") and 1024 or self.block_size
    local es = (self.target == "ESP8266") and calc_erase_8266(job.offset, fsize) or fsize
    if not self:flash_begin(job.offset, es, bs, math.ceil(fsize / bs)) then
        print("FLASH_BEGIN 命令被芯片拒绝")
        return false, "BEGIN失败"
    end
    print("烧录:" .. job.name)
    local seq, addr, last_pct = 0, 0, -1
    while addr < fsize do
        local chunk = math.min(bs, fsize - addr)
        local _, bin = f_read(job.path, addr, chunk)
        if not bin or #bin == 0 then
            return false, "读文件内容失败 @0x" .. tohex(addr)
        end
        if (fsize - addr) == chunk and (#bin % 4 ~= 0) then
            bin = bin .. string.rep("\xFF", 4 - (#bin % 4))
        end
        if not self:flash_data(seq, bin) then
            return false, "写数据失败 @块" .. seq
        end
        seq, addr = seq + 1, addr + #bin
        do
            local pct = math.floor(addr * 100 / fsize)
            if pct - last_pct >= 10 then
                last_pct = pct
                print(string.format("%s %d%%", job.name, pct))
            end
        end
        if on_progress then
            on_progress(
                math.floor(addr * 100 / fsize),
                string.format("段%d/%d %s %d/%d", idx, total, job.name, addr, fsize)
            )
        end
    end
    print("完成:" .. job.name)
    return true
end
function ESP.flash_all(self, jobs, expected_chip, on_progress)
    if #jobs == 0 then
        return false, "没有固件任务"
    end
    print("烧录启动")
    self:enter_bootloader()
    uart_clear_rx(self.port)
    if not self:sync() then
        self:release_pins()
        return false, "SYNC失败"
    end
    local name = self:detect_chip()
    if not name then
        self:release_pins()
        return false, "未识别芯片"
    end
    if expected_chip ~= "Auto" and name ~= expected_chip then
        self:release_pins()
        return false, "选中[" .. expected_chip .. "]实际[" .. name .. "]"
    end
    self.target = name
    self:apply_target()
    state.detected = name
    if on_progress then
        on_progress(0, "芯片: " .. name)
    end
    if not self:spi_attach() then
        self:release_pins()
        return false, "ATTACH失败"
    end
    if not self:spi_set_params() then
        self:release_pins()
        return false, "SETPARAMS失败"
    end
    for i, job in ipairs(jobs) do
        local ok, msg = self:flash_one(job, on_progress, i, #jobs)
        if not ok then
            self:release_pins()
            return false, msg
        end
    end
    if state.verify then
        local vok, vmsg = self:verify_all(jobs, on_progress)
        if vok == false then
            self:release_pins()
            return false, vmsg
        end
    end
    self:release_pins()
    if on_progress then
        on_progress(100, "完成+校验OK")
    end
    return true, "完成"
end
local ui = {}
local esp = ESP.new(CFG.UART_PORT, CFG.BAUD)
state = {
    chip_idx = 1, -- 默认 Auto
    baud_idx = 1, -- 默认 115200 波特率
    sel = 1,
    progress = 0,
    status = "就绪",
    busy = false,
    verify = true, -- 烧后 MD5 校验开关
    reset_mode = "auto", -- 复位模式：auto=EN+BOOT自动，manual=手动进下载/手动复位
    detected = nil,
    status_color = nil, -- 本次识别到的实际芯片（Auto/手动均显示，防认错）
    pkgs = {}, -- 固件包列表：{name=目录名, label, chip, dir}
    pkg_idx = 0, -- 当前包（0=无包/兼容旧单目录）
    jobs = {
        {name = "bootloader.bin", path = PATH .. "/bootloader.bin", offset = 0x0000},
        {name = "partition-table.bin", path = PATH .. "/partition-table.bin", offset = 0x8000},
        {name = "firmware.bin", path = PATH .. "/firmware.bin", offset = 0x10000}
    }
}
local function parse_manifest_file(mf_path, base_dir)
    local ok, size = pcall(f_size, mf_path)
    if not ok or not size or size <= 0 or size > 4096 then return nil end
    local r = {pcall(f_read, mf_path, 0, size)}
    if not r[1] then return nil end
    local body = r[3]
    if type(body) ~= "string" then return nil end
    local label = string.match(body, '"label"%s*:%s*"([^"]+)"')
    local chip = string.match(body, '"chip"%s*:%s*"([^"]+)"')
    local files = {}
    for p, o in string.gmatch(body, '"path"%s*:%s*"([^"]+)"%s*,%s*"offset"%s*:%s*"([^"]+)"') do
        local off = tonumber(o)
        if off == nil then off = 0 end
        files[#files + 1] = {name = p, path = base_dir .. "/" .. p, offset = off}
    end
    if #files == 0 then return nil end
    return {label = label, chip = chip, files = files}
end
local function refresh_jobs()
    for _, j in ipairs(state.jobs) do
        local sz = f_size(j.path)
        if sz and sz > 0 then
            j.exist, j.fsize = true, sz
        else
            j.exist, j.fsize = false, 0
        end
    end
end
local function apply_pkg(idx)
    local pkg = state.pkgs[idx]
    if not pkg then return end
    state.pkg_idx = idx
    state.jobs = pkg.files
    if pkg.chip then
        for ci, cn in ipairs(CHIP_LIST) do
            if cn == pkg.chip then
                state.chip_idx = ci
                esp.target = cn
                esp:apply_target()
                break
            end
        end
    end
    refresh_jobs()
end
-- 包列表来自 ESP/packages.json：{"packages":["sw_s3","other_c3"]}
-- 不用 f_dir（它返回带表头的多行文本，且每调一次不存在的文件底层打一条 f_open 报错）。
local function scan_packages()
    state.pkgs = {}
    state.pkg_idx = 0
    local names = {}
    local r = {pcall(f_read, PATH .. "/packages.json", 0, 1024)}
    if r[1] and type(r[3]) == "string" then
        for nm in string.gmatch(r[3], '"([^"]+)"') do
            if nm ~= "packages" then names[#names + 1] = nm end
        end
    end
    for _, n in ipairs(names) do
        local dir = PATH .. "/" .. n
        local mf = parse_manifest_file(dir .. "/manifest.json", dir)
        if mf then
            state.pkgs[#state.pkgs + 1] = {name = n, label = mf.label or n, chip = mf.chip, files = mf.files, dir = dir}
        end
    end
    if #state.pkgs > 0 then
        apply_pkg(1)
    else
        state.pkg_idx = 0
        state.jobs = {
            {name = "bootloader.bin", path = PATH .. "/bootloader.bin", offset = 0x0000},
            {name = "partition-table.bin", path = PATH .. "/partition-table.bin", offset = 0x8000},
            {name = "firmware.bin", path = PATH .. "/firmware.bin", offset = 0x10000}
        }
        local mf = parse_manifest_file(PATH .. "/manifest.json", PATH)
        if mf then state.jobs = mf.files end
        refresh_jobs()
    end
end
local function load_manifest()
    scan_packages()
end
local function cls()
    lcd_clr(C.BG)
end
local function text(x, y, s, size, fc, bc, align, w)
    lcd_disp_str(x, y, s, size or 16, fc or C.TEXT, bc or C.BG, w or SCREEN_W, align or 0)
end
local function bar(x, y, w, h, color)
    lcd_fill_rect(x, y, h, w, color)
end
local function line(x1, y1, x2, y2, color)
    lcd_draw_line(x1, y1, x2, y2, color)
end
local function chip_name()
    return CHIP_LIST[state.chip_idx]
end
local function pkg_label()
    if #state.pkgs == 0 then return "无（用ESP根目录）" end
    local p = state.pkgs[state.pkg_idx] or state.pkgs[1]
    return (p.label or p.name) .. string.format(" %d/%d", state.pkg_idx, #state.pkgs)
end
local function menu_items()
    local items = {}
    table.insert(items, {type = "pkg"})
    table.insert(items, {type = "chip"})
    table.insert(items, {type = "mode"})
    table.insert(items, {type = "baud"})
    table.insert(items, {type = "verify"})
    for i = 1, #state.jobs do
        table.insert(items, {type = "job", idx = i})
    end
    table.insert(items, {type = "flash"})
    table.insert(items, {type = "exit"})
    return items
end

local function draw_menu()
    cls()
    bar(0, 0, SCREEN_W, 20, C.TITLE_BG)
    local title = "ESP Serial Flasher"
    if state.detected then title = title .. "[" .. state.detected .. "]" end
    text(0, 2, title, 16, C.TITLE_TEXT, C.TITLE_BG, 1, SCREEN_W)
    line(0, 20, SCREEN_W - 1, 20, C.LINE)
    local items = menu_items()
    if state.sel > #items then
        state.sel = #items
    end
    if state.sel < 1 then
        state.sel = 1
    end
    local y = 26
    for i, it in ipairs(items) do
        local selected = (i == state.sel)
        local fc = selected and C.HL_TEXT or C.TEXT
        local bc = selected and C.HL or C.BG
        if it.type == "mode" then
            if selected then bar(0, y - 1, SCREEN_W, 16, C.HL) end
            text(2, y, "复位模式 : " .. (state.reset_mode == "manual" and "手动" or "自动EN+BOOT"), 16, fc, bc, 0, SCREEN_W - 2)
            y = y + 17
        elseif it.type == "pkg" then
            if selected then bar(0, y - 1, SCREEN_W, 16, C.HL) end
            text(2, y, "固件包   : " .. pkg_label(), 16, fc, bc, 0, SCREEN_W - 2)
            y = y + 17
        elseif it.type == "chip" then
            if selected then bar(0, y - 1, SCREEN_W, 16, C.HL) end
            text(2, y, "芯片型号 : " .. chip_name(), 16, fc, bc, 0, SCREEN_W - 2)
            y = y + 17
        elseif it.type == "baud" then
            if selected then bar(0, y - 1, SCREEN_W, 16, C.HL) end
            text(2, y, "波特率   : " .. BAUD_LIST[state.baud_idx], 16, fc, bc, 0, SCREEN_W - 2)
            y = y + 17
        elseif it.type == "verify" then
            if selected then bar(0, y - 1, SCREEN_W, 16, C.HL) end
            text(2, y, "烧后校验 : " .. (state.verify and "开" or "关"), 16, fc, bc, 0, SCREEN_W - 2)
            y = y + 17
        elseif it.type == "job" then
            if selected then bar(0, y - 1, SCREEN_W, 16, C.HL) end
            local j = state.jobs[it.idx]
            text(2, y, string.format("%d.", it.idx), 16, fc, bc, 0, 22)
            local n_str = j.name
            if #n_str > 18 then
                n_str = string.sub(n_str, 1, 16) .. ".."
            end
            text(24, y + 2, n_str, 12, fc, bc, 0, 110)
            local has = (j.exist and j.fsize > 0)
            local sz_s = has and string.format("%dK", math.floor(j.fsize / 1024)) or "缺"
            text(136, y + 2, sz_s, 12, has and C.OK or C.ERR, bc, 0, 40)
            text(178, y, string.format("@0x%X", j.offset), 16, fc, bc, 0, 62)
            y = y + 17
        elseif it.type == "flash" then
            local half_w = math.floor(SCREEN_W / 2)
            if selected then bar(0, y - 1, half_w, 16, C.HL) end
            text(0, y, "[ 开始烧录 ]", 16, fc, bc, 1, half_w)
        elseif it.type == "exit" then
            local half_w = math.floor(SCREEN_W / 2)
            if selected then bar(half_w, y - 1, SCREEN_W - half_w, 16, C.HL) end
            text(half_w, y, "[   退出   ]", 16, fc, bc, 1, SCREEN_W - half_w)
            y = y + 17
        end
        if y > 196 then break end
    end
    bar(0, 208, SCREEN_W, 2, C.LINE)
    if state.progress > 0 then
        bar(0, 208, math.floor(SCREEN_W * state.progress / 100), 2, C.PROG)
    end
    text(0, 212, state.status, 12, state.status_color or C.STATUS, C.BG)
    lcd_refresh()
end
function update_progress(pct, status)
    if pct ~= nil then state.progress = pct end
    state.status = status or state.status
    bar(0, 208, SCREEN_W, 2, C.LINE)
    if state.progress > 0 then
        local w = math.floor(SCREEN_W * state.progress / 100)
        if w > SCREEN_W then w = SCREEN_W end
        bar(0, 208, w, 2, C.PROG)
    end
    text(0, 212, state.status, 12, state.status_color or C.STATUS, C.BG)
    lcd_refresh()
end
local function wait_key()
    while true do
        local k = get_key()
        if k == KEY.UP or k == KEY.DOWN or k == KEY.OK or k == KEY.CANCEL or k == KEY.HOME then
            return k
        end
        delayms(20)
    end
end
local function draw_wiring()
    cls()
    bar(0, 0, SCREEN_W, 20, C.TITLE_BG)
    text(0, 2, "接线图", 16, C.TITLE_TEXT, C.TITLE_BG, 1, SCREEN_W)
    line(0, 20, SCREEN_W - 1, 20, C.LINE)
    text(2, 30, "H7-TOOL  ->  ESP", 16, C.TEXT, C.BG, 0, SCREEN_W)
    text(2, 50, "TTLTX  ->  RX", 16, C.TEXT, C.BG, 0, SCREEN_W)
    text(2, 67, "TTLRX  ->  TX", 16, C.TEXT, C.BG, 0, SCREEN_W)
    text(2, 84, "D2     ->  EN", 16, C.TEXT, C.BG, 0, SCREEN_W)
    text(2, 101, "D3     ->  IO0", 16, C.TEXT, C.BG, 0, SCREEN_W)
    text(2, 118, "TVCC   ->  VCC", 16, C.TEXT, C.BG, 0, SCREEN_W)
    text(2, 135, "GND    ->  GND", 16, C.TEXT, C.BG, 0, SCREEN_W)
    text(2, 160, "TX/RX交叉,手动模式", 12, C.GRAY, C.BG, 0, SCREEN_W)
    text(2, 176, "可不接D2/D3", 12, C.GRAY, C.BG, 0, SCREEN_W)
    text(2, 200, "C/OK返回", 16, C.TEXT, C.BG, 1, SCREEN_W)
    lcd_refresh()
    while true do
        local k = wait_key()
        if k == KEY.OK or k == KEY.CANCEL or k == KEY.HOME then break end
    end
    draw_menu()
end
local function handle_menu_key(k)
    local items = menu_items()
    if k == KEY.UP then
        state.sel = state.sel - 1
        if state.sel < 1 then
            state.sel = #items
        end
        draw_menu()
    elseif k == KEY.DOWN then
        state.sel = state.sel + 1
        if state.sel > #items then
            state.sel = 1
        end
        draw_menu()
    elseif k == KEY.OK then
        local it = items[state.sel]
        if not it then
            return
        end
        if it.type == "pkg" then
            if #state.pkgs > 0 then
                local nxt = (state.pkg_idx % #state.pkgs) + 1
                apply_pkg(nxt)
            end
            draw_menu()
        elseif it.type == "mode" then
            state.reset_mode = (state.reset_mode == "manual") and "auto" or "manual"
            draw_menu()
        elseif it.type == "chip" then
            state.chip_idx = (state.chip_idx % #CHIP_LIST) + 1
            esp.target = CHIP_LIST[state.chip_idx]
            esp:apply_target()
            draw_menu()
        elseif it.type == "baud" then
            state.baud_idx = (state.baud_idx % #BAUD_LIST) + 1
            esp.baud = BAUD_LIST[state.baud_idx]
            uart_cfg(esp.port, esp.baud, 0, 8, 1)
            draw_menu()
        elseif it.type == "verify" then
            state.verify = not state.verify
            draw_menu()
        elseif it.type == "job" then
            local j = state.jobs[it.idx]
            for i, v in ipairs(OFFSET_PRESETS) do
                if v == j.offset then
                    j.offset = OFFSET_PRESETS[(i % #OFFSET_PRESETS) + 1]
                    break
                end
            end
            draw_menu()
        elseif it.type == "flash" then
            start_flash()
        elseif it.type == "exit" then
            state.busy = true
        end
    elseif k == KEY.CANCEL then
        draw_wiring()
    elseif k == KEY.HOME then
        state.busy = true
    end
end
function start_flash()
    if #state.jobs == 0 then
        state.status = "请先添加固件"
        draw_menu()
        return
    end
    refresh_jobs()
    do
        local miss = {}
        for _, j in ipairs(state.jobs) do
            if not j.exist then miss[#miss + 1] = j.name end
        end
        if #miss > 0 then
            state.busy, state.progress = false, 0
            state.status_color = C.ERR
            state.status = "缺文件:" .. table.concat(miss, ",")
            update_progress(0, state.status)
            delayms(1500)
            draw_menu()
            return
        end
    end
    state.busy, state.progress, state.status = true, 0, "连接中..."
    state.status_color = nil
    update_progress(0, state.status)
    beep()
    local expected_chip = CHIP_LIST[state.chip_idx]
    local ok, msg =
        esp:flash_all(
        state.jobs,
        expected_chip,
        function(pct, st)
            update_progress(pct, st)
        end
    )
    state.busy = false
    if ok then
        state.status_color = C.OK
        state.status = "OK[" .. (state.detected or "?") .. "] " .. msg
        state.progress = 100
        beep()
        delayms(120)
        beep()
    else
        state.status_color = C.ERR
        state.status = "FAIL[" .. (state.detected or "?") .. "]: " .. msg
        state.progress = 0
        print("失败: " .. msg)
    end
    update_progress(state.progress, state.status)
    delayms(1500)
    draw_menu()
end
local function main()
    delayms(300)
    for i = 1, 20 do
        get_key()
        delayms(10)
    end
    clear_key()
    set_tvcc(CFG.TVCC_VOLT)
    uart_cfg(esp.port, esp.baud, 0, 8, 1)
    uart_clear_rx(esp.port)
    esp.target = CHIP_LIST[state.chip_idx]
    esp:apply_target()
    load_manifest()
    draw_menu()
    while true do
        local k = wait_key()
        handle_menu_key(k)
        if state.busy then
            break
        end
    end
    delayms(500)
    clear_key()
end
main()