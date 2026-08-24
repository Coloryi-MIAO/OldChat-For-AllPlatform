import 'package:flutter/material.dart';
import '../services/app_localizations.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../widgets/cached_image.dart';
import '../services/auth_service.dart';
import '../utils/url_helper.dart';
import '../pages/moments_page.dart';
import '../pages/chat_page.dart';

class UserProfilePage extends StatefulWidget {
  final String uid;
  const UserProfilePage({super.key, required this.uid});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  Map<String, dynamic>? _profile;
  bool _loading = true;
  String? _error;
  bool _isFriend = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final api = ApiService();
      final profile = await api.getUserProfile(widget.uid);
      final friends = await api.getFriends();
      setState(() {
        _profile = profile;
        _isFriend = friends.any((f) => f.id == widget.uid);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _sendFriendRequest() async {
    try {
      final api = ApiService();
      await api.sendFriendRequest(widget.uid);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.current.t('好友申请已发送'))),
      );
      if (mounted) setState(() => _isFriend = true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.current.t('发送失败: $e'))),
      );
    }
  }

  void _jumpToChat() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatPage(
          conversationId: widget.uid,
          type: 'direct',
          title: _profile?['display_name'] ?? _profile?['username'] ?? '聊天',
          embed: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final myUid = context.read<AuthService>().userId;
    final isMe = widget.uid == myUid;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.current.t(isMe ? '我的资料' : '用户资料')),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadProfile,
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(AppLocalizations.current.t('加载失败: $_error')))
              : _profile == null
                  ? Center(child: Text(AppLocalizations.current.t('暂无数据')))
                  : Row(
                      children: [
                        // 左侧个人信息
                        Container(
                          width: 280,
                          padding: const EdgeInsets.all(16),
                          color: Colors.grey[50],
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              CircleAvatar(
                                radius: 50,
                                backgroundImage: null,
                                child: _profile!['avatar_url'] == null ||
                                        _profile!['avatar_url']
                                            .toString()
                                            .isEmpty
                                    ? const Icon(Icons.person, size: 46)
                                    : ClipOval(
                                        child: CachedImage(
                                          resolveMediaUrl(_profile!['avatar_url']),
                                          width: 100,
                                          height: 100,
                                          cacheWidth: 240,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              const Icon(Icons.person, size: 46),
                                        ),
                                      ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _profile!['display_name'] ??
                                    _profile!['username'] ??
                                    '未命名',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                _profile!['uid'] ?? '',
                                style: const TextStyle(color: Colors.grey),
                              ),
                              if ((_profile!['user_title'] ?? _profile!['title'] ?? '').toString().trim().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Chip(label: Text((_profile!['user_title'] ?? _profile!['title']).toString())),
                                ),
                              SizedBox(height: 8),
                              Text(
                                _profile!['signature'] ?? '暂无签名',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 20),
                              if (!isMe)
                                _isFriend
                                    ? ElevatedButton.icon(
                                        onPressed: _jumpToChat,
                                        icon: const Icon(Icons.chat),
                                        label: Text(AppLocalizations.current.t('发私信')),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: primaryColor,
                                          foregroundColor: Colors.white,
                                        ),
                                      )
                                    : ElevatedButton.icon(
                                        onPressed: _sendFriendRequest,
                                        icon: const Icon(Icons.person_add),
                                        label: Text(AppLocalizations.current.t('添加好友')),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: primaryColor,
                                          foregroundColor: Colors.white,
                                        ),
                                      ),
                              const Spacer(),
                              Text(
                                'UID: ${_profile!['uid']}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // 右侧动态
                        Expanded(
                          child: MomentsPage(uid: widget.uid, embedded: true),
                        ),
                      ],
                    ),
    );
  }
}
