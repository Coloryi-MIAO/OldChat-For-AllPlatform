import 'package:flutter/material.dart';

class AppLocalizations {
  final Locale locale;

  const AppLocalizations(this.locale);

  static const delegate = _AppLocalizationsDelegate();
  static const supportedLocales = [Locale('zh'), Locale('en')];
  static AppLocalizations current = AppLocalizations(const Locale('zh'));

  static void setCurrent(Locale locale) {
    current = AppLocalizations(locale);
  }

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations) ??
      const AppLocalizations(Locale('zh'));

  bool get isEnglish => locale.languageCode == 'en';

  String text(String zh, String en) => isEnglish ? en : zh;
  String t(String zh) => isEnglish ? _english[zh] ?? zh : zh;

  static final _english = <String, String>{
    '加载消息失败: \$e': 'Failed to load messages: \$e',
    '搜索聊天记录': 'Search chat history',
    '输入关键词后搜索聊天记录': 'Enter keywords to search chat history',
    '关闭': 'Close',
    '我已认真阅读并完全同意《用户服务协议与免责声明》':
        'I have carefully read and fully agree to the User Service Agreement and Disclaimer',
    '我已完整阅读并同意《用户服务协议与免责声明》':
        'I have read and agree to the User Service Agreement and Disclaimer',
    '阅读《用户服务协议与免责声明》': 'Read the User Service Agreement and Disclaimer',
    '搜索': 'Search',
    '群成员': 'Group members',
    '查看成员、身份与资料': 'View members, roles, and profiles',
    '搜索历史消息': 'Search message history',
    '按关键词定位历史内容': 'Find historical content by keyword',
    '暂无成员': 'No members yet',
    '加载群成员失败: \$e': 'Failed to load group members: \$e',
    '不是好友': 'Not friends',
    '您还不是对方的好友，需要先发送好友申请才能聊天。':
        'You are not friends yet. Send a friend request before chatting.',
    '取消': 'Cancel',
    '发送申请': 'Send request',
    '你们已经是好友了': 'You are already friends',
    '您已发送过好友申请，请等待对方通过':
        'You have already sent a friend request. Please wait for approval.',
    '对方已向您发送好友申请，请检查通知':
        'The other person sent you a friend request. Check your notifications.',
    '好友申请已发送，等待对方通过': 'Friend request sent. Waiting for approval.',
    '发送申请失败: \$e': 'Failed to send request: \$e',
    '操作已提交': 'Action submitted',
    '操作失败：\$error': 'Action failed: \$error',
    '发送失败: \$e': 'Failed to send: \$e',
    '发红包': 'Send red packet',
    '请输入有效金额': 'Enter a valid amount',
    '请输入有效个数': 'Enter a valid quantity',
    '发送': 'Send',
    '红包已发送': 'Red packet sent',
    '红包发送失败: \$e': 'Failed to send red packet: \$e',
    '领取成功：\$amount 旧币': 'Claimed successfully: \$amount old coins',
    '该红包已被领取': 'This red packet has already been claimed',
    '领取失败: \$e': 'Failed to claim: \$e',
    '回到底部': 'Back to bottom',
    '刷新消息': 'Refresh messages',
    '先输入要发送的内容': 'Enter something to send first',
    '引用': 'Quote',
    '复制': 'Copy',
    '已复制': 'Copied',
    '撤回': 'Recall',
    '打开阅后即焚消息失败：\$error': 'Failed to open disappearing message: \$error',
    '撤回失败: \$e': 'Failed to recall: \$e',
    '引用: \${_quotedMessage!.fromUid}': 'Quote: \${_quotedMessage!.fromUid}',
    '图片': 'Image',
    '视频': 'Video',
    '文件': 'File',
    '红包': 'Red packet',
    '暂无本地收藏表情': 'No locally saved stickers',
    '发送表情失败：\$error': 'Failed to send sticker: \$error',
    '消息最多 2000 字': 'Messages can be up to 2,000 characters',
    '@提及': '@Mention',
    '查看资料': 'View profile',
    '发送剪贴板内容？': 'Send clipboard content?',
    '已复制会话ID': 'Session ID copied',
    '清空输入框': 'Clear input',
    '复制会话ID': 'Copy session ID',
    '群成员与群工具': 'Group members and tools',
    '关键词': 'Keyword',
    '金额 (旧币)': 'Amount (old coins)',
    '个数': 'Quantity',
    '红包标题': 'Red packet title',
    '打开后多少秒销毁（5-86400）': 'Destroy how many seconds after opening (5–86400)',
    '发送图片/视频/红包': 'Send image/video/red packet',
    '发送收藏表情': 'Send saved sticker',
    '查看未读消息': 'View unread messages',
    '查看群成员': 'View group members',
    '编辑功能按钮': 'Edit feature buttons',
    '保存': 'Save',
    '人机验证': 'Human verification',
    '处理失败：\$error': 'Processing failed: \$error',
    '加载失败：\$_error': 'Load failed: \$_error',
    '暂无\$title': 'No \$title',
    '自动领取红包': 'Auto-claim red packets',
    '默认关闭；请自行确认风险': 'Off by default; confirm the risks yourself',
    '私聊': 'Direct message',
    '群聊': 'Group chat',
    '插件中心': 'Plugin center',
    '系统插件默认关闭。自动发送图片、红包和动态必须先通过审核；插件不能读取 Token、执行脚本或绕过宿主 API。':
        'System plugins are off by default. Automatic sending of images, red packets, and posts requires review first; plugins cannot read Tokens, run scripts, or bypass the host API.',
    '待审核操作': 'Pending actions',
    '功能按钮编辑': 'Feature button editor',
    '自定义功能页中的入口显示，不影响安全入口':
        'Customize entry points shown on the feature page; security entry points are unaffected',
    '权限：\$permissions': 'Permissions: \$permissions',
    '每分钟最多领取': 'Maximum claims per minute',
    '每日最多领取': 'Maximum claims per day',
    '适用会话': 'Applicable chats',
    '触发关键词': 'Trigger keywords',
    '自动回复内容': 'Auto-reply content',
    '自动回复冷却秒数': 'Auto-reply cooldown (seconds)',
    'CIP 已导入，请在 CIP 中心启用后运行':
        'CIP imported. Enable it in the CIP center before running.',
    '仅支持 .oldchat-plugin 文件；CIP 请在 CIP 中心导入':
        'Only .oldchat-plugin files are supported here; import CIP files in the CIP center.',
    '导入 .oldchat-plugin / .cip': 'Import .oldchat-plugin / .cip',
    '通过并执行': 'Approve and execute',
    '拒绝': 'Reject',
    'CIP 小程序': 'CIP applet',
    '协议加载失败': 'Failed to load the agreement',
    '空消息': 'Empty message',
    '服务器返回的消息无效': 'The server returned an invalid message',
    '点击完成人机验证': 'Complete human verification',
    '人机验证已完成，点击重新验证': 'Verification complete; click to verify again',
    '上一张': 'Previous',
    '下一张': 'Next',
    '系统：\${_environment!.operatingSystem}':
        'System: \${_environment!.operatingSystem}',
    '模式：\${_environment!.buildMode} · \${_environment!.architecture}':
        'Mode: \${_environment!.buildMode} · \${_environment!.architecture}',
    '缓存：\${_environment!.cacheBytes} bytes':
        'Cache: \${_environment!.cacheBytes} bytes',
    '缓存目录：\${_environment!.cachePath}':
        'Cache directory: \${_environment!.cachePath}',
    '缓存已清除': 'Cache cleared',
    '清除缓存失败：\$error': 'Failed to clear cache: \$error',
    '缓存位置已设置为 \$result': 'Cache location set to \$result',
    'Aria2 设置已保存': 'Aria2 settings saved',
    '确定': 'OK',
    '清除缓存': 'Clear cache',
    '选择位置': 'Choose location',
    '保存 Aria2 设置': 'Save Aria2 settings',
    'DNS 缓存已清除': 'DNS cache cleared',
    '字体': 'Font',
    'API 路径版本': 'API path version',
    'v1（兼容旧服务端）': 'v1 (compatible with legacy servers)',
    'v2（新版服务端）': 'v2 (new server)',
    'API 已切换为 \$value，重新进入页面后生效':
        'API switched to \$value; take effect after re-entering the page',
    '粉色主题': 'Pink theme',
    '启用粉色主题配色': 'Enable pink theme colors',
    '桌面通知': 'Desktop notifications',
    '收到新消息时显示 Windows 通知': 'Show Windows notifications for new messages',
    '关闭时确认': 'Confirm on close',
    '关闭窗口时弹出确认对话框': 'Show a confirmation dialog when closing the window',
    '关闭操作': 'Close action',
    '缓存大小': 'Cache size',
    'Aria2 设置': 'Aria2 settings',
    '显示高级下载设置': 'Show advanced download settings',
    '端点': 'Endpoint',
    '密钥': 'Key',
    '管理自动回复、红包助手和审核队列':
        'Manage auto-replies, red packet assistant, and review queue',
    '自动检查更新': 'Check for updates automatically',
    '启动应用后在后台检查新版本':
        'Check for new versions in the background after launching the app',
    '检查更新': 'Check for updates',
    '点击检查是否有新版本': 'Click to check for a new version',
    '环境诊断': 'Environment diagnostics',
    '查看系统环境信息': 'View system environment information',
    'DNS 缓存': 'DNS cache',
    '清除系统 DNS 缓存': 'Clear the system DNS cache',
    '退出登录': 'Log out',
    '清除登录状态并返回登录页': 'Clear login state and return to the login page',
    '请填写所有字段': 'Please fill in all fields',
    '仅支持 126、163、QQ 邮箱': 'Only 126, 163, and QQ Mail are supported',
    '请先完成人机验证': 'Complete human verification first',
    '请先填写邮箱并完成人机验证': 'Fill in your email and complete human verification first',
    '验证码已发送': 'Verification code sent',
    '服务器地址设置': 'Server address settings',
    '修改后会自动保存并刷新': 'Changes are saved and applied automatically',
    '请输入服务器地址': 'Enter the server address',
    '地址必须以 http:// 或 https:// 开头':
        'The address must start with http:// or https://',
    '设置已保存，页面将刷新': 'Settings saved; the page will refresh',
    '记住密码': 'Remember password',
    '服务器设置': 'Server settings',
    '用户名 / 邮箱 / UID': 'Username / email / UID',
    '密码': 'Password',
    '用户名': 'Username',
    '邮箱（仅支持 126 / 163 / QQ）': 'Email (126 / 163 / QQ only)',
    '密码（至少6位）': 'Password (at least 6 characters)',
    '邮箱验证码': 'Email verification code',
    '今日配额已用完，请明天再试': 'Today’s quota is used up. Try again tomorrow.',
    'AI 接口设置': 'AI API settings',
    'AI 助手': 'AI assistant',
    '模型': 'Model',
    'AI 会话': 'AI conversation',
    '问AI任何问题': 'Ask AI anything',
    '模型名称': 'Model name',
    '例如：deepseek-chat': 'Example: deepseek-chat',
    '输入问题...': 'Enter a question...',
    '收藏操作失败：\$error': 'Failed to favorite: \$error',
    '暂无可分享的聊天': 'No chats available to share',
    '选择分享对象': 'Choose who to share with',
    '好友': 'Friends',
    '获取会话失败: \$error': 'Failed to get conversation: \$error',
    '已分享给 \${target.name ?? target.id}':
        'Shared with \${target.name ?? target.id}',
    '分享失败: \$error': 'Failed to share: \$error',
    '表情广场': 'Sticker plaza',
    '加载失败: \$_errorMessage': 'Load failed: \$_errorMessage',
    '重试': 'Retry',
    '暂无表情': 'No stickers yet',
    '加载更多': 'Load more',
    '喜欢 \${emoji.likes}': 'Like \${emoji.likes}',
    '上传功能请使用网页端或 App 内文件选择': 'Use the web or the in-app file picker to upload',
    '加载动态失败: \$e': 'Failed to load posts: \$e',
    '操作失败: \$e': 'Action failed: \$e',
    '评论成功': 'Comment posted',
    '评论失败: \$e': 'Failed to comment: \$e',
    '删除动态': 'Delete post',
    '确定要删除这条动态吗？': 'Are you sure you want to delete this post?',
    '删除': 'Delete',
    '已删除': 'Deleted',
    '删除失败: \$e': 'Failed to delete: \$e',
    '发布动态': 'Create post',
    '上传失败: \$e': 'Upload failed: \$e',
    '发布': 'Post',
    '请输入内容或选择图片': 'Enter content or select an image',
    '发布成功': 'Posted successfully',
    '发布失败: \$e': 'Failed to post: \$e',
    '写评论': 'Write a comment',
    '全部评论 (\${comments.length})': 'All comments (\${comments.length})',
    '暂无评论': 'No comments yet',
    '查看全部 \${moment.comments} 条评论': 'View all \${moment.comments} comments',
    '分享你的想法...': 'Share your thoughts...',
    '选择图片（可多选）': 'Select images (multiple allowed)',
    '输入评论...': 'Enter a comment...',
    '写评论...': 'Write a comment...',
    '频道': 'Channel',
    '\${_channel.subscriberCount} 人订阅':
        '\${_channel.subscriberCount} subscribers',
    '暂无帖子': 'No posts yet',
    '搜索失败：\$error': 'Search failed: \$error',
    '频道发现': 'Discover channels',
    '发布频道消息': 'Publish channel message',
    '搜索频道': 'Search channels',
    '头像已更新': 'Avatar updated',
    '更新失败: \$e': 'Update failed: \$e',
    '昵称已更新': 'Nickname updated',
    '签名已更新': 'Bio updated',
    '添加好友': 'Add friend',
    '添加': 'Add',
    '好友申请已发送': 'Friend request sent',
    '加入群聊': 'Join group chat',
    '加入': 'Join',
    '已加入群聊': 'Joined group chat',
    '加入失败: \$e': 'Failed to join: \$e',
    '个人主页': 'Profile',
    '加载失败: \$_error': 'Load failed: \$_error',
    '暂无数据': 'No data yet',
    '旧币数量': 'Old coin balance',
    '查看我的动态': 'View my posts',
    '编辑\$label': 'Edit\$label',
    '我的动态 (0)': 'My posts (0)',
    '暂无动态': 'No posts yet',
    '我的动态 (\${_myMoments.length})': 'My posts (\${_myMoments.length})',

    '查看全部 (\${_myMoments.length})': 'View all (\${_myMoments.length})',
    '输入对方 UID': 'Enter the other person’s UID',
    '输入群聊 ID': 'Enter the group chat ID',
    '我的动态': 'My posts',
    '请输入\$label': 'Enter \$label',
    '发私信': 'Send a direct message',
    '加载音乐失败: \$e': 'Failed to load music: \$e',
    '\${music.title} · 歌词': '\${music.title} · Lyrics',
    '音频链接无效': 'Invalid audio link',
    '\$artist · \${music.plays}次播放': '\$artist · \${music.plays} plays',
    '选择一首歌曲播放': 'Choose a song to play',
    '展开歌词': 'Expand lyrics',
    '暂无歌词': 'No lyrics yet',
    '分享到聊天': 'Share to chat',
    '音乐广场': 'Music plaza',
    '分享': 'Share',
    '搜索音乐': 'Search music',
    '资源上传成功': 'Resource uploaded successfully',
    '上传失败：\$error': 'Upload failed: \$error',
    '全部': 'All',
    '该分区暂无资源': 'No resources in this section',
    '打开': 'Open',
    '下载': 'Download',
    '资源广场': 'Resource plaza',
    '下载资源': 'Download resource',
    '搜索资源': 'Search resources',
    '加载收藏失败: \$e': 'Failed to load favorites: \$e',
    '移除收藏': 'Remove favorite',
    '确定要移除该收藏吗？': 'Are you sure you want to remove this favorite?',
    '移除': 'Remove',
    '已移除收藏': 'Favorite removed',
    '类型: \$type': 'Type: \$type',

    '我的收藏': 'My favorites',
    '暂无收藏': 'No favorites yet',
    '详情': 'Details',
    '选择一个会话开始聊天': 'Choose a conversation to start chatting',
    '右键刷新': 'Right-click to refresh',
    '群聊已不存在，已从会话列表移除':
        'The group chat no longer exists and was removed from the conversation list',
    '没有匹配的会话': 'No matching conversations',
    '最近会话': 'Recent conversations',
    '搜索好友或群聊...': 'Search friends or group chats...',
    '表情': 'Sticker',
    '签到失败：\$error': 'Check-in failed: \$error',
    '图片上传失败：\$error': 'Image upload failed: \$error',
    '已发布到签到墙': 'Published to the check-in wall',
    '发布失败：\$error': 'Failed to post: \$error',
    '签到墙': 'Check-in wall',
    '今日签到': 'Today’s check-in',
    '已选择 \${_mediaUrls.length} 张图片': '\${_mediaUrls.length} images selected',
    '签到': 'Check in',
    '暂无签到动态': 'No check-in posts yet',
    '写下今天的状态…': 'Write today’s status…',
    '公开法庭': 'Public court',
    '暂无公开案件': 'No public cases yet',
    '状态：\$status': 'Status: \$status',
    '投票成功': 'Vote submitted',
    '投票失败：\$error': 'Voting failed: \$error',
    '讨论已提交': 'Discussion submitted',
    '提交讨论失败：\$error': 'Failed to submit discussion: \$error',
    '陈述已提交': 'Statement submitted',
    '提交失败：\$error': 'Submission failed: \$error',

    '举报证据：\$evidence': 'Report evidence: \$evidence',

    '支持': 'Support',
    '反对': 'Oppose',
    '提交陈述': 'Submit statement',
    '讨论 (\${_discussions.length})': 'Discussion (\${_discussions.length})',
    '发布讨论': 'Post discussion',
    '暂无讨论': 'No discussions yet',
    '写下你的观点': 'Write your opinion',
    '参与讨论': 'Join the discussion',
    '处理群聊申请失败：\$e': 'Failed to process group chat request: \$e',
    '加载通知失败: \$e': 'Failed to load notifications: \$e',
    '请求ID无效': 'Invalid request ID',
    '好友申请 (\${_friendRequests.length})':
        'Friend requests (\${_friendRequests.length})',
    '点击操作': 'Click an action',
    '请求添加您为好友 · \${_formatTime(createdAt)}':
        'Requested to add you as a friend · \${_formatTime(createdAt)}',
    '群聊申请 (\${_groupRequests.length})':
        'Group chat requests (\${_groupRequests.length})',
    '\$fromName 申请加入 \$groupName': '\$fromName requested to join \$groupName',
    '系统通知 (\${_notifications.length})':
        'System notifications (\${_notifications.length})',
    '暂无通知': 'No notifications yet',
    '通知中心': 'Notification center',
    '接受': 'Accept',
    '全部已读': 'Mark all as read',
    '文件已保存到 Windows 下载文件夹。': 'File saved to the Windows Downloads folder.',
    '文件：\${widget.fileName}': 'File: \${widget.fileName}',
    '下载完成，文件已保存到 Windows“下载”文件夹。':
        'Download complete. The file was saved to the Windows “Downloads” folder.',
    '浏览器打开': 'Open in browser',
    '系统播放器打开': 'Open in system player',
    '下载视频': 'Download video',
    '播放视频': 'Play video',
    '发现新版本 \${release.tagName}': 'New version found: \${release.tagName}',
    '当前版本：\${widget.currentVersion}':
        'Current version: \${widget.currentVersion}',
    '最新版本：\${release.name}': 'Latest version: \${release.name}',
    '发布时间：\${release.publishedAt!.toLocal()}':
        'Released: \${release.publishedAt!.toLocal()}',
    '本次更新': 'What’s new',
    '下载完成，点击“立即更新”后将启动更新程序并关闭当前 OldChat。':
        'Download complete. Click “Update now” to launch the updater and close the current OldChat.',
    '正在启动更新程序，即将关闭当前 OldChat…':
        'Launching the updater. The current OldChat will close shortly…',
    '打开位置': 'Open location',
    '已交给 aria2 下载（任务 \$gid）': 'Sent to aria2 for download (task \$gid)',
    '图片已保存到：\$path': 'Image saved to: \$path',
    '保存失败：\$error': 'Save failed: \$error',
    '没有可显示的图片': 'No image to display',
    '保存当前图片': 'Save current image',
    '无法打开浏览器': 'Unable to open browser',
    '图片已保存到: \$path': 'Image saved to: \$path',
    '保存失败': 'Save failed',
    '保存图片': 'Save image',
    '查看原图': 'View original image',
    '语音链接无效': 'Invalid voice link',
    '共 \$count 条消息': '\$count messages',
    '... 等\${items.length}条': '... and \${items.length} more',
    '图片链接无效': 'Invalid image link',
    '引用: \$quoteFrom': 'Quote: \$quoteFrom',
    '歌词': 'Lyrics',
    '\$amountDisplay 旧币': '\$amountDisplay old coins',
    '· \${totalCount}个': '· \${totalCount}',
    '· 剩\${remainingCount}个': '· \${remainingCount} left',
    '已领取': 'Claimed',
    '已发送': 'Sent',
    '领取': 'Claim',
    '我': 'Me',
    '用浏览器打开': 'Open in browser',
    '下载文件': 'Download file',
    '关闭 OldChat': 'Close OldChat',
    '不再提示': 'Don’t show again',
    '最小化到托盘': 'Minimize to tray',
    '直接关闭': 'Close directly',
    '显示窗口': 'Show window',
    '隐藏窗口': 'Hide window',
    '退出': 'Exit',
    '聊天': 'Chat',
    'Windows 通知测试成功': 'Windows notification test succeeded',
    'Windows 通知测试': 'Windows notification test',
    '测试通知未发送：WinToast 未初始化':
        'Test notification was not sent: WinToast is not initialized',
    '关键词提醒：': 'Keyword alert: ',
    '金币余额': 'Coin balance',
    '今日已刮得': 'Earned today',
    '登录失败:': 'Login failed: ',
    '注册失败:': 'Registration failed: ',
    '更新 UID 失败': 'Failed to update UID',
    'CIP 导入失败': 'CIP import failed',
    'CIP 执行失败': 'CIP execution failed',
    'CIP 已执行': 'CIP executed',
    '运行': 'Run',
    '已启用': 'Enabled',
    '已停用': 'Disabled',
    '请先写下观点': 'Write your viewpoint before voting',
    '观点与投票已提交': 'Viewpoint and vote submitted',
    '无法读取证据图片': 'Unable to read the evidence image',
    '《用户服务协议与免责声明》': 'User Service Agreement and Disclaimer',
    '我已阅读并同意': 'I have read and agree',
    '无法读取图片': 'Unable to read the image',
    '上传图片': 'Upload image',
    '已订阅': 'Subscribed',
    '订阅': 'Subscribe',
    '设置': 'Settings',
    '功能中心': 'Tools',
    '更多': 'More',
    '刷新': 'Refresh',
    '语言': 'Language',
    '遮罩时间': 'Splash duration',
    '缓存': 'Cache',
    '鸿蒙字体': 'HarmonyOS font',
    '微软雅黑（系统字体）': 'Microsoft YaHei (system font)',
    '开机自启动设置失败': 'Failed to configure launch at startup',
    '重新检测': 'Recheck',
    '置顶': 'Pin',
    '取消置顶': 'Unpin',
    '添加到最近会话': 'Add to recent conversations',
    '移除最近会话': 'Remove from recent conversations',
    '已接受申请': 'Request accepted',
    '已拒绝申请': 'Request rejected',
    '好友申请': 'Friend request',
    '群聊申请': 'Group chat request',
    '已接受群聊申请': 'Group chat request accepted',
    '已拒绝群聊申请': 'Group chat request rejected',
    '已接受好友申请': 'Friend request accepted',
    '已拒绝': 'Rejected',
    '我的资料': 'My profile',
    '用户资料': 'User profile',
    '无内容': 'No content',
    '上传中…': 'Uploading…',
    '已取消本地收藏': 'Removed from local favorites',
    '已保存到本地': 'Saved locally',
    'TA的动态': 'Their posts',
    '动态': 'Posts',
    '完成': 'Done',
    '未知用户': 'Unknown user',
    '阅后即焚': 'Disappearing message',
    '暂无匹配成员': 'No matching members',
    '发布失败': 'Failed to publish',
    '操作': 'Action',
    '选项': 'Option',
    '导入 .cip': 'Import .cip',
    '暂无本地 CIP，点击右上角导入': 'No local CIP. Click the top-right button to import one.',
    '任务栏闪动通知': 'Taskbar flash notifications',
    '窗口最小化时闪动任务栏图标': 'Flash the taskbar icon when the window is minimized',
    '测试 Windows 通知': 'Test Windows notifications',
    'Windows 通知已发送': 'Windows notification sent',
    '多会话消息接收': 'Multi-session message reception',
    '后台接收所有会话的消息': 'Receive messages from all conversations in the background',
    '消息排序修正': 'Message ordering correction',
    '按服务端时间、序号和消息 ID 排序': 'Sort by server time, sequence, and message ID',
    '最小化到系统托盘': 'Minimize to the system tray',
    '直接退出程序': 'Exit the application directly',
    '留空则不使用密钥': 'Leave blank to use no key',
    '选择服务器': 'Select server',
    '当前服务器地址': 'Current server address',
    '服务器已保存': 'Server saved',
    '自定义服务器（每行一个）': 'Custom servers (one per line)',
    '设置已恢复默认': 'Settings restored to defaults',
    '恢复默认设置': 'Restore default settings',
    '未命名': 'Untitled',
    '未命名分区': 'Untitled section',
    '未命名资源': 'Untitled resource',
    '公开案件': 'Public case',
    '原告': 'Plaintiff',
    '被告': 'Defendant',
    '用户': 'User',
    '未知': 'Unknown',
    '举报人': 'Reporter',
    '举报理由': 'Report reason',
    '辩护理由': 'Defense',
    '裁决': 'Verdict',
    '封禁时长': 'Ban duration',
    '投票': 'Votes',
    '当前系统没有可用的内置浏览器，请使用系统浏览器完成验证': 'No built-in browser is available. Use the system browser to complete verification.',
    '人机验证加载失败': 'Failed to load human verification',
    '请先阅读并同意用户服务协议与免责声明': 'Read and agree to the User Service Agreement and Disclaimer first',
    '仅支持 QQ 邮箱': 'Only QQ Mail is supported',
    '请先完整阅读用户服务协议，至少 30 秒后才能注册': 'Read the complete User Service Agreement for at least 30 seconds before registering',
    '注册成功！请登录': 'Registration successful. Please log in.',
    '邮箱（仅支持 QQ）': 'Email (QQ Mail only)',
    '没有可显示的入口，请到设置中恢复默认设置': 'No entries to display. Restore the defaults in Settings.',
    '支持并提交': 'Support and submit',
    '反对并提交': 'Oppose and submit',
    '写下观点后选择投票，可选上传图片': 'Write your viewpoint, choose a vote, and optionally upload an image',
    '关于 OldChat': 'About OldChat',
    '暂无会话': 'No conversations yet',
    '主页': 'Home',
    '功能': 'Tools',
    '个人': 'Profile',
  };

  String get settings => t('设置');
  String get tools => t('功能中心');
  String get more => t('更多');
  String get logout => t('退出登录');
  String get refresh => t('刷新');
  String get pluginCenter => t('插件中心');
  String get cip => t('CIP 小程序');
  String get language => text('语言 / Language', 'Language');
  String get chinese => t('中文');
  String get english => 'English';
  String get splashDuration => t('遮罩时间');
  String splashSeconds(double value) => isEnglish
      ? '${value.toStringAsFixed(1)} seconds (2–5)'
      : '${value.toStringAsFixed(1)} 秒（2–5 秒）';
  String get cache => t('缓存');
  String get clearCache => t('清除缓存');
  String get notifications => t('通知');
  String get desktopNotifications => t('桌面通知');
  String get font => t('字体');
  String get harmonyFont => t('鸿蒙字体');
  String get yaheiFont => t('微软雅黑（系统字体）');
  String get update => t('检查更新');
  String get functionButtonEditor => t('功能按钮编辑');
  String get save => t('保存');
  String get cancel => t('取消');
  String get close => t('关闭');
  String get login => text('登录', 'Log in');
  String get register => text('注册', 'Register');
  String get chat => text('聊天', 'Chat');
  String get profile => text('个人中心', 'Profile');
  String get loading => text('加载中…', 'Loading…');
  String get retry => t('重试');
  String get send => t('发送');
  String get delete => t('删除');
  String get confirm => t('确定');
  String get scratchCard => t('每日刮刮乐');
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'zh' || locale.languageCode == 'en';

  @override
  Future<AppLocalizations> load(Locale locale) async {
    final value = AppLocalizations(locale);
    AppLocalizations.setCurrent(locale);
    return value;
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

extension AppLocalizationContext on BuildContext {
  AppLocalizations get tr => AppLocalizations.of(this);
}
