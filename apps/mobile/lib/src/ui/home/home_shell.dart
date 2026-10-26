import 'package:ad_platform_mobile/src/state/providers.dart';
import 'package:ad_platform_mobile/src/ui/analytics/analytics_screen.dart';
import 'package:ad_platform_mobile/src/ui/billing/billing_screen.dart';
import 'package:ad_platform_mobile/src/ui/campaigns/campaigns_screen.dart';
import 'package:ad_platform_mobile/src/ui/home/dashboard_screen.dart';
import 'package:ad_platform_mobile/src/ui/moderation/moderation_screen.dart';
import 'package:ad_platform_mobile/src/ui/profile/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final user = ref.read(sessionProvider).user;
      if (user != null) ref.read(appDataProvider.notifier).load(user.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(sessionProvider).user?.role == 'admin';
    final screens = [
      DashboardScreen(onNavigate: (index) => setState(() => _index = index)),
      const CampaignsScreen(),
      const BillingScreen(),
      const AnalyticsScreen(),
      if (isAdmin) const ModerationScreen(),
      const ProfileScreen(),
    ];
    final railDestinations = <NavigationRailDestination>[
      const NavigationRailDestination(
        icon: Icon(Icons.space_dashboard_outlined),
        selectedIcon: Icon(Icons.space_dashboard_rounded),
        label: Text('Главная'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.campaign_outlined),
        selectedIcon: Icon(Icons.campaign_rounded),
        label: Text('Кампании'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.account_balance_wallet_outlined),
        selectedIcon: Icon(Icons.account_balance_wallet_rounded),
        label: Text('Финансы'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.insights_outlined),
        selectedIcon: Icon(Icons.insights_rounded),
        label: Text('Аналитика'),
      ),
      if (isAdmin)
        const NavigationRailDestination(
          icon: Icon(Icons.fact_check_outlined),
          selectedIcon: Icon(Icons.fact_check_rounded),
          label: Text('Модерация'),
        ),
      const NavigationRailDestination(
        icon: Icon(Icons.person_outline_rounded),
        selectedIcon: Icon(Icons.person_rounded),
        label: Text('Профиль'),
      ),
    ];
    final bottomDestinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.space_dashboard_outlined),
        selectedIcon: Icon(Icons.space_dashboard_rounded),
        label: 'Главная',
      ),
      const NavigationDestination(
        icon: Icon(Icons.campaign_outlined),
        selectedIcon: Icon(Icons.campaign_rounded),
        label: 'Кампании',
      ),
      const NavigationDestination(
        icon: Icon(Icons.account_balance_wallet_outlined),
        selectedIcon: Icon(Icons.account_balance_wallet_rounded),
        label: 'Финансы',
      ),
      const NavigationDestination(
        icon: Icon(Icons.insights_outlined),
        selectedIcon: Icon(Icons.insights_rounded),
        label: 'Аналитика',
      ),
      if (isAdmin)
        const NavigationDestination(
          icon: Icon(Icons.fact_check_outlined),
          selectedIcon: Icon(Icons.fact_check_rounded),
          label: 'Модерация',
        ),
      const NavigationDestination(
        icon: Icon(Icons.person_outline_rounded),
        selectedIcon: Icon(Icons.person_rounded),
        label: 'Профиль',
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final content = IndexedStack(index: _index, children: screens);
        return Scaffold(
          body:
              wide
                  ? Row(
                    children: [
                      SafeArea(
                        right: false,
                        child: NavigationRail(
                          extended: constraints.maxWidth >= 1100,
                          selectedIndex: _index,
                          onDestinationSelected:
                              (value) => setState(() => _index = value),
                          labelType:
                              constraints.maxWidth >= 1100
                                  ? NavigationRailLabelType.none
                                  : NavigationRailLabelType.selected,
                          destinations: railDestinations,
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: SafeArea(
                          bottom: false,
                          left: false,
                          child: content,
                        ),
                      ),
                    ],
                  )
                  : SafeArea(bottom: false, child: content),
          bottomNavigationBar:
              wide
                  ? null
                  : NavigationBar(
                    selectedIndex: _index,
                    onDestinationSelected:
                        (value) => setState(() => _index = value),
                    destinations: bottomDestinations,
                  ),
          floatingActionButton:
              isAdmin
                  ? FloatingActionButton.small(
                    tooltip: 'Администрирование',
                    onPressed:
                        () => ref
                            .read(sessionProvider.notifier)
                            .switchWorkspace(AppWorkspace.admin),
                    child: const Icon(Icons.admin_panel_settings_rounded),
                  )
                  : null,
        );
      },
    );
  }
}
