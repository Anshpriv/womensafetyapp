import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageProvider extends ChangeNotifier {
  String _currentLanguage = 'en';

  String get currentLanguage => _currentLanguage;

  LanguageProvider() {
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    _currentLanguage = prefs.getString('language') ?? 'en';
    notifyListeners();
  }

  Future<void> changeLanguage(String languageCode) async {
    _currentLanguage = languageCode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', languageCode);
    notifyListeners();
  }

  String translate(String key) {
    // Import your translations
    final Map<String, Map<String, String>> translations = {
      'en': require('../l10n/app_en.dart').en,
      'hi': require('../l10n/app_hi.dart').hi,
      'mr': require('../l10n/app_mr.dart').mr,
    };
    
    return translations[_currentLanguage]?[key] ?? key;
  }
}
