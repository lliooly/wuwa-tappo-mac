# Wuwa Tappo 1.0.2 Windows 版分析

分析日期：2026-10-30。样本为 `WuwaTappo/WuwaTappo.exe`，SHA-256 为 `cedc37d0c11d112f4d933647fb6cf00e1dca847fc763250984c647080f849080`。

后续素材排查已补充恢复程序中内联的图片、Windows 原生图标，以及官方公开图鉴和素材索引中的 3,098 张图片；其中包含未在账号中解锁的外观素材。具体范围、中文目录和核验方法见 [美术素材归档](../../assets/README.md)。下文关于仅有默认素材的描述保留为首次分析时的结论。

## 已恢复的内容

`frontend/` 是从可执行文件的 Tauri 资源索引中解压的前端发行文件，共 132 项，合计 62,931,240 字节。包括 21 个 JavaScript 文件、9 个 CSS 文件、83 张 PNG、3 张 JPEG、12 个 WOFF2 字体、2 个 SVG、1 个 HTML 和 1 个 TypeScript 声明文件。`manifest.json` 保存每个资源在原文件中的压缩位置、长度和解压后 SHA-256。

资源索引中的 132 项均已按其记录的压缩长度解压，提取结果与独立的连续流扫描结果逐项一致；保存后重新计算的大小和 SHA-256 均与清单一致。21 个 JavaScript 文件均通过语法检查。对 HTML、CSS 和 JavaScript 中可静态识别的一部分相对资源引用进行了检查，73 个引用目标均存在。动态生成的路径和远端资源不在这一检查的覆盖范围内。

前端是已经打包、压缩的 Vue 构建产物，不是原始 Vue 单文件组件或原始工程。图片、字体和这套前端构建产物可以作为后续适配的输入，但其能否完整运行仍取决于原生接口和远端服务。

## IDA Pro 观察

IDA 将样本识别为 x86-64 Windows PE，可执行代码以 Rust/Tauri 2 为基础。数据库包含约 55,500 个函数，绝大多数已去符号；因此下面的函数名是 IDA 自动生成的标识，而不是原始源码名称。已保存的数据库位于 `WuwaTappo/WuwaTappo.exe.i64`。

| 位置 | 静态分析结果 |
| --- | --- |
| `0x140004CF0` | 调用 `SetWindowsHookExW(14, …)` 安装低级鼠标钩子，并运行 Windows 消息循环。 |
| `0x140186DD0` | 调用 `SetWindowsHookExW(13, …)` 安装低级键盘钩子，并运行 Windows 消息循环。 |
| `0x140014AF0` | 引用 `key-press`、`key-release`、`mouse-button`、`global-clap-mouse` 等事件，并检查前台窗口等状态。 |
| `0x1404EEBA0` | 轮询 `XInputGetState`，包含方向键、按键和扳机相关名称，并引用 `gamepad-button-press`。 |
| `0x14001D0A0` | 包含 WebView 强制忽略鼠标的穿透状态及相关日志。 |
| `0x1405D1260` | 与 `set_shortcut_capture`、`set_app_shortcuts` 等 Tauri 命令的分发相关。 |

前端还调用 `set_main_hit_region`、`set_main_swallow_mouse`、`set_overlay_cursor`、`set_main_force_cursor_ignore` 等自定义命令。它将自身的可交互区域传给原生端，再配合鼠标穿透和事件路由工作，不能只把 HTML 放进一个普通 WebView 就视为移植完成。

现有证据表明桌宠与全局键鼠、手柄输入及前台窗口状态有关；静态分析尚未发现需要读取游戏进程内存的证据，这并不能排除其他间接调用或运行时行为。

## 主要功能和依赖

从已恢复的界面文案、路由和代码可见桌宠、宝箱、背包、图鉴、合成、联机、设置、登录和更新等功能。应用包含本地默认角色与表情素材，也有使用 CDN 地址获取角色、配件等资源的路径。登录 SDK、服务端 API 和 Socket.IO 联机逻辑存在远端依赖，尚未进行登录或联机实测。

## 本地数据与服务端数据

- 键盘、鼠标和手柄事件在客户端处理，前端维护 `localClickCount`，并通过 `load_key_press_count`、`save_key_press_count` 读取和保存本地计数。IDA 的相关代码引用了本地存储标识 `kuro-mc-keypress-store-v1`。未登录时的计数计算分支使用本地数值。
- 登录后，用户资料包含服务端的 `total_click_count` 和 `total_click_consume`；前端还会按账号及环境恢复本地累计数据，计算待同步的数量。Socket.IO 连接建立且已登录时，代码发送 `cr` 事件，载荷中有汇总数值 `num`，并包含约 30 秒的重试或定时同步逻辑。登出和打开宝箱的请求也会携带计数。这里只确认这些代码路径，未抓包验证实际传输行为。
- 登录和用户资料、图鉴、背包、合成、外观预设、创建或加入房间、开启宝箱等均有对应的远端 API；房间状态和事件另外使用 Socket.IO。部分角色及配件资源会从服务端返回的素材地址获取。本地已有的默认素材不等于服务端资源全集。
- 恢复的客户端还包含事件诊断和 SDK 日志上报代码。静态代码存在这些路径并不证明它们在所有状态下都会执行，也不足以完整说明所有上报内容。

当前拿到的是客户端程序和前端发行文件，并非服务端源码。能否复用官方账号、跨平台同步计数、领取同一份奖励并进入原版房间，取决于官方服务端和登录 SDK 对 macOS 客户端的实际响应，尚未验证。

Windows 原生后端不能直接在 macOS 执行；Rust 反编译伪代码也不是可直接重新编译的源码。快捷键、全局事件、手柄、透明窗口、鼠标命中区域、显示器切换和全屏检测等需要建立 macOS 版本，并与现有前端的命令及事件协议对接。

macOS 的 [NSWindow 全屏辅助窗口行为](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/fullscreenauxiliary)可作为全屏空间适配的起点；[CGEvent 事件监听](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate%28tap%3Aplace%3Aoptions%3Aeventsofinterest%3Acallback%3Auserinfo%3A%29)涉及系统授权；[Game Controller 后台事件设置](https://developer.apple.com/documentation/gamecontroller/gccontroller/shouldmonitorbackgroundevents)需要单独考虑。是否能在目标机器的原生《鸣潮》全屏状态下正确覆盖、交互和接收输入，必须在实际游戏中验证。

当前尚未创建 macOS 工程，也未运行前端、访问账号服务或验证游戏联动。
