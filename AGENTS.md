# 本项目的素材使用规则

使用或实现 Wuwa Tappo 素材前，必须先阅读独立素材仓库的 [素材使用与维护规则](../wuwa-tappo-assets/AGENTS.md) 和 [使用指南](../wuwa-tappo-assets/docs/使用指南.md)。它们规定了图鉴、角色分层、配件、表情、界面和默认素材分别应使用的文件。

素材仓库未检出在相邻目录时，使用 [远端素材规则](https://github.com/lliooly/wuwa-tappo-assets/blob/main/AGENTS.md) 和 [远端使用指南](https://github.com/lliooly/wuwa-tappo-assets/blob/main/docs/使用指南.md)。以素材条目的实际路径和用途为准，不能仅凭同名文件互换素材；发现规则不明确时先核实再使用。

不要使用视觉伴侣。对于用户自己的个人仓库，除非用户强制要求，否则不要创建 worktree；如需使用 dev 分支，先提醒用户。

## 跨仓库版本同步

- 接到 [更新监控](../wuwa-scripts/wuwa-tappo-update/README.md) 的国服新版或同版本安装包变更后，核对版本、样本来源和 SHA-256，并与上一版对照素材。
- 每次都要在 [素材仓库更新日志](../wuwa-tappo-assets/changelog/README.md) 留下该版本的核对记录，即使没有新增素材。写明核对日期、样本、范围和结果，区分内置资源与公开图鉴、CDN 的核对情况。
- 有素材变动时，按素材仓库的规则同步维护文件及索引。已核对且一致时记录沿用的快照，尚未核对的范围也要写明。完成 macOS 版本更新前，确认素材日志及其索引已经同步。
