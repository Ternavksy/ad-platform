import 'dart:async';

import 'package:ad_platform_mobile/src/core/api_client.dart';
import 'package:ad_platform_mobile/src/core/api_config.dart';
import 'package:ad_platform_mobile/src/domain/models.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class MfaRequiredException implements Exception {
  const MfaRequiredException(this.challenge);

  final MfaChallenge challenge;
}

class AdPlatformRepository {
  AdPlatformRepository({
    ApiTransport? auth,
    ApiTransport? ads,
    ApiTransport? analytics,
    FlutterSecureStorage? storage,
  }) : _auth = auth ?? ApiClient(ApiConfig.authBaseUrl),
       _ads = ads ?? ApiClient(ApiConfig.adsBaseUrl),
       _analytics = analytics ?? ApiClient(ApiConfig.analyticsBaseUrl),
       _storage = storage ?? const FlutterSecureStorage() {
    for (final transport in [_auth, _ads, _analytics]) {
      if (transport is ApiClient) {
        transport.setUnauthorizedHandler(_refreshAfterUnauthorized);
      }
    }
  }

  static const _tokenKey = 'ad_platform_access_token';
  static const _refreshTokenKey = 'ad_platform_refresh_token';
  final ApiTransport _auth;
  final ApiTransport _ads;
  final ApiTransport _analytics;
  final FlutterSecureStorage _storage;
  final _sessionInvalidated = StreamController<void>.broadcast();
  Future<bool>? _refreshingSession;

  Stream<void> get sessionInvalidated => _sessionInvalidated.stream;

  Future<bool> _refreshAfterUnauthorized() async {
    final existing = _refreshingSession;
    if (existing != null) return existing;
    final future = _performUnauthorizedRefresh();
    _refreshingSession = future;
    try {
      return await future;
    } finally {
      _refreshingSession = null;
    }
  }

  Future<bool> _performUnauthorizedRefresh() async {
    try {
      await refreshSession();
      return true;
    } catch (_) {
      await _clearSession();
      _sessionInvalidated.add(null);
      return false;
    }
  }

  void dispose() => _sessionInvalidated.close();

  void _setToken(String? value) {
    _auth.setToken(value);
    _ads.setToken(value);
    _analytics.setToken(value);
  }

  Future<AppUser?> restoreSession() async {
    final saved = await _storage.read(key: _tokenKey);
    if (saved == null) return null;
    _setToken(saved);
    try {
      return await currentUser();
    } catch (_) {
      try {
        await refreshSession();
        return await currentUser();
      } catch (_) {
        await _clearSession();
        return null;
      }
    }
  }

  Future<AppUser> login(String email, String password) async {
    final json =
        await _auth.post(
              '/auth/login',
              data: {'email': email.trim(), 'password': password},
            )
            as Map<String, dynamic>;
    if (json['mfa_required'] == true || json['mfa_setup_required'] == true) {
      throw MfaRequiredException(
        MfaChallenge(
          token: json['mfa_challenge'] as String,
          setupRequired: json['mfa_setup_required'] as bool? ?? false,
          secret: json['mfa_secret'] as String?,
          otpauthUri: json['otpauth_uri'] as String?,
        ),
      );
    }
    await _saveTokens(json);
    return currentUser();
  }

  Future<({AppUser user, List<String> recoveryCodes})> confirmMfa(
    MfaChallenge challenge,
    String code,
  ) async {
    final json =
        await _auth.post(
              '/auth/mfa/confirm',
              data: {'challenge_token': challenge.token, 'code': code.trim()},
            )
            as Map<String, dynamic>;
    await _saveTokens(json);
    return (
      user: await currentUser(),
      recoveryCodes:
          (json['recovery_codes'] as List? ?? const [])
              .map((item) => item.toString())
              .toList(),
    );
  }

  Future<void> _saveTokens(Map<String, dynamic> json) async {
    final access = json['access_token'] as String;
    final refresh = json['refresh_token'] as String;
    _setToken(access);
    await Future.wait([
      _storage.write(key: _tokenKey, value: access),
      _storage.write(key: _refreshTokenKey, value: refresh),
    ]);
  }

