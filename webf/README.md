# 官方小程序（桌面 / Web）

客户端通过 `assets/webf/manifest.json` 显示内置小程序列表，所有应用共用路由和宿主接口，通过平台容器分别在桌面和 Web 中运行。当前内置 StarHope、便签和番茄钟；账户页和学习看板的小程序入口均打开此列表，旧 `/starhope` 链接继续可用。

## 分层架构

- **业务层**：各应用的 React/Vue/TypeScript、清单与业务数据，不依赖 Flutter 或 WebF。
- **SDK / 协议层**：`sdk.ts` 提供统一接口，`transport.ts` 在桌面使用 WebF methodChannel，在浏览器使用带请求 ID 的 postMessage。
- **宿主服务层**：`MiniAppBridge` 实现认证、请求白名单、JSON 存储；不依赖平台渲染器。
- **平台容器层**：`host/mini_app_host.dart` 条件导出原生 WebF 容器或 Web iframe 容器，共用同一份 HTML。`MiniAppBrowser` 单独负责浏览器 DOM 与消息通信，Flutter 组件只负责资源加载和视图挂载。Web 编译不导入 WebF 原生库。

Web 容器使用 `sandbox="allow-scripts"` 的不透明源 iframe，校验消息来源窗口及协议，移除容器时解除消息监听；应用无法直接访问宿主 DOM、令牌或浏览器存储。宿主自己的 Drift Web 存储使用项目已有 IndexedDB / SQLite WASM 配置。数据按部署、账户和应用隔离，但桌面本机数据和浏览器本地数据是两份存储，只有应用自己实现的服务端同步才能跨端共享。

## 新增一个小程序

只需在本目录添加 `<app-id>/`，包含：

- `manifest.json`：名称、描述、图标、版本、宿主 API 版本和允许的服务端请求。
- `main.ts`、`main.tsx`、`main.js`、`main.jsx` 中恰好一个：前端入口，支持 React、Vue 3 和原生 JS/TS。
- 应用需要的源码、样式和测试。

构建自动发现所有包含清单的一级子目录，生成 `assets/webf/<app-id>.html` 和应用目录清单。无需修改 Dart、路由、`pubspec.yaml`、构建脚本或 CI 的应用列表。普通 Flutter 构建使用已提交资源；新增内置应用仍需重新构建、发布对应的桌面或 Web 客户端。

最小清单（`id` 必须等于目录名，格式为小写字母开头的字母、数字、短横线，最长 64 字符）：

```json
{
  "id": "my-tool",
  "apiVersion": 1,
  "version": "1.0.0",
  "icon": "🔧",
  "name": {"zh-CN": "我的工具", "en-US": "My tool"},
  "description": {"zh-CN": "工具说明", "en-US": "A useful tool"}
}
```

前端通过统一 SDK 使用宿主能力：

```ts
import { miniApp } from '../sdk';

const context = await miniApp.context(); // appId / version / apiVersion / userId / locale / dark
const notes = await miniApp.load<string[]>() ?? [];
notes.push('hello');
await miniApp.save(notes);
const id = await miniApp.newId();
```

API v1 提供 `context()`、`newId()`、`load<T>()`、`save(value)`、`request<T>(name, options)`。所有调用都是 Promise，失败时抛出 Error，其 message 为 `host`、`session`、`invalid`、`forbidden`、`storage`、`offline` 或 `sync`。保存失败时应用应保留输入并允许重试；只有保存成功才显示已保存。

`load`/`save` 是每个应用自己的 JSON 快照，最大 16 MiB。数据按服务器、账户、小程序 ID 隔离，存入 Drift，独立于聊天缓存。便签和番茄钟只保存在本机；番茄钟保存截止时间，重新打开后恢复倒计时，但不提供后台系统通知。StarHope 的旧数据会自动迁移，题库、文件夹、作答记录继续使用原有同步协议。

## React 小程序

已安装并锁定 React / ReactDOM 19.3.1 和对应类型。构建使用 Vite 自带的 JSX/TSX 转译与 React 自动 JSX runtime；`check` 同时检查 `.ts`、`.tsx` 与 `.vue`，不需要按框架拆分宿主、SDK 或应用清单。

新建 `<app-id>/manifest.json` 后，可以直接使用以下 `main.tsx`：

