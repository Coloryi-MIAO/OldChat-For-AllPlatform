# OldChat For AllPlatform 插件开发文档

适用于 OldChat For AllPlatform `1.4.8-beta.5+6`。插件是受权限控制的本地功能模块，不是任意代码执行器。本文以当前 `PluginService`、`PluginCenterPage` 和 `CipPage` 的实际行为为准。

## 1. 两种包格式

### `.oldchat-plugin`

这是 ZIP 包，根目录必须包含 `manifest.json`，其余文件只能位于 `assets/`。也可以直接导入 JSON manifest，适合最小规则插件。

### `.cip`

这是 ZIP 包，根目录必须包含 `manifest.json` 与 `main.lua`，其余文件只能位于 `assets/`。CIP 会在 CIP 中心展示，可启用后手动运行，也可在收到消息时由宿主触发。

大小限制：插件压缩包最多 4 MiB、解压后最多 16 MiB、最多 128 个条目；CIP 压缩包最多 2 MiB、解压后最多 8 MiB、脚本最多 512 KiB。路径不能以 `/` 开头，不能包含 `..`、盘符或符号链接。

导入后的插件和 CIP 会按当前用户保存到本地账户存储，重启应用不会丢失；CIP 页面会监听执行结果并直接渲染页面、按钮、输入框、复选框、图片和容器。插件主题不是自动强制替换主题，必须启用插件后在插件中心点击“应用主题”。

## 2. manifest

```json
{
  "id": "example.plugin",
  "name": "Example Plugin",
  "version": "1.0.0",
  "api_version": 1,
  "description": "A small OldChat For AllPlatform plugin",
  "permissions": ["events.message", "storage.local"],
  "rules": [],
  "config": {},
  "entry": "main.lua"
}
```

`id` 必须符合 `^[a-z0-9][a-z0-9._-]*$`，并作为稳定唯一标识。`name`、`version`、`description` 用于界面展示。`permissions` 之外的未知字段会保留，但未知权限会直接拒绝，不会静默提权。CIP 的脚本入口固定为根目录 `main.lua`；`entry` 仅用于文档表达，不能替代该文件。

## 3. 权限

当前宿主允许：

| 权限 | 用途 |
| --- | --- |
| `events.message` | 接收当前消息事件 |
| `messages.send` | 发送宿主允许的文本消息 |
| `messages.send_image` | 提交图片消息待审核 |
| `redpacket.claim` | 执行红包领取 |
| `redpacket.send` | 提交红包发送待审核 |
| `checkin.run` | 执行每日签到 |
| `checkin.post` | 提交签到墙内容待审核 |
| `moments.post` | 提交动态待审核 |
| `theme.apply` | 允许用户手动应用主题 |
| `storage.local` / `storage` | 访问当前账户的插件专属存储 |
| `network` / `network_external` | 通过宿主 API 访问受限网络能力 |
| `files.local` | 由用户发起文件选择 |
| `camera` | 由用户发起拍摄 |

插件不能读取其他账户目录、token、密码、设备密钥或系统剪贴板，不能绕过宿主 API，不能自行连接未声明的服务器。网络请求使用 `app_http_get(path)`，路径必须是以 `/` 开头的宿主 API 相对路径。

## 4. 规则插件

```json
{
  "id": "example.auto-reply",
  "name": "Example Auto Reply",
  "version": "1.0.0",
  "permissions": ["events.message", "messages.send"],
  "rules": [
    {
      "when": {
        "conversation_types": ["direct", "group"],
        "contains": "hello"
      },
      "action": {
        "type": "send_text",
        "text": "收到：{text}",
        "cooldown_seconds": 60
      }
    }
  ]
}
```

事件字段包括 `type`、`conversation_type`、`conversation_id`、`message_id`、`from_uid`、`text`、`msg_type`、`created_at` 与 `media_url`。文本动作支持 `{text}`、`{uid}` 和 `{conversation_id}`。图片、红包、签到和动态动作会进入待审核队列，用户在插件中心确认后才执行。

## 5. CIP Lua 宿主 API

CIP Lua 在受限环境运行。宿主会关闭 `io`、`os`、`debug`、`package`、`require`、`dofile`、`loadfile`、`load` 和 `collectgarbage`，不要依赖这些库。

### 基础函数

```lua
app_toast("Hello")
local value = app_storage_get("counter")
app_storage_set("counter", "1")
app_storage_remove("counter")
app_storage_clear()
local asset_url = app_asset("icon.png")
```

同时提供表形式：`app.toast`、`app.storage_get`、`app.storage_set`、`app.storage_remove`、`app.storage_clear`、`app.asset`。

`app_toast` 会调用当前系统通知适配层；Web 使用浏览器通知能力（需要用户授权），不支持时只保留应用内反馈。存储自动加上当前 CIP 的专属前缀，不能读取其他插件数据。

### 事件变量

消息触发时可读取：

```lua
print(event_type)
print(event_text)
print(conversation_id)
print(from_uid)
print(event.text)
print(event.conversation_type)
```

### 文件、相机与网络

```lua
local file, err = app_file_pick()
local photo, camera_err = app_camera_capture()
local response, request_err = app_http_get("/api/example")
```

这些函数需要对应权限；文件选择和相机由宿主发起，用户取消时返回 `nil, error`。网络只接受相对路径，不能使用 `http://`、`https://`、`..` 或反斜杠。

### 声明式 UI

CIP 可以用 UI 工厂返回节点，再交给 `ui_result` 显示：

```lua
local page = ui.page({
  type = "page",
  children = {
    { type = "text", text = "输入内容" },
    { type = "input", id = "message", label = "Message" },
    { type = "button", id = "run", label = "Run", action = "run" }
  }
})
ui_result(page)
```

支持节点：`page`、`column`、`row`、`list`、`text`、`button`、`image`、`input`、`checkbox`、`spacer`。按钮动作 `run` 或 `submit` 会把输入值、复选框值和节点 ID 传回 `event` 并再次执行 CIP；`clear` 清除当前结果。未知节点会被丢弃，深度、内容与字段均由宿主限制。

## 6. 生命周期与调试

1. 校验后缀、ZIP 路径、大小与 manifest。
2. 校验权限和脚本入口。
3. 导入到当前 UID 的账户存储并保持原有启用状态。
4. 用户在界面查看权限后启用。
5. 运行时捕获异常并写入插件日志，UI 结果通过监听器刷新。
6. 卸载插件会删除插件和账户级状态，不删除聊天缓存。

推荐先使用 `app_toast` 和 `app_storage_set` 验证宿主连接，再逐步加入网络、文件或 UI 权限。不要在脚本中写入任何 token、密码、私钥或生产数据。

## 7. 最小 CIP 示例

`manifest.json`：

```json
{
  "id": "example.hello-cip",
  "name": "Hello CIP",
  "version": "1.0.0",
  "description": "A minimal CIP applet",
  "permissions": ["storage.local"],
  "api_version": 1
}
```

`main.lua`：

```lua
local count = tonumber(app_storage_get("count") or "0") + 1
app_storage_set("count", tostring(count))
app_toast("CIP executed: " .. tostring(count))
```

把两个文件压缩为 `.cip`，在应用的 CIP 小程序页面导入、启用并运行。构建验证命令：

```bash
flutter pub get
flutter analyze lib test --no-fatal-infos --no-fatal-warnings
flutter test
```
