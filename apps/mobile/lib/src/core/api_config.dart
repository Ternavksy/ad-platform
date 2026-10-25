import 'dart:io';

abstract final class ApiConfig {
  static const _authOverride = String.fromEnvironment('AUTH_API_URL');
  static const _adsOverride = String.fromEnvironment('ADS_API_URL');
  static const _analyticsOverride = String.fromEnvironment('ANALYTICS_API_URL');

  static String get _localHost => Platform.isAndroid ? '10.0.2.2' : '127.0.0.1';

  static String get authBaseUrl =>
      _authOverride.isNotEmpty ? _authOverride : 'http://$_localHost:8000';
  static String get adsBaseUrl =>
      _adsOverride.isNotEmpty ? _adsOverride : 'http://$_localHost:8080';
  static String get analyticsBaseUrl =>
      _analyticsOverride.isNotEmpty
          ? _analyticsOverride
          : 'http://$_localHost:8100';

  static String resolveAdsUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme) return value;
    final base = adsBaseUrl.endsWith('/') ? adsBaseUrl : '$adsBaseUrl/';
    return Uri.parse(
      base,
    ).resolve(value.replaceFirst(RegExp(r'^/'), '')).toString();
  }
}
