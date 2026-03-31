# FnVoiceInput

一个 macOS 14+ 菜单栏语音输入应用。按住热键开始录音，松开后将识别结果注入当前聚焦输入框。

当前实现以稳定性优先，默认热键为 `Option`。最初设计是 `Fn`，但由于 macOS 会把 `Fn/Globe` 优先用于系统级功能，现版本改为 `Option` 以保证可用性。

## 功能

- 菜单栏常驻运行，`LSUIElement` 模式，无 Dock 图标
- 按住 `Option` 录音，松开后注入文本
- Apple `Speech` framework 流式识别
- 屏幕底部胶囊悬浮窗，实时波形由音频电平驱动
- 支持识别语言切换
  - 简体中文
  - 繁体中文
  - 英语
  - 日语
  - 韩语
- 可选 LLM 纠错
  - OpenAI 兼容 API
  - 可配置 `Base URL`、`API Key`、`Model`
- 粘贴注入前自动处理输入法，避免 CJK 输入法拦截 `Cmd+V`

## 权限要求

首次使用前需要在系统设置中授权：

- 辅助功能
- 麦克风
- 语音识别

如果未授权，菜单栏菜单会显示当前状态，并提供打开系统设置的入口。

## 构建

```bash
cd /Users/x/FnVoiceInput
make build
```

产物位置：

```text
/Users/x/FnVoiceInput/.build/release/FnVoiceInput.app
```

## 运行

```bash
cd /Users/x/FnVoiceInput
make run
```

## 安装

```bash
cd /Users/x/FnVoiceInput
make install
```

安装位置：

```text
/Users/x/Applications/FnVoiceInput.app
```

建议始终从 `~/Applications/FnVoiceInput.app` 启动，这样辅助功能权限不会因为构建目录变化而失效。

## 日常更新流程

1. 修改源码
2. 重新安装本机版本

```bash
cd /Users/x/FnVoiceInput
make install
```

3. 实际打开 `~/Applications/FnVoiceInput.app` 验证
4. 提交并推送到 GitHub

```bash
cd /Users/x/FnVoiceInput
git status
git add .
git commit -m "你的更新说明"
git push
```

## 仓库

- GitHub: <https://github.com/cnoo-c/talk>

## 给新会话助手的接手说明

如果这是一个全新会话，优先先读本文件，再继续动代码。

当前项目状态：

- 这是一个 macOS 14+ SwiftPM 菜单栏语音输入应用
- 安装路径通常是 `~/Applications/FnVoiceInput.app`
- 当前默认热键是 `Option`，不是 `Fn`
- 当前主识别链路使用 Apple `Speech` framework
- 当前菜单和设置界面文案是中文
- GitHub 仓库地址是 <https://github.com/cnoo-c/talk>

建议接手顺序：

1. 进入仓库目录
2. 阅读 `README.md`
3. 运行 `git status`
4. 如需本地验证，运行 `make install`
5. 从 `~/Applications/FnVoiceInput.app` 启动实际测试

项目里最关键的文件：

- `Sources/FnVoiceInput/AppDelegate.swift`
- `Sources/FnVoiceInput/SpeechRecognizerService.swift`
- `Sources/FnVoiceInput/OverlayPanelController.swift`
- `Sources/FnVoiceInput/StatusBarController.swift`
- `Sources/FnVoiceInput/SettingsWindowController.swift`
- `Sources/FnVoiceInput/PasteInjector.swift`

## 当前说明

- 当前默认热键是 `Option`，不是 `Fn`
- 当前 UI 和菜单文案为中文
- 当前识别主链路基于 Apple `Speech` framework
- 如果启用 LLM 纠错，松开热键后会先做保守纠错，再注入文本
