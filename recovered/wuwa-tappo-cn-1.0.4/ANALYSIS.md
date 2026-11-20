# Wuwa Tappo 国服 1.0.4 Windows 版逆向分析

2026-11-05。以项目根目录中的国服安装器为样本，以 [国服 1.0.3 恢复记录](../wuwa-tappo-cn-1.0.3/ANALYSIS.md) 为对照。本次分析覆盖静态解包、前端差异及 Windows 原生关键调用。

## 样本与恢复

| 样本 | 字节数 | SHA-256 |
| --- | ---: | --- |
| `WuwaTappo-cn_1.0.4_x64-setup.exe` | 201,758,432 | `eb4e6d2103c222297508837a5ca92eeaa058891c9f1e2e7bf034c23f37668e26` |
| `WuwaTappo/1.0.4/WuwaTappo.exe` | 78,128,864 | `ee829c55916619ea2882e4a13546cbaf2f880363237608285105c7a4958e70b3` |
| `WuwaTappo/1.0.4/uninstall.exe` | 70,745,824 | `bc44a6baacf74e226f3376b4f13027bf62885d89bf4c1e5a74f91aad2bb02b23` |

安装器在文件偏移 `0x4171c69` 包含长 `0x7c03438` 字节的 NSIS 归档。截取这段字节并在前方补 512 字节，再用 7-Zip 按 NSIS 格式读取。归档中的 `$_21_` 经 PE 文件描述和版本字段核实为桌宠主程序。安装器、主程序、卸载器的文件版本与产品版本均为 `1.0.4.0`，对应 `VS_FIXEDFILEINFO` 偏移分别为 `0xc046e48`、`0x4a5c848`、`0x4355a48`。

主程序的 Tauri 资源表从文件偏移 `0x45e8830` 开始，每条 32 字节，依次保存路径虚拟地址、路径长度、Brotli 流虚拟地址和压缩长度。按 PE 节表将虚拟地址换算为文件偏移，再按长度解压。使用连续的「路径 + Brotli 流」布局独立核对流边界与解压字节。

- [主程序前端](frontend/index.html) 共 132 项、62,949,915 字节。[资源清单](manifest.json) 记录压缩偏移、长度及解压后 SHA-256。21 个 JavaScript 文件均通过语法检查，静态识别的 324 处资源引用均能解析到本地，涉及 125 个不同目标。
- 安装器和卸载器的资源表分别位于 `0x414ce60` 与 `0x40b54f0`。两套前端均有 132 项、62,964,939 字节，每个路径的解压内容都一致。这两套发行文件留在本地 `build/tappo-cn-1.0.4-installer` 和 `build/tappo-cn-1.0.4-uninstaller`，主程序发行文件单独归档。
- 与 1.0.3 主程序对比，112 项路径和字节均相同。其余差异分布在 17 个 JavaScript、2 个 CSS 和 HTML 入口，包含 Vite 文件名与导入引用的连带变化。独立 PNG、JPEG、SVG、WOFF2 文件逐字节一致。前端中静态识别的 96 个唯一内联图片内容哈希集合也一致。此处只覆盖本地发行包中的素材。

## 前端行为变化

下表的定位词可在对应的发行文件中直接搜索。

