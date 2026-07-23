import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/in_app_notice_service.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../theme/design_system.dart';
import '../theme/theme_provider.dart';
import 'account_login_screen.dart';
import 'premium_screen.dart';
import 'public_profile_screen.dart';

const int kFreeMaxChatMessagesPerDay = 10;

/// Mesaj saatini "14:05" biçiminde verir. Sunucu damgası henüz işlenmediyse
/// (yeni gönderilmiş mesaj) boş döner — "00:00" göstermek yanıltıcı olurdu.
String _saat(DateTime? t) {
  if (t == null) return '';
  final s = t.hour.toString().padLeft(2, '0');
  final d = t.minute.toString().padLeft(2, '0');
  return '$s:$d';
}

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

  // Kullanıcının 6 haneli ID'si (arkadaş eklemede paylaşılır). Bir kez üretilip
  // saklanır; ekran açıldığında garantiye alınır.
  bool _kodChecked = false;
  String? _myKod;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  /// Kullanıcının 6 haneli kodunu BİR KEZ garantiye alır (yoksa üretir).
  void _ensureKod(String uid, String name) {
    if (_kodChecked) return;
    _kodChecked = true;
    _chat.ensureMyKod(uid: uid, name: name).then((kod) {
      if (!mounted || kod == null) return;
      setState(() => _myKod = kod);
    });
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
      return const _ChatLoginPrompt();
    }

    final premium = storage.isPremiumUser();
    final uid = auth.currentUser!.uid;
    // İSİM ÖNCELİĞİ: Profil'de yazılan isim BİRİNCİL (kullanıcı isteği —
    // sohbet dahil her yerde seçtiği isim görünsün); hesap adı yalnızca yedek.
    final authName = auth.currentUser!.displayName;
    final displayName = storage.getUserName().isNotEmpty
        ? storage.getUserName()
        : ((authName != null && authName.isNotEmpty) ? authName : 'Kullanıcı');

    _checkNotifications(uid);
    _ensureKod(uid, displayName);

    return Scaffold(
      appBar: AppBar(
        title: const Text('💬 Sohbet'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.center,
          tabs: const [
            Tab(text: 'Genel Sohbet'),
            Tab(text: 'Mesajlarım'),
            Tab(text: 'Arkadaşlar'),
          ],
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
          // Arkadaşlar sekmesi: gelen istekler + arkadaş listesi. İstekler
          // buraya alındı çünkü bir isteği kabul etmek = arkadaş edinmek;
          // ikisi aynı yerde durunca akış daha anlaşılır.
          _FriendsTab(chat: _chat, uid: uid, myName: displayName, myKod: _myKod),
        ],
      ),
    );
  }
}

