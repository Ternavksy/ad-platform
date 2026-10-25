import 'package:ad_platform_mobile/src/core/app_theme.dart';
import 'package:ad_platform_mobile/src/domain/models.dart';
import 'package:ad_platform_mobile/src/state/providers.dart';
import 'package:ad_platform_mobile/src/ui/widgets/common.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  int? _campaignId;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(appDataProvider);
    final points =
        _campaignId == null
            ? data.analytics
            : data.analytics
                .where((item) => item.campaignId == _campaignId)
                .toList();
    final impressions = points.fold<int>(
      0,
      (sum, item) => sum + item.impressions,
    );
    final clicks = points.fold<int>(0, (sum, item) => sum + item.clicks);
    final conversions = points.fold<int>(
      0,
      (sum, item) => sum + item.conversions,
    );
    final conversionValue = points.fold<double>(
      0,
      (sum, item) => sum + item.conversionValue,
    );
    final cost = points.fold<double>(0, (sum, item) => sum + item.cost);
    final ctr = impressions == 0 ? 0.0 : clicks / impressions * 100;
    final conversionRate = clicks == 0 ? 0.0 : conversions / clicks * 100;

    return AdaptivePageBody(
      child: RefreshIndicator(
        onRefresh: ref.read(appDataProvider.notifier).refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 30),
          children: [
            const PageHeader(
              title: 'Аналитика',
              subtitle: 'Результаты рекламных кампаний',
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Column(
                children: [
                  DropdownButtonFormField<int?>(
                    value: _campaignId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Кампания',
                      prefixIcon: Icon(Icons.filter_alt_outlined),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Все кампании'),
                      ),
                      ...data.campaigns.map(
                        (campaign) => DropdownMenuItem<int?>(
                          value: campaign.id,
                          child: Text(
                            campaign.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) => setState(() => _campaignId = value),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _AnalyticsMetric(
                          icon: Icons.visibility_outlined,
                          color: AppColors.primary,
                          label: 'Показы',
                          value: NumberFormat.compact(
                            locale: 'ru',
                          ).format(impressions),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _AnalyticsMetric(
                          icon: Icons.touch_app_outlined,
                          color: AppColors.teal,
                          label: 'Клики',
                          value: NumberFormat.compact(
                            locale: 'ru',
                          ).format(clicks),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _AnalyticsMetric(
                          icon: Icons.shopping_bag_outlined,
                          color: AppColors.amber,
                          label: 'Конверсии',
                          value: NumberFormat.compact(
                            locale: 'ru',
                          ).format(conversions),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _AnalyticsMetric(
                          icon: Icons.trending_up_rounded,
                          color: AppColors.coral,
                          label: 'Конверсия кликов',
                          value: '${conversionRate.toStringAsFixed(2)}%',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _AnalyticsMetric(
                          icon: Icons.percent_rounded,
                          color: AppColors.primary,
                          label: 'CTR',
                          value: '${ctr.toStringAsFixed(2)}%',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _AnalyticsMetric(
                          icon: Icons.payments_outlined,
                          color: AppColors.coral,
                          label: 'Расход',
                          value: moneyFormat.format(cost),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _AnalyticsMetric(
                    icon: Icons.account_balance_wallet_outlined,
                    color: AppColors.teal,
                    label: 'Ценность конверсий',
                    value: moneyFormat.format(conversionValue),
                  ),
                  const SizedBox(height: 24),
                  SurfaceCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionTitle('Показы по дням'),
                        const SizedBox(height: 6),
                        const Text('Динамика охвата рекламных кампаний'),
                        const SizedBox(height: 24),
                        SizedBox(
                          height: 220,
                          child:
                              points.isEmpty
                                  ? const EmptyState(
                                    icon: Icons.query_stats_rounded,
                                    title: 'Данных пока нет',
                                    message:
                                        'Статистика появится после первых событий.',
                                  )
                                  : _AnalyticsChart(points: points),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  SurfaceCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.teal.withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.bolt_rounded,
                            color: AppColors.teal,
                          ),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Данные в реальном времени',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 5),
                              const Text(
                                'События поступают через RabbitMQ и агрегируются в ClickHouse.',
                              ),
                            ],
                          ),
                        ),
                      ],
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

class _AnalyticsMetric extends StatelessWidget {
  const _AnalyticsMetric({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.all(15),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 12),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
      ],
    ),
  );
}

class _AnalyticsChart extends StatelessWidget {
  const _AnalyticsChart({required this.points});

  final List<AnalyticsPoint> points;

  @override
  Widget build(BuildContext context) {
    final sorted = [...points]..sort((a, b) => a.date.compareTo(b.date));
    final spots = [
      for (var i = 0; i < sorted.length; i++)
        FlSpot(i.toDouble(), sorted[i].impressions.toDouble()),
    ];
    final peak = spots
        .map((item) => item.y)
        .fold<double>(0, (a, b) => a > b ? a : b);
    return LineChart(
      LineChartData(
        minY: 0,
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: (peak / 3).clamp(1, double.infinity).toDouble(),
          getDrawingHorizontalLine:
              (_) => const FlLine(color: AppColors.border, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 38),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval:
                  sorted.length > 5 ? (sorted.length / 4).ceilToDouble() : 1,
              reservedSize: 30,
              getTitlesWidget: (value, meta) {
                final index = value.round();
                if (index < 0 || index >= sorted.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    DateFormat('d MMM', 'ru').format(sorted[index].date),
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.muted,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: AppColors.primary,
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.primary.withValues(alpha: .1),
            ),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 350),
    );
  }
}
