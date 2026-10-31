# 第三方代码、素材与许可

本项目不是一个所有内容均适用 MIT 的资源包。根目录 [LICENSE](LICENSE) 仅授权本项目原创部分。

| 范围 | 来源与许可边界 |
| --- | --- |
| `native/`、`original-adapter/`、`src/`、`panel/`、`preview/`、脚本、测试及原创文档 | 本项目自行编写的适配与工具代码适用 MIT；不包括其中引用或嵌入的上游内容。 |
| `recovered/wuwa-tappo-cn-1.0.2/` | 从官方 CN 1.0.2 发行文件恢复的前端、SDK 与安装器资料，保留原始权利；不是官方开源源码，也不由本项目授予再分发权。 |
| `assets/`、相邻 `wuwa-tappo-assets` 中的游戏图片与数据 | 官方客户端及公开接口的归档；按用途保留符号链接、来源与哈希，不授予新的开放许可。 |
| `docs/images/` | 现有发行图标与本项目真实运行截图；包含上游美术及界面，不属于原创代码的 MIT 授权。 |
| 第三方字体与打包进原版前端的库 | 适用各自原始许可与版权声明，见下文。 |

## 原版第三方清单

原客户端携带的 [开源声明数据](recovered/wuwa-tappo-cn-1.0.2/frontend/assets/ossNoticeData-BO8f3UDL.js) 保留完整；应用的「开源声明」页面继续展示它。其中包含 Vue、Pinia、Vue Router、Vue I18n、Axios、Socket.IO、Tauri 等项目的声明与许可文本。

这份清单描述原始 Windows 客户端的声明，包含 Rust、Windows 和构建工具条目，不能据此认为 macOS 适配仍使用其原生运行库。当前 macOS 宿主由 Swift 与系统框架构建，不使用 Cargo 或 npm 安装这些原生组件。依赖层次见 [开发指南](docs/开发指南.md)。

恢复包中库的准确组成、漏洞情况与完整再分发条件尚未进行独立审计；无 npm 安装依赖不等于原版打包代码没有第三方依赖或安全风险。

## 字体

保留相邻素材库的 [字体许可核对](https://github.com/lliooly/wuwa-tappo-assets/blob/6fd82980bb8f193e88bfa21c15cbc5b6cae66f48/docs/字体授权.md) 及 [字体原始名称记录](https://github.com/lliooly/wuwa-tappo-assets/blob/6fd82980bb8f193e88bfa21c15cbc5b6cae66f48/data/来源快照/font-name-records.json)。

- `975MaruSC`、`GenSenRounded`／`GenSenRoundedJP`、`Prompt`：原字体字段注明 SIL OFL 1.1。
- `NanumGothic`：原客户端声明为 SIL OFL 1.1，具体文件版权信息仍须一并保留。
- 本快照中的两个 `SourceHanSansCN` 文件：字体字段注明 Apache-2.0，应以具体文件为准。

许可全文保存在 [OFL-1.1](LICENSES/OFL-1.1.txt) 和 [Apache-2.0](LICENSES/Apache-2.0.txt)。构建脚本会把字体名称记录、两份字体许可文本、版权说明及本项目许可／免责声明复制进应用资源；后续修改打包范围时仍需逐项核对许可和随包材料。此项补充随之后的新构建生效，之前的本机 build 7 包不会被自动替换。

## 来源证据

- [恢复清单与哈希](recovered/wuwa-tappo-cn-1.0.2/manifest.json)
- [素材目录说明](assets/README.md)
- [素材来源及权利说明](https://github.com/lliooly/wuwa-tappo-assets/blob/6fd82980bb8f193e88bfa21c15cbc5b6cae66f48/docs/版权与来源.md)
- [本项目非官方声明](DISCLAIMER.md)

本文件只整理已知来源与声明，不将官方软件或美术重新授权，也不代替各项许可原文。