/// Sohbete giriş yapılmadan bakıldığında gösterilen yönlendirme ekranı.
///
/// DEĞİŞTİRİLDİ (kullanıcı isteği): Sohbet içinde ARTIK giriş yap butonları
/// (Google/Apple) YOK. Bunun yerine kullanıcı, tüm giriş yollarını (e-posta,
/// kullanıcı adı, Google, Apple) barındıran asıl giriş ekranına yönlendiriliyor.
/// Böylece giriş tek bir yerden (Ayarlar > Giriş Yap ile aynı ekran) yapılıyor.
class _ChatLoginPrompt extends StatelessWidget {
  const _ChatLoginPrompt();

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
                const Text('Sohbete katıl!',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                  'Diğer KPSS adaylarıyla sohbet edip mesajlaşmak için giriş yapman '
                  'gerekiyor. Giriş yaptıktan sonra otomatik olarak sohbete dönersin.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.textFaint),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: 260,
                  child: DsPillButton(
                    label: 'Giriş Yap',
                    color: c.violet,
                    leadingIcon: Icons.login_rounded,
                    onPressed: () {
                      context.read<SoundService>().click();
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const AccountLoginScreen(),
                      ));
                    },
                  ),
                ),
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

  /// Bir mesaja dokunulduğunda açılan kullanıcı işlemleri menüsü.
  ///
  /// DÜZELTİLEN HATA: eskiden bu metot kendi mesajlarımız için `return` ile
  /// SESSİZCE çıkıyordu. Sohbette çoğunlukla kendi mesajını gören kullanıcı
  /// için bu, "dokunuyorum ama hiçbir şey açılmıyor" demekti. Artık kendi
  /// mesajımızda da bir menü açılıyor (kendini engelleme/şikayet etme gibi
  /// anlamsız seçenekler olmadan).
  void _openMessageActions(ChatMessage msg, String myUid, Set<String> blocked) {
    final storage = context.read<StorageService>();
    final benimMesajim = msg.senderUid == myUid;
    final isBlocked = blocked.contains(msg.senderUid);
    final c = context.read<ThemeProvider>().colors;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Kimin hakkında işlem yaptığımız her zaman görünsün.
            ListTile(
              leading: CircleAvatar(
                backgroundColor: c.violet.withValues(alpha: 0.18),
                child: Text(msg.character.isNotEmpty ? msg.character : '🙂'),
              ),
              title: Text(msg.senderName,
                  style: const TextStyle(fontWeight: FontWeight.w900)),
              subtitle: Text(benimMesajim ? 'Bu senin mesajın' : 'Sohbet üyesi'),
            ),
            Divider(height: 1, color: c.border),

            ListTile(
              leading: Icon(Icons.person_outline, color: c.violetL),
              title: const Text('Profili Gör'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PublicProfileScreen(
                      uid: msg.senderUid, fallbackName: msg.senderName),
                ));
              },
            ),

            if (!benimMesajim) ...[
              // DM ücretsiz kullanıcılar için de açık (bkz. kFreeMaxChatMessagesPerDay).
              ListTile(
                leading: Icon(Icons.mail_outline, color: c.mint),
                title: const Text('Mesaj Gönder'),
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
                leading: Icon(Icons.person_add_alt_1, color: c.gold),
                title: const Text('Arkadaş Ekle'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    final sonuc = await widget.chat.sendFriendRequest(
                      fromUid: myUid,
                      fromName: widget.displayName,
                      toUid: msg.senderUid,
                      toName: msg.senderName,
                    );
                    messenger.showSnackBar(SnackBar(content: Text(sonuc)));
                  } catch (e) {
                    messenger.showSnackBar(SnackBar(
                        content: Text('Arkadaşlık isteği gönderilemedi: $e')));
                  }
                },
              ),

              Divider(height: 1, color: c.border),

              // ENGELLEME ve ŞİKAYET ARTIK ÜCRETSİZ.
              // Bunlar konfor değil GÜVENLİK özellikleridir. App Store
              // İnceleme Kuralı 1.2, kullanıcı içeriği barındıran uygulamaların
              // taciz edici kullanıcıları engelleme ve uygunsuz içeriği
              // bildirme imkânı SUNMASINI şart koşar; bunları ödeme duvarının
              // arkasına koymak reddedilme sebebidir. (Google Play'in Kullanıcı
              // Ürettiği İçerik politikası da aynı şeyi ister.)
              ListTile(
                leading: Icon(isBlocked ? Icons.lock_open : Icons.block,
                    color: c.danger),
                title: Text(isBlocked ? 'Engeli Kaldır' : 'Kullanıcıyı Engelle'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    if (isBlocked) {
                      await widget.chat
                          .unblockUser(myUid: myUid, blockedUid: msg.senderUid);
                      messenger.showSnackBar(SnackBar(
                          content: Text(
                              '${msg.senderName} kişisinin engeli kaldırıldı.')));
                    } else {
                      await widget.chat
                          .blockUser(myUid: myUid, blockedUid: msg.senderUid);
                      messenger.showSnackBar(SnackBar(
                          content: Text('${msg.senderName} engellendi.')));
                    }
                  } catch (e) {
                    messenger.showSnackBar(
                        SnackBar(content: Text('İşlem başarısız: $e')));
                  }
                },
              ),
              ListTile(
                leading: Icon(Icons.flag_outlined, color: c.warn),
                title: const Text('Şikayet Et'),
                subtitle: const Text('Spam veya uygunsuz içerik'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await widget.chat.reportMessage(
                      messageId: msg.id,
                      reporterUid: myUid,
                      reportedUid: msg.senderUid,
                      reason: 'spam_or_uygunsuz',
                    );
                    messenger.showSnackBar(const SnackBar(
                        content: Text('Mesaj şikayet edildi, teşekkürler.')));
                  } catch (e) {
                    messenger.showSnackBar(
                        SnackBar(content: Text('Şikayet gönderilemedi: $e')));
                  }
                },
              ),
            ],
          ],
        ),
      ),
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
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                decoration: BoxDecoration(
                  // Karşı tarafın balonu ARTIK `border` renginden türetilmiyor.
                  // `border` bazı temalarda metin rengine çok yakın olduğu için
                  // mesajlar zemine karışıyordu; `glass2` bu iş için var olan,
                  // her temada zeminden ayrışan yüzey rengi.
                  color: mine
                      ? colors.violet.withValues(alpha: 0.22)
                      : colors.glass2,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: mine
                        ? colors.violetL.withValues(alpha: 0.35)
                        : colors.border,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!mine) ...[
                      Text(message.senderName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w900,
                              // violet yerine violetL: koyu temalarda `violet`
                              // balon zeminine çok yakın kalıp adı okunmaz
                              // hale getiriyordu.
                              color: colors.violetL)),
                      const SizedBox(height: 3),
                    ],
                    // KRİTİK: metne AÇIKÇA tema rengi veriliyor. Eskiden renk
                    // hiç belirtilmiyordu ve Material'ın varsayılan gövde rengi
                    // devreye giriyordu; bu renk uygulamanın 9 temasının
                    // çoğunda balon zeminiyle yeterli kontrast oluşturmuyor,
                    // mesaj "silik/yarı görünmez" görünüyordu.
                    Text(message.message,
                        style: TextStyle(
                            fontSize: 14.5, height: 1.35, color: colors.text)),
                    const SizedBox(height: 4),
                    Text(_saat(message.createdAt),
                        style: TextStyle(fontSize: 10, color: colors.textFaint)),
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

