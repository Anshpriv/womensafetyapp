import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_en.dart';
import '../l10n/app_hi.dart';
import '../l10n/app_mr.dart';

class TranslationService {
  static final Map<String, Map<String, String>> _translations = {
    'en': en,
    'hi': hi,
    'mr': mr,
  };

  static String _currentLanguage = 'en';

  // Get current language
  static String get currentLanguage => _currentLanguage;

  // Initialize and load saved language
  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _currentLanguage = prefs.getString('language') ?? 'en';
  }

  // Change language and save
  static Future<void> changeLanguage(String languageCode) async {
    _currentLanguage = languageCode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', languageCode);
  }

  // Translate a key
  static String t(String key) {
    final translations = _translations[_currentLanguage] ?? _translations['en']!;
    return translations[key] ?? key;
  }

  static List<Map<String, String>> get supportedLanguages => [
    {'code': 'en', 'name': 'English', 'flag': '🇬🇧'},
    {'code': 'hi', 'name': 'हिंदी', 'flag': '🇮🇳'},
    {'code': 'mr', 'name': 'मराठी', 'flag': '🇮🇳'},
  ];
}
