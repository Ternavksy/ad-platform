import 'package:ad_platform_mobile/src/core/api_client.dart';
import 'package:ad_platform_mobile/src/data/ad_platform_repository.dart';
import 'package:ad_platform_mobile/src/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeApiTransport implements ApiTransport {
  String? token;
  String? method;
  String? path;
  Object? data;
  Map<String, dynamic>? query;
  Map<String, String>? fields;
  String? filePath;
  String? fileName;

  @override
  void setToken(String? value) => token = value;

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    method = 'GET';
    this.path = path;
    this.query = query;
    if (path == '/admin/dashboard') {
      return {
        'total_users': 2,
        'active_users': 1,
        'blocked_users': 1,
        'new_users': 1,
        'recent_audit': <dynamic>[],
      };
    }
    if (path == '/admin/users') {
      return {
        'items': [_adminUserJson()],
        'next_cursor': null,
      };
    }
    if (path == '/admin/audit') return {'items': <dynamic>[]};
    if (path.startsWith('/admin/users/')) return _adminUserJson();
    return <dynamic>[];
  }

  @override
  Future<dynamic> post(
    String path, {
    Object? data,
    Map<String, dynamic>? query,
  }) async {
    method = 'POST';
    this.path = path;
    this.data = data;
    this.query = query;
    if (path == '/delivery/select') {
      return {
        'delivery_id': 'delivery-1',
        'campaign_id': 7,
        'ad_id': 11,
        'creative_id': 13,
        'title': 'Offer',
        'content': 'Buy now',
        'destination_url': 'https://example.com/offer',
        'impression_url': 'http://localhost/delivery/delivery-1/impression',
        'click_url': 'http://localhost/delivery/delivery-1/click',
        'conversion_url': 'http://localhost/delivery/delivery-1/conversion',
        'media': {'type': 'image', 'url': '/media/banner.png'},
      };
    }
    if (path.endsWith('/impression')) {
      return {
        'delivery_id': 'delivery-1',
        'event_id': 'impression-1',
        'event_type': 'ad_impression',
        'recorded': true,
        'occurred_at': '2026-10-25T10:00:00Z',
      };
    }
    if (path.endsWith('/click')) {
      return {
        'delivery_id': 'delivery-1',
        'event_id': 'click-1',
        'event_type': 'ad_click',
        'recorded': true,
        'occurred_at': '2026-10-25T10:01:00Z',
      };
    }
    if (path.endsWith('/conversion')) {
      final conversion = data! as Map<String, dynamic>;
      return {
        'delivery_id': 'delivery-1',
        'event_id': conversion['event_id'],
        'event_type': 'ad_conversion',
        'recorded': true,
        'occurred_at': '2026-10-25T10:02:00Z',
        'conversion_type': conversion['conversion_type'],
        'conversion_value': conversion['value'],
        'conversion_currency': conversion['currency'],
        'attribution_model': 'last_click',
        'attribution_window_hours': 168,
        'is_fraud': false,
      };
    }
    if (path.endsWith('/submit')) {
      return {
        'id': 9,
        'ad_id': 3,
        'content': 'Creative',
        'media': {'type': 'text'},
        'moderation_status': 'pending',
      };
    }
    if (path.contains('/moderation/creatives/') && path.endsWith('/review')) {
      final review = data! as Map<String, dynamic>;
      return {
        'id': 9,
        'ad_id': 3,
        'content': 'Creative',
        'media': {'type': 'text'},
        'moderation_status': review['decision'],
        'moderation_reason': review['reason'],
      };
    }
    if (path.startsWith('/admin/users/')) {
      return _adminUserJson(
        status: path.endsWith('/block') ? 'blocked' : 'active',
      );
    }
    final payload = data! as Map<String, dynamic>;
    return {
      'id': 42,
      'user_id': payload['user_id'],
      'name': payload['name'],
      'status': payload['status'],
    };
  }

  @override
  Future<dynamic> put(String path, {Object? data}) async {
    method = 'PUT';
    this.path = path;
    this.data = data;
    if (path.startsWith('/admin/users/')) return _adminUserJson();
    return <String, dynamic>{};
  }

  Map<String, dynamic> _adminUserJson({String status = 'active'}) => {
    'id': 42,
    'email': 'managed@example.com',
    'role': 'user',
    'roles': ['user'],
    'permissions': <String>[],
    'status': status,
    'mfa_enabled': false,
    'password_reset_required': false,
    'workspaces': ['advertiser'],
    'row_version': 2,
    'created_at': '2026-10-26T10:00:00Z',
    'balance': 0,
    'active_sessions': 1,
    'campaigns': 0,
    'transactions': 0,
  };

  @override
  Future<void> delete(String path) async {
    method = 'DELETE';
    this.path = path;
  }

  @override
  Future<dynamic> upload(
    String path, {
    required String method,
    required Map<String, String> fields,
    required String filePath,
    required String fileName,
  }) async {
    this.method = method;
    this.path = path;
    this.fields = fields;
    this.filePath = filePath;
    this.fileName = fileName;
    return {
      'id': 77,
      'ad_id': int.parse(fields['ad_id'] ?? '9'),
      'content': fields['content'] ?? '',
      'media': {
        'type': 'image',
        'url': '/media/file.png',
        'mime_type': 'image/png',
        'file_name': fileName,
        'file_size': 128,
      },
    };
  }
}

