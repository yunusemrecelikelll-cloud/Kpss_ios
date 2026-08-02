import 'package:flutter/material.dart';
import 'app_theme.dart';
import '../services/storage_service.dart';

class ThemeProvider extends ChangeNotifier {
  final StorageService storage;
  // Kullanıcı isteği: uygulama İLK açıldığında (kayıtlı tema yokken) Pembe
  // Rüya temasıyla açılsın. Kayıtlı tercihi olan kullanıcılar kendi temasında
  // kalır. 'pembe' ücretsiz temalar arasında (bkz. kFreeThemeIds).
  String _themeId = 'pembe';

  ThemeProvider(this.storage) {
    _themeId = (storage.getSettings()['theme'] as String?) ?? 'pembe';
  }

  /// Premium düşerse (abonelik iptal vb.) kilitli bir temada takılı kalmasın.
  KpssColors get colors {
    if (!kFreeThemeIds.contains(_themeId) && !storage.isPremiumUser()) {
      return kThemes['default']!;
    }
    return kThemes[_themeId] ?? kThemes['default']!;
  }

  ThemeData get themeData => buildThemeData(colors);
  String get themeId => _themeId;

  /// Tema premium'a özelse ve kullanıcı ücretsizse false döner (UI Premium'a yönlendirsin).
  Future<bool> setTheme(String id) async {
    if (!kThemes.containsKey(id)) return false;
    if (!kFreeThemeIds.contains(id) && !storage.isPremiumUser()) return false;
    _themeId = id;
    await storage.saveSettings({'theme': id});
    notifyListeners();
    return true;
  }
}
