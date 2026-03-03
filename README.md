# Swift Webview

Swift 跨平台 [webview](https://github.com/webview/webview) 绑定库。

## 依赖

根据目标平台的不同，你需要安装以下内容。

### macOS

开箱即用™

### Linux

你需要安装 `libgtk-3-dev` 和 `libwebkit2gtk-4.0-dev`，或者发行版对应的等效包。

```sh
sudo apt install libgtk-3-dev libwebkit2gtk-4.0-dev
```

### Windows

Windows 目前尚未测试，也不被官方支持。欢迎在此贡献代码。

## 使用方法

查看生成的文档 [点击此处](https://jakenvac.github.io/SwiftWebview/)。

### 基础用法

```swift
import SwiftWebview

// 创建一个新的 webview
let wv = WebView()
      // 导航到指定 URL
      .navigate("https://example.com")
      // 直接设置 HTML 内容
      .setHtml("<h1>Hello World</h1>")
      // 设置窗口标题
      .setTitle("My Webview Window")
      // 设置窗口大小
      .setSize(800, 600, .None)
      // 向每个新页面注入 JavaScript 代码
      .inject("console.log('this happens before window.onload')")
      // 异步在当前页面执行 JavaScript
      .eval("console.log('this was evaled at runtime')")

// 运行 webview
wv.run()

// 使用完毕后销毁 webview
wv.destroy()
```

### 函数绑定

```swift
let wv = WebView()

let mySwiftFunction: JSCallback = { args in
  return "Hello \(args[0])"
}

wv.bind("boundFunction", mySwiftFunction)
wv.run()
```

```javascript
var result = window.boundFunction("World");
console.log(result); // Hello World
```
