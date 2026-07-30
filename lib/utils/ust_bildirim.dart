import '../services/in_app_notice_service.dart';

/// Alttan çıkan SnackBar yerine ekranın ÜSTÜNDEN kayan afiş gösterir
/// (bkz. InAppNoticeService / InAppNoticeOverlay). Kullanıcı isteği:
/// "bütün alttan gelen bildirimler üstten gelsin".
///
/// BuildContext GEREKMEZ: servis bir singleton olduğundan async boşluk sonrası
/// da güvenle çağrılabilir (yakalanmış `messenger` değişkenine gerek kalmaz).
///
/// Afiş overlay'i tek satırdır: [mesaj] başlık olarak çizilir. Emoji, mesajın
/// türünü sezdirir; [etiket] verilirse aynı etiketli peş peşe afişler tek
/// (en son) afişe iner (bkz. InAppNotice.etiket).
void ustBildirim(
  String mesaj, {
  UstBildirimTuru tur = UstBildirimTuru.bilgi,
  String? etiket,
}) {
  InAppNoticeService.instance.goster(InAppNotice(
    baslik: mesaj,
    govde: '',
    emoji: switch (tur) {
      UstBildirimTuru.basari => '✅',
      UstBildirimTuru.hata => '⚠️',
      UstBildirimTuru.bilgi => 'ℹ️',
    },
    etiket: etiket,
  ));
}

/// Üst afişin emojisini seçen tür. Metin renkleri temadan gelir; yalnızca emoji
/// değişir (yüzey rengi tema morudur, kırmızı/yeşil SnackBar'lardan farklı).
enum UstBildirimTuru { basari, hata, bilgi }