```tsx
import { createRoot } from 'react-dom/client';
import { useEffect, useState } from 'react';
import { miniApp } from '../sdk';

function App() {
  const [locale, setLocale] = useState('');
  useEffect(() => {
    void miniApp.context().then(context => setLocale(context.locale));
  }, []);
  return <p>当前语言：{locale}</p>;
}

createRoot(document.getElementById('app')!).render(<App />);
```

JSX 自动导入 `react/jsx-runtime`，无需添加 `import React`。React 的状态、effect、事件处理及宿主调用可参考 `notes/App.tsx`。便签采用 React 实现，沿用原来的 JSON 存储格式；StarHope、番茄钟仍采用 Vue，三者由同一构建命令打包。生产单文件构建不使用 Fast Refresh，也不包含 SSR / React Server Components。

## 服务端请求

清单可声明命名接口，例如：

```json
"requests": {
  "questions.list": {"method": "GET", "path": "/starhope/questions"}
}
```

```ts
const result = await miniApp.request('questions.list', {
  query: { since: '2026-11-13T00:00:00Z' },
});
```

允许 GET/POST/PUT/PATCH/DELETE；POST 等可传 `body`。请求只能使用清单中的固定相对 API 路径，前端不能覆写 URL、方法、请求头或提供令牌。Flutter 使用当前 `ApiSession` 自动带认证、刷新令牌并解析服务端信封。清单授权的是客户端可调用接口；服务端仍须自行鉴权。新业务接口需要后端实现，但不需要为每个应用新增 Flutter 桥接代码。

这套机制用于随客户端发布的官方应用，不是第三方代码沙箱。新增宿主原生能力时仍需要升级宿主 API 和客户端。

## 构建与验证

需要 Node.js 24+ 和 pnpm 12.6.0。在桌面仓库根目录执行：

```sh
pnpm --dir webf install --frozen-lockfile --ignore-scripts
pnpm --dir webf check
pnpm --dir webf test
pnpm --dir webf build
pnpm --dir webf check:asset
flutter test --no-pub test/core/mini_app_manifest_test.dart test/core/mini_app_bridge_test.dart test/core/mini_apps_screen_test.dart
```

每个小程序构建为单文件 IIFE，CSS 一并内联，不允许额外模块导入或未内联的资源文件。提交时一并更新生成的 HTML 和目录清单；CI 的 `check:asset` 验证源码与产物一致。StarHope 支持五种题型、练习即时判分、考试到期交卷和历史恢复；文本题采用忽略大小写的原文匹配，不含 AI 评分。

真实引擎回归需要对应平台 WebF 动态库：设置 `WEBF_LIBRARY_PATH` 为库目录，Linux 同时把该目录加入 `LD_LIBRARY_PATH`，再运行：

```sh
flutter test --no-pub test/core/starhope_webf_runtime_test.dart test/core/mini_app_webf_runtime_test.dart
```

未配置动态库时会跳过这两项。设置 `MINI_APP_SCREENSHOT_DIR` 可从真实引擎回归导出便签和番茄钟截图，`MINI_APPS_SCREENSHOT` 可从列表界面测试导出截图。

浏览器回归（需要 Chrome/Chromium，可通过 `CHROME_EXECUTABLE` 指定）：

```sh
node webf/test-browser.mjs
flutter build web --no-pub --no-wasm-dry-run --no-tree-shake-icons --no-web-resources-cdn
```

Flutter 浏览器测试服务器不提供应用 assets，`test-browser.mjs` 会在随机本地端口提供已构建的原始 HTML 和清单，避免把大体积 React 产物嵌入编译参数，无需维护另一份测试页面。可用 `FLUTTER_BIN` 指定 Flutter 可执行文件。

浏览器回归在真实隔离 iframe 内运行同一份 React 便签产物，通过 SDK 和宿主桥接完成保存，并验证外部窗口不能伪造小程序请求。Web 部署需继续包含 `web/DRIFT_WEB_ASSETS.md` 说明的 SQLite WASM / worker 资源。

当前原生 WebF 宿主管理器最多保留两个实例、同时挂载一个。存储采用整份快照写入，单应用多窗口并发和大型数据集需要后续扩展。StarHope 同步的 LWW 冲突处理依赖设备时钟。

界面截图：[小程序列表](../docs/screenshots/mini-apps/catalog.png)、[便签（React / Web）](../docs/screenshots/mini-apps/notes-react-web.png)、[番茄钟](../docs/screenshots/mini-apps/pomodoro.png)。
