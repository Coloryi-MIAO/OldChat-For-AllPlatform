# OldChat For AllPlatform 插件开发

适用于 `OldChat For AllPlatform 1.4.5-beta.5+7`。插件是受权限控制的本地功能模块，不是任意代码执行器。

## 包格式

- `.oldchat-plugin`：ZIP 插件包，通常包含 `manifest.json`、规则/脚本和资源。
- `.cip`：CIP 功能包。
- 扩展名判断大小写不敏感，例如 `.OLDCHAT-PLUGIN` 和 `.CIP` 也必须被识别。
- 导入后必须复制到当前 UID 的账户插件目录，不能依赖临时选择路径。

## manifest

```json
{
  "id": "example.plugin",
  "name": "Example Plugin",
  "version": "1.0.0",
  "api_version": 1,
  "description": "A small OldChat For AllPlatform plugin",
  "permissions": [],
  "entry": "rules.json"
}
```

`id` 必须稳定且唯一；`entry` 必须指向包内文件。未知字段可以保留，未知权限必须拒绝，不得静默提权。

## 权限

可申请的最小权限包括：

- `chat.read`：读取当前允许的消息上下文
- `chat.send`：发送用户允许的文本或固定动作
- `notifications.show`：显示本地通知
- `redpacket.claim`：执行红包领取动作
- `storage.account`：读写当前 UID 的插件数据
- `files.local`：由用户发起的本地文件选择
- `camera`：由用户发起的拍摄

插件不得读取其他账户目录，不得读取或导出 token、密码、设备密钥，不得绕过 API 会话签名，不得自行访问未声明的服务器地址。服务器地址由宿主统一管理，当前主服务器为 `http://60.205.94.101:8080`，隐藏回退地址不可由插件查看。

## 红包助手规则

红包助手必须：

1. 以红包 ID 去重；
2. 记录尝试、成功、已领取、过期和失败状态；
3. 遵守服务端冷却、过期时间和用户确认要求；
4. 对 400、401、429 立即停止当前红包的重试；
5. 禁止并发领取同一红包、后台高频轮询和无限重试。

示例：

```json
{
  "rules": [
    {
      "when": "message.type == 'red_packet'",
      "action": "redpacket.claim",
      "require_user_confirmation": true
    }
  ]
}
```

## 生命周期

1. 检查后缀和包结构；
2. 解析并校验 manifest；
3. 展示权限，等待用户确认；
4. 写入当前账户插件目录；
5. 启用前做静态校验，运行时隔离异常；
6. 卸载插件文件和账户级状态，但不删除聊天缓存。

插件界面可见文本必须走本地化。插件包不得硬编码访问令牌、密码或未声明的 API 地址。

## 验证

```bash
flutter pub get
flutter analyze
flutter test
```

具体接口格式见 `api.md`，服务端路由见 `routes.md`。