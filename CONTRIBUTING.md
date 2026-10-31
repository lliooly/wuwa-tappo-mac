# 贡献指南

修改前请阅读 [开发指南](docs/开发指南.md)。涉及素材时，遵守 [素材规则](AGENTS.md)。

默认界面来自恢复的 Windows 前端，macOS 适配放在 `original-adapter/` 和 `native/`。保留 `recovered/` 原档；前端补丁统一写入 `scripts/prepare-original.py`，同时记录匹配条件和补丁用途。

提交信息使用 Conventional Commits，说明用中文，例如 `fix(输入): 避免面板点击重复计数`。一次提交解决一个问题。

验证命令见 [检查层次](docs/开发指南.md#检查层次)。文档修改检查链接与示例；代码修改运行受影响的测试，发布前执行完整构建和独立运行检查。

新增依赖时说明用途及许可。GitHub Actions 和 Python 工具依赖由 Dependabot 每周检查；更新 PR 通过 CI 后再合并。原版打包前端的第三方库随上游版本维护。

问题反馈请附应用版本、macOS 版本和复现步骤。安全问题见 [安全报告](SECURITY.md)。