  Future<void> refreshSession() async {
    final refresh = await _storage.read(key: _refreshTokenKey);
    if (refresh == null) throw const ApiException('Сессия истекла');
    final json =
        await _auth.post('/auth/refresh', data: {'refresh_token': refresh})
            as Map<String, dynamic>;
    await _saveTokens(json);
  }

  Future<AppUser> register(String email, String password) async {
    await _auth.post(
      '/auth/register',
      data: {'email': email.trim(), 'password': password},
    );
    return login(email, password);
  }

  Future<AppUser> currentUser() async {
    final json = await _auth.get('/auth/me') as Map<String, dynamic>;
    return AppUser.fromJson(json);
  }

  Future<void> logout() async {
    final refresh = await _storage.read(key: _refreshTokenKey);
    if (refresh != null) {
      try {
        await _auth.post('/auth/logout', data: {'refresh_token': refresh});
      } catch (_) {
        // Local logout must still complete when the session already expired.
      }
    }
    await _clearSession();
  }

  Future<void> logoutAll() async {
    try {
      await _auth.post('/auth/logout-all');
    } finally {
      await _clearSession();
    }
  }

  Future<void> _clearSession() async {
    _setToken(null);
    await Future.wait([
      _storage.delete(key: _tokenKey),
      _storage.delete(key: _refreshTokenKey),
    ]);
  }

  Future<AdminDashboard> getAdminDashboard() async {
    final json = await _auth.get('/admin/dashboard') as Map<String, dynamic>;
    return AdminDashboard.fromJson(json);
  }

  Future<({List<AdminUser> items, int? nextCursor})> getAdminUsers({
    String? query,
    String? status,
    String? role,
    int? cursor,
  }) async {
    final json =
        await _auth.get(
              '/admin/users',
              query: {
                if (query?.trim().isNotEmpty == true) 'query': query!.trim(),
                if (status?.isNotEmpty == true) 'status': status,
                if (role?.isNotEmpty == true) 'role': role,
                if (cursor != null) 'cursor': cursor,
              },
            )
            as Map<String, dynamic>;
    return (
      items:
          (json['items'] as List)
              .cast<Map<String, dynamic>>()
              .map(AdminUser.fromJson)
              .toList(),
      nextCursor: (json['next_cursor'] as num?)?.toInt(),
    );
  }

  Future<AdminUser> getAdminUser(int userId) async {
    final json =
        await _auth.get('/admin/users/$userId') as Map<String, dynamic>;
    return AdminUser.fromJson(json);
  }

  Future<List<AdminAuditEvent>> getAdminAudit({int? userId}) async {
    final data =
        userId == null
            ? await _auth.get('/admin/audit')
            : await _auth.get('/admin/users/$userId/audit');
    final items =
        data is Map<String, dynamic> ? data['items'] as List : data as List;
    return items
        .cast<Map<String, dynamic>>()
        .map(AdminAuditEvent.fromJson)
        .toList();
  }

  Future<AdminUser> setAdminUserStatus(
    AdminUser user,
    String action, {
    required String reason,
    required String mfaCode,
    DateTime? suspendedUntil,
  }) async {
    final json =
        await _auth.post(
              '/admin/users/${user.id}/$action',
              data: {
                'reason': reason.trim(),
                'row_version': user.rowVersion,
                'mfa_code': mfaCode.trim(),
                if (suspendedUntil != null)
                  'suspended_until': suspendedUntil.toUtc().toIso8601String(),
              },
            )
            as Map<String, dynamic>;
    return AdminUser.fromJson(json);
  }

  Future<AdminUser> updateAdminUserRoles(
    AdminUser user,
    List<String> roles, {
    required String reason,
    required String mfaCode,
  }) async {
    final json =
        await _auth.put(
              '/admin/users/${user.id}/roles',
              data: {
                'roles': roles,
                'reason': reason.trim(),
                'row_version': user.rowVersion,
                'mfa_code': mfaCode.trim(),
              },
            )
            as Map<String, dynamic>;
    return AdminUser.fromJson(json);
  }

