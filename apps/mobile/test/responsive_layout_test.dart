import 'package:ad_platform_mobile/src/core/app_theme.dart';
import 'package:ad_platform_mobile/src/data/ad_platform_repository.dart';
import 'package:ad_platform_mobile/src/domain/models.dart';
import 'package:ad_platform_mobile/src/state/providers.dart';
import 'package:ad_platform_mobile/src/ui/analytics/analytics_screen.dart';
import 'package:ad_platform_mobile/src/ui/auth/auth_screen.dart';
import 'package:ad_platform_mobile/src/ui/billing/billing_screen.dart';
import 'package:ad_platform_mobile/src/ui/campaigns/campaign_detail_screen.dart';
import 'package:ad_platform_mobile/src/ui/campaigns/campaigns_screen.dart';
import 'package:ad_platform_mobile/src/ui/home/dashboard_screen.dart';
import 'package:ad_platform_mobile/src/ui/home/home_shell.dart';
import 'package:ad_platform_mobile/src/ui/moderation/moderation_screen.dart';
import 'package:ad_platform_mobile/src/ui/profile/profile_screen.dart';
import 'package:ad_platform_mobile/src/ui/sites/sites_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

const _user = AppUser(id: 1, email: 'long.username@example.com', role: 'user');

final _sampleState = AppDataState(
  balance: 987654321.45,
  campaigns: const [
    Campaign(
      id: 1,
      userId: 1,
      name: 'Очень длинное название рекламной кампании',
      status: 'active',
      budget: CampaignBudget(
        total: 1000000,
        dailyLimit: 50000,
        spentTotal: 750000,
        spentToday: 25000,
      ),
      schedule: CampaignSchedule(
        daysOfWeek: [1, 2, 3, 4, 5],
        startHour: 8,
        endHour: 22,
      ),
    ),
  ],
  adsByCampaign: const {
    1: [
      AdItem(
        id: 10,
        campaignId: 1,
        title: 'Очень длинный заголовок рекламного объявления',
        status: 'active',
        placement: 'banner',
        destinationUrl: 'https://example.com/a/very/long/destination/path',
        weight: 1000,
        bidCpm: 1234.56,
        targeting: AdTargeting(
          minAge: 18,
          maxAge: 35,
          genders: ['female'],
          interests: ['travel', 'technology'],
          countries: ['RU', 'KZ'],
          cities: ['moscow'],
          deviceTypes: ['mobile'],
          operatingSystems: ['android', 'ios'],
        ),
      ),
    ],
  },
  creativesByAd: const {
    10: [
      Creative(
        id: 100,
        adId: 10,
        content:
            'Длинный текст рекламного креатива для проверки переноса строк.',
      ),
    ],
  },
  transactions: [
    BillingTransaction(
      id: 1,
      amount: 987654321.45,
      type: 'deposit',
      description: 'Пополнение с очень длинным описанием операции',
      createdAt: DateTime(2026, 10, 24, 12, 30),
    ),
  ],
  analytics: [
    AnalyticsPoint(
      date: DateTime(2026, 10, 24),
      campaignId: 1,
      adId: 10,
      creativeId: 100,
      impressions: 123456789,
      clicks: 1234567,
      conversions: 12345,
      conversionValue: 123456789.45,
      cost: 987654321.45,
    ),
  ],
  sites: const [
    Site(
      id: 20,
      userId: 1,
      name: 'Новостное приложение с длинным названием',
      domain: 'news.example.com',
      status: 'active',
    ),
  ],
  formats: const [
    AdFormat(
      id: 30,
      code: 'banner_320x50',
      name: 'Мобильный баннер',
      kind: 'banner',
      width: 320,
      height: 50,
      status: 'active',
    ),
  ],
  placementsBySite: const {
    20: [
      Placement(
        id: 40,
        siteId: 20,
        formatId: 30,
        name: 'Баннер в верхней части главной страницы',
        code: '010c236c-20c1-48f9-ac13-d9b9db620845',
        status: 'active',
      ),
    ],
  },
);

class _FakeRepository extends AdPlatformRepository {
  @override
  Future<AppUser?> restoreSession() async => _user;

  @override
  Future<List<AnalyticsPoint>> getAdAnalytics(int adId) async =>
      _sampleState.analytics;
}

class _TestSessionController extends SessionController {
  _TestSessionController(super.repository) {
    state = const SessionState(
      status: SessionStatus.authenticated,
      user: _user,
    );
  }
}

class _TestAppDataController extends AppDataController {
  _TestAppDataController(super.repository) {
    state = _sampleState;
  }

  @override
  Future<void> load(int userId) async {}

  @override
  Future<void> refresh() async {}
}

class _TestModerationController extends ModerationController {
  _TestModerationController(super.repository) {
    state = const ModerationState(
      items: [
        Creative(
          id: 100,
          adId: 10,
          content: 'Креатив, ожидающий проверки модератором.',
          moderationStatus: 'pending',
          adTitle: 'Рекламное объявление',
          campaignName: 'Рекламная кампания',
          ownerUserId: 1,
        ),
      ],
    );
  }

  @override
  Future<void> load([String? status]) async {}

  @override
  Future<void> review(int id, String decision, {String reason = ''}) async {}
}

Widget _testApp(Widget screen, {required double textScale}) {
  final repository = _FakeRepository();
  return ProviderScope(
    overrides: [
      repositoryProvider.overrideWithValue(repository),
      sessionProvider.overrideWith((ref) => _TestSessionController(repository)),
      appDataProvider.overrideWith((ref) => _TestAppDataController(repository)),
      moderationProvider.overrideWith(
        (ref) => _TestModerationController(repository),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      builder:
          (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
      home: Scaffold(body: SafeArea(child: screen)),
    ),
  );
}

Future<void> _pumpAt(
  WidgetTester tester,
  Widget screen,
  Size size, {
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_testApp(screen, textScale: textScale));
  await tester.pump(const Duration(seconds: 1));
  expect(tester.takeException(), isNull);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru_RU');
  });

  final screens = <String, Widget>{
    'dashboard': DashboardScreen(onNavigate: (_) {}),
    'campaigns': const CampaignsScreen(),
    'billing': const BillingScreen(),
    'analytics': const AnalyticsScreen(),
    'profile': const ProfileScreen(),
    'campaign details': const CampaignDetailScreen(campaignId: 1),
    'ad details': const AdDetailScreen(adId: 10),
    'sites': const SitesScreen(),
    'moderation': const ModerationScreen(),
  };

  for (final viewport in <(String, Size, double)>[
    ('compact phone', const Size(320, 568), 1),
    ('large text phone', const Size(360, 640), 1.3),
    ('tablet', const Size(800, 1280), 1),
    ('wide landscape', const Size(1366, 768), 1),
  ]) {
    for (final entry in screens.entries) {
      testWidgets('${entry.key} fits ${viewport.$1}', (tester) async {
        await _pumpAt(tester, entry.value, viewport.$2, textScale: viewport.$3);
      });
    }
  }

  testWidgets('authentication fits compact and wide screens', (tester) async {
    await _pumpAt(tester, const AuthScreen(), const Size(320, 568));
    await _pumpAt(tester, const AuthScreen(), const Size(1366, 768));
  });

  testWidgets('shell switches between bottom bar and navigation rail', (
    tester,
  ) async {
    await _pumpAt(tester, const HomeShell(), const Size(360, 640));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);

    await _pumpAt(tester, const HomeShell(), const Size(800, 1280));
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsOneWidget);
  });
}
