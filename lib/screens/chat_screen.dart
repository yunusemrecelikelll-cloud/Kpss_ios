import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_provider.dart';
import 'premium_screen.dart';
import 'public_profile_screen.dart';

const int kFreeMaxChatMessagesPerDay = 10;

String _genderEmoji(String gender) {
  if (gender == 'k') return '👩';
  if (gender == 'e') return '👨';
  return '🙂';
}

/// Genel sohbet + kullanıcıdan kullanıcıya mesajlaşma (DM) ekranı.
/// Firebase yapılandırılmamışsa ya da kullanıcı giriş yapmamışsa uygun bir
/// yer tutucu / giriş daveti gösterir — hiçbir zaman çökmez.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with SingleTickerProviderStateMixin {
  final ChatService _chat = ChatService();
  late final TabController _tabController;
  bool _notifChecked = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Sohbet ekranı açıldığında BİR KEZ, bu kullanıcıya bırakılmış hafif
  /// bildirimleri (ör. "bir mesajın rapor edildi") kontrol eder ve varsa tek
  /// satırlık bir SnackBar ile gösterir. Tam bir bildirim merkezi değil —
  /// gösterildikten sonra bildirimler sunucudan silinir (bkz.
  /// ChatService.fetchAndClearNotifications).
  void _checkNotifications(String uid) {
    if (_notifChecked) return;
    _notifChecked = true;
    _chat.fetchAndClearNotifications(uid).then((messages) {
      if (!mounted || messages.isEmpty) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(messages.first), duration: const Duration(seconds: 5)),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final storage = context.watch<StorageService>();
    final c = context.watch<ThemeProvider>().colors;

    if (!_chat.isConfigured) {
      return Scaffold(
        appBar: AppBar(title: const Text('💬 Sohbet')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Sohbet özelliği şu an kullanılamıyor.', style: TextStyle(color: c.textFaint)),
          ),
        ),
      );
    }

    if (!auth.isSignedIn) {
      return _ChatLoginPrompt(auth: auth);
    }

    final premium = storage.isPremiumUser();
    final uid = auth.currentUser!.uid;
    final authName = auth.currentUser!.displayName;
    final displayName = (authName != null && authName.isNotEmpty)
        ? authName
        : (storage.getUserName().isNotEmpty ? storage.getUserName() : 'Kullanıcı');

    _checkNotifications(uid);

    return Scaffold(
      appBar: AppBar(
        title: const Text('💬 Sohbet'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'Genel Sohbet'), Tab(text: 'Mesajlarım')],
        ),
        actions: [
          IconButton(
            tooltip: 'Engellenen Kullanıcılar',
            icon: const Icon(Icons.block),
            onPressed: () {
              context.read<SoundService>().click();
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => _BlockedUsersScreen(chat: _chat, uid: uid),
              ));
            },
          ),
          IconButton(
            tooltip: 'Çıkış Yap',
            icon: const Icon(Icons.logout),
            onPressed: () {
              context.read<SoundService>().click();
              auth.signOut();
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _GeneralChatTab(chat: _chat, uid: uid, displayName: displayName, premium: premium),
          // Mesajlarım (DM) artık ücretsiz kullanıcılar için de açık —
          // sadece genel sohbetle AYNI paylaşılan günlük mesaj hakkına tabi
          // (bkz. kFreeMaxChatMessagesPerDay, _DmThreadScreenState._send).
          _DmInboxTab(chat: _chat, uid: uid),
        ],
      ),
    );
  }
}

class _ChatLoginPrompt extends StatefulWidget {
  final AuthService auth;
  const _ChatLoginPrompt({required this.auth});

  @override
  State<_ChatLoginPrompt> createState() => _ChatLoginPromptState();
}

class _ChatLoginPromptState extends State<_ChatLoginPrompt> {
  bool _busy = false;

