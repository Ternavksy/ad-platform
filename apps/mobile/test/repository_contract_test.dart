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
    return <String, dynamic>{};
  }

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
}