/// "Mesajlarım" sekmesi: yalnızca sürmekte olan özel sohbetler (DM).
///
/// Arkadaşlık istekleri ve arkadaş listesi ARTIK ayrı "Arkadaşlar" sekmesinde
/// (bkz. _FriendsTab). Böylece bu sekme tek işe odaklanıyor: konuşmalarım.
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
        // HATA GÖRÜNÜR OLMALI. Eskiden yalnızca `hasData` kontrol ediliyordu;
        // sorgu hata verince (ör. eksik Firestore indeksi) ekran sonsuza dek
        // dönen halkada kalıyor ve kullanıcı "Mesajlarım çalışmıyor" diyordu.
        if (snap.hasError) {
          return _HataNotu(mesaj: 'Mesajların yüklenemedi.\n${snap.error}');
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final threads = snap.data!.where((t) => t.peerUid.isNotEmpty).toList();

        if (threads.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('💬', style: TextStyle(fontSize: 40)),
                  const SizedBox(height: 10),
                  Text(
                    'Henüz özel mesajın yok.\n\nGenel sohbette ya da Arkadaşlar sekmesinde '
                    'birine dokunup mesaj gönderebilirsin.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.textFaint, height: 1.5),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            for (final t in threads)
              // İSİM ÖNCELİĞİ: önce thread dokümanındaki `names` (arkadaş
              // olmayan yabancılar için de dolu — gönderen her mesajda kendi
              // adını yazar), sonra yerel önbellek, en son "Kullanıcı".
              _KisiSatiri(
                ad: t.peerName.isNotEmpty
                    ? t.peerName
                    : (peerNames[t.peerUid] ?? 'Kullanıcı'),
                emoji: '💬',
                colors: c,
                // İsmin altında SON MESAJ önizlemesi; ben yazdıysam "Sen:"
                // önekiyle. Mesaj yoksa (eski thread) zaman etiketi kalır.
                altBilgi: t.lastMessage.isNotEmpty
                    ? (t.lastSenderUid == uid
                        ? 'Sen: ${t.lastMessage}'
                        : t.lastMessage)
                    : _sonMesajZamani(t.updatedAt),
                // Okunmamış mesaj varsa isim kalın + sayı rozeti; sohbeti
                // açınca markThreadRead sayacı sıfırlar, ikisi de kalkar.
                kalin: t.unreadCount > 0,
                rozet: t.unreadCount,
                onTap: () {
                  context.read<SoundService>().click();
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => _DmThreadScreen(
                      chat: chat,
                      myUid: uid,
                      peerUid: t.peerUid,
                      peerName: t.peerName.isNotEmpty
                          ? t.peerName
                          : (peerNames[t.peerUid] ?? 'Kullanıcı'),
                    ),
                  ));
                },
                onProfil: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PublicProfileScreen(
                      uid: t.peerUid,
                      fallbackName: t.peerName.isNotEmpty
                          ? t.peerName
                          : (peerNames[t.peerUid] ?? 'Kullanıcı')),
                )),
              ),
          ],
        );
      },
    );
  }
}

