# 项目画像：Swift Webview

## 项目基线

- **项目名称**：Swift Webview
- **技术栈**：Swift，跨平台 WebView 绑定
- **支持平台**：macOS、Linux、Windows
- **核心功能**：提供 Swift 语言的跨平台 WebView 能力封装

## 平台依赖

| 平台 | 依赖要求 |
|------|----------|
| macOS | 无需额外依赖 |
| Linux | `sudo apt install libgtk-4-dev libwebkitgtk-6.0-dev` |
| Windows | 无需额外依赖 |

## 核心能力

- WebView 创建与管理
- 页面导航控制（加载 URL、前进/后退/刷新）
- 窗口属性设置（标题、大小、位置）
- HTML 内容直接设置
- JavaScript 注入与执行
- Swift 与 JavaScript 双向绑定（JS 可调用 Swift 函数）

## 关键入口

- 主入口：`README.md`（中文文档）
- 依赖配置：各平台需按上述要求安装系统依赖

## 文档说明

- README.md 包含完整中文 API 文档与 4 个示例代码
- 提交规范：遵循 Conventional Commits（如 `docs:` 前缀）
