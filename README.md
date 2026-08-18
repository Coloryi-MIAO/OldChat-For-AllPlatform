# OldChat For AllPlatform

OldChat For AllPlatform 是基于 Flutter 的跨平台聊天客户端，当前版本为 `1.4.5-beta.5+7`。同一套代码覆盖 Windows、Android、iOS、macOS、Linux 和 Web；移动端使用独立 Chat 页面，Windows/Linux/macOS 使用更适合桌面的布局。

## 平台标识

- 产品名：`OldChat For AllPlatform`
- Dart package：`oldchat_for_allplatform`
- Android applicationId：`com.coloryi.oldchat_for_allplatform`
- iOS Bundle ID：`com.coloryi.oldchat_for_allplatform`
- macOS Bundle ID：`com.coloryi.oldchat_for_allplatform`
- Linux application ID：`com.coloryi.oldchat_for_allplatform`
- Windows 可执行文件：`OldChat_For_AllPlatform.exe`
- Windows AUMID：`Coloryi.OldChatForAllPlatform`
- Windows Toast CLSID：`936C39FC-6BBC-4A57-B8F8-7C627E401B2F`
- 图标源：`file assets/app_icon.png`；Windows 原生图标：`file assets/app_icon.ico`

Android 的原生入口位于 `file android/app/src/main/kotlin/com/coloryi/oldchat_for_allplatform/MainActivity.kt`。测试 target 会使用同一标识加 `.RunnerTests` 后缀，这是 Apple 工具链的独立测试 bundle。

## 服务端与数据

默认服务器为 `http://60.205.94.101:8080`；`http://***.***.***.***` 是隐藏的自动回退地址。服务器列表和账户设置按 UID 保存。

Windows 的账户数据目录为：

```text
%APPDATA%\OldChat_For_AllPlatform\accounts\<UID>
```

缓存、设置、媒体、插件状态和日志均按账户隔离。不要把真实 token、密码、设备密钥或生产账户数据提交到 Git。

## 媒体与跨平台兼容

媒体依赖全部来自 pub.dev，不使用本地 path 覆盖。项目保留并使用：

- `media_kit`
- `media_kit_video`
- `video_player_media_kit`
- `media_kit_libs_video`
- `media_kit_libs_windows_video`

平台不支持的桌面能力会在运行时隔离，不应阻塞登录、聊天和 Web 构建。图片与视频应先完成缓存再替换展示，避免半文件和重复重建造成闪烁。

## 本地开发

需要 Flutter stable、Dart、对应平台 SDK，以及项目所需的系统依赖。常用命令：

```bash
flutter pub get
flutter analyze
flutter test
```

构建命令：

```bash
flutter build windows --release
flutter build apk --release
flutter build ios --release --no-codesign
flutter build macos --release --no-codesign
flutter build linux --release
flutter build web --release
```

当前开发容器未安装 Flutter SDK，因此本地无法代替 GitHub runner 执行 Dart 分析或平台构建；仓库内的 GitHub Actions 会在干净环境中完成验证和构建。

## GitHub Actions

`file .github/workflows/build.yml` 提供以下流程：

1. Ubuntu 上执行 `flutter pub get`、`flutter analyze` 和 `flutter test`；
2. 分别构建 Android APK、Web、Linux、Windows、macOS 和未签名 iOS；
3. 将各平台产物上传为 Actions artifacts；
4. 支持 push、Pull Request、`v*` 标签和手动触发。

iOS 真机发布仍需要 Apple 签名；Android 正式发布需要配置自己的签名，不应使用调试签名。

## 插件

插件中心只负责 `.oldchat-plugin`；CIP 文件统一在 CIP 中心导入、启用和运行。系统内置的功能按钮插件仍保留并继续提供入口排序与隐藏配置，但不再在插件中心单独绘制“功能按钮编辑”卡片。

自动回复支持私聊与群聊、多关键词、变量 `{text}`、`{uid}`、`{conversation_id}` 和按会话冷却。红包助手支持私聊与群聊、红包 ID 去重、并发领取锁、过期/已领取过滤、最低剩余份数、金额范围、自己发送过滤、每分钟/每日限额；遇到临时认证或限流错误会退避，不会无限重试。

支持大小写不敏感的 `.oldchat-plugin` 与 `.cip` 文件。插件必须声明 manifest、入口和最小权限；不得读取其他账户、导出认证信息或绕过宿主请求层。

更多接口约定见 `file api.md`，服务端路由见 `file routes.md`，插件规范见 `file PLUGIN_DEVELOPMENT.md`。

## 许可

请参阅 `LICENSE`。


## 更新

关于页和设置页从 GitHub Releases 检查更新，仓库为 `https://github.com/Coloryi-MIAO/OldChat-For-AllPlatform`；不会再使用已移除的旧服务器更新地址。