/// "Arkadaşlar" sekmesi: gelen arkadaşlık istekleri (en üstte, yalnızca varsa)
/// + arkadaş listesi.
///
/// İstekler buraya alındı çünkü bir isteği KABUL etmek = arkadaş edinmek;
/// ikisinin aynı ekranda olması akışı doğal kılıyor. İstek varken en üstte
/// altın renkli kartlarla belirginleşiyor, yokken hiç yer kaplamıyor.
class _FriendsTab extends StatelessWidget {
  final ChatService chat;
  final String uid;
  final String myName;
  final String? myKod;
  const _FriendsTab({
    required this.chat,
    required this.uid,
    required this.myName,
    required this.myKod,
  });

  /// Bir arkadaşa dokunulunca açılan işlem menüsü: mesaj gönder, profili gör,
  /// engelle, şikayet et, arkadaşlıktan çıkar.
  void _arkadasMenu(BuildContext context, Friend a) {
    final c = context.read<ThemeProvider>().colors;
    final storage = context.read<StorageService>();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: DsIconBadge(emoji: '👤', color: c.violetL, size: 40, glow: false),
              title: Text(a.name, style: const TextStyle(fontWeight: FontWeight.w900)),
              subtitle: const Text('Arkadaşın'),
            ),
            Divider(height: 1, color: c.border),
            ListTile(
              leading: Icon(Icons.mail_outline, color: c.mint),
              title: const Text('Mesaj Gönder'),
              onTap: () async {
                Navigator.pop(ctx);
                await storage.saveDmPeerName(a.uid, a.name);
                if (!context.mounted) return;
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => _DmThreadScreen(
                      chat: chat, myUid: uid, peerUid: a.uid, peerName: a.name),
                ));
              },
            ),
            ListTile(
              leading: Icon(Icons.person_outline, color: c.violetL),
              title: const Text('Profili Gör'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PublicProfileScreen(uid: a.uid, fallbackName: a.name),
                ));
              },
            ),
            ListTile(
              leading: Icon(Icons.block, color: c.danger),
              title: const Text('Engelle'),
              onTap: () async {
                Navigator.pop(ctx);
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await chat.blockUser(myUid: uid, blockedUid: a.uid);
                  messenger.showSnackBar(
                      SnackBar(content: Text('${a.name} engellendi.')));
                } catch (e) {
                  messenger.showSnackBar(SnackBar(content: Text('İşlem başarısız: $e')));
                }
              },
            ),
            ListTile(
              leading: Icon(Icons.flag_outlined, color: c.warn),
              title: const Text('Şikayet Et'),
              onTap: () async {
                Navigator.pop(ctx);
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await chat.reportUser(reporterUid: uid, reportedUid: a.uid);
                  messenger.showSnackBar(const SnackBar(
                      content: Text('Şikayet alındı, teşekkürler.')));
                } catch (e) {
                  messenger.showSnackBar(SnackBar(content: Text('Şikayet gönderilemedi: $e')));
                }
              },
            ),
            ListTile(
              leading: Icon(Icons.person_remove_outlined, color: c.textDim),
              title: const Text('Arkadaşlıktan Çıkar'),
              onTap: () async {
                Navigator.pop(ctx);
                final messenger = ScaffoldMessenger.of(context);
                final onay = await showDialog<bool>(
                  context: context,
                  builder: (dCtx) => AlertDialog(
                    title: const Text('Arkadaşlıktan çıkar?'),
                    content: Text('${a.name} arkadaş listenden kaldırılacak.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Vazgeç')),
                      TextButton(onPressed: () => Navigator.pop(dCtx, true), child: const Text('Çıkar')),
                    ],
                  ),
                );
                if (onay != true) return;
                await chat.removeFriend(myUid: uid, friendUid: a.uid);
                messenger.showSnackBar(
                    SnackBar(content: Text('${a.name} arkadaşlıktan çıkarıldı.')));
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;

    return StreamBuilder<List<FriendRequest>>(
      stream: chat.streamIncomingRequests(uid),
      builder: (context, istekSnap) {
        final istekler = istekSnap.data ?? const <FriendRequest>[];

        return StreamBuilder<List<Friend>>(
          stream: chat.streamFriends(uid),
          builder: (context, arkadasSnap) {
            if (arkadasSnap.hasError) {
              return _HataNotu(mesaj: 'Arkadaşların yüklenemedi.\n${arkadasSnap.error}');
            }
            final arkadaslar = arkadasSnap.data ?? const <Friend>[];

            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                // ID kartı + ID ile arkadaş ekleme (her zaman en üstte).
                _ArkadasEkleKarti(
                    chat: chat, myUid: uid, myName: myName, myKod: myKod),
                const SizedBox(height: 18),

                if (istekler.isNotEmpty) ...[
                  DsSectionHeader(title: '🤝 Gelen İstekler (${istekler.length})'),
                  const SizedBox(height: 8),
                  for (final istek in istekler)
                    _IstekKarti(
                      istek: istek,
                      colors: c,
                      onKabul: () async {
                        final storage = context.read<StorageService>();
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          await chat.acceptFriendRequest(
                            myUid: uid,
                            myName: myName,
                            fromUid: istek.fromUid,
                            fromName: istek.fromName,
                          );
                          await storage.saveDmPeerName(istek.fromUid, istek.fromName);
                          messenger.showSnackBar(SnackBar(
                              content: Text('${istek.fromName} artık arkadaşın!')));
                        } catch (e) {
                          messenger.showSnackBar(
                              SnackBar(content: Text('Kabul edilemedi: $e')));
                        }
                      },
                      onRed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          await chat.rejectFriendRequest(
                              myUid: uid, fromUid: istek.fromUid);
                          messenger.showSnackBar(
                              const SnackBar(content: Text('İstek reddedildi.')));
                        } catch (e) {
                          messenger.showSnackBar(
                              SnackBar(content: Text('İşlem başarısız: $e')));
                        }
                      },
                    ),
                  const SizedBox(height: 18),
                ],

                DsSectionHeader(
                    title: arkadaslar.isEmpty
                        ? '👥 Arkadaşlarım'
                        : '👥 Arkadaşlarım (${arkadaslar.length})'),
                const SizedBox(height: 8),
                if (!arkadasSnap.hasData)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (arkadaslar.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                        'Henüz arkadaşın yok. Yukarıdan ID ile arkadaş ekleyebilir '
                        'ya da genel sohbette birine "Arkadaş Ekle" diyebilirsin.',
                        style: TextStyle(color: c.textFaint, height: 1.4)),
                  ),
                for (final a in arkadaslar)
                  _KisiSatiri(
                    ad: a.name,
                    emoji: '👤',
                    colors: c,
                    altBilgi: 'İşlemler için dokun',
                    onTap: () {
                      context.read<SoundService>().click();
                      _arkadasMenu(context, a);
                    },
                    onProfil: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          PublicProfileScreen(uid: a.uid, fallbackName: a.name),
                    )),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