void main() {
  test('createCampaign uses the campaigns API contract', () async {
    final ads = _FakeApiTransport();
    final repository = AdPlatformRepository(
      auth: _FakeApiTransport(),
      ads: ads,
      analytics: _FakeApiTransport(),
    );

    final campaign = await repository.createCampaign(
      7,
      'Autumn launch',
      'active',
      const CampaignBudget(total: 1000, dailyLimit: 100),
      const CampaignSchedule(
        daysOfWeek: [1, 2, 3, 4, 5],
        startHour: 8,
        endHour: 20,
      ),
    );

    expect(ads.method, 'POST');
    expect(ads.path, '/campaigns');
    expect(ads.data, {
      'user_id': 7,
      'name': 'Autumn launch',
      'status': 'active',
      'budget': {'total': 1000.0, 'daily_limit': 100.0},
      'schedule': {
        'starts_at': null,
        'ends_at': null,
        'days_of_week': [1, 2, 3, 4, 5],
        'start_hour': 8,
        'end_hour': 20,
        'timezone': 'UTC',
      },
    });
    expect(campaign.id, 42);
    expect(campaign.userId, 7);
    expect(campaign.name, 'Autumn launch');
    expect(campaign.isActive, isTrue);
  });

  test('updateAd sends delivery configuration', () async {
    final ads = _FakeApiTransport();
    final repository = AdPlatformRepository(
      auth: _FakeApiTransport(),
      ads: ads,
      analytics: _FakeApiTransport(),
    );
    const item = AdItem(
      id: 9,
      campaignId: 7,
      title: 'Old title',
      status: 'draft',
      placement: 'feed',
      destinationUrl: 'https://old.example',
      weight: 1,
    );

    await repository.updateAd(
      item,
      'Offer',
      'active',
      'banner',
      'https://example.com/offer',
      20,
      12.5,
      51,
      const AdTargeting(
        minAge: 18,
        maxAge: 35,
        genders: ['female'],
        interests: ['travel'],
        countries: ['RU'],
        deviceTypes: ['mobile'],
        operatingSystems: ['android'],
      ),
    );

    expect(ads.method, 'PUT');
    expect(ads.path, '/ads/9');
    expect(ads.data, {
      'campaign_id': 7,
      'title': 'Offer',
      'status': 'active',
      'placement': 'banner',
      'destination_url': 'https://example.com/offer',
      'weight': 20,
      'bid_cpm': 12.5,
      'placement_id': 51,
      'targeting': {
        'audience': {
          'min_age': 18,
          'max_age': 35,
          'genders': ['female'],
          'interests': ['travel'],
        },
        'geography': {
          'countries': ['RU'],
          'regions': <String>[],
          'cities': <String>[],
        },
        'device': {
          'types': ['mobile'],
          'operating_systems': ['android'],
        },
      },
    });
  });

  test('createCreativeWithMedia uses multipart upload contract', () async {
    final ads = _FakeApiTransport();
    final repository = AdPlatformRepository(
      auth: _FakeApiTransport(),
      ads: ads,
      analytics: _FakeApiTransport(),
    );

    final creative = await repository.createCreativeWithMedia(
      9,
      'Banner',
      '/tmp/banner.png',
      'banner.png',
    );

    expect(ads.method, 'POST');
    expect(ads.path, '/creatives/upload');
    expect(ads.fields, {'ad_id': '9', 'content': 'Banner'});
    expect(ads.filePath, '/tmp/banner.png');
    expect(creative.media.isImage, isTrue);
    expect(creative.media.url, '/media/file.png');
  });

  test('creative moderation uses submit and admin review contracts', () async {
    final ads = _FakeApiTransport();
    final repository = AdPlatformRepository(
      auth: _FakeApiTransport(),
      ads: ads,
      analytics: _FakeApiTransport(),
    );

    final pending = await repository.submitCreativeForModeration(9);
    expect(ads.method, 'POST');
    expect(ads.path, '/creatives/9/submit');
    expect(pending.moderationStatus, 'pending');

    final rejected = await repository.reviewCreative(
      9,
      'rejected',
      reason: 'Missing disclaimer',
    );
    expect(ads.path, '/moderation/creatives/9/review');
    expect(ads.data, {'decision': 'rejected', 'reason': 'Missing disclaimer'});
    expect(rejected.isRejected, isTrue);
  });

  test(
    'delivery tracking sends impression, click and conversion events',
    () async {
      final ads = _FakeApiTransport();
      final repository = AdPlatformRepository(
        auth: _FakeApiTransport(),
        ads: ads,
        analytics: _FakeApiTransport(),
      );

      final delivery = await repository.selectAd(
        requestId: 'request-1',
        placementCode: 'placement-1',
        visitorId: 'visitor-1',
        age: 27,
        country: 'RU',
        deviceType: 'mobile',
        operatingSystem: 'android',
      );
      expect(delivery?.impressionUrl, contains('/impression'));
      expect((ads.data! as Map<String, dynamic>)['audience'], {
        'age': 27,
        'gender': '',
        'interests': <String>[],
      });

      final impression = await repository.trackImpression('delivery-1');
      expect(ads.path, '/delivery/delivery-1/impression');
      expect(impression.eventType, 'ad_impression');

      final click = await repository.trackClick('delivery-1');
      expect(ads.path, '/delivery/delivery-1/click');
      expect(click.eventType, 'ad_click');

      final conversion = await repository.trackConversion(
        'delivery-1',
        eventId: 'order-42',
        value: 1499.9,
        currency: 'RUB',
      );
      expect(ads.path, '/delivery/delivery-1/conversion');
      expect(ads.data, {
        'event_id': 'order-42',
        'conversion_type': 'purchase',
        'value': 1499.9,
        'currency': 'RUB',
      });
      expect(conversion.conversionValue, 1499.9);

      final attributed = await repository.trackAttributedConversion(
        'visitor-1',
        eventId: 'order-43',
        conversionType: 'signup',
      );
      expect(ads.path, '/attribution/conversion');
      expect(ads.data, {
        'visitor_id': 'visitor-1',
        'event_id': 'order-43',
        'conversion_type': 'signup',
        'value': 0.0,
        'currency': '',
      });
      expect(attributed.attributionModel, 'last_click');
      expect(attributed.isFraud, isFalse);
    },
  );

  test('admin user management uses protected admin contracts', () async {
    final auth = _FakeApiTransport();
    final repository = AdPlatformRepository(
      auth: auth,
      ads: _FakeApiTransport(),
      analytics: _FakeApiTransport(),
    );

    final page = await repository.getAdminUsers(query: 'managed');
    expect(auth.method, 'GET');
    expect(auth.path, '/admin/users');
    expect(auth.query?['query'], 'managed');
    expect(page.items.single.email, 'managed@example.com');

    final blocked = await repository.setAdminUserStatus(
      page.items.single,
      'block',
      reason: 'confirmed abuse',
      mfaCode: '123456',
    );
    expect(auth.path, '/admin/users/42/block');
    expect(auth.data, {
      'reason': 'confirmed abuse',
      'row_version': 2,
      'mfa_code': '123456',
    });
    expect(blocked.isBlocked, isTrue);

    await repository.updateAdminUserRoles(
      page.items.single,
      ['user', 'support'],
      reason: 'support duties',
      mfaCode: '654321',
    );
    expect(auth.method, 'PUT');
    expect(auth.path, '/admin/users/42/roles');
  });
}
