import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

class AppLocalizations {
  static const Locale fallbackLocale = Locale('en');

  static const Map<String, String> _englishStrings = {
    'appTitle': 'EBN — Verify Any Asset',
    'navMenu': 'Menu',
    'navBrowse': 'Browse',
    'navHowItWorks': 'How it works',
    'navMembership': 'Membership',
    'navPlatform': 'Platform',
    'navAboutUs': 'About Us',
    'navContactUs': 'Contact Us',
    'navFaq': 'FAQ',
    'navSearch': 'Search',
    'navLanguage': 'Language',
    'languageEnglish': 'English',
    'languageAmharic': 'Amharic',
    'languageAfanOromo': 'Afan Oromo',
    'languageTigrinya': 'Tigrinya',
    'languageSelected': '{language} selected. Full translation is coming soon.',
    'searchNoMatches': 'No matches found.',
    'searchFieldLabel': 'Search EBN…',
    'searchHeroTitle': 'What are you looking for?',
    'searchHeroSubtitle':
        'Order a verified inspection or get matched with an agent.',
    'heroOrderUs': 'Order Us',
    'heroGetAgent': 'Get your agent',
    'quickActionGetVerified': 'Get Verified',
    'quickActionGetVerifiedSubtitle': 'Request an on-site inspection',
    'quickActionSellWithUs': 'Sell With Us',
    'quickActionSellWithUsSubtitle': 'List an asset, meet a broker',
    'categoryLabel': 'Category',
    'postAd': 'Post ad',
    'trendingAds': 'Trending ads',
    'listingsAvailable': '{count} listing{plural} available',
    'noListingsMatchYourSearch': 'No listings match your search yet.',
    'getStartedToRequest': 'Get started to request',
    'browseCtaTitle': 'Ready to verify with confidence?',
    'browseCtaSubtitle':
        'Sign up to request an on-site inspection on any listing above.',
    'getStartedSignUp': 'Get Started / Sign Up',
    'footerTagline': 'Verify any asset. On-site. On demand.',
    'footerAdmin': 'Admin',
    'mobileHowItWorks': 'How it works',
    'mobileMembership': 'Membership',
    'mobilePlatform': 'Platform',
    'mobileAboutUs': 'About Us',
    'mobileContactUs': 'Contact Us',
    'mobileFaq': 'FAQ',
    'mobileLogIn': 'Log In',
    'mobileGetStarted': 'Get started',
    'allLabel': 'All',
    'serviceLabelAll': 'All',
    'title': 'EBN',
    'browse': 'Browse',
    'searchResultsCategory': 'Category',
    'searchResultsAction': 'Action',
    'searchResultsPage': 'Page',
  };

  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('am'),
    Locale('ti'),
    Locale('om'),
  ];

  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = [
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  static final Map<String, Map<String, String>> _cache = {};

  static LocaleResolutionCallback get localeResolutionCallback =>
      (locale, supported) {
        if (locale == null) return fallbackLocale;

        for (final supportedLocale in supported) {
          if (supportedLocale.languageCode == locale.languageCode) {
            return supportedLocale;
          }
        }

        return fallbackLocale;
      };

  final Locale locale;

  AppLocalizations(this.locale) {
    _strings = Map<String, String>.from(_englishStrings);
  }

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        AppLocalizations(fallbackLocale);
  }

  static bool isSupported(Locale locale) {
    return supportedLocales.any(
      (supportedLocale) => supportedLocale.languageCode == locale.languageCode,
    );
  }

  static Future<AppLocalizations> load(Locale locale) async {
    final loaded = AppLocalizations(locale);
    await loaded._load();
    return loaded;
  }

  Map<String, String> _strings = {};

  Future<void> _load() async {
    final languageCode = locale.languageCode;
    final fallbackStrings = Map<String, String>.from(_englishStrings);
    final targetStrings = await _readJson(languageCode);

    _strings = {
      ...fallbackStrings,
      ...targetStrings,
    };

    _strings = _strings.map((key, value) {
      return MapEntry(
          key, value.isEmpty ? (fallbackStrings[key] ?? value) : value);
    });

    _cache[languageCode] = _strings;
    _cache[fallbackLocale.languageCode] = fallbackStrings;
  }

  static Future<Map<String, String>> _readJson(String languageCode) async {
    try {
      final raw = await rootBundle.loadString('assets/i18n/$languageCode.json');
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((key, value) => MapEntry(key, value.toString()));
    } on FlutterError {
      return {};
    } on Exception {
      return {};
    }
  }

  String text(String key, [Map<String, String>? interpolations]) {
    final fallback = _cache[fallbackLocale.languageCode]?[key] ??
        _englishStrings[key] ??
        key;
    final value = _strings[key]?.isNotEmpty == true ? _strings[key]! : fallback;
    if (interpolations == null || interpolations.isEmpty) {
      return value;
    }

    var result = value;
    interpolations.forEach((placeholder, replacement) {
      result = result.replaceAll('{$placeholder}', replacement);
    });
    return result;
  }
}

class AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLocalizations.isSupported(locale);

  @override
  Future<AppLocalizations> load(Locale locale) => AppLocalizations.load(locale);

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) =>
      false;
}