/// "Arkadaşlar" sekmesinin üstündeki kart: kullanıcının kendi 6 haneli ID'sini
/// gösterir (paylaşabilsin diye) ve bir ID girip arkadaş eklemeyi sağlar.
class _ArkadasEkleKarti extends StatefulWidget {
  final ChatService chat;
  final String myUid;
  final String myName;
  final String? myKod;
  const _ArkadasEkleKarti({
    required this.chat,
    required this.myUid,
    required this.myName,
    required this.myKod,
  });

  @override
  State<_ArkadasEkleKarti> createState() => _ArkadasEkleKartiState();
}

class _ArkadasEkleKartiState extends State<_ArkadasEkleKarti> {
  final _controller = TextEditingController();
  bool _gonderiliyor = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _ekle() async {
    final kod = _controller.text.trim();
    if (kod.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('6 haneli bir ID gir.')),
      );
      return;
    }
    context.read<SoundService>().click();
    setState(() => _gonderiliyor = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final sonuc = await widget.chat.sendFriendRequestByKod(
        myUid: widget.myUid,
        myName: widget.myName,
        kod: kod,
      );
      _controller.clear();
      messenger.showSnackBar(SnackBar(content: Text(sonuc)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('İstek gönderilemedi: $e')));
    } finally {
      if (mounted) setState(() => _gonderiliyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return DsCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Kendi ID'in.
          Row(
            children: [
              DsIconBadge(emoji: '🆔', color: c.gold, size: 40, glow: false),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Senin ID\'in',
                        style: TextStyle(fontSize: 11.5, color: c.textFaint)),
                    const SizedBox(height: 2),
                    Text(
                      widget.myKod ?? '— — — — — —',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 3,
                          color: c.text),
                    ),
                  ],
                ),
              ),
              if (widget.myKod != null)
                IconButton(
                  tooltip: 'Kopyala',
                  icon: Icon(Icons.copy_rounded, size: 20, color: c.textFaint),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: widget.myKod!));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('ID kopyalandı.')),
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text('Bu ID\'yi paylaş; arkadaşların seni bu numarayla ekleyebilir.',
              style: TextStyle(fontSize: 11.5, color: c.textFaint)),
          Divider(height: 20, color: c.border),
          // ID ile arkadaş ekle.
          Text('ID ile arkadaş ekle',
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w800, color: c.textDim)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    hintText: '6 haneli ID',
                    counterText: '',
                    prefixIcon: Icon(Icons.tag),
                  ),
                  onSubmitted: (_) => _ekle(),
                ),
              ),
              const SizedBox(width: 8),
              DsPillButton(
                label: 'Ekle',
                color: c.violet,
                leadingIcon: Icons.person_add_alt_1,
                onPressed: _gonderiliyor ? null : _ekle,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "3 dk önce" / "dün" gibi kısa bir zaman etiketi.
String _sonMesajZamani(DateTime? t) {
  if (t == null) return '';
  final fark = DateTime.now().difference(t);
  if (fark.inMinutes < 1) return 'az önce';
  if (fark.inMinutes < 60) return '${fark.inMinutes} dk önce';
  if (fark.inHours < 24) return '${fark.inHours} saat önce';
  if (fark.inDays == 1) return 'dün';
  return '${fark.inDays} gün önce';
}

/// Bekleyen bir arkadaşlık isteği: kabul / reddet.
class _IstekKarti extends StatelessWidget {
  final FriendRequest istek;
  final KpssColors colors;
  final Future<void> Function() onKabul;
  final Future<void> Function() onRed;
  const _IstekKarti({
    required this.istek,
    required this.colors,
    required this.onKabul,
    required this.onRed,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DsCard(
        accent: c.gold,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            DsIconBadge(emoji: '🤝', color: c.gold, size: 40, glow: false),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(istek.fromName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 14, color: c.text)),
                  const SizedBox(height: 2),
                  Text('Arkadaşlık isteği gönderdi',
                      style: TextStyle(fontSize: 11.5, color: c.textFaint)),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Kabul et',
              icon: Icon(Icons.check_circle, color: c.success),
              onPressed: () {
                context.read<SoundService>().click();
                onKabul();
              },
            ),
            IconButton(
              tooltip: 'Reddet',
              icon: Icon(Icons.cancel_outlined, color: c.textFaint),
              onPressed: () {
                context.read<SoundService>().click();
                onRed();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Arkadaş / sohbet listesinde tek bir kişi satırı.
class _KisiSatiri extends StatelessWidget {
  final String ad;
  final String emoji;
  final String altBilgi;
  final KpssColors colors;
  final VoidCallback onTap;
  final VoidCallback onProfil;

  /// Okunmamış mesaj varsa isim KALIN gösterilir (okununca normale döner).
  final bool kalin;

  /// Okunmamış mesaj adedi — 0 ise rozet çizilmez.
  final int rozet;

  const _KisiSatiri({
    required this.ad,
    required this.emoji,
    required this.altBilgi,
    required this.colors,
    required this.onTap,
    required this.onProfil,
    this.kalin = false,
    this.rozet = 0,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DsCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        onTap: onTap,
        child: Row(
          children: [
            // Avatara dokunmak profili açar; satırın kalanı sohbeti açar.
            GestureDetector(
              onTap: onProfil,
              child: DsIconBadge(emoji: emoji, color: c.violetL, size: 40, glow: false),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ad,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          // Okunmamış mesaj varken isim belirgin (w900),
                          // okununca normal ağırlığa döner.
                          fontWeight: kalin ? FontWeight.w900 : FontWeight.w700,
                          fontSize: 14,
                          color: c.text)),
                  if (altBilgi.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(altBilgi,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: kalin ? FontWeight.w700 : FontWeight.w400,
                            color: kalin ? c.textDim : c.textFaint)),
                  ],
                ],
              ),
            ),
            if (rozet > 0)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: c.danger,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(rozet > 99 ? '99+' : '$rozet',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: Colors.white)),
              )
            else
              Icon(Icons.chevron_right, size: 18, color: c.textFaint),
          ],
        ),
      ),
    );
  }
}

