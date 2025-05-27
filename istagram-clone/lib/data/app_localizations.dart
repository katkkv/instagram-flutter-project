// localization_service.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class LocalizationService {
  final String baseUrl;
  final String defaultLanguage;
  Map<String, dynamic> _translations = {};
  Locale? _currentLocale;

  LocalizationService({
    required this.baseUrl,
    this.defaultLanguage = 'en',
  });

  static LocalizationService? _instance;
  static LocalizationService get instance => _instance!;
  static Future<void> initialize({
    required String baseUrl,
    String defaultLanguage = 'en',
  }) async {
    _instance = LocalizationService(
      baseUrl: baseUrl,
      defaultLanguage: defaultLanguage,
    );
    await _instance!._loadSavedLanguage();
  }

  Future<void> _loadSavedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final languageCode = prefs.getString('app_language') ?? defaultLanguage;
    _currentLocale = Locale(languageCode);
    await loadTranslations(languageCode);
  }

  Future<bool> loadTranslations(String languageCode) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/translations/$languageCode'),
      );

      if (response.statusCode == 200) {
        _translations = json.decode(response.body);
        _currentLocale = Locale(languageCode);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('app_language', languageCode);

        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // Update the translate method in LocalizationService
  String translate(String key, {List<dynamic>? args}) {
    final keys = key.split('.');
    dynamic result = _translations;

    for (final k in keys) {
      if (result is Map<String, dynamic>) {
        result = result[k];
      } else {
        break;
      }
    }

    String translation = result?.toString() ?? key;

    if (args != null) {
      for (int i = 0; i < args.length; i++) {
        translation = translation.replaceAll('{$i}', args[i].toString());
      }
    }

    return translation;
  }



  Locale? get currentLocale => _currentLocale;
  List<Locale> get supportedLocales => const [
    Locale('en'),
    Locale('ru'),
    Locale('es'),
    Locale('fr'),
    Locale('de'),
    Locale('zh'),
    Locale('ja'),
    Locale('ar'),
    Locale('pt'),
    Locale('hi'),
  ];
}

// Update the extension
extension LocalizationExtension on BuildContext {
  String tr(String key, {List<dynamic>? args}) =>
      LocalizationService.instance.translate(key, args: args);
}