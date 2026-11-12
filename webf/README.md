# StarHope WebF

StarHope 的源码、类型、同步逻辑、构建配置与测试均在本目录。构建和运行不依赖官网仓库。

需要 Node.js 24+ 和 pnpm 12.6.0。在桌面仓库根目录执行：

```sh
pnpm --dir webf install --frozen-lockfile --ignore-scripts
pnpm --dir webf check
pnpm --dir webf test
pnpm --dir webf build
pnpm --dir webf check:asset
```

`build` 输出单文件 IIFE 到 `assets/webf/starhope/index.html`，随 Flutter assets 一起打包。提交修改时一并更新产物；CI 的 `check:asset` 会检查源码与产物是否一致。正常 `flutter build` 使用已提交产物，不需要 Node 或联网下载页面。

Flutter 桥接只提供工作区快照读写、UUID 和 questions/folders/sessions 的同步接口。请求与令牌刷新走当前 ApiSession，JS 不持有令牌。工作区按服务器与账户隔离；数据、删除墓碑、待推状态与游标整体保存在 Drift，网络失败不清除待推数据。

题库支持五种题型和文件夹；练习即时判分，考试到期交卷，作答历史可恢复。文本题使用忽略大小写的原文匹配。阅读器/插件占位页和模拟 AI 不包含在此模块中。

桌面定向回归：

```sh
flutter test --no-pub test/core/starhope_bridge_test.dart
```

真实 WebF 引擎测试需要安装对应平台的 WebF 动态库，设置 `WEBF_LIBRARY_PATH` 为库所在目录后运行 `test/core/starhope_webf_runtime_test.dart`；Linux 同时把该目录加入 `LD_LIBRARY_PATH`。测试覆盖表单创建、离线保存、作答交卷和快速连续多选。普通测试未配置动态库时会跳过此项。

当前使用单设备、单模块工作区，快照上限 16 MiB，整体写入为 O(n)。LWW 依赖设备时钟；大型题库或多窗口协同需要后续拆表和并发控制。