/// Bir akış hata verdiğinde gösterilen not — sessiz sonsuz yükleme yerine.
class _HataNotu extends StatelessWidget {
  final String mesaj;
  const _HataNotu({required this.mesaj});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('⚠️', style: TextStyle(fontSize: 36)),
            const SizedBox(height: 10),
            Text(mesaj,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, height: 1.5, color: c.textFaint)),
          ],
        ),
      ),
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

  // Gelen mesajlar okundukça sayacı sıfırlamak için son görülen mesaj adedi.
  int _sonGorulenMesajSayisi = -1;

  @override
  void initState() {
    super.initState();
    // Bu sohbete bakıldığını gözcüye bildir: bu sohbetin afişi gösterilmesin
    // (mesaj zaten ekranda) — bkz. InAppNoticeOverlay.
    InAppNoticeService.instance.aktifDmPeerUid = widget.peerUid;
    // Sohbet açılır açılmaz okunmamış sayacımı sıfırla (rozet + kalın yazı
    // gelen kutusunda anında kalksın).
    widget.chat.markThreadRead(myUid: widget.myUid, peerUid: widget.peerUid);
  }

  @override
  void dispose() {
    if (InAppNoticeService.instance.aktifDmPeerUid == widget.peerUid) {
      InAppNoticeService.instance.aktifDmPeerUid = null;
    }
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final storage = context.read<StorageService>();
    final auth = context.read<AuthService>();
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

    // Kendi adımı thread'e yazıyorum ki karşı taraf beni hiç kaydetmemiş olsa
    // bile gelen kutusunda adım görünsün (bkz. sendDirectMessage.names).
    // Profil'deki isim birincil (bkz. ekran üstündeki displayName çözümü).
    final authName = auth.currentUser?.displayName;
    final benimAdim = storage.getUserName().isNotEmpty
        ? storage.getUserName()
        : ((authName != null && authName.trim().isNotEmpty)
            ? authName.trim()
            : 'Kullanıcı');

    setState(() => _sending = true);
    try {
      await widget.chat.sendDirectMessage(
        fromUid: widget.myUid,
        toUid: widget.peerUid,
        message: text,
        fromName: benimAdim,
      );
      if (!storage.isPremiumUser()) await storage.incrementChatMessagesSentToday();
      _controller.clear();
    } on ProfanityDetectedException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mesajın uygunsuz bir kelime içeriyor: "${e.matchedWord}"')),
      );
    } on MesajIstegiSiniriException catch (e) {
      // Arkadaş olmayan birine, o yanıt verene kadar en fazla 3 mesaj.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), duration: const Duration(seconds: 5)),
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
                // Sohbet AÇIKKEN yeni mesaj gelirse (liste ters sıralı: [0] en
                // yeni) sunucudaki okunmamış sayacımı hemen sıfırla — gelen
                // kutusundaki rozet/kalınlık bu ekranda bakarken birikmesin.
                if (messages.length != _sonGorulenMesajSayisi) {
                  _sonGorulenMesajSayisi = messages.length;
                  if (messages.first.senderUid != widget.myUid) {
                    widget.chat.markThreadRead(
                        myUid: widget.myUid, peerUid: widget.peerUid);
                  }
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
                        child: Text(m.message,
                            style: TextStyle(fontSize: 14, color: c.text)),
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
