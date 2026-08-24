# OldChat For AllPlatform

OldChat For AllPlatform 是基于 Flutter 的跨平台聊天客户端。`main` 是全平台分支，目标平台为 Windows、Android、iOS、macOS、Linux 和 Web。

## 当前约定

- 所有常规业务请求默认使用 V2 协议。
- 只有设置环境变量 `OLDCHAT_ENABLE_V1_FALLBACK=true` 时，客户端才允许在 V2 不可用时回退到 V1。
- V1 回退服务器：`http://154.9.24.232:8080`。
- HTTP 400 统一向用户显示“服务器开小差了”。
- 登录、注册、人机验证、私聊、群聊、动态、公开法庭、插件和 CIP 均属于客户端支持范围。
- CIP 小程序支持声明式 UI 返回值，UI 由客户端渲染。
- 界面缩放范围为 50%–500%，首次进入会提示设置，之后可在设置中调整并持久化。
- 聊天消息气泡和聊天背景使用分层右键菜单；免打扰只属于 Home 会话列表，不属于聊天内容菜单。
- 资料页中的动态在嵌入模式显示，不额外显示动态页返回按钮。

## 平台与构建

```text
Dart package: oldchatforallplatform
Android: com.coloryi.oldchatforallplatform
iOS/macOS: com.coloryi.oldchatforallplatform
```

安装依赖并运行测试：

```bash
flutter pub get
flutter analyze lib test
flutter test
```

构建全平台 release 产物：

```bash
flutter build apk --release --split-per-abi
flutter build web --release
flutter build windows --release
flutter build linux --release
flutter build macos --release --no-codesign
flutter build ios --release --no-codesign
```

`file .github/workflows/build.yml` 负责全平台构建与产物上传。Apple 的人机验证页面使用 WebView；网络配置允许当前 HTTP 服务端所需的访问方式，应用不因验证码请求相机权限。

## 目录与文档

- `file lib/`：Flutter 客户端源码。
- `file api2.md`：V2 API 与兼容边界。
- `file api.md`：API 参考。
- `file routes.md`：服务端路由。
- `file lua-cip.md`：CIP Lua 与 UI 规范。
- `file PLUGIN_DEVELOPMENT.md`：插件包、权限和生命周期。
- `file .github/workflows/build.yml`：全平台 CI。

## 安全

不要提交真实密码、访问令牌、设备密钥或生产账户数据。V1 回退由本地环境变量显式启用，不由插件控制，也不在普通 UI 中默认开启。

## 许可

MIT License，详见 `file LICENSE`。
