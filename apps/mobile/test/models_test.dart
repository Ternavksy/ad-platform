import 'package:ad_platform_mobile/src/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('domain models parse backend responses', () {
    final user = AppUser.fromJson({'id': 1, 'email': 'user@example.com'});
    final campaign = Campaign.fromJson({
      'id': 3,
      'user_id': 1,
      'name': 'Launch',
      'status': 'active',
      'budget': {
        'total': 1000,
        'daily_limit': 100,
        'spent_total': 25.5,
        'spent_today': 5.5,
      },
      'schedule': {
        'starts_at': '2026-10-24T00:00:00Z',
        'ends_at': '2026-11-24T23:59:59Z',
        'days_of_week': [1, 2, 3, 4, 5],
        'start_hour': 8,
        'end_hour': 20,
        'timezone': 'UTC',
      },
    });
    final ad = AdItem.fromJson({
      'id': 2,
      'campaign_id': 3,
      'title': 'Banner',
      'status': 'active',
      'placement': 'banner',
      'destination_url': 'https://example.com/offer',
      'weight': 25,
      'bid_cpm': 12.5,
      'targeting': {
        'audience': {
          'min_age': 18,
          'max_age': 35,
          'genders': ['female'],
          'interests': ['travel'],
        },
        'geography': {
          'countries': ['RU'],
          'regions': ['moscow'],
          'cities': ['moscow'],
        },
        'device': {
          'types': ['mobile'],
          'operating_systems': ['android'],
        },
      },
    });
    final transaction = BillingTransaction.fromJson({
      'id': 4,
      'amount': 125.5,
      'type': 'deposit',
      'description': 'Initial balance',
      'created_at': '2026-10-24T10:30:00+00:00',
    });
    final analytics = AnalyticsPoint.fromJson({
      'date': '2026-10-24',
      'campaign_id': 3,
      'ad_id': 2,
      'creative_id': null,
      'total_impressions': 200,
      'total_clicks': 10,
      'total_conversions': 2,
      'total_conversion_value': 1499.9,
      'total_cost': 35,
    });
    final creative = Creative.fromJson({
      'id': 8,
      'ad_id': 2,
      'content': 'Banner',
      'media': {
        'type': 'image',
        'url': '/media/banner.png',
        'mime_type': 'image/png',
        'file_name': 'banner.png',
        'file_size': 2048,
      },
      'moderation_status': 'rejected',
      'moderation_reason': 'Missing disclaimer',
      'submitted_at': '2026-10-25T10:00:00Z',
      'reviewed_at': '2026-10-25T10:05:00Z',
      'reviewed_by': 7,
      'ad_title': 'Banner ad',
      'campaign_name': 'Launch',
      'owner_user_id': 1,
    });

    expect(user.role, 'user');
    expect(campaign.budget.spentTotal, 25.5);
    expect(campaign.budget.dailyLimit, 100);
    expect(campaign.schedule.daysOfWeek, [1, 2, 3, 4, 5]);
    expect(campaign.schedule.startHour, 8);
    expect(ad.isActive, isTrue);
    expect(ad.placement, 'banner');
    expect(ad.destinationUrl, 'https://example.com/offer');
    expect(ad.weight, 25);
    expect(ad.bidCpm, 12.5);
    expect(ad.targeting.minAge, 18);
    expect(ad.targeting.countries, ['RU']);
    expect(ad.targeting.deviceTypes, ['mobile']);
    expect(transaction.isIncome, isTrue);
    expect(transaction.amount, 125.5);
    expect(analytics.ctr, 5);
    expect(analytics.conversions, 2);
    expect(analytics.conversionRate, 20);
    expect(analytics.conversionValue, 1499.9);
    expect(analytics.cost, 35);
    expect(creative.media.isImage, isTrue);
    expect(creative.media.fileName, 'banner.png');
    expect(creative.media.fileSize, 2048);
    expect(creative.isRejected, isTrue);
    expect(creative.moderationReason, 'Missing disclaimer');
    expect(creative.reviewedBy, 7);
    expect(creative.campaignName, 'Launch');
  });

  test('analytics CTR is zero when there are no impressions', () {
    final analytics = AnalyticsPoint.fromJson({
      'date': '2026-10-24',
      'campaign_id': null,
      'total_impressions': 0,
      'total_clicks': 0,
      'total_conversions': 0,
      'total_conversion_value': 0,
      'total_cost': 0,
    });

    expect(analytics.campaignId, 0);
    expect(analytics.ctr, 0);
    expect(analytics.conversionRate, 0);
  });

  test('delivery and tracking receipts parse event collection contracts', () {
    final delivery = AdDelivery.fromJson({
      'delivery_id': 'delivery-1',
      'campaign_id': 3,
      'ad_id': 4,
      'creative_id': 5,
      'title': 'Offer',
      'content': 'Buy now',
      'destination_url': 'https://example.com',
      'impression_url': 'https://ads.example/delivery/delivery-1/impression',
      'click_url': 'https://ads.example/delivery/delivery-1/click',
      'conversion_url': 'https://ads.example/delivery/delivery-1/conversion',
      'media': {'type': 'image', 'url': '/media/banner.png'},
    });
    final receipt = TrackingReceipt.fromJson({
      'delivery_id': 'delivery-1',
      'event_id': 'order-42',
      'event_type': 'ad_conversion',
      'recorded': true,
      'occurred_at': '2026-10-25T10:00:00Z',
      'conversion_type': 'purchase',
      'conversion_value': 1499.9,
      'conversion_currency': 'RUB',
    });

    expect(delivery.media.isImage, isTrue);
    expect(delivery.impressionUrl, contains('/impression'));
    expect(receipt.eventType, 'ad_conversion');
    expect(receipt.recorded, isTrue);
    expect(receipt.conversionCurrency, 'RUB');
  });
}
