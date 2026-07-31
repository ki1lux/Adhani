/// Values that describe the published app rather than its behaviour.
///
/// Kept in one place because three of them (the Play id, the privacy policy
/// URL, the support address) also have to appear verbatim in the Play Console
/// listing — having them scattered across screens is how they drift apart from
/// what was submitted.
abstract final class AppConfig {
  /// Must match `applicationId` in android/app/build.gradle.kts.
  static const packageName = 'com.ki1lux.adhani';

  /// The display name used in share text and the about section.
  static const appName = 'أذاني';

  /// Shown in Settings. Keep in step with pubspec.yaml's `version:`.
  static const version = '1.0.0';

  /// Play listing. Valid the moment the app is published; before that it
  /// resolves to a "not found" page, which is why the share sheet leads with
  /// the app's name rather than a bare link.
  static const playStoreUrl =
      'https://play.google.com/store/apps/details?id=$packageName';

  /// Deep link that opens the Play app directly when it's installed.
  static const playStoreMarketUri = 'market://details?id=$packageName';

  /// The privacy policy Play requires a link to, both in the listing and
  /// (for apps that request location) inside the app.
  ///
  /// Points at PRIVACY_POLICY.md in the project repository so the link is live
  /// as soon as the repo is public — no hosting to set up. Replace it if the
  /// policy moves to a custom domain.
  static const privacyPolicyUrl =
      'https://github.com/ki1lux/Adhanuk/blob/main/PRIVACY_POLICY.md';

  static const supportEmail = 'khalilbenfiala001@gmail.com';
  static const developerUrl = 'https://github.com/ki1lux';

  /// Attribution required by the data sources' terms of use.
  static const dataAttribution = 'Aladhan API · OpenStreetMap Nominatim';
}
