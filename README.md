# ESP32 脱机烧录 Lua（H7-TOOL）

H7-TOOL 的 ESP 系列脱机烧录小程序：把编译好的固件拷进 H7-TOOL，不用 PC，直接在 H7 屏上选包烧录。

参考上游开源：[MDLZCOOL/esp-serial-flasher-lua](https://github.com/MDLZCOOL/esp-serial-flasher-lua)（Apache-2.0）。本仓库在其基础上做优化，`up/` 目录存上游原版对照。

## 特性

- 支持 `ESP8266` / `ESP32` / `ESP32-S2` / `ESP32-S3` / `ESP32-C2` / `ESP32-C3` / `ESP32-C5` / `ESP32-C61` / `ESP32-C6` / `ESP32-H2` / `ESP32-P4`，Auto 自动识别（标题栏常显实际型号）。
- ROM 模式烧录（未加载 stub），单文件 < 32KB（H7 加载上限）。
- **多固件包共存**：`ESP/` 下每个子目录一个包，屏上切换，不用删拷。
- **烧后 MD5 校验**：ROM `SPI_FLASH_MD5` 读回片上 + 纯 Lua MD5 算本地，逐段比对（菜单可开关）。
- **复位模式可选**：自动 EN+BOOT / 手动（只接串口的板子）。
- 红绿状态：段大小绿色、缺文件红色；成功/失败状态行着色。

## 硬件接线

| H7-TOOL | ESP 芯片 | 说明 |
|---------|----------|------|
| TTLTX | ESP RX | 交叉连接 |
| TTLRX | ESP TX | 交叉连接 |
| D2 | EN / RST | 复位控制（手动模式可不接） |
| D3 | GPIO0 (BOOT) | 下载模式选择（手动模式可不接） |
| TVCC | VCC | 供电，默认 3.3V |

屏上短按 C 可看接线图。

## 固件包目录

```text
0:/H7-TOOL/Lua/ESP/
├── packages.json          ← 包注册表 {"packages": ["BC1-board", ...]}
└── BC1-board/             ← 包目录名即板子名
    ├── manifest.json
    ├── bootloader.bin
    ├── partition-table.bin
    └── firmware.bin
```

`ESP/packages.json`（必须，多包选包依据）：

```json
{"packages": ["BC1-board"]}
```

`manifest.json`（包内段表）：

```json
{"label": "BC1-board", "chip": "ESP32-S3",
 "files": [{"path": "bootloader.bin", "offset": "0x0"},
           {"path": "partition-table.bin", "offset": "0x8000"},
           {"path": "firmware.bin", "offset": "0x10000"}]}
```

- `files.path` 相对包目录；`offset` 以 `build/flasher_args.json` 为准，十六进制字符串；`chip` 用标准名，用于菜单联动（可省略）。
- 无 `packages.json` 时回落旧行为：`ESP/` 根目录 `manifest.json` 或默认 3 段。
- 偏移也可在屏上按段循环切换，可选值：0x00000 / 0x01000 / 0x08000 / 0x0E000 / 0x10000 / 0x100000 / 0x200000 / 0x300000 / 0x400000。

## 部署到 H7-TOOL

1. 把 `esp_serial_flasher.lua` 拷到 `0:/H7-TOOL/Lua/`（核对大小，当前版 31280 字节）。
2. `ESP/` 下建包目录，放 bin + `manifest.json`；`ESP/` 下放 `packages.json`。
3. 在 H7-TOOL 上运行该脚本。

## UI 操作

| 按键 | 作用 |
|------|------|
| ↑ | 上移光标 |
| ↓ | 下移光标 |
| OK | 执行动作/切换参数（固件包、芯片、复位模式、波特率、校验开关、偏移） |
| C | 短按看接线图，长按退出程序 |
| HOME | 退出程序 |

菜单从上到下：固件包 → 芯片型号 → 复位模式 → 波特率 → 烧后校验 → 各固件段（绿色大小 / 红色"缺"）→ 开始烧录 / 退出。

## 复位模式（自动 / 手动）

| 模式 | 接线 | 操作 |
|------|------|------|
| 自动EN+BOOT | D2→EN，D3→GPIO0，再加串口+供电 | 点开始烧录，全自动 |
| 手动 | 只接串口+供电，D2/D3 不接 | 先手动进下载模式（BOOT拉低后按复位/重上电，接好线），再点开始烧录，直接 SYNC；烧完屏显"完成，请手动复位"再按一次复位 |

菜单"复位模式"行按 OK 切换，换板子不用改脚本。

## 故障排查

- 脚本打不开 / 报 `near <eof>`：文件没拷全，核对大小（须与仓库一致）。
- SYNC 握手失败：检查 TX/RX 是否交叉、EN/BOOT 接线是否正确、波特率是否过高；先降到 `115200` 再试。
- 点烧录提示 `缺文件:xxx`：包目录下 bin 没放全，对照 manifest 检查。
- 芯片错误：菜单所选与实际不一致（`期望[S3]实际[C3]`），或改回 `Auto`。
- 包选不到：确认 `ESP/packages.json` 存在且包名拼写一致，包内有 `manifest.json`。
- 校验不一致：确认烧录无 SYNC 重试刷屏，重烧一次。
- `f_open` 报错：缺文件时的底层提示，放好包后消失；持续刷屏请提 issue。

## 固件打包提示词（发给 AI 用）

```markdown
# 指令：为 H7-TOOL Lua 烧录脚本打包 ESP32 固件

烧录脚本用法（先读）：https://github.com/rain1711/ESP32_FLASH_LUA_TOOL

## 输入

- 工程源码路径：（填）
- 目标芯片：（填，如 ESP32-S3）
- 包名/板子名：（填，须唯一，如 BC1-board）

## 输出

zip 包，解压后与现有 `ESP/` 合并（新增包目录 + 更新 `packages.json`）。

## 步骤

1. 编译（ESP-IDF：`idf.py set-target <芯片> && idf.py build`；Arduino：编译导出 bin）。
2. 打开 `build/flasher_args.json`，抄下 bootloader / partition-table / app 三个 bin 的烧录地址（不要凭记忆）。
3. 建目录 `<包名>/`，拷入 3 个 bin。
4. 写 `<包名>/manifest.json`：
   ```json
   {"label": "<包名>", "chip": "<标准名>",
    "files": [{"path": "xxx.bin", "offset": "0x..."}]}
   ```
   `chip` 只能用：ESP32 / ESP32-S2 / ESP32-S3 / ESP32-C3 / ESP32-C2 / ESP32-C6 / ESP32-H2 / ESP32-C5 / ESP32-C61 / ESP32-P4 / ESP8266。
5. 更新 `packages.json`（追加，不要覆盖已有包）：
   ```json
   {"packages": ["SwitchBoard", "<新包名>"]}
   ```
6. zip 打包（`<包名>/` + 更新后的 `packages.json`），列出包名、芯片、各文件地址+大小供核对。

## 约束

- 只输出固件包，不改烧录脚本；bin 不进 git。
- 包名必须唯一；`packages.json` 必须保留已有包。
```

## 相对上游的改动

| # | 改动 |
|---|------|
| 1 | 烧后 MD5 校验（ROM `SPI_FLASH_MD5=0x13` + 纯 Lua MD5，手册无 md5 API，菜单可开关） |
| 2 | 多固件包共存（`packages.json` 注册 + 菜单切换 + 芯片自动联动） |
| 3 | 复位模式可选（自动EN+BOOT / 手动）；标题栏常显实际型号 |
| 4 | 缺文件缓存（启动一次性探测，缺包直接拦停不空跑 SYNC）；红绿状态着色；C 键接线图 |
| 5 | 瘦身 < 32KB（H7 单文件加载上限）：去注释/空行/调试打印、缩短文案，功能无损 |
| 6 | 修 `slip_decode` 坏转义吞错；修 `send_command` 超时撑大；`uart_recive` 超时取整；修 `f_read` 多返回值 |
| 7 | 补 `FLASH_END=0x04` 命令字 |
| 8 | 编码与上游一致：GBK 无 BOM（`lcd_disp_str` 屏显中文要求） |

## 参考

- 上游开源 [MDLZCOOL/esp-serial-flasher-lua](https://github.com/MDLZCOOL/esp-serial-flasher-lua)（Apache-2.0，`up/` 存原版）
- Espressif [`esp-serial-flasher`](https://github.com/espressif/esp-serial-flasher)
- 《H7-TOOL Lua 脚本 API 手册 V1.2》
- [ROM 串口协议](https://docs.espressif.com/projects/esptool/en/latest/esp32/advanced-topics/serial-protocol.html)