  Future<AdminUser> revokeAdminUserSessions(
    AdminUser user, {
    required String reason,
    required String mfaCode,
  }) async {
    final json =
        await _auth.post(
              '/admin/users/${user.id}/revoke-sessions',
              data: {
                'reason': reason.trim(),
                'row_version': user.rowVersion,
                'mfa_code': mfaCode.trim(),
              },
            )
            as Map<String, dynamic>;
    return AdminUser.fromJson(json['user'] as Map<String, dynamic>);
  }

  Future<AdminUser> requestAdminPasswordReset(
    AdminUser user, {
    required String reason,
    required String mfaCode,
  }) async {
    final json =
        await _auth.post(
              '/admin/users/${user.id}/password-reset',
              data: {
                'reason': reason.trim(),
                'row_version': user.rowVersion,
                'mfa_code': mfaCode.trim(),
              },
            )
            as Map<String, dynamic>;
    return AdminUser.fromJson(json['user'] as Map<String, dynamic>);
  }

  Future<double> getBalance(int userId) async {
    final json =
        await _auth.get('/billing/balance/$userId') as Map<String, dynamic>;
    return (json['balance'] as num).toDouble();
  }

  Future<List<BillingTransaction>> getTransactions(int userId) async {
    final json = await _auth.get('/billing/transactions/$userId') as List;
    return json
        .cast<Map<String, dynamic>>()
        .map(BillingTransaction.fromJson)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> deposit(int userId, double amount, String? description) async {
    await _auth.post(
      '/billing/deposit',
      data: {
        'user_id': userId,
        'amount': amount,
        'description': description?.trim().isEmpty == true ? null : description,
      },
    );
  }

  Future<void> withdraw(int userId, double amount, String? description) async {
    await _auth.post(
      '/billing/withdraw',
      data: {
        'user_id': userId,
        'amount': amount,
        'description': description?.trim().isEmpty == true ? null : description,
      },
    );
  }

  Future<List<Campaign>> getCampaigns(int userId) async {
    final json =
        await _ads.get('/campaigns', query: {'user_id': userId}) as List;
    return json.cast<Map<String, dynamic>>().map(Campaign.fromJson).toList();
  }

  Future<Campaign> createCampaign(
    int userId,
    String name,
    String status,
    CampaignBudget budget,
    CampaignSchedule schedule,
  ) async {
    final json =
        await _ads.post(
              '/campaigns',
              data: {
                'user_id': userId,
                'name': name.trim(),
                'status': status,
                'budget': budget.toJson(),
                'schedule': schedule.toJson(),
              },
            )
            as Map<String, dynamic>;
    return Campaign.fromJson(json);
  }

  Future<void> updateCampaign(
    Campaign item,
    String name,
    String status,
    CampaignBudget budget,
    CampaignSchedule schedule,
  ) async {
    await _ads.put(
      '/campaigns/${item.id}',
      data: {
        'user_id': item.userId,
        'name': name.trim(),
        'status': status,
        'budget': budget.toJson(),
        'schedule': schedule.toJson(),
      },
    );
  }

  Future<void> deleteCampaign(int id) => _ads.delete('/campaigns/$id');

  Future<List<AdItem>> getAds(int campaignId) async {
    final json =
        await _ads.get('/ads', query: {'campaign_id': campaignId}) as List;
    return json.cast<Map<String, dynamic>>().map(AdItem.fromJson).toList();
  }

  Future<AdItem> createAd(
    int campaignId,
    String title,
    String status,
    String placement,
    String destinationUrl,
    int weight,
    double bidCpm,
    int? placementId,
    AdTargeting targeting,
  ) async {
    final json =
        await _ads.post(
              '/ads',
              data: {
                'campaign_id': campaignId,
                'title': title.trim(),
                'status': status,
                'placement': placement,
                'destination_url': destinationUrl.trim(),
                'weight': weight,
                'bid_cpm': bidCpm,
                'placement_id': placementId,
                'targeting': targeting.toJson(),
              },
            )
            as Map<String, dynamic>;
    return AdItem.fromJson(json);
  }

  Future<void> updateAd(
    AdItem item,
    String title,
    String status,
    String placement,
    String destinationUrl,
    int weight,
    double bidCpm,
    int? placementId,
    AdTargeting targeting,
  ) async {
    await _ads.put(
      '/ads/${item.id}',
      data: {
        'campaign_id': item.campaignId,
        'title': title.trim(),
        'status': status,
        'placement': placement,
        'destination_url': destinationUrl.trim(),
        'weight': weight,
        'bid_cpm': bidCpm,
        'placement_id': placementId,
        'targeting': targeting.toJson(),
      },
    );
  }

  Future<void> deleteAd(int id) => _ads.delete('/ads/$id');

  Future<List<Site>> getSites(int userId) async {
    final json = await _ads.get('/sites', query: {'user_id': userId}) as List;
    return json.cast<Map<String, dynamic>>().map(Site.fromJson).toList();
  }

  Future<Site> createSite(
    int userId,
    String name,
    String domain,
    String status,
  ) async {
    final json =
        await _ads.post(
              '/sites',
              data: {
                'user_id': userId,
                'name': name.trim(),
                'domain': domain.trim(),
                'status': status,
              },
            )
            as Map<String, dynamic>;
    return Site.fromJson(json);
  }

  Future<void> updateSite(
    Site item,
    String name,
    String domain,
    String status,
  ) => _ads.put(
    '/sites/${item.id}',
    data: {'name': name.trim(), 'domain': domain.trim(), 'status': status},
  );

  Future<void> deleteSite(int id) => _ads.delete('/sites/$id');

  Future<List<AdFormat>> getFormats() async {
    final json = await _ads.get('/formats') as List;
    return json.cast<Map<String, dynamic>>().map(AdFormat.fromJson).toList();
  }

  Future<List<Placement>> getPlacements(int siteId) async {
    final json =
        await _ads.get('/placements', query: {'site_id': siteId}) as List;
    return json.cast<Map<String, dynamic>>().map(Placement.fromJson).toList();
  }

  Future<Placement> createPlacement(
    int siteId,
    int formatId,
    String name,
    String status,
  ) async {
    final json =
        await _ads.post(
              '/placements',
              data: {
                'site_id': siteId,
                'format_id': formatId,
                'name': name.trim(),
                'status': status,
              },
            )
            as Map<String, dynamic>;
    return Placement.fromJson(json);
  }

  Future<void> updatePlacement(
    Placement item,
    int formatId,
    String name,
    String status,
  ) => _ads.put(
    '/placements/${item.id}',
    data: {
      'site_id': item.siteId,
      'format_id': formatId,
      'name': name.trim(),
      'status': status,
    },
  );

  Future<void> deletePlacement(int id) => _ads.delete('/placements/$id');

  Future<List<Creative>> getCreatives(int adId) async {
    final json = await _ads.get('/creatives', query: {'ad_id': adId}) as List;
    return json.cast<Map<String, dynamic>>().map(Creative.fromJson).toList();
  }

  Future<Creative> createCreative(int adId, String content) async {
    final json =
        await _ads.post(
              '/creatives',
              data: {'ad_id': adId, 'content': content.trim()},
            )
            as Map<String, dynamic>;
    return Creative.fromJson(json);
  }

  Future<Creative> createCreativeWithMedia(
    int adId,
    String content,
    String filePath,
    String fileName,
  ) async {
    final json =
        await _ads.upload(
              '/creatives/upload',
              method: 'POST',
              fields: {'ad_id': '$adId', 'content': content.trim()},
              filePath: filePath,
              fileName: fileName,
            )
            as Map<String, dynamic>;
    return Creative.fromJson(json);
  }

  Future<void> updateCreative(Creative item, String content) async {
    await _ads.put(
      '/creatives/${item.id}',
      data: {'ad_id': item.adId, 'content': content.trim()},
    );
  }

  Future<void> updateCreativeWithMedia(
    Creative item,
    String content,
    String filePath,
    String fileName,
  ) async {
    await _ads.upload(
      '/creatives/${item.id}/upload',
      method: 'PUT',
      fields: {'content': content.trim()},
      filePath: filePath,
      fileName: fileName,
    );
  }

  Future<void> deleteCreative(int id) => _ads.delete('/creatives/$id');

  Future<Creative> submitCreativeForModeration(int id) async {
    final json =
        await _ads.post('/creatives/$id/submit') as Map<String, dynamic>;
    return Creative.fromJson(json);
  }

  Future<List<Creative>> getModerationCreatives(String status) async {
    final json =
        await _ads.get('/moderation/creatives', query: {'status': status})
            as List;
    return json.cast<Map<String, dynamic>>().map(Creative.fromJson).toList();
  }

  Future<Creative> reviewCreative(
    int id,
    String decision, {
    String reason = '',
  }) async {
    final json =
        await _ads.post(
              '/moderation/creatives/$id/review',
              data: {'decision': decision, 'reason': reason.trim()},
            )
            as Map<String, dynamic>;
    return Creative.fromJson(json);
  }

  Future<AdDelivery?> selectAd({
    String? requestId,
    String placement = 'feed',
    String placementCode = '',
    String visitorId = '',
    int age = 0,
    String gender = '',
    List<String> interests = const [],
    String country = '',
    String region = '',
    String city = '',
    String deviceType = '',
    String operatingSystem = '',
  }) async {
    final json = await _ads.post(
      '/delivery/select',
      data: {
        if (requestId != null) 'request_id': requestId,
        'placement': placement,
        'placement_code': placementCode,
        'visitor_id': visitorId,
        'audience': {'age': age, 'gender': gender, 'interests': interests},
        'geography': {'country': country, 'region': region, 'city': city},
        'device': {'type': deviceType, 'operating_system': operatingSystem},
      },
    );
    if (json == null) return null;
    return AdDelivery.fromJson(json as Map<String, dynamic>);
  }

  Future<TrackingReceipt> trackImpression(String deliveryId) async {
    final json =
        await _ads.post('/delivery/$deliveryId/impression')
            as Map<String, dynamic>;
    return TrackingReceipt.fromJson(json);
  }

  Future<TrackingReceipt> trackClick(String deliveryId) async {
    final json =
        await _ads.post('/delivery/$deliveryId/click') as Map<String, dynamic>;
    return TrackingReceipt.fromJson(json);
  }

  Future<TrackingReceipt> trackConversion(
    String deliveryId, {
    String? eventId,
    String conversionType = 'purchase',
    double value = 0,
    String currency = '',
  }) async {
    final deliveryPrefix =
        deliveryId.length <= 8 ? deliveryId : deliveryId.substring(0, 8);
    final stableEventId =
        eventId ??
        'mobile-${DateTime.now().microsecondsSinceEpoch}-$deliveryPrefix';
    final json =
        await _ads.post(
              '/delivery/$deliveryId/conversion',
              data: {
                'event_id': stableEventId,
                'conversion_type': conversionType,
                'value': value,
                'currency': currency,
              },
            )
            as Map<String, dynamic>;
    return TrackingReceipt.fromJson(json);
  }

  Future<TrackingReceipt> trackAttributedConversion(
    String visitorId, {
    required String eventId,
    String conversionType = 'purchase',
    double value = 0,
    String currency = '',
  }) async {
    final json =
        await _ads.post(
              '/attribution/conversion',
              data: {
                'visitor_id': visitorId,
                'event_id': eventId,
                'conversion_type': conversionType,
                'value': value,
                'currency': currency,
              },
            )
            as Map<String, dynamic>;
    return TrackingReceipt.fromJson(json);
  }

  Future<List<AnalyticsPoint>> getCampaignAnalytics({int? campaignId}) async {
    final json =
        await _analytics.get(
              '/campaigns',
              query: campaignId == null ? null : {'campaign_id': campaignId},
            )
            as List;
    return json
        .cast<Map<String, dynamic>>()
        .map(AnalyticsPoint.fromJson)
        .toList();
  }

  Future<List<AnalyticsPoint>> getAdAnalytics(int adId) async {
    final json = await _analytics.get('/ads', query: {'ad_id': adId}) as List;
    return json
        .cast<Map<String, dynamic>>()
        .map(AnalyticsPoint.fromJson)
        .toList();
  }
}