| 范围 | 1.0.4 的行为 | 证据 |
| --- | --- | --- |
| 联机显示 | 新增「仅显示自己」，默认关闭。开启后隐藏其他成员的桌宠，禁用逐个成员的显示开关。该设置写入桌宠本地设置，房间连接和成员状态继续保留。 | `onlyShowSelf`、`set-only-show-self`。[联机面板](frontend/assets/index-BIzzuO5B.js)、[桌宠入口](frontend/assets/index-BFg5ADH5.js) |
| 房间恢复 | 创建或加入返回 `80003` 时，重新获取账号资料，使用其中的 `room_no` 恢复既有房间。恢复查询 `rm` 返回 `80007` 时清理房间状态，符合条件时显示解散提示。其他查询失败或无效快照走重连。 | `restore_existing_failed`、`rm-query-failed`、`rm-invalid-snapshot`。[桌宠入口](frontend/assets/index-BFg5ADH5.js) |
| 本地点击计数 | 点击存储从登录模块移入主入口。普通写入依次排队，仍取磁盘与待写计数的较大值。强制写入递增版本号，使较早的待写任务失效。读取等待写入队列，并检查版本号是否在读取期间发生变化。 | `keyPressPersistence`、`keyPressRevision`。[主入口](frontend/assets/index-CM6qA69G.js) |
| 计数同步 | `cr` 仍发送 `{ num }`，成功 ACK 后更新本地状态。计算上报总量时，1.0.4 在等待本地读取后重新取服务端累计值，并再次检查冻结状态。原版 `applyClickReportSuccess` 仍将本地计数置零。 | `resolveClickReportGrossTotal`、`cat-click-report-success`。[主入口](frontend/assets/index-CM6qA69G.js)、[桌宠入口](frontend/assets/index-BFg5ADH5.js) |
| 登录和续期 | 主窗口每小时调用一次续期检查，继续沿用到期不足 48 小时的阈值以及请求前续期。国服 SDK 登录失败遇到 `10002`、`10003`、`10024` 时，会延迟返回登录方式选择。登录窗口尺寸调整新增可选字段 `keepPosition`。 | `startTokenRenewalPolling`、`inlandSdkLoginProcessing`、`keepPosition`。[主入口](frontend/assets/index-CM6qA69G.js)、[登录逻辑](frontend/assets/useLogin-DsKO81zl.js)、[窗口桥接](frontend/assets/modalWindows-DBr2buyg.js) |
| 合成和桌宠提示 | 合成图鉴加载失败时可在面板内重试。游戏模式提示可以锚定在桌宠上，提示位置变化时重新计算窗口鼠标命中区域。 | `retry-synthesis-atlas`、`showPetToast`、`pet-toast-geometry-changed`。[联机及合成面板](frontend/assets/index-BIzzuO5B.js)、[主入口](frontend/assets/index-CM6qA69G.js)、[桌宠入口](frontend/assets/index-BFg5ADH5.js) |

两个版本各识别出 20 条静态 HTTP API 路径字符串，归一化前导斜杠后集合相同。对前端中符合下划线命名格式且同时出现在主程序中的 51 个字符串进行了对照，集合相同。这是桥接接口的静态线索，参数和行为需逐项判断，例如登录窗口的 `keepPosition`。

## Windows 原生证据

主程序为 x86-64 PE。用 PE 导入表定位导入地址，再用指令反汇编和 IDA Pro 伪代码交叉核对。IDA 自动分析识别了 55,774 个函数，数据库保存在本地 `WuwaTappo/1.0.4/WuwaTappo.exe.i64`。地址为样本在首选基址 `0x140000000` 下的虚拟地址。

| 函数入口或调用点 | 静态证据 |
| --- | --- |
| `0x140149a60` / `0x140149abd` | 将 `13` 传给 `SetWindowsHookExW`，回调地址 `0x140149bc0`，对应低级键盘钩子。安装后运行 Windows 消息循环，退出循环后卸载钩子。 |
| `0x140348340` / `0x140348396` | 将 `14` 传给 `SetWindowsHookExW`，回调地址 `0x1403481c0`，对应低级鼠标钩子。安装后同样运行消息循环。 |
| `0x1406f0860` / `0x1406f0a20` | 调用 `XInputGetState`，检查返回值并处理按键、扳机和摇杆数据。同一函数引用 `gamepad-button-press`。 |
| `0x1402ea6f0` | 引用 Tauri 命令名 `set_main_hit_region`。 |
| `0x14000e0f0`、`0x14023c980` | 均引用本地存储标识 `kuro-mc-keypress-store-v1`。 |

按 DLL 与具名导入组成的集合对比，从 425 项增至 427 项，新增 C 运行时数学函数 `atan2` 和 `fmod`。桌宠脚本仍调用 `set_main_hit_region`、`set_main_swallow_mouse`、`set_main_force_cursor_ignore`、`set_overlay_cursor` 等窗口接口。

## macOS 适配边界

本次将 1.0.4 保存在独立恢复目录。现有 macOS 构建仍以 1.0.3 为输入，`prepare-original.py` 按旧包文件名和精确文本应用补丁。切换输入时，登录窗口参数、点击 ACK 后保留在途新增计数的补丁，以及离线版合成和资源回退均需按新包核对。上述行为来自静态分析，尚无 1.0.4 的 Windows 运行、在线账号或联机抓包结果。
