import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/attempt.dart';
import '../models/question.dart';

/// storage.js'nin Dart/SharedPreferences karşılığı.
/// Çok kullanıcılı yapı: her anahtar aktif kullanıcı adına göre önekleniyor
/// (JS: `kpss_v2_<kullanıcı>_<anahtar>`), localStorage yerine SharedPreferences kullanılıyor.
class StorageService extends ChangeNotifier {
  SharedPreferences? _prefs;
  String _activeUser = '';

  static const _usersKey = 'kpss_v2_users';
  static const _activeKey = 'kpss_v2_active_user';

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _activeUser = _prefs?.getString(_activeKey) ?? '';
  }

  String _safe(String name) {
    final buf = StringBuffer();
    for (final ch in name.runes) {
      final c = String.fromCharCode(ch);
      if (RegExp(r'[a-zA-Z0-9ğüşıöçĞÜŞİÖÇ]').hasMatch(c)) {
        buf.write(c);
      } else {
        buf.write('_');
      }
    }
    final s = buf.toString();
    return s.length > 40 ? s.substring(0, 40) : s;
  }

  String _prefix([String? forUser]) {
    final u = forUser ?? _activeUser;
    return u.isEmpty ? 'kpss_v2_legacy_' : 'kpss_v2_${_safe(u)}_';
  }

  dynamic _get(String key, [dynamic fallback]) {
    final raw = _prefs?.getString(_prefix() + key);
    if (raw == null) return fallback;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return fallback;
    }
  }

  dynamic _getFor(String user, String key, [dynamic fallback]) {
    final raw = _prefs?.getString(_prefix(user) + key);
    if (raw == null) return fallback;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return fallback;
    }
  }

  Future<void> _set(String key, dynamic value) async {
    await _prefs?.setString(_prefix() + key, jsonEncode(value));
    // Neredeyse tüm veri-değiştiren metodlar bu yardımcıdan geçiyor; tek noktadan
    // bildirim vererek Ana Sayfa/Profil gibi dinleyen ekranların (context.watch)
    // test bitince/rozet açılınca vb. otomatik yenilenmesini garantiliyoruz.
    notifyListeners();
  }

  // ── Kullanıcı yönetimi ──
  List<String> getUserList() {
    final raw = _prefs?.getString(_usersKey);
    if (raw == null) return [];
    try {
      return List<String>.from(jsonDecode(raw) as List);
    } catch (_) {
      return [];
    }
  }

  Future<String> addUser(String rawName) async {
    final name = rawName.trim().substring(0, rawName.trim().length.clamp(0, 24));
    final cap = name.isEmpty ? name : name[0].toUpperCase() + name.substring(1);
    final users = getUserList();
    if (!users.contains(cap)) {
      users.add(cap);
      await _prefs?.setString(_usersKey, jsonEncode(users));
    }
    return cap;
  }

  // ── Hesaba bağlı profiller ────────────────────────────────────────────────
  //
  // KÖK SORUN DÜZELTMESİ ("farklı Google hesapları aynı istatistikleri
  // görüyor"): Yerel veriler eskiden cihazdaki TEK profile yazılıyordu; kim
  // giriş yaparsa yapsın aynı istatistik/premium/yanlışlar görünüyordu ve
  // hesap değiştirince veriler birbirine karışıyordu. Artık her Firebase
  // hesabının KENDİ yerel profili var ('hesap_<uid>'); girişte ona geçilir,
  // çıkışta tertemiz Misafir profiline dönülür.

  /// Verilen Firebase uid'i için yerel profil adı.
  static String hesapProfilAdi(String uid) => 'hesap_$uid';

  /// Hesaba bağlı profile geçer (yoksa oluşturur). addUser KULLANILMAZ:
  /// addUser adı 24 karaktere kırpıyor; uid'ler daha uzun olduğundan farklı
  /// hesaplar aynı profile düşebilirdi.
  Future<void> hesapProfilineGec(String uid) async {
    final ad = hesapProfilAdi(uid);
    final users = getUserList();
    if (!users.contains(ad)) {
      users.add(ad);
      await _prefs?.setString(_usersKey, jsonEncode(users));
    }
    await setActiveUser(ad);
  }

  /// Çıkış sonrası TERTEMİZ Misafir profiline döner (kullanıcı isteği:
  /// "çıkış yaptığında uygulama sıfırlansın" — yanlışlarım/premium/istatistik
  /// görünmesin). Hesap profillerine DOKUNULMAZ: aynı hesapla tekrar girişte
  /// o hesabın verileri olduğu gibi geri gelir.
  Future<void> misafireDon() async {
    await deleteUser('Misafir');
    final ad = await addUser('Misafir');
    await setActiveUser(ad);
    await setUserName(ad);
  }

  /// TÜM uygulama verisini sıfırlar — bütün profiller, ayarlar, istatistikler,
  /// rozetler ve PREMIUM dahil. Yalnızca "Hesabımı Sil" akışı kullanır
  /// (kullanıcı isteği: silince premium ve istatistikler de gitsin; uygulama
  /// ilk kurulmuş gibi başlasın).
  ///
  /// NOT: Mağazadan GERÇEKTEN satın alınmış bir abonelik, mağaza hesabında
  /// yaşamaya devam eder — uygulama yeniden girişte satın alımı geri
  /// yükleyebilir (Apple/Google kuralı; aboneliği ancak mağaza iptal eder).
  Future<void> tumVerileriSil() async {
    final keys = _prefs?.getKeys().toList() ?? [];
    for (final k in keys) {
      await _prefs?.remove(k);
    }
    _activeUser = '';
    notifyListeners();
  }

  Future<void> deleteUser(String name) async {
    final prefix = _prefix(name);
    final keys = _prefs?.getKeys().where((k) => k.startsWith(prefix)).toList() ?? [];
    for (final k in keys) {
      await _prefs?.remove(k);
    }
    final users = getUserList()..remove(name);
    await _prefs?.setString(_usersKey, jsonEncode(users));
    if (_activeUser == name) {
      _activeUser = '';
      await _prefs?.remove(_activeKey);
    }
  }

  String getActiveUser() => _activeUser;

  Future<void> setActiveUser(String name) async {
    _activeUser = name;
    await _prefs?.setString(_activeKey, name);
    notifyListeners();
  }

  // ── Gender / karakter / isim ──
  String getUserGender() => _get('gender', '') as String;
  Future<void> setUserGender(String g) => _set('gender', g);
  String getUserGenderFor(String name) => (_getFor(name, 'gender', '')) as String;

  String getUserCharacter() => _get('character', '') as String;
  Future<void> setUserCharacter(String c) => _set('character', c);

  // ── Hedef meslek (ör. 'polis', 'ogretmen', 'memur', 'uzman-yardimcisi') ──
  String getTargetProfession() => _get('targetProfession', '') as String;
  Future<void> setTargetProfession(String p) => _set('targetProfession', p);

  // ── Sınav türü: 'lisans' | 'onlisans' | 'ortaogretim' ──
  String getExamType() => _get('examType', '') as String;
  Future<void> setExamType(String t) => _set('examType', t);

  /// Bu profil bir kez oluşturulduktan sonra tekrar sorulmaz (tek kullanıcılı uygulama).
  bool get hasProfile => getUserName().isNotEmpty;

  /// "Beni Sına" (teşhis/yerleştirme sınavı) kullanıcı daha önce tamamladı mı
  /// — hasProfile ile AYNI kalıcı bayrak deseni. Anasayfa'daki "Beni Sına"
  /// kartı bu bayrağa göre ilk-kez davetkâr metinden "Tekrar Dene" metnine
  /// geçer (bkz. home_screen.dart) — böylece kullanıcı testi bir kez
  /// tamamladıktan sonra agresif biçimde tekrar tekrar davet edilmez.
  bool get hasTakenPlacementExam => _get('placement_exam_taken', false) as bool;
  Future<void> markPlacementExamTaken() => _set('placement_exam_taken', true);

  String getUserName() => _get('name', '') as String;

  /// İsimdeki HER kelimenin ilk harfini büyütür, kalanını küçültür — Türkçe
  /// kurallarıyla ("ali veli" → "Ali Veli", "irem" → "İrem", "IŞIL" → "Işıl").
  /// Dart'ın toUpperCase/toLowerCase'i Unicode varsayılanını uygular; 'i'→'İ'
  /// ve 'I'→'ı' dönüşümleri elle yapılır (bkz. AuthService.usernameKey'deki
  /// aynı tuzak).
  static String _adiBicimle(String ad) {
    return ad
        .trim()
        .split(RegExp(r'\s+'))
        .where((k) => k.isNotEmpty)
        .map((k) {
      final ilk = k[0] == 'i' ? 'İ' : k[0].toUpperCase();
      final kalan =
          k.substring(1).replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();
      return ilk + kalan;
    }).join(' ');
  }

  Future<void> setUserName(String n) {
    final c = n.trim();
    if (c.isEmpty) return _set('name', '');
    return _set('name', _adiBicimle(c));
  }

  // ── Tamamlanan konular ──
  Map<String, bool> getCompletedTopics() => Map<String, bool>.from(_get('completed', <String, dynamic>{}));
  Future<void> markTopicCompleted(String id) async {
    final c = getCompletedTopics();
    c[id] = true;
    await _set('completed', c);
  }

  bool isTopicCompleted(String id) => getCompletedTopics()[id] == true;

  // ── Testler (attempts) ──
  List<Attempt> getAttempts() {
    final raw = _get('attempts', <dynamic>[]) as List;
    return raw.map((a) => Attempt.fromJson(Map<String, dynamic>.from(a as Map))).toList();
  }

  Future<void> addAttempt(Attempt a) async {
    final all = getAttempts()..add(a);
    await _set('attempts', all.map((x) => x.toJson()).toList());
  }

  List<Attempt> getAttemptsForTopic(String id) => getAttempts().where((a) => a.topicId == id).toList();

  int? getBestScore(String id) {
    final arr = getAttemptsForTopic(id);
    if (arr.isEmpty) return null;
    return arr.map((a) => a.skor).reduce((a, b) => a > b ? a : b);
  }

  // ── Kullanılan sorular (tekrar önleme, konu bazlı) ──
  List<String> getUsedQuestions(String topicId) {
    final all = Map<String, dynamic>.from(_get('used_qs', <String, dynamic>{}));
    return List<String>.from(all[topicId] as List? ?? const []);
  }

  Future<void> addUsedQuestions(String topicId, List<String> keys) async {
    final all = Map<String, dynamic>.from(_get('used_qs', <String, dynamic>{}));
    final existing = Set<String>.from(all[topicId] as List? ?? const []);
    existing.addAll(keys);
    all[topicId] = existing.toList();
    await _set('used_qs', all);
  }

  Future<void> resetUsedQuestions(String topicId) async {
    final all = Map<String, dynamic>.from(_get('used_qs', <String, dynamic>{}));
    all.remove(topicId);
    await _set('used_qs', all);
  }

  // ── Yanlışlar bankası ──
  List<Map<String, dynamic>> getWrongBank() =>
      List<Map<String, dynamic>>.from((_get('wrong', <dynamic>[]) as List).map((e) => Map<String, dynamic>.from(e as Map)));

  /// Yanlış bankası anahtarı — addWrongQuestions/removeFromWrongBank ile
  /// QuizEngine.finish() arasında (Yanlışlarım'dan doğru çözülen soruyu
  /// bankadan silme) TUTARLI olması için tek noktadan üretiliyor.
  String wrongBankKeyFor(String soru) => soru.length > 40 ? soru.substring(0, 40) : soru;

  Future<void> addWrongQuestions(List<Question> questions, String subjectId, String subjectAd) async {
    final bank = getWrongBank();
    for (final q in questions) {
      final key = wrongBankKeyFor(q.soru);
      final idx = bank.indexWhere((w) => w['key'] == key);
      if (idx == -1) {
        bank.add({
          'key': key,
          'subjectId': subjectId,
          'subjectAd': subjectAd,
          'soru': q.soru,
          'secenekler': q.secenekler,
          'dogruIndex': q.dogruIndex,
          'aciklama': q.aciklama,
          'distractorAciklama': q.distractorAciklama,
          'kaynak': q.kaynak,
          'count': 1,
          'addedAt': DateTime.now().millisecondsSinceEpoch,
        });
      } else {
        bank[idx]['count'] = (bank[idx]['count'] as int? ?? 1) + 1;
      }
    }
    final trimmed = bank.length > 200 ? bank.sublist(bank.length - 200) : bank;
    await _set('wrong', trimmed);
  }

  Future<void> removeFromWrongBank(String key) async {
    final bank = getWrongBank()..removeWhere((w) => w['key'] == key);
    await _set('wrong', bank);
  }

  Future<void> clearWrongBank() => _set('wrong', <dynamic>[]);

  /// Buluttaki (cloud_backups) yanlış bankası girdilerini yerel bankayla
  /// BİRLEŞTİRİR — asla üzerine yazmaz. Aynı 'key' hem yerelde hem bulutta
  /// varsa, 'count' değerlerinin BÜYÜĞÜ tutulur; sadece bulutta olan girdi
  /// olduğu gibi eklenir. CloudSyncService.syncDown tarafından, kullanıcı
  /// başka bir cihazda Google ile giriş yaptığında yanlış bankasının
  /// "kaybolmuş" gibi görünmemesi için kullanılır.
  Future<void> mergeWrongBank(List<Map<String, dynamic>> remoteBank) async {
    if (remoteBank.isEmpty) return;
    final bank = getWrongBank();
    for (final remote in remoteBank) {
      final key = remote['key'] as String?;
      if (key == null) continue;
      final idx = bank.indexWhere((w) => w['key'] == key);
      if (idx == -1) {
        bank.add(Map<String, dynamic>.from(remote));
      } else {
        final localCount = (bank[idx]['count'] as num?)?.toInt() ?? 1;
        final remoteCount = (remote['count'] as num?)?.toInt() ?? 1;
        bank[idx]['count'] = localCount > remoteCount ? localCount : remoteCount;
      }
    }
    final trimmed = bank.length > 200 ? bank.sublist(bank.length - 200) : bank;
    await _set('wrong', trimmed);
  }

  // ── Rozetler ──
  List<String> getUnlockedBadges() => List<String>.from(_get('badges', <dynamic>[]));
  Future<bool> unlockBadge(String id) async {
    final b = getUnlockedBadges();
    if (!b.contains(id)) {
      b.add(id);
      await _set('badges', b);
      return true;
    }
    return false;
  }

  bool isBadgeUnlocked(String id) => getUnlockedBadges().contains(id);

  // ── Seri (streak) ──
  Map<String, dynamic> getStreak() => Map<String, dynamic>.from(_get('streak', {'count': 0, 'lastDate': null}));

  Future<Map<String, dynamic>> touchStreak() async {
    final today = DateTime.now().toString().split(' ')[0];
    final s = getStreak();
    if (s['lastDate'] == today) return s;
    final yesterday = DateTime.now().subtract(const Duration(days: 1)).toString().split(' ')[0];
    s['count'] = (s['lastDate'] == yesterday) ? (s['count'] as int) + 1 : 1;
    s['lastDate'] = today;
    await _set('streak', s);
    return s;
  }

  /// Bulut yedeğindeki (cloud_backups) seriyi DOĞRUDAN geri yükler —
  /// SADECE CloudSyncService.syncDown tarafından, yerelde henüz gerçek bir
  /// seri yokken (count == 0) kullanılır. touchStreak()'in "bugün/dün"
  /// mantığından farklı olarak burada bulut verisi olduğu gibi yazılır.
  Future<void> restoreStreak(Map<String, dynamic> data) => _set('streak', data);

  // ── Sohbet günlük mesaj limiti (ücretsiz: 10/gün genel sohbet) ──
  int getChatMessagesSentToday() {
    final today = DateTime.now().toString().split(' ')[0];
    final data = Map<String, dynamic>.from(_get('chat_daily', {'date': null, 'count': 0}));
    if (data['date'] != today) return 0;
    return (data['count'] as num).toInt();
  }

  Future<void> incrementChatMessagesSentToday() async {
    final today = DateTime.now().toString().split(' ')[0];
    final current = getChatMessagesSentToday();
    await _set('chat_daily', {'date': today, 'count': current + 1});
  }

  /// DM gelen kutusunda karşı tarafın uid'ini görünen isme çevirmek için
  /// yerel önbellek — bir DM ilk başlatıldığında (genel sohbetteki bir
  /// mesajdan) karşı tarafın adı buraya kaydedilir.
  Map<String, String> getDmPeerNames() => Map<String, String>.from(_get('dm_peer_names', <String, dynamic>{}));

  Future<void> saveDmPeerName(String uid, String name) async {
    final m = getDmPeerNames();
    m[uid] = name;
    await _set('dm_peer_names', m);
  }

  // ── Taslak testler (yarım kalan, BİRDEN FAZLA aynı anda desteklenir) ──
  // Anahtar = testi tetikleyen kimlik (konu id'si, '{subjectId}-sinav' ya da
  // 'full-test') — böylece farklı testlerin taslakları bir arada tutulur;
  // aynı kimlikle yeniden başlanan test üzerine yazar.
  Future<void> saveDraft(String key, Map<String, dynamic> state) async {
    final all = getAllDrafts();
    all[key] = state;
    await _set('drafts', all);
  }

  Map<String, Map<String, dynamic>> getAllDrafts() {
    final raw = _get('drafts', <String, dynamic>{}) as Map;
    return raw.map((k, v) => MapEntry(k as String, Map<String, dynamic>.from(v as Map)));
  }

  Map<String, dynamic>? getDraft(String key) => getAllDrafts()[key];

  Future<void> clearDraft(String key) async {
    final all = getAllDrafts()..remove(key);
    await _set('drafts', all);
    notifyListeners();
  }

  // ── Ayarlar ──
  static const Map<String, dynamic> defaultSettings = {
    'theme': 'default',
    'particleEnabled': true,
    'particleColor': 'rainbow',
    'soundEnabled': true,
    'timerMode': 'auto',
    'secsPerQ': 65,
    'plan': 'free',
    'notifications': {'reminders': true, 'updates': true},
    'cloudBackupEnabled': false,
    'hideStats': false,
    'adaptationSoundsEnabled': false,
  };

  Map<String, dynamic> getSettings() {
    final stored = Map<String, dynamic>.from(_get('settings', <String, dynamic>{}));
    final merged = {...defaultSettings, ...stored};
    merged['notifications'] = {
      ...defaultSettings['notifications'] as Map<String, dynamic>,
      ...(stored['notifications'] as Map<String, dynamic>? ?? {}),
    };
    return merged;
  }

  Future<void> saveSettings(Map<String, dynamic> patch) async {
    final merged = {...getSettings(), ...patch};
    await _set('settings', merged); // _set zaten notifyListeners() çağırıyor
  }

  String getUserPlan() => (getSettings()['plan'] as String?) ?? 'free';
  Future<void> setUserPlan(String plan) => saveSettings({'plan': plan});
  bool isPremiumUser() => getUserPlan() == 'premium';

  Map<String, dynamic> getNotificationSettings() =>
      Map<String, dynamic>.from(getSettings()['notifications'] as Map);
  Future<void> saveNotificationSettings(Map<String, dynamic> cfg) async {
    final n = {...getNotificationSettings(), ...cfg};
    await saveSettings({'notifications': n});
  }

  bool getCloudBackupEnabled() => getSettings()['cloudBackupEnabled'] == true;
  Future<void> setCloudBackupEnabled(bool enabled) => saveSettings({'cloudBackupEnabled': enabled});

  /// "İstatistiklerimi Gizle" gizlilik tercihi — açıksa, bu kullanıcının
  /// profili başka bir kullanıcı tarafından sohbet/DM üzerinden görüntülenmeye
  /// çalışıldığında (bkz. PublicProfileScreen, LeagueService.fetchUserProfile)
  /// gerçek sayılar yerine "istatistiklerini gizli tutuyor" yer tutucusu
  /// gösterilir. Diğer senkronize kullanıcı tercihleri (plan, cloudBackupEnabled
  /// vb.) ile AYNI `settings` deseni kullanılır.
  bool getHideStatsEnabled() => getSettings()['hideStats'] == true;
  Future<void> setHideStatsEnabled(bool enabled) => saveSettings({'hideStats': enabled});

  /// "Adaptasyon Sesleri" — testi çözerken arka planda gerçekçi bir sınav
  /// salonu atmosferi (öksürük, kağıt hışırtısı, kalem sesi vb.) duyulsun mu?
  /// bkz. QuizScreen (tetikleme) ve SoundService.startFocusAmbience/
  /// stopFocusAmbience (zaten var olan, önceden hiçbir yerden çağrılmayan
  /// oynatma mekanizması — burada sadece bir ayar anahtarıyla bağlanıyor).
  bool getAdaptationSoundsEnabled() => getSettings()['adaptationSoundsEnabled'] == true;
  Future<void> setAdaptationSoundsEnabled(bool enabled) => saveSettings({'adaptationSoundsEnabled': enabled});

  // ── Kart Eşleştirme Oyunu: günlük hak takibi ──
  Map<String, dynamic> getCardGameState() {
    final today = DateTime.now().toString().split(' ')[0];
    final s = Map<String, dynamic>.from(_get('cardgame', {'date': today, 'plays': 0}));
    if (s['date'] != today) return {'date': today, 'plays': 0};
    return s;
  }

  Future<int> useCardGamePlay() async {
    final s = getCardGameState();
    s['plays'] = (s['plays'] as int) + 1;
    await _set('cardgame', s);
    return s['plays'] as int;
  }

  // ── Eşleştirme Solitaire: oyun-içi coin/altın ekonomisi ──
  // ÖNEMLİ: Bu coin YALNIZCA Eşleştirme Solitaire oyununa özel, tamamen
  // KOZMETİK bir oyun-içi puandır. Gerçek para / `in_app_purchase` ile HİÇBİR
  // ilgisi YOKTUR; App Store / Play Store satın almalarına bağlanmaz. Oyuncu
  // doğru eşleştirme yaptıkça kazanır, oyun içi markette ekstra ipucu / geri-al
  // / joker / hamle satın almak için harcar. (Kalıcı, günlük sıfırlanmaz.)
  int getSolitaireCoins() => ((_get('solitaire_coins', 0) as num?) ?? 0).toInt();

  Future<void> addSolitaireCoins(int amount) async {
    if (amount <= 0) return;
    await _set('solitaire_coins', getSolitaireCoins() + amount);
  }

  /// Yeterli coin varsa [amount] kadar düşer ve true döner; YETERSİZSE hiç
  /// düşmez ve false döner (market butonları buna göre pasifleşir).
  Future<bool> spendSolitaireCoins(int amount) async {
    if (amount <= 0) return true;
    final cur = getSolitaireCoins();
    if (cur < amount) return false;
    await _set('solitaire_coins', cur - amount);
    return true;
  }

  // ── Genel oyun günlük hak takibi (Kart Oyunu V2 / Solitaire) — JS: getGamePlayState/useGamePlay.
  // NOT: Kart Oyunu v1 kendi ayrı sayacını (getCardGameState/useCardGamePlay) kullanır; JS'te
  // FREE_CARDGAME_DAILY (v1) ile FREE_GAME_DAILY (v2/solitaire, oyun başına ayrı) farklı sayaçlardır.
  Map<String, dynamic> getGamePlayState(String gameId) {
    final today = DateTime.now().toString().split(' ')[0];
    final s = Map<String, dynamic>.from(_get('gameplays_$gameId', {'date': today, 'plays': 0}));
    if (s['date'] != today) return {'date': today, 'plays': 0};
    return s;
  }

  Future<int> useGamePlay(String gameId) async {
    final s = getGamePlayState(gameId);
    s['plays'] = (s['plays'] as int) + 1;
    await _set('gameplays_$gameId', s);
    return s['plays'] as int;
  }

  // ── HAK CÜZDANI + reklam/satın alma ile ekstra haklar ──────────────────────
  //
  // Birleşik "hak" kredisi (kullanıcı kararı): ödüllü reklam +2, satın alma
  // +10. 1 hak = 1 ekstra oyun hakkı YA DA 1 deneme sınavı tekrarı. Kredi
  // istenen yerde harcanır (sohbet/DM HARİÇ — onlar reklamla açılmaz).
  // Premium kullanıcıda tüm bu sistem GİZLİDİR (sınırsız).

  int getHaklar() => (_get('haklar', 0) as num).toInt();
  Future<void> hakEkle(int n) async => _set('haklar', getHaklar() + n);

  /// [n] hak harcamayı dener. Yeterli bakiye yoksa false döner ve hiçbir şey
  /// değişmez.
  Future<bool> hakHarca(int n) async {
    final mevcut = getHaklar();
    if (mevcut < n) return false;
    await _set('haklar', mevcut - n);
    return true;
  }

  /// Bir oyunun BUGÜN için kazanılmış EKSTRA oynama hakları (reklam/hak ile).
  /// Günlük ücretsiz limitin ÜSTÜNE eklenir; gün değişince sıfırlanır.
  int getExtraPlays(String gameId) {
    final today = DateTime.now().toString().split(' ')[0];
    final s = Map<String, dynamic>.from(
        _get('extraplays_$gameId', {'date': today, 'extra': 0}));
    if (s['date'] != today) return 0;
    return (s['extra'] as num).toInt();
  }

  Future<void> addExtraPlays(String gameId, int n) async {
    final today = DateTime.now().toString().split(' ')[0];
    final mevcut = getExtraPlays(gameId);
    await _set('extraplays_$gameId', {'date': today, 'extra': mevcut + n});
  }

  /// Tam deneme sınavı için kazanılmış ekstra tekrar hakları (reklam/hak ile).
  /// Deneme sınavı ömür boyu sayıldığından bu da ömür boyu birikir.
  int getBonusFullTests() => (_get('bonus_full_tests', 0) as num).toInt();
  Future<void> addBonusFullTests(int n) async =>
      _set('bonus_full_tests', getBonusFullTests() + n);

  // ── Onboarding (karşılama tanıtımı) — CİHAZA özel, GLOBAL ────────────────────
  // Profil/hesaptan bağımsız: kaydırmalı tanıtım cihazda YALNIZCA İLK kurulumda
  // bir kez gösterilir. Bu yüzden profil ön eki KULLANILMAZ, doğrudan _prefs.
  bool onboardingGorulduMu() => _prefs?.getBool('onboarding_seen_v1') ?? false;
  Future<void> onboardingGoruldu() async =>
      _prefs?.setBool('onboarding_seen_v1', true);

  // ── Oyun ilerlemesi (Kart Oyunu V2 / Solitaire) — konu bazlı geçme takibi ──
  Map<String, bool> getGamePassedTopics(String gameId) =>
      Map<String, bool>.from(_get('game_passed_$gameId', <String, dynamic>{}));

  Future<void> markGameTopicPassed(String gameId, String topicId) async {
    final m = getGamePassedTopics(gameId);
    m[topicId] = true;
    await _set('game_passed_$gameId', m);
  }

  bool isGameTopicPassed(String gameId, String topicId) => getGamePassedTopics(gameId)[topicId] == true;

  // ── Çalışma kronometresi ──
  Map<String, int> getStudyTime() => Map<String, int>.from(_get('studytime', <String, dynamic>{}));
  Future<void> addStudyTime(String subjectId, int seconds) async {
    final t = getStudyTime();
    t[subjectId] = (t[subjectId] ?? 0) + seconds;
    await _set('studytime', t);
  }

  int getTotalStudyTime() => getStudyTime().values.fold(0, (a, b) => a + b);

  // ── Mini oyun bazlı toplam oynama süresi (Kart Oyunu / Balon Patlat / Hız 60 /
  // Düello vb.) — `getStudyTime`/`addStudyTime` ile AYNI desen (Map<String, int>,
  // ders yerine oyun kimliği anahtarlı), ama TAMAMEN AYRI bir alanda tutulur;
  // "kaç saat/dakika oynadın" gibi kalıcı, hiç sıfırlanmayan bir toplam sağlar.
  Map<String, int> getGameTimeSpentAll() => Map<String, int>.from(_get('game_time_spent', <String, dynamic>{}));

  /// [gameId] için o oyunda geçirilen kümülatif süreyi saniye cinsinden döner.
  int getGameTimeSpent(String gameId) => getGameTimeSpentAll()[gameId] ?? 0;

  /// Bir oyun oturumu bittiğinde (dispose/finish, erken çıkış dahil) çağrılır;
  /// [duration] o oturumda geçen süredir ve mevcut toplama EKLENİR.
  Future<void> addGameTimeSpent(String gameId, Duration duration) async {
    final seconds = duration.inSeconds;
    if (seconds <= 0) return;
    final t = getGameTimeSpentAll();
    t[gameId] = (t[gameId] ?? 0) + seconds;
    await _set('game_time_spent', t);
  }

  // ── İçerik güncelleme bildirimi ("Yeni sorular eklendi") ──
  // Sunucudaki (Firestore app_meta/content_version) son güncelleme zaman
  // damgası, kullanıcının EN SON GÖRDÜĞÜ sürümle karşılaştırılır — sunucu
  // daha yeniyse "Tüm Soruları İndir" ile güncelleme bildirimi gösterilir.
  int getLastSeenContentVersionMs() => (_get('last_seen_content_version', 0) as num).toInt();
  Future<void> setLastSeenContentVersionMs(int millis) => _set('last_seen_content_version', millis);

  // ── Haftalık lig puanı (Pazartesi başlangıçlı; hafta değişince otomatik sıfırlanır) ──
  String _mondayOf(DateTime d) {
    final monday = d.subtract(Duration(days: d.weekday - 1));
    final day = DateTime(monday.year, monday.month, monday.day);
    return day.toIso8601String().split('T')[0];
  }

  Map<String, dynamic> _weeklyRaw() =>
      Map<String, dynamic>.from(_get('weekly_points', <String, dynamic>{'weekStart': '', 'points': 0}));

  /// Bu haftanın (Pazartesi'den bugüne) lig puanı — hafta değiştiyse 0 döner.
  int getWeeklyPoints() {
    final raw = _weeklyRaw();
    if (raw['weekStart'] != _mondayOf(DateTime.now())) return 0;
    return (raw['points'] as num?)?.toInt() ?? 0;
  }

  /// Doğru cevap başına çağrılır (bkz. QuizEngine.finish) — hafta değiştiyse
  /// önce sıfırlar, sonra puanı ekler.
  Future<void> addWeeklyPoints(int points) async {
    if (points <= 0) return;
    final thisWeek = _mondayOf(DateTime.now());
    final raw = _weeklyRaw();
    final current = raw['weekStart'] == thisWeek ? ((raw['points'] as num?)?.toInt() ?? 0) : 0;
    await _set('weekly_points', {'weekStart': thisWeek, 'points': current + points});
  }

  // ── Konu testi sıfırlama ──
  Future<void> resetTopicAttempts(String topicId) async {
    final remaining = getAttempts().where((a) => a.topicId != topicId).toList();
    await _set('attempts', remaining.map((x) => x.toJson()).toList());
    final c = getCompletedTopics()..remove(topicId);
    await _set('completed', c);
    await resetUsedQuestions(topicId);
    await clearDraft(topicId);
  }

  // ── Bilgi Maratonu: en uzun seri (yerel rekor) ──
  int getBestMarathonStreak() => ((_get('best_marathon_streak', 0) as num?) ?? 0).toInt();

  Future<void> setBestMarathonStreak(int streak) async {
    if (streak > getBestMarathonStreak()) {
      await _set('best_marathon_streak', streak);
    }
  }

  // ── Oyun rekorları: her mini oyun için "en yüksek skor" + son doğru/yanlış ──
  //
  // Tek bir ortak API; her oyun kendi `gameId`'sini verir (ör. 'hiz_60',
  // 'yazim_yanlislari', 'tarihleri_bil', 'kimim_ben'). Böylece her oyuna ayrı
  // ayrı anahtar/metod eklemek gerekmez.

  Map<String, dynamic> _highScores() =>
      Map<String, dynamic>.from((_get('game_high_scores', {}) as Map?) ?? {});

  /// [gameId] için kaydedilmiş en yüksek skor (hiç oynanmadıysa 0).
  int getHighScore(String gameId) =>
      ((_highScores()[gameId] as num?) ?? 0).toInt();

  /// Skoru kaydeder — SADECE önceki rekordan büyükse günceller.
  /// Yeni bir rekor kırıldıysa `true` döner (UI "Yeni rekor!" gösterebilir).
  Future<bool> submitHighScore(String gameId, int score) async {
    if (score <= getHighScore(gameId)) return false;
    final all = _highScores();
    all[gameId] = score;
    await _set('game_high_scores', all);
    return true;
  }

  /// Bir oyunun EN SON turundaki doğru/yanlış sayısı — sonuç ekranında
  /// "hangisine çalışmalısın" yorumunu üretmek için kullanılır.
  Map<String, int> getLastRoundStats(String gameId) {
    final all = Map<String, dynamic>.from(
        (_get('game_last_round', {}) as Map?) ?? {});
    final row = Map<String, dynamic>.from((all[gameId] as Map?) ?? {});
    return {
      'correct': ((row['correct'] as num?) ?? 0).toInt(),
      'wrong': ((row['wrong'] as num?) ?? 0).toInt(),
    };
  }

  Future<void> setLastRoundStats(
    String gameId, {
    required int correct,
    required int wrong,
  }) async {
    final all = Map<String, dynamic>.from(
        (_get('game_last_round', {}) as Map?) ?? {});
    all[gameId] = {'correct': correct, 'wrong': wrong};
    await _set('game_last_round', all);
  }

  // ── Günün Patronu: günde 1 kez oynanabilir + toplam tamamlama sayacı ──
  // (rozet eşiği için, bkz. models/badge.dart 'gunun-patronu').
  String? getGununPatronuLastDate() => _get('gunun_patronu_last', null) as String?;

  bool hasPlayedGununPatronuToday() {
    final today = DateTime.now().toString().split(' ')[0];
    return getGununPatronuLastDate() == today;
  }

  int getGununPatronuCompletedCount() => ((_get('gunun_patronu_count', 0) as num?) ?? 0).toInt();

  /// 20 soruluk günlük Günün Patronu turu tamamlandığında çağrılır — bugünü
  /// "oynandı" olarak kilitler ve toplam tamamlama sayacını bir artırır.
  Future<void> markGununPatronuCompleted() async {
    final today = DateTime.now().toString().split(' ')[0];
    await _set('gunun_patronu_last', today);
    await _set('gunun_patronu_count', getGununPatronuCompletedCount() + 1);
  }

  // ── İstatistik yardımcıları ──
  int? computeSubjectAvg(String subjectId) {
    final arr = getAttempts().where((a) => a.subjectId == subjectId).toList();
    if (arr.isEmpty) return null;
    return (arr.map((a) => a.skor).reduce((a, b) => a + b) / arr.length).round();
  }

  ({int solved, int correct, int rate, int tests}) computeOverall() {
    final a = getAttempts();
    final solved = a.fold(0, (s, x) => s + x.toplam);
    final correct = a.fold(0, (s, x) => s + x.dogru);
    final rate = solved > 0 ? ((correct / solved) * 100).round() : 0;
    return (solved: solved, correct: correct, rate: rate, tests: a.length);
  }

  // ── Toplam XP / Seviye (KALICI, asla sıfırlanmaz) ──
  // NOT: Bu, hafta değişince sıfırlanan `weekly_points` (bkz. getWeeklyPoints/
  // addWeeklyPoints, haftalık lig puanı) alanından TAMAMEN AYRI bir alandır.
  // Toplam XP hiç sıfırlanmaz; kullanıcının kalıcı "Seviye"sini besler.
  int getTotalXp() => ((_get('total_xp', 0) as num?) ?? 0).toInt();

  /// QuizEngine.finish() içinde her doğru cevap için çağrılır (bkz. XP=5/doğru,
  /// haftalık lig puanı=10/doğru — birbirinden bağımsız iki katsayı).
  Future<void> addXp(int amount) async {
    if (amount <= 0) return;
    await _set('total_xp', getTotalXp() + amount);
  }

  /// Seviye eğrisi: level = 1 + floor(sqrt(xp / 50)).
  /// Seviye 1: 0-49 XP, Seviye 2: 50-199 XP, Seviye 3: 200-449 XP, Seviye 4: 450-799 XP, ...
  /// Kare kök eğrisi seçildi çünkü bir sonraki seviyeye ulaşmak için gereken XP
  /// farkı seviye arttıkça büyür (50, 150, 250, 350, ...) — bu da erken
  /// seviyelerin hızlı, ileri seviyelerin daha zor açılmasını sağlar.
  static int getLevelForXp(int xp) {
    if (xp <= 0) return 1;
    return 1 + sqrt(xp / 50).floor();
  }

  /// getLevelForXp'nin tersi: verilen seviyeye ulaşmak için gereken TOPLAM XP eşiği.
  /// xp = 50 * (level - 1)^2
  static int xpForLevel(int level) {
    if (level <= 1) return 0;
    final n = level - 1;
    return 50 * n * n;
  }

  /// Şu anki seviyeden BİR SONRAKİ seviyeye geçmek için gereken TOPLAM XP eşiği.
  static int xpForNextLevel(int currentLevel) => xpForLevel(currentLevel + 1);

  // ── Sezon XP (aylık; ay değişince otomatik sıfırlanır — weekly_points ile
  // AYNI desen, sadece Pazartesi yerine ay bazlı bir "seasonKey" kullanılır). ──
  String _seasonKeyOf(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

  Map<String, dynamic> _seasonRaw() =>
      Map<String, dynamic>.from(_get('season_xp', <String, dynamic>{'seasonKey': '', 'xp': 0}));

  /// Bu ayın (sezonun) toplam XP'si — ay değiştiyse 0 döner.
  int getSeasonXp() {
    final raw = _seasonRaw();
    if (raw['seasonKey'] != _seasonKeyOf(DateTime.now())) return 0;
    return (raw['xp'] as num?)?.toInt() ?? 0;
  }

  /// QuizEngine.finish() içinde toplam XP ile AYNI ANDA (aynı katsayıyla)
  /// çağrılır — toplam XP kalıcı seviye içindir, sezon XP'si sadece bu ayki
  /// performansı gösterir ve ay değişince sıfırlanır.
  Future<void> addSeasonXp(int amount) async {
    if (amount <= 0) return;
    final thisSeason = _seasonKeyOf(DateTime.now());
    final raw = _seasonRaw();
    final current = raw['seasonKey'] == thisSeason ? ((raw['xp'] as num?)?.toInt() ?? 0) : 0;
    await _set('season_xp', {'seasonKey': thisSeason, 'xp': current + amount});
  }

  /// Profil ekranında gösterilen "Temmuz 2026 Sezonu" gibi bir etiket üretir.
  String getCurrentSeasonLabel() {
    const months = [
      'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
      'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
    ];
    final now = DateTime.now();
    return '${months[now.month - 1]} ${now.year}';
  }

  // ── PDF dışa aktarma sayacı — bir konu için kaç kez PDF oluşturulduğunu
  // saklar; ilk PDF'de konu anlatımı dahil edilir, sonraki PDF'lerde yalnızca
  // farklı sorular verilir (bkz. pdf_export_service.dart / topic_screen.dart). ──
  int getPdfExportCount(String topicId) {
    final m = _get('pdf_export_counts', <String, dynamic>{});
    final v = m[topicId];
    return v is int ? v : 0;
  }

  Future<void> incrementPdfExportCount(String topicId) async {
    final m = Map<String, dynamic>.from(_get('pdf_export_counts', <String, dynamic>{}));
    m[topicId] = getPdfExportCount(topicId) + 1;
    await _set('pdf_export_counts', m);
  }

  // ── Günlük Giriş Ödülü ──
  static const int kDailyLoginRewardXp = 15;

  /// Uygulama bugün ilk kez açıldığında (ya da ilk kez bu metot çağrıldığında)
  /// bir kerelik XP ödülü verir ve `true` döner; bugün zaten alındıysa `false`
  /// döner. bkz. HomeScreen._checkDailyLoginReward.
  Future<bool> claimDailyLoginRewardIfNeeded() async {
    final today = DateTime.now().toString().split(' ')[0];
    final last = _get('daily_login_reward_last', null) as String?;
    if (last == today) return false;
    await _set('daily_login_reward_last', today);
    await addXp(kDailyLoginRewardXp);
    return true;
  }
}
