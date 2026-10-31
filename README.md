<div align="center">
  <img src="docs/images/app-icon.png" alt="Wuwa Tappo 原发行包图标" width="96" height="96">
  <h1>Wuwa Tappo · macOS</h1>
  <p><strong>让 Wuwa Tappo 在 Mac 桌面上响应你的每一次敲击。</strong></p>
  <p>非官方 macOS 适配 · 复用原版 Vue 界面 · Swift 原生系统集成</p>
  <p>
    <img src="https://img.shields.io/badge/macOS-13%2B-555555?style=flat-square" alt="macOS 13 及以上">
    <img src="https://img.shields.io/badge/architecture-arm64-555555?style=flat-square" alt="Apple Silicon arm64">
    <img src="https://img.shields.io/badge/version-0.2.0-926044?style=flat-square" alt="版本 0.2.0">
    <a href="LICENSE"><img src="https://img.shields.io/badge/original_code-MIT-926044?style=flat-square" alt="原创适配代码采用 MIT"></a>
  </p>
  <p>
    <a href="#快速开始">快速开始</a> ·
    <a href="#功能与范围">功能</a> ·
    <a href="#使用与设置">使用说明</a> ·
    <a href="#文档与开发">开发文档</a> ·
    <a href="#许可与声明">许可与声明</a>
  </p>
</div>

---

这是面向 Apple Silicon Mac 的 **Wuwa Tappo 非官方适配**。项目托管从 Windows CN 1.0.2 发行包恢复的 Vue/CSS 前端，通过 AppKit、WKWebView 和独立兼容层接入 macOS，保留原版桌宠动作、面板和本地交互。

离线基线为 **0.2.0（build 7）**，已完成约定的未登录功能与系统交互验收，详见 [验收报告](docs/最终验收结果.md)。当前 main 正在接入官方在线业务，登录、账号读取、换装、计数同步和单人房间创建已有实测，完整范围见 [在线接入记录](docs/superpowers/specs/2026-10-31-online-services.md)。仓库目前私有，尚未提供 GitHub Release 下载；可按下文从源码构建。

> 本项目与库洛游戏无官方关联。MIT 仅适用于原创适配代码与文档，官方恢复前端、游戏素材、字体和商标保留各自权利。使用前请阅读 [非官方声明](DISCLAIMER.md) 和 [第三方说明](THIRD_PARTY_NOTICES.md)。

## 预览

<p align="center">
  <img src="docs/images/backpack.png" alt="macOS 实际运行的原版背包：角色预览、表情槽和物品分类" width="900">
</p>

<details>
<summary>查看原版设置页面</summary>

<p align="center">
  <img src="docs/images/settings.png" alt="macOS 实际运行的原版设置页面" width="900">
</p>

</details>

图像来自当前应用的实际运行导出，未使用概念稿。图标沿用原发行包资源，权利归原权利人。

## 功能与范围

| 功能 | 当前支持 |
| --- | --- |
| 桌面陪伴 | 原版头身分层、交替拍击、独立眨眼、配件偏移与表情气泡。 |
| 输入响应 | 全局键盘、鼠标和手柄输入；重复过滤、计数持久化及睡眠唤醒恢复。 |
| 背包与图鉴 | 原版分类动画、换装与五个表情槽；12 个默认物品、899 条公开图鉴快照。 |
| 原生交互 | 桌宠拖动、透明区域点击穿透、点击保留其他应用输入焦点、大面板边缘缩放。 |
| 本地设置 | 大小、透明度、快捷键、菜单栏、Dock 图标、开机启动、切换屏幕及全屏自动游戏模式。 |
| 离线运行 | 独立 `.app` 内置运行资源，不依赖 Node.js、Python、本地服务或相邻素材库。 |

**在线功能正在验收。** 已恢复官方 CN 通行证 SDK、业务会话保存与重启恢复、真实背包、收藏、换装、预设创建、在线图鉴、点击上报和房间创建。Socket.IO 继续使用原版业务逻辑，通过 macOS 原生 WebSocket 传输。跨账号动作／表情互通、房间退出及加入、真实开箱／合成／兑换和异常恢复仍需对应运行证据。UID 登录保留原版实现，尚未另发验证码实测。公开素材不等于账号已解锁。主程序遥测和 Windows 更新器保持禁用，SDK 已识别的分析上报由网络规则阻止。

## 快速开始

### 环境要求

| 用途 | 要求 |
| --- | --- |
| 运行应用 | Apple Silicon Mac，macOS 13 或更高版本。当前不提供 Intel 包。 |
| 从源码构建 | 上述环境、Xcode Command Line Tools 或完整 Xcode、Python 3.9+、Git、相邻素材库。 |
| 执行测试 | Node.js 22+；完整测试还需要先构建 `.app`。无 npm 第三方安装依赖。 |

### 构建并启动

将两个仓库检出到**同一父目录**。当前仓库私有，克隆需要相应访问权限：

```sh
git clone https://github.com/lliooly/wuwa-tappo-assets.git
git -C wuwa-tappo-assets checkout 6fd82980bb8f193e88bfa21c15cbc5b6cae66f48
git clone https://github.com/lliooly/wuwa-tappo-mac.git
cd wuwa-tappo-mac

python3 scripts/build-macos.py
open 'dist/Wuwa Tappo.app'
```

