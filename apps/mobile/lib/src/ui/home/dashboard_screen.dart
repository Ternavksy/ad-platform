import 'package:ad_platform_mobile/src/core/app_theme.dart';
import 'package:ad_platform_mobile/src/state/providers.dart';
import 'package:ad_platform_mobile/src/ui/widgets/common.dart';
import 'package:ad_platform_mobile/src/ui/sites/sites_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({required this.onNavigate, super.key});

  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final data = ref.watch(appDataProvider);
    final emailName = session.user?.email.split('@').first ?? 'пользователь';

    return AdaptivePageBody(
      child: RefreshIndicator(
        onRefresh: ref.read(appDataProvider.notifier).refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: PageHeader(
                title: 'Добрый день, $emailName',
                subtitle: DateFormat(
                  'd MMMM, EEEE',
                  'ru_RU',
                ).format(DateTime.now()),
                action: const AppLogo(size: 46),
              ),
            ),
            if (data.loading && data.campaigns.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (data.error != null && data.campaigns.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: 'Нет связи с бэкендом',
                  message: data.error!,
                  action: FilledButton.tonal(
                    onPressed: ref.read(appDataProvider.notifier).refresh,
                    child: const Text('Повторить'),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                sliver: SliverList.list(
                  children: [
                    _BalanceHero(
                      balance: data.balance,
                      onTap: () => onNavigate(2),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _MetricCard(
                            icon: Icons.campaign_rounded,
                            color: AppColors.primary,
                            value: '${data.campaigns.length}',
                            label: 'Кампаний',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _MetricCard(
                            icon: Icons.ads_click_rounded,
                            color: AppColors.teal,
                            value: '${data.allAds.length}',
                            label: 'Объявлений',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const SectionTitle('Быстрые действия'),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 600 ? 4 : 2;
                        final width =
                            (constraints.maxWidth - (columns - 1) * 10) /
                            columns;
                        return Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            SizedBox(
                              width: width,
                              child: _QuickAction(
                                icon: Icons.add_circle_outline_rounded,
                                label: 'Новая кампания',
                                onTap: () => onNavigate(1),
                              ),
                            ),
                            SizedBox(
                              width: width,
                              child: _QuickAction(
                                icon: Icons.add_card_rounded,
                                label: 'Пополнить',
                                onTap: () => onNavigate(2),
                              ),
                            ),
                            SizedBox(
                              width: width,
                              child: _QuickAction(
                                icon: Icons.auto_graph_rounded,
                                label: 'Отчёты',
                                onTap: () => onNavigate(3),
                              ),
                            ),
                            SizedBox(
                              width: width,
                              child: _QuickAction(
                                icon: Icons.language_rounded,
                                label: 'Площадки',
                                onTap:
                                    () => Navigator.push(
                                      context,
                                      MaterialPageRoute<void>(
                                        builder: (_) => const SitesScreen(),
                                      ),
                                    ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 26),
                    SectionTitle(
                      'Кампании',
                      trailing: TextButton(
                        onPressed: () => onNavigate(1),
                        child: const Text('Все'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (data.campaigns.isEmpty)
                      SurfaceCard(
                        child: Row(
                          children: [
                            const Icon(
                              Icons.campaign_outlined,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text('Создайте первую рекламную кампанию'),
                            ),
                            IconButton(
                              onPressed: () => onNavigate(1),
                              icon: const Icon(Icons.arrow_forward_rounded),
                            ),
                          ],
                        ),
                      )
                    else
                      ...data.campaigns
                          .take(3)
                          .map(
                            (campaign) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: SurfaceCard(
                                onTap: () => onNavigate(1),
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withValues(
                                          alpha: .09,
                                        ),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: const Icon(
                                        Icons.campaign_rounded,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            campaign.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style:
                                                Theme.of(
                                                  context,
                                                ).textTheme.titleMedium,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${data.adsByCampaign[campaign.id]?.length ?? 0} объявлений',
                                            style:
                                                Theme.of(
                                                  context,
                                                ).textTheme.bodyMedium,
                                          ),
                                        ],
                                      ),
                                    ),
                                    StatusBadge(active: campaign.isActive),
                                  ],
                                ),
                              ),
                            ),
                          ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BalanceHero extends StatelessWidget {
  const _BalanceHero({required this.balance, required this.onTap});

  final double balance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF171A3A), Color(0xFF5542D2)],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: .22),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Доступный баланс',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .67),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    moneyFormat.format(balance),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.7,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Text(
                    'Управление финансами  →',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              color: AppColors.teal.withValues(alpha: .18),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.account_balance_wallet_rounded,
              color: AppColors.teal,
              size: 30,
            ),
          ),
        ],
      ),
    ),
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.all(16),
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: color, size: 21),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: Container(
      constraints: const BoxConstraints(minHeight: 88),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppColors.primary, size: 24),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}
