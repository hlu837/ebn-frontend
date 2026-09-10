import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onsite_demo/l10n/app_localizations.dart';

void main() {
  test('supported locales include the required languages', () {
    expect(
      AppLocalizations.supportedLocales.map((locale) => locale.languageCode),
      containsAll(['en', 'am', 'ti', 'om']),
    );
    expect(AppLocalizations.fallbackLocale.languageCode, 'en');
  });

  test('missing locale values fall back to English', () async {
    final localizations = await AppLocalizations.load(const Locale('am'));
    expect(localizations.text('appTitle'), 'EBN — Verify Any Asset');
  });
}
