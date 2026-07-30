import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'storage_service.dart';
import 'study_plan_service.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// Yerel bildirimler — "Günlük Çalışma Planı" hatırlatıcıları
/// ─────────────────────────────────────────────────────────────────────────
///
/// Kullanıcının plandaki her günü/saati için HAFTALIK TEKRARLAYAN bir yerel
/// bildirim kurar. Bildirim metni kullanıcının adıyla hitap eder ve her
/// seferinde farklı bir motivasyon cümlesi seçilir.
///
/// DAYANIKLILIK: Bu sınıftaki HİÇBİR metod istisna fırlatmaz. İzin reddedilirse,
/// platform desteklemiyorsa (web/masaüstü) ya da eklenti bir hata dönerse
/// sessizce no-op olunur ve durum [debugPrint] ile loglanır. Böylece bildirim
/// katmanı hiçbir koşulda uygulamayı çökertemez.
///
/// KULLANIM (main.dart):
///   await NotificationService.instance.initialize();
class NotificationService {
  NotificationService._();

  /// Tekil örnek — main.dart'ta bir kez `initialize()` edilir, her yerden
  /// `NotificationService.instance` ile erişilir (Provider'a kaydetmek şart
  /// değil, bkz. StudyPlanScreen).
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  final Random _rastgele = Random();

  /// Plan bildirimleri için kimlik tabanı. Uygulamadaki başka bir bildirimle
  /// çakışmaması için yüksek ve ayrık bir aralık seçildi.
  ///
  /// KİMLİK ŞEMASI (çoklu seans): Premium'da aynı güne birden fazla çalışma
  /// aralığı eklenebildiği için gün başına tek id yetmiyor. Her gün için SABİT
  /// [StudyPlanService.kSeansIdKapasitesi] kadar bölme ayrılır (ekleme limiti
  /// premium'a göre değişse de kimlik şeması hep bu kapasiteye göredir; yoksa
  /// premium 2. seansı başka bir günün kimliğiyle çakışırdı):
  ///
  ///   id = _kBaseId + 1 + (gun - 1) * kSeansIdKapasitesi + seansSirasi
  ///
  /// Böylece 9101..9184 aralığı plan bildirimlerine ayrılmış olur ve hiçbir
  /// seansın kimliği bir diğeriyle çakışmaz. 9100 (taban) tek seferlik test
  /// bildirimi için ayrılmıştır, bu aralığın dışındadır.
  static const int _kBaseId = 9100;

  /// İPTAL aralığı — kaç kimliği temizleyeceğimiz. Kimlik kapasitesiyle (7 gün ×
  /// gün başına kapasite) aynıdır; eski/tüm plan bildirimlerini kapsar.
  static const int _kPlanIdAdedi = 7 * StudyPlanService.kSeansIdKapasitesi;

  /// [gun] (1-7) gününün [sira]. seansı için bildirim kimliği.
  static int _planBildirimId(int gun, int sira) =>
      _kBaseId + 1 + (gun - 1) * StudyPlanService.kSeansIdKapasitesi + sira;

  static const String _kChannelId = 'kpss_calisma_plani';
  static const String _kChannelName = 'Çalışma Planı Hatırlatıcıları';
  static const String _kChannelDesc =
      'Planladığın gün ve saatte çalışma hatırlatması gönderir.';

  bool _hazir = false;

  /// Eklenti başarıyla kurulduysa true (web/masaüstünde her zaman false).
  bool get hazir => _hazir;

