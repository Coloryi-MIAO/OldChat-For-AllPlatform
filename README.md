# OldChat For AllPlatform

[![Latest Release](https://img.shields.io/github/v/release/Coloryi-MIAO/OldChat-For-AllPlatform?display_name=tag&sort=semver)](https://github.com/Coloryi-MIAO/OldChat-For-AllPlatform/releases)
[![License](https://img.shields.io/github/license/Coloryi-MIAO/OldChat-For-AllPlatform)](LICENSE)
[![Forks](https://img.shields.io/github/forks/Coloryi-MIAO/OldChat-For-AllPlatform?style=flat)](https://github.com/Coloryi-MIAO/OldChat-For-AllPlatform/network/members)
[![Build](https://github.com/Coloryi-MIAO/OldChat-For-AllPlatform/actions/workflows/build.yml/badge.svg)](https://github.com/Coloryi-MIAO/OldChat-For-AllPlatform/actions/workflows/build.yml)

OldChat For AllPlatform 是基于 Flutter 的跨平台聊天客户端。当前版本为 `1.4.7-beta.8+5`，同一套代码覆盖 Windows、Android、iOS、macOS、Linux 和 Web。

## 功能范围

- 私聊、群聊、频道、动态、通知、收藏、资源、音乐、表情和公开法庭。
- WebSocket 会话与 HTTP API，支持消息刷新、重连和账户级缓存。
- 本地账户与登录状态按 UID 隔离；移动端登录凭据保存在系统安全存储适配层中，不会因为普通启动而清理。
- `.oldchat-plugin` 插件包和 `.cip` 小程序包导入、启用、运行、导出与账户级持久化。
- CIP 使用受限 Lua 宿主 API 与声明式 UI，禁止直接访问系统文件、凭据或未声明网络。
- 图片、视频、文件选择、系统通知和桌面能力按平台适配；Web 使用浏览器能力降级。

## 平台标识

- 产品名：`OldChat For AllPlatform`
- Dart package：`oldchatforallplatform`
- Android applicationId：`com.coloryi.oldchatforallplatform`
- iOS Bundle ID：`com.coloryi.oldchatforallplatform`
- macOS Bundle ID：`com.coloryi.oldchatforallplatform`
- Linux application ID：`com.coloryi.oldchatforallplatform`
- Windows 可执行文件：`OldChatForAllPlatform.exe`
- Windows AUMID：`Coloryi.OldChatForAllPlatform`
- Windows Toast CLSID：`936C39FC-6BBC-4A57-B8F8-7C627E401B2F`

## 服务端与数据

默认服务器为 `http://60.205.94.101:8080`；隐藏回退地址不会暴露给插件。服务器列表和账户设置按 UID 保存。Windows 账户数据目录为：

```text
%APPDATA%\\OldChatForAllPlatform\\accounts\\<UID>
```

不要把真实 token、密码、设备密钥或生产账户数据提交到 Git。

## 本地开发

需要 Flutter stable、Dart、对应平台 SDK，以及项目所需的系统依赖。项目 CI 固定使用 Flutter `3.44.8`。

```bash
flutter pub get
flutter analyze lib test --no-fatal-infos --no-fatal-warnings
flutter test
flutter build web --release
flutter build apk --release --split-per-abi
flutter build windows --release
flutter build linux --release
flutter build macos --release --no-codesign
flutter build ios --release --no-codesign
```

平台能力在运行时隔离；不支持的桌面能力不能阻塞登录、聊天或 Web 构建。Android 已允许访问当前服务端所需的明文 HTTP API。

## 构建与 CI

`file .github/workflows/build.yml` 执行分析、测试和最终产物构建：

- Android：`armeabi-v7a`、`arm64-v8a`、`x86_64` 三个 APK。
- Linux：x64 `.deb` 与 `.rpm`。
- Windows：x64 安装/压缩产物。
- macOS：x64 与 arm64 DMG。
- iOS：开发测试用 ad hoc 签名 IPA；它不是 App Store 分发签名。
- Web：release 静态站点。

`file .github/workflows/cross_compile_engine.yml` 单独维护跨平台构建引擎验证，并记录每个平台、runner、架构和 Flutter 版本。GitHub Actions 不会把 info 或 warning 当作失败，但错误和测试失败仍会阻止发布。

Apple 离线构建使用 `codesign -s -` ad hoc 签名，不依赖证书、P12、钥匙串或密码。OpenSSL 自签名证书不能替代 Apple 的有效开发者/分发证书，因此不会伪装成可上架签名。

## 插件与 CIP

插件中心负责 `.oldchat-plugin`，CIP 中心负责 `.cip`。导入后内容保存到当前 UID 的账户存储，不依赖临时选择路径；扩展名大小写不敏感。插件权限必须显式声明，未知权限直接拒绝。

详细格式、权限、生命周期、宿主 API、UI 节点和示例见 `file PLUGIN_DEVELOPMENT.md`。

## API 与协议文档

- `file api.md`：客户端 API 约定。
- `file api2.md`：新旧 API 差异。
- `file routes.md`：服务端路由。
- `file client.md`：客户端行为说明。
- `file lua-cip.md`：CIP Lua 参考。

## 许可

本项目使用 MIT License，详见 `file LICENSE`。