素材库固定到已验证提交；不要随意用同名图片替换分层或图鉴资源。构建前请阅读其 [素材规则](https://github.com/lliooly/wuwa-tappo-assets/blob/6fd82980bb8f193e88bfa21c15cbc5b6cae66f48/AGENTS.md) 与 [使用指南](https://github.com/lliooly/wuwa-tappo-assets/blob/6fd82980bb8f193e88bfa21c15cbc5b6cae66f48/docs/使用指南.md)。

构建生成 `dist/Wuwa Tappo.app` 和 `dist/Wuwa-Tappo-mac-arm64.zip`。安装后可将 `.app` 放入「应用程序」再运行，日常使用无需保留源码。已有 Node.js 时，`npm run build:macos` 等价于上面的 Python 构建命令；无需执行 `npm install`。

当前默认使用 **ad-hoc 本地签名，未做 Developer ID 公证**。开发者可通过 `WUWA_SIGN_IDENTITY` 指定本机已有签名身份，见 [开发指南](docs/开发指南.md)。

### 授权输入监控

1. 启动后，从「团团」菜单栏入口选择「授权输入监控…」。
2. 在「系统设置 → 隐私与安全性 → 输入监控」中启用当前 Wuwa Tappo 应用。
3. 返回应用点击「重试监听」；若系统要求，退出后重新启动。

菜单显示「正在监听键鼠」后，可在其他应用输入或点击验证动作与计数。输入监听不提取或保存文字；系统安全输入可能暂时阻止键盘监听。未授权时，玩偶仍会眨眼。

## 使用与设置

- **打开面板**：点击玩偶信息条右侧菜单，或使用菜单栏入口，进入背包、图鉴、合成、联机与设置。
- **调整外观**：在背包中选择角色、配件与表情；大小和透明度在设置中调整。
- **移动与缩放**：拖动玩偶可在当前屏幕内移动；桌宠通过设置缩放，大面板支持边缘缩放。
- **切换屏幕**：使用设置中的切屏按钮或默认 F10；部分键盘需按 Fn+F10。原版拖动规则不允许直接拖过屏幕边缘。
- **宝箱入口**：未登录时显示两个登录入口，不代表已获得两份奖励；本地点击不会扣除字符或发放物品。规则见 [宝箱与跨屏逻辑](docs/宝箱与跨屏原版逻辑.md)。

<details>
<summary>权限、数据与常见问题</summary>

- **重新打包后无响应**：ad-hoc 重签可能使原授权失效；移除旧的输入监控条目，再添加当前 `.app`。以应用包的授权结果为准，不要用终端直接运行可执行文件代替。
- **计数与设置**：保存在本机偏好及 WebKit 存储中；待同步点击与账号累计记录分开，业务登录会话存于 Keychain。应用标识为 `io.lliooly.wuwa-tappo.mac`；日志位于 `~/Library/Logs/Wuwa Tappo/`。
- **开机启动**：在设置中开启，macOS 如提示后台项目审批，需要在系统设置中允许。
- **离线启动**：通过 `open -n 'dist/Wuwa Tappo.app' --args --offline` 显式离线；离线不读取生产登录会话。
- **登录提示钥匙串访问**：自定义协议无法保存原版 Secure Cookie，业务会话使用 Keychain。开发时优先沿用同一签名；重签后可能需要用户允许当前应用读取已有会话，不必反复发送验证码。

</details>

## 文档与开发

| 文档 | 内容 |
| --- | --- |
| [开发指南](docs/开发指南.md) | 目录结构、依赖、构建、检查、签名与旧实现预览。 |
| [原版移植规格](docs/superpowers/specs/2026-10-31-original-frontend-port.md) | 默认前端的移植边界、兼容层与实现记录。 |
| [动画规格](docs/superpowers/specs/2026-10-30-animation-design.md) | 原版动作来源、时序及图层规则。 |
| [最终验收结果](docs/最终验收结果.md) | build 7 的检查范围与实际系统验收记录。 |
| [在线功能验收](docs/在线功能验收.md) | 当前 main 的账号／联机实际结果与待验收范围。 |
| [宝箱与跨屏逻辑](docs/宝箱与跨屏原版逻辑.md) | 原版规则、未登录入口与验证依据。 |
| [更新记录](CHANGELOG.md) | 当前已交付版本。 |

核心结构：`recovered/` 原档 → `prepare-original.py` 生成构建副本 → `original-adapter/` 兼容层 → `native/` 系统宿主。原档保持不变，适配补丁及源哈希写入包内 `adapter-manifest.json`。前期手写页面仅以 `--legacy-ui` 回退保留。

本地完整检查（先完成构建）：

```sh
npm test
python3 scripts/verify-original-port.py
python3 scripts/verify-package.py
python3 scripts/verify-standalone.py
```

最后一项会启动隔离偏好的临时应用并导出原版页面；系统权限、手柄、双屏、睡眠及自动启动仍需真实 Mac 验收。CI 仅覆盖仓库静态检查与基础动画测试，不代替这些系统检查。

## 参与维护

请先阅读 [贡献指南](CONTRIBUTING.md)。提交按 `feat`、`fix`、`test`、`docs`、`chore` 等类型拆分，避免混入生成文件、原始 Windows 二进制、个人数据或签名材料。敏感问题按 [安全报告说明](SECURITY.md) 处理。

## 许可与声明

原创适配代码与文档采用 [MIT](LICENSE)。恢复的官方前端、游戏美术、字体、标识和截图中的上游内容不在此授权范围内；完整来源与许可边界见 [第三方声明](THIRD_PARTY_NOTICES.md) 和 [非官方声明](DISCLAIMER.md)。

感谢 Wuwa Tappo 及相关上游项目。仓库私有并不构成官方软件或素材的再分发授权，公开发布前仍需核实权利和许可条件。