  /// Bu platformda yerel bildirim destekleniyor mu?
  /// `flutter_local_notifications` web'de çalışmaz; burada yalnızca Android ve
  /// iOS destekleniyor sayılıyor.
  bool get destekleniyorMu {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  // ── Başlatma ─────────────────────────────────────────────────────────────

  /// Timezone veritabanını yükler, yerel saat dilimini ayarlar ve eklentiyi
  /// iOS/Android ayarlarıyla başlatır. Birden fazla kez çağrılması güvenlidir.
  Future<void> initialize() async {
    if (!destekleniyorMu) {
      debugPrint('NotificationService: bu platformda bildirim desteklenmiyor, atlanıyor.');
      return;
    }
    if (_hazir) return;

    try {
      tzdata.initializeTimeZones();
      _setLocalLocation();

      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwin = DarwinInitializationSettings(
        // İzin akışını AÇIKÇA requestPermission() yönetsin — başlangıçta
        // kullanıcıyı karşılamadan izin penceresi açılmasın.
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );

      await _plugin.initialize(
        const InitializationSettings(android: android, iOS: darwin, macOS: darwin),
      );
      _hazir = true;
      debugPrint('NotificationService: başlatıldı (tz=${tz.local.name}).');
    } catch (e) {
      _hazir = false;
      debugPrint('NotificationService.initialize hatası: $e');
    }
  }

  /// Yerel saat dilimini ayarlar. Cihazın IANA bölge adını okuyacak bir paket
  /// (flutter_timezone) bağımlılığı yok; uygulama Türkiye'ye yönelik olduğu
  /// için varsayılan olarak Europe/Istanbul kullanılır. O da bulunamazsa
  /// cihazın UTC farkına en yakın bölgeye, en kötü ihtimalle UTC'ye düşülür.
  void _setLocalLocation() {
    try {
      tz.setLocalLocation(tz.getLocation('Europe/Istanbul'));
      return;
    } catch (e) {
      debugPrint('NotificationService: Europe/Istanbul bulunamadı ($e), UTC kullanılıyor.');
    }
    try {
      tz.setLocalLocation(tz.UTC);
    } catch (e) {
      debugPrint('NotificationService: yerel saat dilimi ayarlanamadı: $e');
    }
  }

  // ── İzin ─────────────────────────────────────────────────────────────────

  /// iOS'ta bildirim iznini, Android 13+ (API 33) üzerinde POST_NOTIFICATIONS
  /// iznini ister. Kullanıcı reddederse false döner — çağıran taraf yine de
  /// çalışmaya devam edebilir (plan kaydedilir, sadece bildirim gitmez).
  Future<bool> requestPermission() async {
    if (!destekleniyorMu) return false;
    if (!_hazir) await initialize();
    if (!_hazir) return false;

    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final ios = _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        final sonuc = await ios?.requestPermissions(alert: true, badge: true, sound: true);
        return sonuc ?? false;
      }

      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        // Android 13+ çalışma zamanı bildirim izni.
        final bildirim = await android?.requestNotificationsPermission();

        // ALARM İZNİ BİLEREK İSTENMİYOR.
        // Eskiden burada requestExactAlarmsPermission() çağrılıyordu ve bu,
        // kullanıcıya "Alarmlara ve hatırlatıcılara izin ver" sistem ekranını
        // açıyordu. Çalışma planı bir alarm değil, bir hatırlatmadır: dakikası
        // dakikasına çalması gerekmez. Zaten bildirimleri
        // AndroidScheduleMode.inexactAllowWhileIdle ile kuruyoruz (bkz.
        // schedulePlan) — yani izin verilse bile tam zamanlı alarm
        // kullanılmıyordu, izin ekranı tamamen gereksiz bir rahatsızlıktı.
        return bildirim ?? false;
      }
    } catch (e) {
      debugPrint('NotificationService.requestPermission hatası: $e');
    }
    return false;
  }

  // ── Planlama ─────────────────────────────────────────────────────────────

  /// Plandaki AKTİF her gün için haftalık tekrarlayan bir bildirim kurar.
  ///
  /// Önce daha önce kurulmuş plan bildirimlerini iptal eder; böylece plan
  /// değiştiğinde çift bildirim oluşmaz.
  Future<void> schedulePlan(
    List<StudyPlanEntry> plan, {
    required StorageService storage,
  }) async {
    if (!destekleniyorMu) {
      debugPrint('NotificationService.schedulePlan: platform desteklemiyor, atlandı.');
      return;
    }
    if (!_hazir) await initialize();
    if (!_hazir) return;

    // 1) Eski plan bildirimlerini temizle (çift bildirim koruması).
    await cancelPlanNotifications();

    // 2) Kullanıcı ayarlarından hatırlatmalar kapalıysa hiç kurma.
    try {
      final ayarlar = storage.getNotificationSettings();
      if (ayarlar['reminders'] == false) {
        debugPrint('NotificationService: hatırlatmalar kapalı, bildirim kurulmadı.');
        return;
      }
    } catch (e) {
      debugPrint('NotificationService: bildirim ayarı okunamadı: $e');
    }

    final ad = _hitap(storage);
    final detaylar = _detaylar();

    // Her gün için ayrı bir sıra sayacı: aynı güne birden fazla seans varsa
    // her biri kendi kimlik bölmesini alır (bkz. _planBildirimId).
    final gunSayaci = <int, int>{};

    // Kimliklerin cihaz yeniden kurulumları arasında tutarlı olması için
    // seansları gün + başlangıç saatine göre sıralı işliyoruz.
    final sirali = plan.where((e) => e.aktif && e.gecerliMi).toList()
      ..sort((a, b) {
        final g = a.gun.compareTo(b.gun);
        if (g != 0) return g;
        return a.baslangicDakikaToplam.compareTo(b.baslangicDakikaToplam);
      });

    for (final entry in sirali) {
      final sira = gunSayaci[entry.gun] ?? 0;
      if (sira >= StudyPlanService.kSeansIdKapasitesi) {
        debugPrint('NotificationService: ${StudyPlanService.gunAdi(entry.gun)} '
            'için seans kimliği kalmadı, atlandı.');
        continue;
      }
      gunSayaci[entry.gun] = sira + 1;

      try {
        final zaman = _sonrakiHaftalikAn(entry.gun, entry.baslangicSaat, entry.baslangicDakika);
        // ANDROID GÜVENİLİRLİK — 2. TUR ("test bildirimi geliyor ama planlı
        // gelmiyor, alarm izni açık"):
        // Haftalık tekrar (matchDateTimeComponents) Android'de eklentinin
        // kendi kendini yeniden kurmasına dayanır ve bazı üretici ROM'larında
        // bu zincir sessizce kopuyor. Bu yüzden Android'de artık TEKRARSIZ,
        // SOMUT tek alarm kuruluyor: her seansın YALNIZCA BİR SONRAKİ oluşu
        // planlanır. Uygulama zaten HER AÇILIŞTA schedulePlan'i yeniden
        // çalıştırdığı için (bkz. main.dart) bir sonraki hafta otomatik
        // yeniden kurulur. Tek sınır: kullanıcı uygulamayı 1 haftadan uzun
        // hiç açmazsa sonraki haftanın bildirimi kurulmaz — çalışma
        // uygulaması için kabul edilebilir bir ödünleşme, güvenilir teslimat
        // daha önemli.
        //
        // iOS'ta haftalık eşleme sistem takviminde sorunsuz çalıştığı için
        // aynen korunuyor.
        //
        // EXACT modu önce denenir (Android 12-13'te izin kurulumda otomatik;
        // 14+'ta kapalıysa inexact'e düşülür — plan ekranındaki "Bildirim
        // Durumu" kartı izni açtırabiliyor).
        final androidMi = defaultTargetPlatform == TargetPlatform.android;
        final esleme =
            androidMi ? null : DateTimeComponents.dayOfWeekAndTime;
        try {
          await _plugin.zonedSchedule(
            _planBildirimId(entry.gun, sira),
            _baslikSec(ad),
            _govdeSec(ad, entry),
            zaman,
            detaylar,
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            matchDateTimeComponents: esleme,
            payload: 'study_plan_${entry.gun}_${entry.id}',
          );
        } on PlatformException catch (e) {
          if (e.code != 'exact_alarms_not_permitted') rethrow;
          await _plugin.zonedSchedule(
            _planBildirimId(entry.gun, sira),
            _baslikSec(ad),
            _govdeSec(ad, entry),
            zaman,
            detaylar,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            matchDateTimeComponents: esleme,
            payload: 'study_plan_${entry.gun}_${entry.id}',
          );
        }
        debugPrint('NotificationService: ${StudyPlanService.gunAdi(entry.gun)} '
            '${entry.araliqMetni} için bildirim kuruldu.');
      } catch (e) {
        // Tek bir seansın kurulamaması diğerlerini engellemesin.
        debugPrint('NotificationService: ${entry.gun}. gün / ${entry.baslangicMetni} '
            'bildirimi kurulamadı: $e');
      }
    }
  }

  /// SADECE çalışma planı bildirimlerini (9101..9184) iptal eder — uygulamanın
  /// ileride ekleyebileceği başka bildirimlere dokunmaz.
  Future<void> cancelPlanNotifications() async {
    if (!destekleniyorMu || !_hazir) return;
    for (var i = 1; i <= _kPlanIdAdedi; i++) {
      final id = _kBaseId + i;
      try {
        await _plugin.cancel(id);
      } catch (e) {
        debugPrint('NotificationService: $id iptal edilemedi: $e');
      }
    }
  }

  /// Bekleyen TÜM bildirimleri iptal eder.
  Future<void> cancelAll() async {
    if (!destekleniyorMu) return;
    if (!_hazir) return;
    try {
      await _plugin.cancelAll();
      debugPrint('NotificationService: tüm bildirimler iptal edildi.');
    } catch (e) {
      debugPrint('NotificationService.cancelAll hatası: $e');
    }
  }

  /// Genel amaçlı ANLIK bildirim (planlı değil): yeni mesaj / arkadaşlık
  /// isteği gibi olaylar için, uygulama arka plandayken telefon bildirimi
  /// göstermekte kullanılır (bkz. InAppNoticeOverlay).
  ///
  /// Kimlikler 9300-9389 aralığında döndürülür — çalışma planı bildirimleriyle
  /// (9101..9184) ÇAKIŞMAZ, art arda gelen mesajlar birbirini ezmez.
  static int _basitBildirimSira = 0;
  Future<void> showBasit({required String baslik, required String govde}) async {
    if (!destekleniyorMu) return;
    if (!_hazir) await initialize();
    if (!_hazir) return;
    try {
      _basitBildirimSira = (_basitBildirimSira + 1) % 90;
      await _plugin.show(9300 + _basitBildirimSira, baslik, govde, _detaylar());
    } catch (e) {
      debugPrint('NotificationService.showBasit hatası: $e');
    }
  }

  // ── Günlük motivasyon bildirimi ──────────────────────────────────────────

  /// Motivasyon bildirimleri için kimlik tabanı. Plan (9101..9184), test (9100)
  /// ve anlık (9300..9389) aralıklarıyla ÇAKIŞMAZ.
  static const int _kMotivasyonBaseId = 9200;

  /// Kaç gün ileriye motivasyon kurulacağı. Her açılışta yeniden kurulduğu için
  /// (bkz. main.dart) 7 gün ileriyi doldurmak fazlasıyla yeterli.
  static const int _kMotivasyonGunSayisi = 7;

  static const String _kMotivChannelId = 'kpss_motivasyon';
  static const String _kMotivChannelName = 'Günlük Motivasyon';
  static const String _kMotivChannelDesc =
      'Her akşam kısa bir motivasyon ve çalışma hatırlatması gönderir.';

  /// SADECE motivasyon bildirimlerini (9200..9206) iptal eder.
  Future<void> cancelMotivation() async {
    if (!destekleniyorMu || !_hazir) return;
    for (var i = 0; i < _kMotivasyonGunSayisi; i++) {
      try {
        await _plugin.cancel(_kMotivasyonBaseId + i);
      } catch (e) {
        debugPrint('NotificationService: motivasyon ${_kMotivasyonBaseId + i} '
            'iptal edilemedi: $e');
      }
    }
  }

  /// Önümüzdeki [_kMotivasyonGunSayisi] gün için HER GÜN akşam 18:00–20:00
  /// arasında RASTGELE bir saatte bir motivasyon bildirimi kurar (kullanıcı
  /// isteği: "günlük 18:00–20:00 motivasyon bildirimleri").
  ///
  /// Her güne AYRI rastgele saat verilir (aynı saatte tekrarlayan tek bildirim
  /// yerine) — böylece bildirim mekanik hissettirmez. Uygulama her açılışta
  /// yeniden kurduğu için pencere sürekli ileriye kayar.
  ///
  /// Hatırlatmalar ayarlardan kapalıysa hiç kurulmaz (plan bildirimiyle aynı
  /// anahtar). Platform desteklemiyorsa / izin yoksa sessizce no-op.
  Future<void> scheduleDailyMotivation({required StorageService storage}) async {
    if (!destekleniyorMu) {
      debugPrint('NotificationService.scheduleDailyMotivation: platform yok, atlandı.');
      return;
    }
    if (!_hazir) await initialize();
    if (!_hazir) return;

    await cancelMotivation();

    try {
      final ayarlar = storage.getNotificationSettings();
      if (ayarlar['reminders'] == false) {
        debugPrint('NotificationService: hatırlatmalar kapalı, motivasyon kurulmadı.');
        return;
      }
    } catch (e) {
      debugPrint('NotificationService: motivasyon ayarı okunamadı: $e');
    }

    final ad = _hitap(storage);
    final detaylar = _motivasyonDetaylar();
    final simdi = tz.TZDateTime.now(tz.local);

    for (var i = 0; i < _kMotivasyonGunSayisi; i++) {
      // 18:00 (=1080 dk) ile 20:00 (=1200 dk) arası rastgele dakika.
      final toplamDk = 18 * 60 + _rastgele.nextInt(120); // 1080..1199
      final saat = toplamDk ~/ 60;
      final dakika = toplamDk % 60;
      var an = tz.TZDateTime(
        tz.local,
        simdi.year,
        simdi.month,
        simdi.day,
        saat,
        dakika,
      ).add(Duration(days: i));
      // Bugünün penceresi çoktan geçtiyse (ör. saat 21:00) bugünü atla.
      if (!an.isAfter(simdi)) continue;

      try {
        await _plugin.zonedSchedule(
          _kMotivasyonBaseId + i,
          _doldur(_secRastgele(_motivBasliklar), ad),
          _doldur(_secRastgele(_motivGovdeler), ad),
          an,
          detaylar,
          // Motivasyon dakikası dakikasına gelmek zorunda değil; alarm izni
          // istememek için inexact yeterli (plan mantığıyla aynı yaklaşım).
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: 'motivasyon',
        );
      } catch (e) {
        debugPrint('NotificationService: motivasyon (gün +$i) kurulamadı: $e');
      }
    }
    debugPrint('NotificationService: günlük motivasyon bildirimleri kuruldu.');
  }

  NotificationDetails _motivasyonDetaylar() {
    const android = AndroidNotificationDetails(
      _kMotivChannelId,
      _kMotivChannelName,
      channelDescription: _kMotivChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(''),
    );
    const darwin = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    return const NotificationDetails(android: android, iOS: darwin, macOS: darwin);
  }

  static const List<String> _motivBasliklar = [
    'Akşam motivasyonu 🌙',
    '{ad}, günü tamamla ✨',
    'Bugün ne yaptın {ad}? 📚',
    'Küçük bir adım daha {ad} 🚀',
    'KPSS seni bekliyor {ad} 🎯',
    'Seri bozulmasın {ad} 🔥',
  ];

  static const List<String> _motivGovdeler = [
    '{ad}, bugün 20 dakika çalışsan yarın bir adım öndesin. Hadi başla! 💪',
    'Akşamın en verimli saati {ad} 🌙 Kısa bir test çözmeye ne dersin?',
    'Seri bozulmasın {ad}! 🔥 Bugünkü çalışmanı tamamladın mı?',
    '{ad}, bugünkü net sayın yarınki hedefin. Hadi biraz çalışalım ✨',
    'Unutma {ad}: düzenli 30 dakika, ayda koca bir konu demek 📈',
    '{ad}, telefonu bırakıp 15 dakika soru çözsek mi? 🎯',
  ];

  // ── Yardımcılar ──────────────────────────────────────────────────────────

  NotificationDetails _detaylar() {
    const android = AndroidNotificationDetails(
      _kChannelId,
      _kChannelName,
      channelDescription: _kChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(''),
    );
    const darwin = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    return const NotificationDetails(android: android, iOS: darwin, macOS: darwin);
  }

  /// Verilen hafta günü (1=Pzt..7=Paz) ve saat için gelecekteki İLK anı bulur.
  /// `matchDateTimeComponents: dayOfWeekAndTime` ile birlikte bu, haftalık
  /// tekrar eden bir bildirim demektir.
  tz.TZDateTime _sonrakiHaftalikAn(int gun, int saat, int dakika) {
    final simdi = tz.TZDateTime.now(tz.local);
    var an = tz.TZDateTime(tz.local, simdi.year, simdi.month, simdi.day, saat, dakika);
    // Doğru hafta gününe ilerle.
    while (an.weekday != gun || !an.isAfter(simdi)) {
      an = an.add(const Duration(days: 1));
      an = tz.TZDateTime(tz.local, an.year, an.month, an.day, saat, dakika);
    }
    return an;
  }

  /// Kullanıcının adı — boşsa nötr bir hitap. "{ad}" yer tutucusu ASLA
  /// kullanıcıya görünmez; tüm şablonlar bu değerle doldurulur.
  String _hitap(StorageService storage) {
    try {
      final ad = storage.getUserName().trim();
      if (ad.isNotEmpty) return ad;
    } catch (e) {
      debugPrint('NotificationService: kullanıcı adı okunamadı: $e');
    }
    return 'Aday';
  }

  static const List<String> _basliklar = [
    '{ad}, çalışma vaktin! ⏰',
    'Hadi {ad}! 📚',
    'Plan seni bekliyor {ad} 🎯',
    '{ad}, sıra sende 💪',
    'KPSS yolculuğun devam ediyor {ad} 🚀',
  ];

  /// Bir SEANSA bağlı bildirim gövdeleri. `{aralik}` yer tutucusu seansın saat
  /// aralığıyla (ör. "14:00 - 15:30") doldurulur.
  ///
  /// Metinler kullanıcının KENDİ kurduğu plana atıfta bulunur ("çalışacaktık"):
  /// hatırlatma, dışarıdan gelen bir emir gibi değil, kişinin kendi verdiği
  /// sözün hatırlatılması gibi okunuyor — bu ton, genel "hadi çalış"
  /// mesajlarından daha çok işe yarıyor.
  static const List<String> _seansGovdeleri = [
    '{ad}, {aralik} arasında çalışacaktık. Hadi gel, başlayalım! 💪',
    'Hatırlatma {ad}: {aralik} çalışma saatin. Hadi gel! ⏰',
    '{ad}, {aralik} için söz vermiştin 🎯 Şimdi tam zamanı, hadi gel!',
    'Planında {aralik} yazıyor {ad} 📚 Hadi gel, seriyi bozmayalım.',
    '{ad}, {aralik} arası senin çalışma vaktin 🚀 Hadi gel, başlıyoruz!',
    'Vakit geldi {ad}! {aralik} arasında çalışacaktık ✨ Hadi gel.',
  ];

  /// Seansa bağlı OLMAYAN (ör. ayarlardaki "Dene" butonu) genel gövdeler.
  static const List<String> _genelGovdeler = [
    '{ad}, çalışma vaktin geldi! 💪 Bugünkü 20 dakika, sınavda 2 net demek.',
    'Hadi {ad}! ⏰ Kısa bir test bile seriyi bozmaz.',
    '{ad}, bugün dünden daha güçlü ol 🚀 Seni 15 dakikalık bir tur bekliyor.',
    'Küçük adımlar büyük netler {ad} ✨ Şimdi başla, 20 dakika yeter.',
    'Seri bozulmasın {ad}! 🔥 Bugünkü çalışmanı tamamla.',
  ];

  String _baslikSec(String ad) => _doldur(_secRastgele(_basliklar), ad);

  String _govdeSec(String ad, StudyPlanEntry? entry) {
    // Seans yoksa (test bildirimi) saat aralığından söz edemeyiz.
    if (entry == null) return _doldur(_secRastgele(_genelGovdeler), ad);
    return _doldur(_secRastgele(_seansGovdeleri), ad)
        .replaceAll('{aralik}', entry.araliqMetni);
  }

  String _secRastgele(List<String> liste) =>
      liste.isEmpty ? '' : liste[_rastgele.nextInt(liste.length)];

  /// Şablondaki {ad} yer tutucusunu doldurur. Güvenlik ağı: doldurma sonrası
  /// hâlâ bir yer tutucu kalmışsa temizlenir — ekranda "{ad}" görünmez.
  String _doldur(String sablon, String ad) =>
      sablon.replaceAll('{ad}', ad).replaceAll('{ad}', '').trim();
}
