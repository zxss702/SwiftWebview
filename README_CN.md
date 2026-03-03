# SwiftWebview 使用文档

SwiftWebview 是一个 Swift 跨平台 Webview 绑定库，基于 [webview](https://github.com/webview/webview) 项目开发。它允许你在桌面应用中嵌入 Web 内容，实现 Swift 与 JavaScript 的双向通信。

---

## 目录

- [项目简介](#项目简介)
- [依赖安装](#依赖安装)
- [快速开始](#快速开始)
- [API 参考](#api-参考)
  - [Webview 类](#webview-类)
  - [SizeHint 枚举](#sizehint-枚举)
  - [JSCallback 类型](#jscallback-类型)
- [进阶用法](#进阶用法)
  - [函数绑定](#函数绑定)
  - [JavaScript 执行](#javascript-执行)
  - [异步求值](#异步求值)
- [平台差异说明](#平台差异说明)
- [完整示例](#完整示例)

---

## 项目简介

SwiftWebview 提供了以下核心功能：

- **跨平台支持**：支持 macOS 和 Linux（Windows 支持正在开发中）
- **窗口管理**：设置窗口大小、标题、导航等
- **JavaScript 互操作**：注入脚本、执行代码、绑定 Swift 函数
- **异步执行**：支持 async/await 模式的 JavaScript 求值
- **线程安全**：提供安全的跨线程操作机制

### 技术栈

- **macOS**：基于 WebKit 框架（WKWebView）
- **Linux**：基于 WebKit2GTK

---

## 依赖安装

### macOS

macOS 平台开箱即用，无需额外安装依赖。

### Linux

需要安装 `libgtk-3-dev` 和 `libwebkit2gtk-4.0-dev`，或发行版对应的等效包：

```sh
# Debian/Ubuntu
sudo apt install libgtk-3-dev libwebkit2gtk-4.0-dev

# Fedora
sudo dnf install gtk3-devel webkit2gtk3-devel

# Arch Linux
sudo pacman -S gtk3 webkit2gtk
```

### Windows

Windows 平台目前尚未测试，也不被官方支持。欢迎社区贡献代码。

---

## 快速开始

### 添加依赖

在 `Package.swift` 中添加：

```swift
dependencies: [
    .package(url: "https://github.com/jakenvac/SwiftWebview.git", from: "1.0.0")
]
```

### 基础示例

```swift
import SwiftWebview

// 创建 webview（参数为是否启用调试模式）
let wv = Webview(true)
    // 设置窗口大小：宽 800，高 600，大小提示为 None
    .setSize(800, 600, .None)
    // 设置窗口标题
    .setTitle("我的 Webview 应用")
    // 加载网页
    .navigate("https://example.com")

// 启动主循环（会阻塞当前线程）
wv.run()
```

### 使用 HTML 内容

```swift
let wv = Webview()
    .setSize(500, 500, .None)
    .setHtml("""
    <html>
    <head>
        <style>
            body { 
                font-family: Arial; 
                text-align: center; 
                margin-top: 50px; 
            }
        </style>
    </head>
    <body>
        <h1>Hello SwiftWebview!</h1>
        <p>这是一个本地 HTML 页面</p>
    </body>
    </html>
    """)

wv.run()
```

---

## API 参考

### Webview 类

`Webview` 是库的核心类，提供完整的 Webview 窗口管理能力。

#### 初始化

```swift
public init(_ debug: Bool = false)
```

- **参数**：`debug` - 是否启用开发者工具（调试模式）
- **说明**：在 Linux 上，如果没有可用的 Display/X11，初始化会失败

#### 主循环控制

##### `run()`

```swift
public func run()
```

启动 webview 主循环，阻塞当前线程直到窗口关闭。

##### `terminate()`

```swift
nonisolated public func terminate() -> Webview
```

终止主循环并关闭窗口。此方法是线程安全的，可以从任意线程调用。

##### `dispatch(_:)`

```swift
nonisolated public func dispatch(_ work: @escaping @Sendable () -> Void)
```

将闭包调度到 webview 的 UI 事件循环线程上执行。

> ⚠️ **重要**：在 Linux 上，`run()` 启动的 GTK 主循环与 Swift 的 `@MainActor`（libdispatch 主队列）互不兼容。从后台线程操作 webview 时，必须通过此方法调度。

#### 导航与内容

##### `navigate(_:)`

```swift
@discardableResult
public func navigate(_ url: String) -> Webview
```

导航到指定 URL。

```swift
wv.navigate("https://www.example.com")
```

##### `setHtml(_:)`

```swift
@discardableResult
public func setHtml(_ html: String) -> Webview
```

直接设置 HTML 内容。

```swift
wv.setHtml("<h1>Hello World</h1>")
```

#### 窗口属性

##### `setTitle(_:)`

```swift
@discardableResult
public func setTitle(_ title: String) -> Webview
```

设置窗口标题。

```swift
wv.setTitle("我的应用")
```

##### `setSize(_:_:_:)`

```swift
@discardableResult
public func setSize(_ width: Int32, _ height: Int32, _ hint: SizeHint) -> Webview
```

设置窗口大小。

- **参数**：
  - `width`: 窗口宽度（像素）
  - `height`: 窗口高度（像素）
  - `hint`: 大小提示（详见 SizeHint 枚举）

```swift
wv.setSize(1024, 768, .None)
```

#### JavaScript 操作

##### `inject(_:)`

```swift
@discardableResult
public func inject(_ js: String) -> Webview
```

注入 JavaScript 代码到每个新页面，保证在 `window.onload` 之前执行。

```swift
wv.inject("""
    console.log('这段代码在每个页面加载前执行');
    window.myAppVersion = '1.0.0';
""")
```

##### `eval(_:)`

```swift
@discardableResult
public func eval(_ js: String) -> Webview
```

在当前页面执行 JavaScript 代码（fire-and-forget 模式，不返回结果）。

```swift
wv.eval("console.log('当前时间：', new Date())")
```

##### `evaluateJavaScript(_:)`

```swift
public func evaluateJavaScript(_ js: String) async throws -> String
```

异步执行 JavaScript 代码并返回结果。支持 async/await 模式。

```swift
Task {
    do {
        let result = try await wv.evaluateJavaScript("navigator.userAgent")
        print("User Agent: \(result)")
    } catch {
        print("执行失败: \(error)")
    }
}
```

**错误类型**：
- `EvalError.destroyed`: Webview 已被销毁
- `EvalError.executionError(String)`: JavaScript 执行出错

#### 函数绑定

##### `bind(_:_:)`

```swift
@discardableResult
public func bind(_ name: String, _ callback: @escaping JSCallback) -> Webview
```

绑定 Swift 函数到全局 JavaScript 函数。

```swift
let greet: JSCallback = { args in
    guard let name = args.first as? String else {
        return "Hello, stranger!"
    }
    return "Hello, \(name)!"
}

wv.bind("greet", greet)
```

JavaScript 端调用：

```javascript
var message = window.greet("Swift");
console.log(message); // Hello, Swift!
```

##### `unbind(_:)`

```swift
@discardableResult
public func unbind(_ name: String) -> Webview
```

解绑已绑定的 JavaScript 函数。

```swift
wv.unbind("greet")
```

#### 生命周期

##### `destroy()`

```swift
@discardableResult
public func destroy() -> Webview
```

销毁 webview 并关闭窗口。销毁后不可再使用。

```swift
wv.destroy()
```

#### 状态查询

##### `isLoading`

```swift
public var isLoading: Bool { get }
```

查询当前页面是否正在加载。

```swift
if wv.isLoading {
    print("页面加载中...")
}
```

---

### SizeHint 枚举

`SizeHint` 用于控制窗口大小的行为模式。

```swift
public enum SizeHint: Int32, Sendable {
    /// 默认大小，用户可以随意调整窗口
    case None = 0
    
    /// 固定大小，用户不可调整窗口尺寸
    case Fixed = 1
    
    /// 最小边界，设置窗口的最小尺寸
    case Min = 2
    
    /// 最大边界，设置窗口的最大尺寸
    case Max = 3
}
```

#### 使用示例

```swift
// 固定大小窗口
wv.setSize(400, 300, .Fixed)

// 设置最小尺寸
wv.setSize(800, 600, .Min)

// 设置最大尺寸
wv.setSize(1920, 1080, .Max)
```

---

### JSCallback 类型

`JSCallback` 定义了绑定到 JavaScript 的 Swift 函数签名。

```swift
public typealias JSCallback = @Sendable ([Any]) throws -> Codable
```

- **参数**：`[Any]` - JavaScript 调用时传递的参数数组
- **返回值**：`Codable` - 任意可编码的类型，将被序列化为 JSON 返回给 JavaScript
- **异常**：可以抛出错误，错误会被传递给 JavaScript

#### 参数说明

JavaScript 调用时传递的参数会被解析为 Swift 的 `Array<Any>`，支持的类型包括：
- `String` -> Swift `String`
- `Number` -> Swift `Double` 或 `Int`
- `Boolean` -> Swift `Bool`
- `Object/Array` -> Swift `Dictionary` 或 `Array`
- `null` -> Swift `NSNull`

#### 返回值说明

返回值必须是 `Codable` 类型，会被自动序列化为 JSON：

```swift
// 返回字符串
let stringCallback: JSCallback = { _ in
    return "Hello from Swift!"
}

// 返回数字
let numberCallback: JSCallback = { args in
    guard let a = args[0] as? Double, let b = args[1] as? Double else {
        throw NSError(domain: "Invalid arguments", code: 400)
    }
    return a + b
}

// 返回对象（需要 Codable）
struct User: Codable {
    let name: String
    let age: Int
}

let userCallback: JSCallback = { _ in
    return User(name: "张三", age: 25)
}
```

---

## 进阶用法

### 函数绑定详解

#### 基础绑定

```swift
let wv = Webview()

// 绑定无参数的函数
wv.bind("getVersion") { _ in
    return "1.0.0"
}

// 绑定带参数的函数
wv.bind("calculate") { args in
    guard args.count >= 2,
          let a = args[0] as? Double,
          let b = args[1] as? Double else {
        throw NSError(domain: "需要两个数字参数", code: 400)
    }
    return a + b
}
```

JavaScript 端：

```javascript
// 调用无参数函数
console.log(window.getVersion()); // "1.0.0"

// 调用带参数函数
console.log(window.calculate(10, 20)); // 30
```

#### 处理复杂数据

```swift
struct Task: Codable {
    let id: Int
    let title: String
    let completed: Bool
}

var tasks: [Task] = []

// 获取所有任务
wv.bind("getTasks") { _ in
    return tasks
}

// 添加任务
wv.bind("addTask") { args in
    guard let title = args.first as? String else {
        throw NSError(domain: "需要任务标题", code: 400)
    }
    let task = Task(id: tasks.count + 1, title: title, completed: false)
    tasks.append(task)
    return task
}

// 完成任务
wv.bind("completeTask") { args in
    guard let id = args.first as? Int,
          let index = tasks.firstIndex(where: { $0.id == id }) else {
        throw NSError(domain: "任务不存在", code: 404)
    }
    tasks[index] = Task(id: id, title: tasks[index].title, completed: true)
    return true
}
```

### JavaScript 执行详解

#### 注入初始化脚本

```swift
// 在所有页面加载前执行
wv.inject("""
    // 创建全局应用对象
    window.MyApp = {
        version: '1.0.0',
        platform: 'desktop'
    };
    
    // 设置页面主题
    document.documentElement.setAttribute('data-theme', 'light');
""")
```

#### 运行时执行

```swift
// 动态修改页面内容
wv.eval("""
    document.body.style.backgroundColor = '#f0f0f0';
    var counter = document.getElementById('counter');
    if (counter) counter.innerText = parseInt(counter.innerText || '0') + 1;
""")
```

### 异步求值详解

`evaluateJavaScript` 支持获取异步 JavaScript 的执行结果：

#### 获取同步结果

```swift
Task {
    do {
        let title = try await wv.evaluateJavaScript("document.title")
        print("页面标题: \(title)")
    } catch {
        print("获取失败: \(error)")
    }
}
```

#### 获取异步结果

```swift
Task {
    do {
        // 调用返回 Promise 的函数
        let data = try await wv.evaluateJavaScript("""
            fetch('https://api.example.com/data')
                .then(r => r.json())
                .then(data => JSON.stringify(data))
        """)
        print("获取的数据: \(data)")
    } catch {
        print("请求失败: \(error)")
    }
}
```

#### 错误处理

```swift
Task {
    do {
        let result = try await wv.evaluateJavaScript("nonExistentFunction()")
    } catch EvalError.executionError(let message) {
        print("JavaScript 错误: \(message)")
    } catch {
        print("其他错误: \(error)")
    }
}
```

---

## 平台差异说明

### macOS

- 使用原生 WebKit 框架
- 完全支持 `@MainActor` 隔离
- 调试模式启用 Safari 开发者工具
- 线程调度与标准 Swift Concurrency 一致

### Linux

- 使用 WebKit2GTK 库
- **重要限制**：`run()` 启动的 GTK 主循环与 Swift 的 `@MainActor` 互不兼容
- 从后台线程操作 webview 时，必须使用 `dispatch(_:)` 方法

#### Linux 线程调度示例

```swift
// ❌ 错误：在 Linux 上可能无法正常工作
Task {
    let data = await fetchData()
    wv.eval("updateUI('\(data)')")  // 可能崩溃或无响应
}

// ✅ 正确：使用 dispatch 调度到 UI 线程
Task {
    let data = await fetchData()
    wv.dispatch {
        wv.eval("updateUI('\(data)')")
    }
}
```

#### Linux 无头环境

在服务器或无显示环境中运行，需要使用 `xvfb-run`：

```sh
xvfb-run swift run
```

### Windows

目前尚未支持，正在开发中。

---

## 完整示例

### 示例 1：基础应用

```swift
import SwiftWebview

let wv = Webview(true)
    .setSize(800, 600, .None)
    .setTitle("基础示例")
    .setHtml("""
    <!DOCTYPE html>
    <html>
    <head>
        <style>
            body {
                font-family: system-ui, -apple-system, sans-serif;
                display: flex;
                justify-content: center;
                align-items: center;
                height: 100vh;
                margin: 0;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            }
            h1 {
                color: white;
                text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
            }
        </style>
    </head>
    <body>
        <h1>欢迎使用 SwiftWebview!</h1>
    </body>
    </html>
    """)

wv.run()
```

### 示例 2：双向通信应用

```swift
import SwiftWebview

let wv = Webview(true)
    .setSize(600, 400, .None)
    .setTitle("双向通信示例")
    .setHtml("""
    <!DOCTYPE html>
    <html>
    <head>
        <style>
            body {
                font-family: Arial, sans-serif;
                padding: 20px;
            }
            button {
                padding: 10px 20px;
                font-size: 16px;
                cursor: pointer;
            }
            #output {
                margin-top: 20px;
                padding: 10px;
                background: #f0f0f0;
                border-radius: 4px;
            }
        </style>
    </head>
    <body>
        <h1>Swift ↔ JavaScript 通信</h1>
        <button onclick="callSwift()">调用 Swift 函数</button>
        <button onclick="getSystemInfo()">获取系统信息</button>
        <div id="output"></div>
        
        <script>
            function callSwift() {
                try {
                    var result = window.sayHello('JavaScript');
                    document.getElementById('output').innerText = 
                        'Swift 返回: ' + result;
                } catch(e) {
                    document.getElementById('output').innerText = 
                        '错误: ' + e.message;
                }
            }
            
            function getSystemInfo() {
                try {
                    var info = window.getSystemInfo();
                    document.getElementById('output').innerText = 
                        '系统信息: ' + JSON.stringify(info, null, 2);
                } catch(e) {
                    document.getElementById('output').innerText = 
                        '错误: ' + e.message;
                }
            }
        </script>
    </body>
    </html>
    """)

// 绑定问候函数
wv.bind("sayHello") { args in
    let name = args.first as? String ?? "World"
    return "Hello from Swift, \(name)!"
}

// 绑定系统信息函数
wv.bind("getSystemInfo") { _ in
    struct SystemInfo: Codable {
        let platform: String
        let version: String
        let timestamp: TimeInterval
    }
    
    return SystemInfo(
        platform: "SwiftWebview",
        version: "1.0.0",
        timestamp: Date().timeIntervalSince1970
    )
}

wv.run()
```

### 示例 3：异步数据获取

```swift
import SwiftWebview
import Foundation

let wv = Webview(true)
    .setSize(900, 600, .None)
    .setTitle("异步数据示例")
    .setHtml("""
    <!DOCTYPE html>
    <html>
    <head>
        <style>
            body {
                font-family: Arial, sans-serif;
                padding: 20px;
            }
            .post {
                border: 1px solid #ddd;
                padding: 15px;
                margin: 10px 0;
                border-radius: 8px;
            }
            .post h3 {
                margin: 0 0 10px 0;
                color: #333;
            }
            .post p {
                margin: 0;
                color: #666;
            }
            #loading {
                display: none;
                color: #666;
            }
        </style>
    </head>
    <body>
        <h1>JSONPlaceholder 文章列表</h1>
        <button onclick="loadPosts()">加载文章</button>
        <div id="loading">加载中...</div>
        <div id="posts"></div>
        
        <script>
            async function loadPosts() {
                document.getElementById('loading').style.display = 'block';
                document.getElementById('posts').innerHTML = '';
                
                try {
                    var posts = await window.fetchPosts();
                    document.getElementById('loading').style.display = 'none';
                    
                    var container = document.getElementById('posts');
                    posts.forEach(function(post) {
                        var div = document.createElement('div');
                        div.className = 'post';
                        div.innerHTML = '<h3>' + post.title + '</h3>' +
                                       '<p>' + post.body + '</p>';
                        container.appendChild(div);
                    });
                } catch(e) {
                    document.getElementById('loading').style.display = 'none';
                    document.getElementById('posts').innerHTML = 
                        '<p style="color: red;">加载失败: ' + e.message + '</p>';
                }
            }
        </script>
    </body>
    </html>
    """)

// 绑定获取文章函数
wv.bind("fetchPosts") { _ in
    // 模拟异步获取数据
    struct Post: Codable {
        let id: Int
        let title: String
        let body: String
    }
    
    return [
        Post(id: 1, title: "SwiftWebview 入门", 
             body: "SwiftWebview 是一个跨平台的 Webview 绑定库，支持 macOS 和 Linux。"),
        Post(id: 2, title: "函数绑定详解", 
             body: "通过 bind 方法可以将 Swift 函数暴露给 JavaScript 调用。"),
        Post(id: 3, title: "异步执行指南", 
             body: "evaluateJavaScript 方法支持 async/await 模式，方便获取异步结果。")
    ]
}

wv.run()
```

### 示例 4：完整桌面应用

```swift
import SwiftWebview
import Foundation

// 创建一个待办事项应用
let wv = Webview(true)
    .setSize(500, 700, .None)
    .setTitle("待办事项")

struct TodoItem: Codable {
    let id: Int
    var text: String
    var completed: Bool
}

var todos: [TodoItem] = []
var nextId = 1

// 绑定 API
wv.bind("getTodos") { _ in
    return todos
}

wv.bind("addTodo") { args in
    guard let text = args.first as? String, !text.isEmpty else {
        throw NSError(domain: "内容不能为空", code: 400)
    }
    
    let todo = TodoItem(id: nextId, text: text, completed: false)
    nextId += 1
    todos.append(todo)
    return todo
}

wv.bind("toggleTodo") { args in
    guard let id = args.first as? Int,
          let index = todos.firstIndex(where: { $0.id == id }) else {
        throw NSError(domain: "待办事项不存在", code: 404)
    }
    todos[index].completed.toggle()
    return todos[index]
}

wv.bind("deleteTodo") { args in
    guard let id = args.first as? Int,
          let index = todos.firstIndex(where: { $0.id == id }) else {
        throw NSError(domain: "待办事项不存在", code: 404)
    }
    todos.remove(at: index)
    return true
}

// 设置 HTML 内容
wv.setHtml("""
<!DOCTYPE html>
<html>
<head>
    <style>
        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #f5f5f5;
            padding: 20px;
        }
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px;
            border-radius: 12px;
            margin-bottom: 20px;
        }
        .header h1 {
            font-size: 28px;
            margin-bottom: 10px;
        }
        .input-group {
            display: flex;
            gap: 10px;
            margin-bottom: 20px;
        }
        .input-group input {
            flex: 1;
            padding: 12px 16px;
            border: 2px solid #e0e0e0;
            border-radius: 8px;
            font-size: 16px;
            transition: border-color 0.2s;
        }
        .input-group input:focus {
            outline: none;
            border-color: #667eea;
        }
        .input-group button {
            padding: 12px 24px;
            background: #667eea;
            color: white;
            border: none;
            border-radius: 8px;
            font-size: 16px;
            cursor: pointer;
            transition: background 0.2s;
        }
        .input-group button:hover {
            background: #5a67d8;
        }
        .todo-list {
            list-style: none;
        }
        .todo-item {
            background: white;
            padding: 16px;
            margin-bottom: 10px;
            border-radius: 8px;
            display: flex;
            align-items: center;
            gap: 12px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.05);
            transition: transform 0.2s, box-shadow 0.2s;
        }
        .todo-item:hover {
            transform: translateY(-2px);
            box-shadow: 0 4px 8px rgba(0,0,0,0.1);
        }
        .todo-item.completed .todo-text {
            text-decoration: line-through;
            color: #999;
        }
        .todo-checkbox {
            width: 24px;
            height: 24px;
            cursor: pointer;
        }
        .todo-text {
            flex: 1;
            font-size: 16px;
        }
        .todo-delete {
            padding: 8px 16px;
            background: #ff6b6b;
            color: white;
            border: none;
            border-radius: 6px;
            cursor: pointer;
            font-size: 14px;
        }
        .todo-delete:hover {
            background: #ee5a5a;
        }
        .empty-state {
            text-align: center;
            padding: 60px 20px;
            color: #999;
        }
        .empty-state svg {
            width: 80px;
            height: 80px;
            margin-bottom: 20px;
            opacity: 0.5;
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>📋 待办事项</h1>
        <p>使用 SwiftWebview 构建</p>
    </div>
    
    <div class="input-group">
        <input type="text" id="todoInput" placeholder="添加新待办事项..." 
               onkeypress="if(event.key==='Enter')addTodo()">
        <button onclick="addTodo()">添加</button>
    </div>
    
    <ul class="todo-list" id="todoList"></ul>
    
    <div class="empty-state" id="emptyState" style="display: none;">
        <p>📝 暂无待办事项</p>
        <p>添加一个新任务开始吧！</p>
    </div>

    <script>
        async function loadTodos() {
            try {
                var todos = await window.getTodos();
                renderTodos(todos);
            } catch(e) {
                console.error('加载失败:', e);
            }
        }
        
        function renderTodos(todos) {
            var list = document.getElementById('todoList');
            var emptyState = document.getElementById('emptyState');
            
            if (todos.length === 0) {
                list.innerHTML = '';
                emptyState.style.display = 'block';
                return;
            }
            
            emptyState.style.display = 'none';
            list.innerHTML = todos.map(function(todo) {
                return '<li class="todo-item ' + (todo.completed ? 'completed' : '') + '">' +
                    '<input type="checkbox" class="todo-checkbox" ' + 
                    (todo.completed ? 'checked' : '') + 
                    ' onchange="toggleTodo(' + todo.id + ')">' +
                    '<span class="todo-text">' + escapeHtml(todo.text) + '</span>' +
                    '<button class="todo-delete" onclick="deleteTodo(' + todo.id + ')">删除</button>' +
                    '</li>';
            }).join('');
        }
        
        async function addTodo() {
            var input = document.getElementById('todoInput');
            var text = input.value.trim();
            if (!text) return;
            
            try {
                await window.addTodo(text);
                input.value = '';
                loadTodos();
            } catch(e) {
                alert('添加失败: ' + e.message);
            }
        }
        
        async function toggleTodo(id) {
            try {
                await window.toggleTodo(id);
                loadTodos();
            } catch(e) {
                alert('更新失败: ' + e.message);
            }
        }
        
        async function deleteTodo(id) {
            try {
                await window.deleteTodo(id);
                loadTodos();
            } catch(e) {
                alert('删除失败: ' + e.message);
            }
        }
        
        function escapeHtml(text) {
            var div = document.createElement('div');
            div.textContent = text;
            return div.innerHTML;
        }
        
        // 初始加载
        loadTodos();
    </script>
</body>
</html>
""")

wv.run()
```

---

## 许可证

本项目基于 MIT 许可证开源。详见 [LICENSE](LICENSE) 文件。

---

## 相关链接

- [GitHub 仓库](https://github.com/jakenvac/SwiftWebview)
- [API 文档](https://jakenvac.github.io/SwiftWebview/)
- [webview 项目](https://github.com/webview/webview)

---

如有问题或建议，欢迎在 GitHub 上提交 Issue 或 Pull Request。