  Future<void> _signIn(Future<AuthResult> Function() method) async {
    context.read<SoundService>().click();
    setState(() => _busy = true);
    final result = await method();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.errorMessage ?? 'Giriş başarısız oldu.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return Scaffold(
      appBar: AppBar(title: const Text('💬 Sohbet')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('💬', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 12),
                const Text('Sohbete katıl!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                  'Diğer KPSS adaylarıyla sohbet edebilmek ve mesajlaşabilmek için giriş yapman gerekiyor.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.textFaint),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: 280,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _signIn(widget.auth.signInWithGoogle),
                    icon: const Text('🇬', style: TextStyle(fontSize: 16)),
                    label: const Text('Google ile Giriş Yap'),
                  ),
                ),
                if (widget.auth.isAppleSignInAvailable) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: 280,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : () => _signIn(widget.auth.signInWithApple),
                      icon: const Icon(Icons.apple, size: 18),
                      label: const Text('Apple ile Giriş Yap'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GeneralChatTab extends StatefulWidget {
  final ChatService chat;
  final String uid;
  final String displayName;
  final bool premium;
  const _GeneralChatTab({required this.chat, required this.uid, required this.displayName, required this.premium});

  @override
  State<_GeneralChatTab> createState() => _GeneralChatTabState();
}

class _GeneralChatTabState extends State<_GeneralChatTab> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send(StorageService storage) async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    context.read<SoundService>().click();

    if (!widget.premium && storage.getChatMessagesSentToday() >= kFreeMaxChatMessagesPerDay) {
      _showUpgradeSheet();
      return;
    }

    setState(() => _sending = true);
    try {
      await widget.chat.sendMessage(
        senderUid: widget.uid,
        senderName: widget.displayName,
        character: _genderEmoji(storage.getUserGender()),
        message: text,
      );
      await storage.incrementChatMessagesSentToday();
      _controller.clear();
    } on ProfanityDetectedException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mesajın uygunsuz bir kelime içeriyor: "${e.matchedWord}"')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Mesaj gönderilemedi: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showUpgradeSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Günlük mesaj hakkın doldu',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 8),
              Text('Ücretsiz sürümde günde $kFreeMaxChatMessagesPerDay mesaj gönderebilirsin. '
                  'Sınırsız mesaj ve kişilere DM atabilmek için Premium\'a geç.'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PremiumScreen()));
                },
                child: const Text("Premium'a Geç"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openMessageActions(ChatMessage msg, String myUid, Set<String> blocked) {
    if (msg.senderUid == myUid) return;
    final storage = context.read<StorageService>();
    final premium = storage.isPremiumUser();
    final isBlocked = blocked.contains(msg.senderUid);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // DM artık ücretsiz kullanıcılar için de açık (bkz. kFreeMaxChatMessagesPerDay).
            ListTile(
              leading: const Icon(Icons.mail_outline),
              title: Text('${msg.senderName} kişisine DM gönder'),
              onTap: () async {
                Navigator.pop(ctx);
                await storage.saveDmPeerName(msg.senderUid, msg.senderName);
                if (!context.mounted) return;
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => _DmThreadScreen(
                    chat: widget.chat,
                    myUid: myUid,
                    peerUid: msg.senderUid,
                    peerName: msg.senderName,
                  ),
                ));
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text('${msg.senderName} profilini gör'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PublicProfileScreen(uid: msg.senderUid, fallbackName: msg.senderName),
                ));
              },
            ),
            ListTile(
              leading: Icon(isBlocked ? Icons.lock_open : Icons.block, color: premium ? null : Theme.of(ctx).disabledColor),
              title: Text(isBlocked ? 'Engeli Kaldır' : 'Kullanıcıyı Engelle'),
              subtitle: premium ? null : const Text('Premium özelliği'),
              onTap: !premium
                  ? () => _premiumOnlySnack(ctx)
                  : () async {
                      Navigator.pop(ctx);
                      if (isBlocked) {
                        await widget.chat.unblockUser(myUid: myUid, blockedUid: msg.senderUid);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('${msg.senderName} kişisinin engeli kaldırıldı.')));
                      } else {
                        await widget.chat.blockUser(myUid: myUid, blockedUid: msg.senderUid);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('${msg.senderName} engellendi.')));
                      }
                    },
            ),
            ListTile(
              leading: Icon(Icons.flag_outlined, color: premium ? null : Theme.of(ctx).disabledColor),
              title: const Text('Şikayet Et (Spam/Uygunsuz)'),
              subtitle: premium ? null : const Text('Premium özelliği'),
              onTap: !premium
                  ? () => _premiumOnlySnack(ctx)
                  : () async {
                      Navigator.pop(ctx);
                      await widget.chat.reportMessage(
                        messageId: msg.id,
                        reporterUid: myUid,
                        reportedUid: msg.senderUid,
                        reason: 'spam_or_uygunsuz',
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('Mesaj şikayet edildi, teşekkürler.')));
                    },
            ),
          ],
        ),
      ),
    );
  }

  void _premiumOnlySnack(BuildContext ctx) {
    Navigator.pop(ctx);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Bu özellik Premium'a özel.")),
    );
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final c = context.watch<ThemeProvider>().colors;
    final remaining = widget.premium ? null : (kFreeMaxChatMessagesPerDay - storage.getChatMessagesSentToday()).clamp(0, kFreeMaxChatMessagesPerDay);

    return Column(
      children: [
        Expanded(
          child: StreamBuilder<List<ChatMessage>>(
            stream: widget.chat.streamMessages(),
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final messages = snap.data!;
              if (messages.isEmpty) {
                return Center(
                  child: Text('Henüz mesaj yok, ilk mesajı sen at! 👋', style: TextStyle(color: c.textFaint)),
                );
              }
              return StreamBuilder<Set<String>>(
                stream: widget.chat.streamBlockedUids(widget.uid),
                builder: (context, blockedSnap) {
                  final blocked = blockedSnap.data ?? const <String>{};
                  final visible = messages.where((m) => !blocked.contains(m.senderUid)).toList();
                  return ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: visible.length,
                    itemBuilder: (context, i) {
                      final m = visible[i];
                      final mine = m.senderUid == widget.uid;
                      return _MessageBubble(
                        message: m,
                        mine: mine,
                        colors: c,
                        onTap: () => _openMessageActions(m, widget.uid, blocked),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
        if (remaining != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Bugün kalan mesaj hakkın: $remaining / $kFreeMaxChatMessagesPerDay',
                  style: TextStyle(fontSize: 11, color: c.textFaint)),
            ),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    maxLength: 300,
                    decoration: const InputDecoration(hintText: 'Bir şeyler yaz…', counterText: ''),
                    onSubmitted: (_) => _send(storage),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _sending ? null : () => _send(storage),
                  icon: _sending
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool mine;
  final KpssColors colors;
  final VoidCallback onTap;
  const _MessageBubble({required this.message, required this.mine, required this.colors, required this.onTap});

  void _openProfile(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PublicProfileScreen(uid: message.senderUid, fallbackName: message.senderName),
    ));
  }

  @override
  Widget build(BuildContext context) {
    // NOT: Avatar'ın kendi GestureDetector'ı, mesaj balonunun onTap'ı içine
    // İÇ İÇE (nested) yerleştirilmiş durumda — Flutter'da bu güvenlidir: bir
    // pointer'a en yakın (en içteki) tanıyıcı jesti kazanır, dıştaki onTap
    // TETİKLENMEZ (ör. ListTile içindeki bir IconButton'a dokunmak sadece
    // IconButton'ı tetikler, ListTile.onTap'ı DEĞİL). Böylece avatara dokunmak
    // sadece profili açar, balonun herhangi bir yerine dokunmak ise sadece
    // mesaj menüsünü açar.
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine) ...[
            GestureDetector(
              onTap: () => _openProfile(context),
              child: CircleAvatar(
                radius: 14,
                backgroundColor: colors.violet.withValues(alpha: 0.18),
                child: Text(message.character.isNotEmpty ? message.character : '🙂',
                    style: const TextStyle(fontSize: 14)),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                decoration: BoxDecoration(
                  color: mine ? colors.violet.withValues(alpha: 0.18) : colors.border.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!mine)
                      Text(message.senderName,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: colors.violet)),
                    if (!mine) const SizedBox(height: 3),
                    Text(message.message, style: const TextStyle(fontSize: 14)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kullanıcının engellediği kişilerin listesi + "Engeli Kaldır" — ChatScreen
/// AppBar'ındaki 🚫 simgesinden açılır. Genel sohbette engellenen kullanıcının
/// mesajları TAMAMEN gizlendiği için (bkz. _GeneralChatTabState: `visible`
/// listesi engellenenleri filtreler), mesaj balonu üzerinden bir daha o
/// kullanıcıya erişilemez — bu yüzden engeli kaldırmak için AYRI bir liste
/// gereklidir.
class _BlockedUsersScreen extends StatelessWidget {
  final ChatService chat;
  final String uid;
  const _BlockedUsersScreen({required this.chat, required this.uid});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final peerNames = context.watch<StorageService>().getDmPeerNames();
    return Scaffold(
      appBar: AppBar(title: const Text('Engellenen Kullanıcılar')),
      body: StreamBuilder<Set<String>>(
        stream: chat.streamBlockedUids(uid),
        builder: (context, snap) {
          final blockedList = (snap.data ?? const <String>{}).toList();
          if (blockedList.isEmpty) {
            return Center(
              child: Text('Engellediğin kimse yok.', style: TextStyle(color: c.textFaint)),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: blockedList.length,
            itemBuilder: (context, i) {
              final peerUid = blockedList[i];
              final name = peerNames[peerUid] ?? 'Kullanıcı';
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.block)),
                  title: Text(name),
                  trailing: TextButton(
                    onPressed: () async {
                      context.read<SoundService>().click();
                      await chat.unblockUser(myUid: uid, blockedUid: peerUid);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('$name kişisinin engeli kaldırıldı.')),
                      );
                    },
                    child: const Text('Engeli Kaldır'),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _DmInboxTab extends StatelessWidget {
  final ChatService chat;
  final String uid;
  const _DmInboxTab({required this.chat, required this.uid});

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final c = context.watch<ThemeProvider>().colors;
    final peerNames = storage.getDmPeerNames();

    return StreamBuilder<List<DmThreadSummary>>(
      stream: chat.streamMyThreads(uid),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final threads = snap.data!.where((t) => t.peerUid.isNotEmpty).toList();
        if (threads.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Henüz mesajın yok. Genel sohbette birinin mesajına dokun ve "DM gönder"i seç.',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textFaint),
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: threads.length,
          itemBuilder: (context, i) {
            final t = threads[i];
            final name = peerNames[t.peerUid] ?? 'Kullanıcı';
            return Card(
              child: ListTile(
                leading: GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => PublicProfileScreen(uid: t.peerUid, fallbackName: name),
                  )),
                  child: const CircleAvatar(child: Text('💬')),
                ),
                title: Text(name),
                onTap: () {
                  context.read<SoundService>().click();
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => _DmThreadScreen(chat: chat, myUid: uid, peerUid: t.peerUid, peerName: name),
                  ));
                },
              ),
            );
          },
        );
      },
    );
  }
}

class _DmThreadScreen extends StatefulWidget {
  final ChatService chat;
  final String myUid;
  final String peerUid;
  final String peerName;
  const _DmThreadScreen({required this.chat, required this.myUid, required this.peerUid, required this.peerName});

  @override
  State<_DmThreadScreen> createState() => _DmThreadScreenState();
}

class _DmThreadScreenState extends State<_DmThreadScreen> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final storage = context.read<StorageService>();
    context.read<SoundService>().click();

    // DM artık ücretsiz kullanıcılar için de açık, ama genel sohbetle AYNI
    // paylaşılan günlük mesaj hakkına (bkz. kFreeMaxChatMessagesPerDay) tabi —
    // yeni bir sınır icat etmek yerine mevcut deseni yeniden kullanıyoruz.
    if (!storage.isPremiumUser() && storage.getChatMessagesSentToday() >= kFreeMaxChatMessagesPerDay) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
            'Bugünkü ücretsiz mesaj hakkın ($kFreeMaxChatMessagesPerDay) doldu. Sınırsız mesajlaşmak için Premium\'a geç.')),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      await widget.chat.sendDirectMessage(fromUid: widget.myUid, toUid: widget.peerUid, message: text);
      if (!storage.isPremiumUser()) await storage.incrementChatMessagesSentToday();
      _controller.clear();
    } on ProfanityDetectedException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mesajın uygunsuz bir kelime içeriyor: "${e.matchedWord}"')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Mesaj gönderilemedi: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final storage = context.watch<StorageService>();
    final remaining = storage.isPremiumUser()
        ? null
        : (kFreeMaxChatMessagesPerDay - storage.getChatMessagesSentToday()).clamp(0, kFreeMaxChatMessagesPerDay);
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => PublicProfileScreen(uid: widget.peerUid, fallbackName: widget.peerName),
          )),
          child: Text(widget.peerName),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<DirectMessage>>(
              stream: widget.chat.streamDirectMessages(uidA: widget.myUid, uidB: widget.peerUid),
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final messages = snap.data!;
                if (messages.isEmpty) {
                  return Center(child: Text('Henüz mesaj yok.', style: TextStyle(color: c.textFaint)));
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, i) {
                    final m = messages[i];
                    final mine = m.senderUid == widget.myUid;
                    return Align(
                      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                        decoration: BoxDecoration(
                          color: mine ? c.violet.withValues(alpha: 0.18) : c.border.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(m.message, style: const TextStyle(fontSize: 14)),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (remaining != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Bugün kalan mesaj hakkın: $remaining / $kFreeMaxChatMessagesPerDay',
                    style: TextStyle(fontSize: 11, color: c.textFaint)),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      maxLength: 300,
                      decoration: const InputDecoration(hintText: 'Bir şeyler yaz…', counterText: ''),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
