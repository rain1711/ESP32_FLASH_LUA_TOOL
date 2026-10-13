# ESP32 脱机烧录 Lua（H7-TOOL）

H7-TOOL 的 ESP 系列脱机烧录小程序：把编译好的固件拷进 H7-TOOL，不用 PC，直接在 H7 屏上选包烧录。

参考上游开源：[MDLZCOOL/esp-serial-flasher-lua](https://github.com/MDLZCOOL/esp-serial-flasher-lua)（Apache-2.0）。本仓库在其基础上做优化，`up/` 目录存上游原版对照。

## 特性

- 支持 `ESP8266` / `ESP32` / `ESP32-S2` / `ESP32-S3` / `ESP32-C2` / `ESP32-C3` / `ESP32-C5` / `ESP32-C61` / `ESP32-C6` / `ESP32-H2` / `ESP32-P4`，支持 Auto 自动识别。
- ROM 模式烧录（未加载 stub）。
- **多固件包共存**：`ESP/` 下每个子目录一个包，屏上切换，不用删拷。
- **烧后 MD5 校验**：ROM `SPI_FLASH_MD5` 读回片上 + 纯 Lua MD5 算本地，逐段比对（菜单可开关）。
- 交互式 UI：选包 / 选芯片 / 换波特率 / 改偏移 / 看进度与报错。

## 硬件接线

| H7-TOOL | ESP 芯片 | 说明 |
|---------|----------|------|
| TTLTX | ESP RX | 交叉连接 |
| TTLRX | ESP TX | 交叉连接 |
| D2 | EN / RST | 复位控制 |
| D3 | GPIO0 (BOOT) | 下载模式选择 |
| TVCC | VCC | 供电，默认 3.3V |

## 固件包目录

```text
0:/H7-TOOL/Lua/ESP/
├── switchboard_s3/
│   ├── manifest.json
│   ├── bootloader.bin
│   ├── partition-table.bin
│   └── firmware.bin
└── other_c3/
    ├── manifest.json
    └── firmware.bin
```

`manifest.json` 格式：

```json
{"label": "switchboard_s3", "chip": "ESP32-S3",
 "files": [{"path": "bootloader.bin", "offset": "0x0"},
           {"path": "firmware.bin", "offset": "0x10000"}]}
```

- `files.path` 相对包目录；`offset` 十六进制字符串；`chip` 用于菜单芯片联动（可省略）。
- 无子包时回落旧行为：`ESP/` 根目录 `manifest.json` 或默认 3 段（bootloader@0x0 / partition-table@0x8000 / firmware@0x10000）。

偏移也可在屏上按段循环切换，可选值：0x00000 / 0x01000 / 0x08000 / 0x0E000 / 0x10000 / 0x100000 / 0x200000 / 0x300000 / 0x400000。

## 部署到 H7-TOOL

1. 把 `esp_serial_flasher.lua` 拷到 H7-TOOL 的 Lua 脚本目录，比如 `0:/H7-TOOL/Lua/`。
2. 按上表把固件包放到 `0:/H7-TOOL/Lua/ESP/` 下的子目录。
3. 在 H7-TOOL 上运行该 Lua 脚本。

## UI 操作

| 按键 | 作用 |
|------|------|
| ↑ | 上移光标 |
| ↓ | 下移光标 |
| OK | 执行动作/切换参数（固件包、芯片、波特率、校验开关、偏移） |
| C | 长按退出程序 |
| HOME | 退出程序 |

菜单从上到下：固件包 → 芯片型号 → 复位模式 → 波特率 → 烧后校验 → 各固件段（显示大小，缺文件显示"缺"）→ 开始烧录 / 退出。

## 复位模式（自动 / 手动）

| 模式 | 接线 | 操作 |
|------|------|------|
| 自动EN+BOOT | D2→EN，D3→GPIO0，再加串口+供电 | 点开始烧录，全自动 |
| 手动 | 只接串口+供电，D2/D3 不接 | 先手动进下载模式（BOOT拉低后按复位/重上电，接好线），再点开始烧录，直接 SYNC；烧完屏显"完成，请手动复位"再按一次复位 |

菜单"复位模式"行按 OK 切换，换板子不用改脚本。

## 故障排查

- SYNC 握手失败：检查 TX/RX 是否交叉、EN/BOOT 接线是否正确、波特率是否过高；可先降到 `115200` 再试。
- 读不到文件：确认路径正确，且 H7-TOOL 未处于 U 盘挂载模式。
- 芯片错误：确认菜单所选型号与实际硬件一致，或改回 `Auto` 让它自动识别。
- 包扫不出来：确认子目录下有 `manifest.json`；`f_dir` 返回格式异常请提 issue 附 `print` 结果。
- 校验不一致：先确认烧录过程无 SYNC 重试刷屏（信号问题），再重烧一次。

## 相对上游的改动

| # | 改动 |
|---|------|
| 2 | 多固件包共存（菜单首行切换，芯片自动联动） |
| 3 | 复位模式可选（自动EN+BOOT / 手动，适配没引复位脚的板子） |
| 4 | 每段显示文件大小，缺文件显示"缺" |
| 5 | 修 `slip_decode` 坏转义吞错；修 `send_command` 超时撑大；`uart_recive` 超时取整；修 `f_read` 多返回值 |
| 6 | 补 `FLASH_END=0x04` 命令字 |
| 7 | 编码与上游一致：GBK 无 BOM（`lcd_disp_str` 屏显中文要求） |

## 参考

- 上游开源 [MDLZCOOL/esp-serial-flasher-lua](https://github.com/MDLZCOOL/esp-serial-flasher-lua)（Apache-2.0，`up/` 存原版）
- Espressif [`esp-serial-flasher`](https://github.com/espressif/esp-serial-flasher)
- 《H7-TOOL Lua 脚本 API 手册 V1.2》
- [ROM 串口协议](https://docs.espressif.com/projects/esptool/en/latest/esp32/advanced-topics/serial-protocol.html)
