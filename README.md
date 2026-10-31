<div align="center">
  <img src="docs/images/app-icon.png" alt="Wuwa Tappo" width="96" height="96">
  <h1>Wuwa Tappo · macOS</h1>
  <p>鸣潮桌宠的非官方 Mac 适配</p>
  <p>
    <img src="https://img.shields.io/badge/macOS-13%2B-555555?style=flat-square" alt="macOS 13 及以上">
    <img src="https://img.shields.io/badge/Apple_Silicon-arm64-555555?style=flat-square" alt="Apple Silicon">
    <img src="https://img.shields.io/badge/version-1.0.3-926044?style=flat-square" alt="版本 1.0.3">
    <a href="LICENSE"><img src="https://img.shields.io/badge/code-MIT-926044?style=flat-square" alt="原创代码采用 MIT"></a>
  </p>
  <p><a href="https://github.com/lliooly/wuwa-tappo-mac/releases/latest">下载安装包</a> · <a href="#使用说明">使用说明</a> · <a href="docs/开发指南.md">开发指南</a></p>
</div>

让共鸣者待在 Mac 桌面上，跟着键盘、鼠标和手柄的操作拍桌子。保留 Windows CN 版的界面，支持登录、换装、开箱、合成、兑换和好友联机。

当前源码版本为 **1.0.3**，与所用 Windows CN 前端版本一致。

<p align="center">
  <img src="docs/images/backpack.png" alt="Mac 上的背包界面" width="900">
</p>

<p align="center">
  <img src="docs/images/settings.png" alt="Mac 上的设置界面" width="900">
</p>


## 安装

需要 **Apple Silicon Mac、macOS 13 或更新版本**。

从 [Releases](https://github.com/lliooly/wuwa-tappo-mac/releases/latest) 下载 arm64 压缩包，解压后将 `Wuwa Tappo.app` 拖入「应用程序」。

安装包未经过 Apple 公证。若系统拦截，请先尝试打开一次，再到「系统设置 → 隐私与安全性」中选择「仍要打开」。

## 使用说明

首次启动，从菜单栏的桌宠图标选择「授权输入监控…」，在「系统设置 → 隐私与安全性 → 输入监控」中启用 Wuwa Tappo，然后回到应用选择「重试监听」。系统要求重启时，退出后重新打开应用。

输入监控只用于动作和计数，不记录输入文字。账号会话保存在系统钥匙串；重新签名后，系统可能要求重新授权。Mac 版通过 Releases 更新。

## 从源码构建

需要 Xcode Command Line Tools、Python 3.9+ 和 Git。将应用与素材仓库放在同一父目录：

```sh
git clone https://github.com/lliooly/wuwa-tappo-assets.git
git -C wuwa-tappo-assets checkout 478ae2fdf4f1308189df87a5b249cd0deb1dfb64
git clone https://github.com/lliooly/wuwa-tappo-mac.git
cd wuwa-tappo-mac
python3 scripts/build-macos.py
open 'dist/Wuwa Tappo.app'
```

产物为 `dist/Wuwa Tappo.app` 和 `dist/Wuwa-Tappo-mac-arm64.zip`。运行测试另需 Node.js 22+，无需 `npm install`。

目录结构、测试、签名和调试命令见 [开发指南](docs/开发指南.md)。选用素材前请阅读素材库的 [使用指南](https://github.com/lliooly/wuwa-tappo-assets/blob/478ae2fdf4f1308189df87a5b249cd0deb1dfb64/docs/使用指南.md)。

## 项目文档

- [更新记录](CHANGELOG.md)
- [贡献指南](CONTRIBUTING.md)
- [验收记录](docs/最终验收结果.md)与[在线功能记录](docs/在线功能验收.md)
- [宝箱与屏幕切换规则](docs/宝箱与跨屏原版逻辑.md)
- [联网接口索引](docs/原版联网业务索引.md)
- [历史设计记录](docs/superpowers/specs/README.md)

## 致谢

- [Wuwa Tappo（CN 国服）](https://download-mc-wuwatappo.kurogames-global.com/download/)：原版桌宠及其角色美术与界面。
- [wuwa-tappo-assets](https://github.com/lliooly/wuwa-tappo-assets)：整理本项目使用的角色、配件、表情、界面和字体素材，保留来源与校验信息。
- Vue、Pinia、Socket.IO 等开源项目：支撑原版前端与联机功能，完整清单见 [第三方说明](THIRD_PARTY_NOTICES.md)。

## 许可

本项目与库洛游戏无官方关联。原创适配代码与文档采用 [MIT](LICENSE)；官方前端、角色美术、字体和商标保留各自权利，详见 [第三方说明](THIRD_PARTY_NOTICES.md) 和 [非官方声明](DISCLAIMER.md)。
