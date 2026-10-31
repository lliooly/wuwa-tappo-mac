# macOS 原生接入与打包

用户授权：在已完成动画模块基础上接入 macOS，生成可运行包并检测输入。

采用 AppKit 原生透明无边框浮动窗口，默认 240 pt，完整画布等比例叠加头、身体与配饰。加入 Spaces 和全屏辅助窗口行为；实际《鸣潮》全屏覆盖仍需实机确认。支持拖动和菜单栏切换鼠标穿透。

沿用已有 `PetAnimation`：构建时仅移除 ES module 导出标识，将同一文件交给系统 JavaScriptCore 执行，通过主线程 Dispatch 定时器和状态回调桥接原生视图，不另写一套拍击/眨眼状态机。原生只接收动作编号，图片预先全部加载。

全局键鼠采用 CGEvent session listenOnly tap，不修改或吞掉事件。keycode 用于按下/释放去重，不提取 Unicode 或保存输入文本。鼠标按下/释放触发身体，移动不触发。修饰键按实际按下状态转为键事件。授权不足时保持待机眨眼，菜单显示未授权，用户可主动请求输入监控、打开系统设置或重试。每 2 秒检查权限，撤销后停止监听并清理输入；tap 被禁用时重启并清理遗留键；睡眠停止，唤醒重启。

应用不自动改变系统授权。权限授权需要用户完成；安全输入等系统限制可能使全局键盘事件暂时不可见，不能用模拟事件伪称真实监听通过。

包内按 catalog 和 SHA-256 校验携带默认 `role_1501_1001` 五张分层及 `accessory_1000` 佩戴图，配饰使用角色偏移，不依赖源目录或 localhost。包含素材来源说明。构建脚本调用系统 swiftc 生成 Apple Silicon、macOS 13+ 的 .app，默认 ad-hoc 签名并生成 zip。该签名适用于本地测试，未做 Developer ID 公证；提供 WUWA_SIGN_IDENTITY 供以后配置正式签名。ad-hoc 重建后的权限识别可能需要用户重新授权。

验证：现有 Node 动画测试；编译和 codesign 校验；包内素材哈希校验；原生 --smoke-test 创建窗口、加载六张图片、通过实际 JS 桥接调用键鼠入口、运行真实定时器验证眨眼。smoke-test 不请求权限，不注入系统输入。全局物理输入的验收必须在用户授权后完成；不等同于桥接自测。

当前不接登录、计数同步、手柄、换装菜单和联机，原有接口保持可扩展。不创建 worktree 或 dev 分支。

API 依据：[Apple 只读监听选项](https://developer.apple.com/documentation/coregraphics/cgeventtapoptions/listenonly)、[Apple 事件 tap](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:))。

## 验证记录

- Apple Silicon 编译成功，codesign --verify --strict 通过，zip 包结构及六张图片与素材仓库哈希一致。
- 8 项 Node 动画/素材测试全部通过。
- 原生 --smoke-test 通过：创建实际原生窗口、加载图片、键盘按下/释放及去重、鼠标交替、真实定时器闭眼/睁眼。
- 原生 --check-input 检测到当前进程可启动输入监听，10 秒采样收到 keyboard events=0、mouse events=10。鼠标为实际全局事件，未注入系统输入。期间未收到真实键盘事件，不能据此宣称真实键盘验收通过。
- 未验证实际《鸣潮》原生全屏场景。未自动更改系统授权。
