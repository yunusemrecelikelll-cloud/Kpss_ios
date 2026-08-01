import 'dart:collection';

import 'package:flutter/foundation.dart';

/// Uygulama İÇİ bildirim afişi (banner) kuyruğu.
///
/// Yeni mesaj / arkadaşlık isteği geldiğinde ekranın ÜSTÜNDEN aşağı kayan,
/// birkaç saniye durup yukarı geri kaybolan bir afiş gösterilir (bkz.
/// InAppNoticeOverlay). Bu servis yalnızca KUYRUĞU yönetir; çizim overlay'in
/// işidir.
///
/// TEST ERTELEME: Kullanıcı test çözerken afiş dikkat dağıtır. quiz_screen
/// [beklet] / [devamEt] çağırır; bekletme sırasında gelen afişler kuyruğa
/// alınır ve test bitince sırayla gösterilir (kullanıcı isteği: "test
/// çözüyorsa bildirim test bittikten sonra gelsin").
///
/// Bekletme SAYAÇLIDIR: iç içe iki ekran beklet derse, ikisi de devamEt
/// demeden akış açılmaz.
class InAppNotice {
  final String baslik;
  final String govde;
  final String emoji;

  /// Aynı etikete sahip PEŞ PEŞE bildirimler tek bir (en son) bildirime
  /// indirgenir — kuyrukta o etiketten yalnızca en yenisi kalır. Örneğin
  /// hızlıca tema değiştirince "Tema değiştirildi" afişleri üst üste yığılmaz;
  /// yalnızca son değişikliğin bildirimi görünür (kullanıcı isteği). Etiket
  /// null ise bu birleştirme yapılmaz (her bildirim ayrı gösterilir).
  final String? etiket;

  const InAppNotice({
    required this.baslik,
    required this.govde,
    this.emoji = '🔔',
    this.etiket,
  });
}

class InAppNoticeService extends ChangeNotifier {
  InAppNoticeService._();
  static final InAppNoticeService instance = InAppNoticeService._();

  final Queue<InAppNotice> _kuyruk = Queue<InAppNotice>();
  int _bekletmeSayaci = 0;

  /// O anda AÇIK olan özel sohbetin karşı taraf uid'i (DM ekranı girişte
  /// yazar, çıkışta temizler). Gözcü, kullanıcının zaten bakmakta olduğu
  /// sohbet için afiş göstermesin diye bunu kontrol eder.
  String? aktifDmPeerUid;

  /// Overlay'in o an göstermesi gereken afiş (yoksa null).
  InAppNotice? _aktif;
  InAppNotice? get aktif => _aktif;

  bool get _bekletiliyor => _bekletmeSayaci > 0;

  /// Yeni bir afiş talep eder. Bekletme aktifse ya da halihazırda bir afiş
  /// gösteriliyorsa kuyruğa girer.
  void goster(InAppNotice bildirim) {
    // KULLANICI İSTEĞİ: Yeni bir bildirim gelince ÖNCEKİLER KOMPLE SİLİNİR ve
    // yenisi HEMEN gösterilir — arka arkaya bildirim yığılmaz, kullanıcı neye
    // tıkladıysa onunla ilgili afiş anında görünür. (Test sırasında akış
    // bekletiliyorsa yalnızca en son bildirim beklemede kalır, o da tek olur.)
    _kuyruk.clear();
    _aktif = null;
    _kuyruk.add(bildirim);
    _iletmeyiDene();
  }

  /// Aktif afiş kapandığında overlay çağırır — sıradaki gösterilir.
  void aktifKapandi() {
    _aktif = null;
    _iletmeyiDene();
  }

  /// Test/sınav başlarken çağrılır: afiş akışını duraklat.
  void beklet() {
    _bekletmeSayaci++;
  }

  /// Test/sınav bitince çağrılır: birikenler sırayla gösterilir.
  void devamEt() {
    if (_bekletmeSayaci > 0) _bekletmeSayaci--;
    _iletmeyiDene();
  }

  void _iletmeyiDene() {
    if (_bekletiliyor || _aktif != null || _kuyruk.isEmpty) return;
    _aktif = _kuyruk.removeFirst();
    notifyListeners();
  }
}
