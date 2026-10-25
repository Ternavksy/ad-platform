import 'dart:io';

import 'package:ad_platform_mobile/src/core/api_config.dart';
import 'package:ad_platform_mobile/src/core/app_theme.dart';
import 'package:ad_platform_mobile/src/domain/models.dart';
import 'package:ad_platform_mobile/src/state/providers.dart';
import 'package:ad_platform_mobile/src/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

class CampaignDetailScreen extends ConsumerWidget {
  const CampaignDetailScreen({required this.campaignId, super.key});

  final int campaignId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appDataProvider);
    final matching = data.campaigns.where((item) => item.id == campaignId);
    if (matching.isEmpty) {
      return const Scaffold(body: Center(child: Text('Кампания не найдена')));
    }
    final campaign = matching.first;
    final ads = data.adsByCampaign[campaignId] ?? const <AdItem>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Кампания'),
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
      ),
      body: AdaptivePageBody(
        child: RefreshIndicator(
          onRefresh: ref.read(appDataProvider.notifier).refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              SurfaceCard(
                child: Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.primaryDark],
                        ),
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: const Icon(
                        Icons.campaign_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            campaign.name,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 7),
                          StatusBadge(active: campaign.isActive),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Бюджет',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 7),
                    Text(
                      campaign.budget.hasTotalLimit
                          ? '${campaign.budget.spentTotal.toStringAsFixed(2)} из ${campaign.budget.total.toStringAsFixed(2)}'
                          : '${campaign.budget.spentTotal.toStringAsFixed(2)} потрачено · без общего лимита',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      campaign.budget.hasDailyLimit
                          ? 'Сегодня ${campaign.budget.spentToday.toStringAsFixed(2)} из ${campaign.budget.dailyLimit.toStringAsFixed(2)}'
                          : 'Дневной лимит не задан',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (campaign.budget.hasTotalLimit) ...[
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: campaign.budget.totalProgress,
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ],
                    const SizedBox(height: 9),
                    Text(
                      _campaignScheduleSummary(campaign.schedule),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SectionTitle(
                'Объявления',
                trailing: FilledButton.tonalIcon(
                  onPressed:
                      () => _showAdEditor(context, ref, campaignId: campaignId),
                  icon: const Icon(Icons.add_rounded, size: 19),
                  label: const Text('Добавить'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                ),
              ),
              const SizedBox(height: 12),
              if (ads.isEmpty)
                EmptyState(
                  icon: Icons.ads_click_outlined,
                  title: 'Нет объявлений',
                  message: 'Добавьте первое объявление в эту кампанию.',
                  action: FilledButton.icon(
                    onPressed:
                        () =>
                            _showAdEditor(context, ref, campaignId: campaignId),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Добавить объявление'),
                  ),
                )
              else
                ...ads.map(
                  (ad) => Padding(
                    padding: const EdgeInsets.only(bottom: 11),
                    child: SurfaceCard(
                      onTap:
                          () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => AdDetailScreen(adId: ad.id),
                            ),
                          ),
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.teal.withValues(alpha: .1),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.ads_click_rounded,
                              color: AppColors.teal,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  ad.title,
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  '${data.creativesByAd[ad.id]?.length ?? 0} креативов · ${_adPlacementLabel(data, ad)} · CPM ${ad.bidCpm.toStringAsFixed(2)}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _targetingSummary(ad.targeting),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          StatusBadge(active: ad.isActive),
                          PopupMenuButton<String>(
                            onSelected: (value) async {
                              if (value == 'edit') {
                                await _showAdEditor(
                                  context,
                                  ref,
                                  campaignId: campaignId,
                                  item: ad,
                                );
                              } else {
                                final creatives =
                                    data.creativesByAd[ad.id] ??
                                    const <Creative>[];
                                if (creatives.isNotEmpty) {
                                  showMessage(
                                    context,
                                    'Сначала удалите креативы объявления',
                                    error: true,
                                  );
                                  return;
                                }
                                if (await confirmAction(
                                  context,
                                  title: 'Удалить объявление?',
                                  message: 'Это действие нельзя отменить.',
                                )) {
                                  try {
                                    await ref
                                        .read(appDataProvider.notifier)
                                        .deleteAd(ad.id);
                                  } catch (error) {
                                    if (context.mounted) {
                                      showMessage(
                                        context,
                                        error.toString(),
                                        error: true,
                                      );
                                    }
                                  }
                                }
                              }
                            },
                            itemBuilder:
                                (_) => const [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Редактировать'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Удалить'),
                                  ),
                                ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class AdDetailScreen extends ConsumerWidget {
  const AdDetailScreen({required this.adId, super.key});

  final int adId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appDataProvider);
    final matching = data.allAds.where((item) => item.id == adId);
    if (matching.isEmpty) {
      return const Scaffold(body: Center(child: Text('Объявление не найдено')));
    }
    final ad = matching.first;
    final creatives = data.creativesByAd[adId] ?? const <Creative>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Объявление'),
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
      ),
      body: AdaptivePageBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          ad.title,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      StatusBadge(active: ad.isActive),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Место: ${_adPlacementLabel(data, ad)} · CPM ${ad.bidCpm.toStringAsFixed(2)} · вес ${ad.weight}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Таргетинг: ${_targetingSummary(ad.targeting)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (ad.destinationUrl.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      ad.destinationUrl,
                      style: Theme.of(context).textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 18,
                    runSpacing: 8,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.tag_rounded,
                            size: 18,
                            color: AppColors.muted,
                          ),
                          const SizedBox(width: 7),
                          Text(
                            'ID $adId',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.palette_outlined,
                            size: 18,
                            color: AppColors.muted,
                          ),
                          const SizedBox(width: 7),
                          Text('${creatives.length} креативов'),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            FutureBuilder<List<AnalyticsPoint>>(
              future: ref.read(repositoryProvider).getAdAnalytics(adId),
              builder: (context, snapshot) {
                final points = snapshot.data ?? const <AnalyticsPoint>[];
                final impressions = points.fold<int>(
                  0,
                  (sum, item) => sum + item.impressions,
                );
                final clicks = points.fold<int>(
                  0,
                  (sum, item) => sum + item.clicks,
                );
                return Row(
                  children: [
                    Expanded(
                      child: _MiniMetric(
                        label: 'Показы',
                        value: '$impressions',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MiniMetric(label: 'Клики', value: '$clicks'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MiniMetric(
                        label: 'CTR',
                        value:
                            impressions == 0
                                ? '0%'
                                : '${(clicks / impressions * 100).toStringAsFixed(1)}%',
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 25),
            SectionTitle(
              'Креативы',
              trailing: FilledButton.tonalIcon(
                onPressed: () => _showCreativeEditor(context, ref, adId: adId),
                icon: const Icon(Icons.add_rounded, size: 19),
                label: const Text('Добавить'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              ),
            ),
            const SizedBox(height: 12),
            if (creatives.isEmpty)
              EmptyState(
                icon: Icons.palette_outlined,
                title: 'Креативов пока нет',
                message: 'Добавьте текст или описание рекламного материала.',
                action: FilledButton.icon(
                  onPressed:
                      () => _showCreativeEditor(context, ref, adId: adId),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Добавить креатив'),
                ),
              )
            else
              ...creatives.map(
                (creative) => Padding(
                  padding: const EdgeInsets.only(bottom: 11),
                  child: SurfaceCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _CreativeThumbnail(creative: creative),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ModerationBadge(
                                status: creative.moderationStatus,
                              ),
                              const SizedBox(height: 7),
                              Text(
                                creative.content.isEmpty
                                    ? creative.media.fileName
                                    : creative.content,
                                style: const TextStyle(
                                  height: 1.45,
                                  color: AppColors.ink,
                                ),
                              ),
                              if (creative.media.hasFile) ...[
                                const SizedBox(height: 5),
                                Text(
                                  '${creative.media.isVideo ? 'Видео' : 'Изображение'} · ${_formatFileSize(creative.media.fileSize)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ],
                              if (creative.moderationReason.isNotEmpty) ...[
                                const SizedBox(height: 7),
                                Text(
                                  creative.moderationReason,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.coral,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        PopupMenuButton<String>(
                          onSelected: (value) async {
                            if (value == 'edit') {
                              await _showCreativeEditor(
                                context,
                                ref,
                                adId: adId,
                                item: creative,
                              );
                            } else if (value == 'submit') {
                              try {
                                await ref
                                    .read(appDataProvider.notifier)
                                    .submitCreativeForModeration(creative.id);
                                if (context.mounted) {
                                  showMessage(
                                    context,
                                    'Креатив отправлен на модерацию.',
                                  );
                                }
                              } catch (error) {
                                if (context.mounted) {
                                  showMessage(
                                    context,
                                    error.toString(),
                                    error: true,
                                  );
                                }
                              }
                            } else if (value == 'delete' &&
                                await confirmAction(
                                  context,
                                  title: 'Удалить креатив?',
                                  message: 'Это действие нельзя отменить.',
                                )) {
                              try {
                                await ref
                                    .read(appDataProvider.notifier)
                                    .deleteCreative(creative.id);
                              } catch (error) {
                                if (context.mounted) {
                                  showMessage(
                                    context,
                                    error.toString(),
                                    error: true,
                                  );
                                }
                              }
                            }
                          },
                          itemBuilder:
                              (_) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Редактировать'),
                                ),
                                if (creative.canSubmitForModeration)
                                  const PopupMenuItem(
                                    value: 'submit',
                                    child: Text('Отправить на модерацию'),
                                  ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Удалить'),
                                ),
                              ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CreativeThumbnail extends StatelessWidget {
  const _CreativeThumbnail({required this.creative});

  final Creative creative;

  @override
  Widget build(BuildContext context) {
    final media = creative.media;
    if (media.isImage && media.url.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Image.network(
          ApiConfig.resolveAdsUrl(media.url),
          width: 52,
          height: 52,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _icon(Icons.broken_image_outlined),
        ),
      );
    }
    return _icon(
      media.isVideo ? Icons.play_circle_outline : Icons.palette_outlined,
    );
  }

  Widget _icon(IconData icon) => Container(
    width: 52,
    height: 52,
    decoration: BoxDecoration(
      color: AppColors.primary.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Icon(icon, color: AppColors.primary),
  );
}

String _formatFileSize(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} КБ';
  return '$bytes Б';
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
    child: Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            maxLines: 1,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.muted),
        ),
      ],
    ),
  );
}

Future<void> _showAdEditor(
  BuildContext context,
  WidgetRef ref, {
  required int campaignId,
  AdItem? item,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _AdEditor(campaignId: campaignId, item: item, parentRef: ref),
);

class _AdEditor extends StatefulWidget {
  const _AdEditor({
    required this.campaignId,
    required this.item,
    required this.parentRef,
  });
  final int campaignId;
  final AdItem? item;
  final WidgetRef parentRef;

  @override
  State<_AdEditor> createState() => _AdEditorState();
}

class _AdEditorState extends State<_AdEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _destinationUrl;
  late final TextEditingController _weight;
  late final TextEditingController _bidCpm;
  late final TextEditingController _minAge;
  late final TextEditingController _maxAge;
  late final TextEditingController _interests;
  late final TextEditingController _countries;
  late final TextEditingController _regions;
  late final TextEditingController _cities;
  late String _status;
  late String _placement;
  late int _placementId;
  late Set<String> _genders;
  late Set<String> _deviceTypes;
  late Set<String> _operatingSystems;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.item?.title);
    _destinationUrl = TextEditingController(text: widget.item?.destinationUrl);
    _weight = TextEditingController(text: '${widget.item?.weight ?? 1}');
    _bidCpm = TextEditingController(
      text: (widget.item?.bidCpm ?? 1).toStringAsFixed(2),
    );
    _status = widget.item?.status ?? 'draft';
    _placement = widget.item?.placement ?? 'feed';
    _placementId = widget.item?.placementId ?? 0;
    final targeting = widget.item?.targeting ?? const AdTargeting();
    _minAge = TextEditingController(
      text: targeting.minAge == 0 ? '' : '${targeting.minAge}',
    );
    _maxAge = TextEditingController(
      text: targeting.maxAge == 0 ? '' : '${targeting.maxAge}',
    );
    _interests = TextEditingController(text: targeting.interests.join(', '));
    _countries = TextEditingController(text: targeting.countries.join(', '));
    _regions = TextEditingController(text: targeting.regions.join(', '));
    _cities = TextEditingController(text: targeting.cities.join(', '));
    _genders = targeting.genders.toSet();
    _deviceTypes = targeting.deviceTypes.toSet();
    _operatingSystems = targeting.operatingSystems.toSet();
  }

  @override
  void dispose() {
    _title.dispose();
    _destinationUrl.dispose();
    _weight.dispose();
    _bidCpm.dispose();
    _minAge.dispose();
    _maxAge.dispose();
    _interests.dispose();
    _countries.dispose();
    _regions.dispose();
    _cities.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final controller = widget.parentRef.read(appDataProvider.notifier);
      final weight = int.parse(_weight.text);
      final bidCpm = double.parse(_bidCpm.text.trim().replaceAll(',', '.'));
      final targeting = AdTargeting(
        minAge: int.tryParse(_minAge.text.trim()) ?? 0,
        maxAge: int.tryParse(_maxAge.text.trim()) ?? 0,
        genders: _genders.toList(),
        interests: _tokens(_interests.text),
        countries:
            _tokens(_countries.text).map((item) => item.toUpperCase()).toList(),
        regions: _tokens(_regions.text),
        cities: _tokens(_cities.text),
        deviceTypes: _deviceTypes.toList(),
        operatingSystems: _operatingSystems.toList(),
      );
      if (widget.item == null) {
        await controller.createAd(
          widget.campaignId,
          _title.text,
          _status,
          _placement,
          _destinationUrl.text,
          weight,
          bidCpm,
          _placementId == 0 ? null : _placementId,
          targeting,
        );
      } else {
        await controller.updateAd(
          widget.item!,
          _title.text,
          _status,
          _placement,
          _destinationUrl.text,
          weight,
          bidCpm,
          _placementId == 0 ? null : _placementId,
          targeting,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        showMessage(context, error.toString(), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.parentRef.read(appDataProvider);
    final formats = {for (final item in data.formats) item.id: item};
    final sites = {for (final item in data.sites) item.id: item};
    return _EditorShell(
      title:
          widget.item == null ? 'Новое объявление' : 'Редактировать объявление',
      bottomInset: MediaQuery.viewInsetsOf(context).bottom,
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            TextFormField(
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Заголовок',
                hintText: 'Что увидит аудитория',
              ),
              validator:
                  (value) =>
                      (value?.trim().isEmpty ?? true)
                          ? 'Введите заголовок'
                          : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _destinationUrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Ссылка перехода',
                hintText: 'https://example.com/offer',
              ),
              validator: (value) {
                final uri = Uri.tryParse(value?.trim() ?? '');
                if (uri == null ||
                    !uri.hasAuthority ||
                    (uri.scheme != 'http' && uri.scheme != 'https')) {
                  return 'Введите полную ссылку http(s)';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              value: _placementId,
              decoration: const InputDecoration(
                labelText: 'Рекламное место',
                helperText:
                    'Точная площадка и формат для выдачи по placement_code',
              ),
              isExpanded: true,
              items: [
                const DropdownMenuItem(
                  value: 0,
                  child: Text('Без привязки (общая выдача)'),
                ),
                ...data.allPlacements.map((placement) {
                  final site = sites[placement.siteId];
                  final format = formats[placement.formatId];
                  return DropdownMenuItem(
                    value: placement.id,
                    child: Text(
                      '${site?.name ?? 'Площадка'} · ${placement.name} · ${format?.sizeLabel ?? 'формат'}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }),
              ],
              onChanged: (value) => setState(() => _placementId = value ?? 0),
            ),
            const SizedBox(height: 16),
            if (_placementId == 0) ...[
              DropdownButtonFormField<String>(
                value: _placement,
                decoration: const InputDecoration(
                  labelText: 'Тип общей выдачи',
                ),
                items: const [
                  DropdownMenuItem(value: 'feed', child: Text('Лента')),
                  DropdownMenuItem(value: 'banner', child: Text('Баннер')),
                  DropdownMenuItem(value: 'story', child: Text('Истории')),
                ],
                onChanged: (value) => setState(() => _placement = value!),
              ),
              const SizedBox(height: 16),
            ],
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 12),
                leading: const Icon(
                  Icons.tune_rounded,
                  color: AppColors.primary,
                ),
                title: const Text('Таргетинг'),
                subtitle: const Text('Аудитория, география и устройство'),
                children: [
                  const _TargetingHeading('Аудитория'),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _minAge,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Возраст от',
                          ),
                          validator: _ageValidator,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _maxAge,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Возраст до',
                          ),
                          validator: (value) {
                            final error = _ageValidator(value);
                            if (error != null) return error;
                            final min = int.tryParse(_minAge.text.trim()) ?? 0;
                            final max = int.tryParse(value?.trim() ?? '') ?? 0;
                            return min > 0 && max > 0 && min > max
                                ? 'Меньше возраста «от»'
                                : null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _ChoiceChips(
                    values: _genders,
                    options: const {
                      'male': 'Мужчины',
                      'female': 'Женщины',
                      'non_binary': 'Небинарный',
                    },
                    onChanged: (value) => setState(() => _genders = value),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _interests,
                    decoration: const InputDecoration(
                      labelText: 'Интересы',
                      hintText: 'спорт, путешествия, технологии',
                      helperText: 'Достаточно совпадения одного интереса',
                    ),
                  ),
                  const SizedBox(height: 18),
                  const _TargetingHeading('География'),
                  TextFormField(
                    controller: _countries,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Страны',
                      hintText: 'RU, KZ, BY',
                      helperText: 'Двухбуквенные ISO-коды через запятую',
                    ),
                    validator: (value) {
                      final invalid = _tokens(
                        value ?? '',
                      ).any((item) => !RegExp(r'^[A-Za-z]{2}$').hasMatch(item));
                      return invalid
                          ? 'Используйте коды вроде RU или KZ'
                          : null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _regions,
                    decoration: const InputDecoration(
                      labelText: 'Регионы',
                      hintText: 'Москва, Московская область',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _cities,
                    decoration: const InputDecoration(
                      labelText: 'Города',
                      hintText: 'Москва, Казань',
                    ),
                  ),
                  const SizedBox(height: 18),
                  const _TargetingHeading('Устройства'),
                  _ChoiceChips(
                    values: _deviceTypes,
                    options: const {
                      'mobile': 'Телефон',
                      'tablet': 'Планшет',
                      'desktop': 'Компьютер',
                      'tv': 'ТВ',
                      'other': 'Другое',
                    },
                    onChanged: (value) => setState(() => _deviceTypes = value),
                  ),
                  const SizedBox(height: 12),
                  _ChoiceChips(
                    values: _operatingSystems,
                    options: const {
                      'android': 'Android',
                      'ios': 'iOS',
                      'windows': 'Windows',
                      'macos': 'macOS',
                      'linux': 'Linux',
                      'other': 'Другая ОС',
                    },
                    onChanged:
                        (value) => setState(() => _operatingSystems = value),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _bidCpm,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Ставка CPM',
                helperText:
                    'Стоимость 1000 показов; списание идёт за каждый показ',
              ),
              validator: (value) {
                final parsed = double.tryParse(
                  (value ?? '').trim().replaceAll(',', '.'),
                );
                return parsed == null || parsed < .01 || parsed > 1000000
                    ? 'Число от 0,01 до 1 000 000'
                    : null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _weight,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Вес показа',
                helperText: 'Чем выше вес, тем чаще выбирается объявление',
              ),
              validator: (value) {
                final parsed = int.tryParse(value ?? '');
                return parsed == null || parsed < 1 || parsed > 1000
                    ? 'Укажите число от 1 до 1000'
                    : null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _status,
              decoration: const InputDecoration(labelText: 'Статус'),
              items: const [
                DropdownMenuItem(value: 'draft', child: Text('Черновик')),
                DropdownMenuItem(value: 'active', child: Text('Активно')),
              ],
              onChanged: (value) => setState(() => _status = value!),
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: _saving ? null : _save,
              child:
                  _saving
                      ? const CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      )
                      : const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }
}

String _adPlacementLabel(AppDataState data, AdItem ad) {
  if (ad.placementId == null) return ad.placement;
  for (final placement in data.allPlacements) {
    if (placement.id == ad.placementId) return placement.name;
  }
  return 'место #${ad.placementId}';
}

String _campaignScheduleSummary(CampaignSchedule schedule) {
  String date(DateTime value) {
    final utc = value.toUtc();
    return '${utc.day.toString().padLeft(2, '0')}.${utc.month.toString().padLeft(2, '0')}.${utc.year}';
  }

  const names = {1: 'Пн', 2: 'Вт', 3: 'Ср', 4: 'Чт', 5: 'Пт', 6: 'Сб', 7: 'Вс'};
  final parts = <String>['Расписание:'];
  if (schedule.startsAt != null) parts.add('с ${date(schedule.startsAt!)}');
  if (schedule.endsAt != null) parts.add('до ${date(schedule.endsAt!)}');
  parts.add(
    schedule.daysOfWeek.isEmpty
        ? 'ежедневно'
        : schedule.daysOfWeek.map((day) => names[day] ?? '$day').join(', '),
  );
  parts.add(
    '${schedule.startHour.toString().padLeft(2, '0')}:00–${schedule.endHour.toString().padLeft(2, '0')}:00 UTC',
  );
  return parts.join(' ');
}

List<String> _tokens(String value) =>
    value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();

String? _ageValidator(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  final age = int.tryParse(text);
  return age == null || age < 1 || age > 120 ? 'Число от 1 до 120' : null;
}

String _targetingSummary(AdTargeting targeting) {
  if (!targeting.hasRules) return 'Вся аудитория';
  final parts = <String>[];
  if (targeting.minAge > 0 || targeting.maxAge > 0) {
    if (targeting.minAge > 0 && targeting.maxAge > 0) {
      parts.add('${targeting.minAge}–${targeting.maxAge} лет');
    } else if (targeting.minAge > 0) {
      parts.add('от ${targeting.minAge} лет');
    } else {
      parts.add('до ${targeting.maxAge} лет');
    }
  }
  if (targeting.genders.isNotEmpty) {
    parts.add('пол: ${targeting.genders.join(', ')}');
  }
  if (targeting.interests.isNotEmpty) {
    parts.add('интересы: ${targeting.interests.join(', ')}');
  }
  final geo = [
    ...targeting.countries,
    ...targeting.regions,
    ...targeting.cities,
  ];
  if (geo.isNotEmpty) {
    parts.add('гео: ${geo.join(', ')}');
  }
  final devices = [...targeting.deviceTypes, ...targeting.operatingSystems];
  if (devices.isNotEmpty) {
    parts.add('устройства: ${devices.join(', ')}');
  }
  return parts.join(' · ');
}

class _TargetingHeading extends StatelessWidget {
  const _TargetingHeading(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    ),
  );
}

class _ChoiceChips extends StatelessWidget {
  const _ChoiceChips({
    required this.values,
    required this.options,
    required this.onChanged,
  });

  final Set<String> values;
  final Map<String, String> options;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 7,
    runSpacing: 7,
    children:
        options.entries
            .map(
              (entry) => FilterChip(
                label: Text(entry.value),
                selected: values.contains(entry.key),
                onSelected: (selected) {
                  final next = {...values};
                  selected ? next.add(entry.key) : next.remove(entry.key);
                  onChanged(next);
                },
              ),
            )
            .toList(),
  );
}

Future<void> _showCreativeEditor(
  BuildContext context,
  WidgetRef ref, {
  required int adId,
  Creative? item,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _CreativeEditor(adId: adId, item: item, parentRef: ref),
);

class _CreativeEditor extends StatefulWidget {
  const _CreativeEditor({
    required this.adId,
    required this.item,
    required this.parentRef,
  });
  final int adId;
  final Creative? item;
  final WidgetRef parentRef;

  @override
  State<_CreativeEditor> createState() => _CreativeEditorState();
}

class _CreativeEditorState extends State<_CreativeEditor> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  late final TextEditingController _content;
  XFile? _selectedFile;
  bool _selectedIsVideo = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _content = TextEditingController(text: widget.item?.content);
  }

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    await _selectFile(file, isVideo: false);
  }

  Future<void> _pickVideo() async {
    final file = await _picker.pickVideo(source: ImageSource.gallery);
    await _selectFile(file, isVideo: true);
  }

  Future<void> _selectFile(XFile? file, {required bool isVideo}) async {
    if (file == null) return;
    final size = await file.length();
    final limit = isVideo ? 100 * 1024 * 1024 : 10 * 1024 * 1024;
    if (size > limit) {
      if (mounted) {
        showMessage(
          context,
          isVideo
              ? 'Размер видео не должен превышать 100 МБ.'
              : 'Размер изображения не должен превышать 10 МБ.',
          error: true,
        );
      }
      return;
    }
    if (mounted) {
      setState(() {
        _selectedFile = file;
        _selectedIsVideo = isVideo;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final controller = widget.parentRef.read(appDataProvider.notifier);
      if (widget.item == null) {
        if (_selectedFile == null) {
          await controller.createCreative(widget.adId, _content.text);
        } else {
          await controller.createCreativeWithMedia(
            widget.adId,
            _content.text,
            _selectedFile!.path,
            _selectedFile!.name,
          );
        }
      } else {
        if (_selectedFile == null) {
          await controller.updateCreative(widget.item!, _content.text);
        } else {
          await controller.updateCreativeWithMedia(
            widget.item!,
            _content.text,
            _selectedFile!.path,
            _selectedFile!.name,
          );
        }
      }
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        showMessage(context, error.toString(), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) => _EditorShell(
    title: widget.item == null ? 'Новый креатив' : 'Редактировать креатив',
    bottomInset: MediaQuery.viewInsetsOf(context).bottom,
    child: Form(
      key: _formKey,
      child: Column(
        children: [
          TextFormField(
            controller: _content,
            autofocus: true,
            minLines: 4,
            maxLines: 7,
            maxLength: 1024,
            decoration: const InputDecoration(
              labelText: 'Содержание',
              alignLabelWithHint: true,
              hintText: 'Текст или описание рекламного материала',
            ),
            validator:
                (value) =>
                    (value?.trim().isEmpty ?? true) &&
                            _selectedFile == null &&
                            !(widget.item?.media.hasFile ?? false)
                        ? 'Добавьте содержание'
                        : null,
          ),
          const SizedBox(height: 14),
          if (_selectedFile != null)
            _SelectedMediaPreview(
              file: _selectedFile!,
              isVideo: _selectedIsVideo,
              onRemove: () => setState(() => _selectedFile = null),
            )
          else if (widget.item?.media.hasFile ?? false)
            _ExistingMediaPreview(media: widget.item!.media),
          if (widget.item != null &&
              widget.item!.moderationStatus != 'draft' &&
              widget.item!.moderationStatus != 'rejected') ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.amber.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'После сохранения креатив станет черновиком и потребуется повторная модерация.',
                style: TextStyle(fontSize: 12, color: AppColors.ink),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: _saving ? null : _pickImage,
                icon: const Icon(Icons.image_outlined),
                label: const Text('Изображение'),
              ),
              OutlinedButton.icon(
                onPressed: _saving ? null : _pickVideo,
                icon: const Icon(Icons.video_library_outlined),
                label: const Text('Видео'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'JPEG, PNG, GIF, WebP до 10 МБ · MP4, WebM, MOV до 100 МБ',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _saving ? null : _save,
            child:
                _saving
                    ? const CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    )
                    : const Text('Сохранить'),
          ),
        ],
      ),
    ),
  );
}

class _SelectedMediaPreview extends StatelessWidget {
  const _SelectedMediaPreview({
    required this.file,
    required this.isVideo,
    required this.onRemove,
  });

  final XFile file;
  final bool isVideo;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.primary.withValues(alpha: .06),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        if (isVideo)
          const SizedBox(
            width: 64,
            height: 64,
            child: Icon(Icons.play_circle_outline, size: 38),
          )
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(
              File(file.path),
              width: 64,
              height: 64,
              fit: BoxFit.cover,
            ),
          ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(file.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        IconButton(
          onPressed: onRemove,
          tooltip: 'Убрать файл',
          icon: const Icon(Icons.close),
        ),
      ],
    ),
  );
}

class _ExistingMediaPreview extends StatelessWidget {
  const _ExistingMediaPreview({required this.media});

  final CreativeMedia media;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.primary.withValues(alpha: .06),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        Icon(
          media.isVideo ? Icons.video_library_outlined : Icons.image_outlined,
          color: AppColors.primary,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            media.fileName.isEmpty ? 'Загруженный файл' : media.fileName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          _formatFileSize(media.fileSize),
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
      ],
    ),
  );
}

class _EditorShell extends StatelessWidget {
  const _EditorShell({
    required this.title,
    required this.child,
    required this.bottomInset,
  });

  final String title;
  final Widget child;
  final double bottomInset;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomInset),
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 20),
          child,
        ],
      ),
    ),
  );
}
