import 'package:ad_platform_mobile/src/core/app_theme.dart';
import 'package:ad_platform_mobile/src/domain/models.dart';
import 'package:ad_platform_mobile/src/state/providers.dart';
import 'package:ad_platform_mobile/src/ui/campaigns/campaign_detail_screen.dart';
import 'package:ad_platform_mobile/src/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CampaignsScreen extends ConsumerWidget {
  const CampaignsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appDataProvider);
    return AdaptivePageBody(
      child: RefreshIndicator(
        onRefresh: ref.read(appDataProvider.notifier).refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: PageHeader(
                title: 'Кампании',
                subtitle: 'Управляйте рекламными запусками',
                action: IconButton.filled(
                  onPressed: () => showCampaignEditor(context, ref),
                  icon: const Icon(Icons.add_rounded),
                  tooltip: 'Новая кампания',
                ),
              ),
            ),
            if (data.loading && data.campaigns.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (data.campaigns.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.campaign_outlined,
                  title: 'Кампаний пока нет',
                  message:
                      'Создайте первую кампанию и добавьте в неё объявления.',
                  action: FilledButton.icon(
                    onPressed: () => showCampaignEditor(context, ref),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Создать кампанию'),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                sliver: SliverList.separated(
                  itemCount: data.campaigns.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final campaign = data.campaigns[index];
                    final ads =
                        data.adsByCampaign[campaign.id] ?? const <AdItem>[];
                    return SurfaceCard(
                      onTap:
                          () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder:
                                  (_) => CampaignDetailScreen(
                                    campaignId: campaign.id,
                                  ),
                            ),
                          ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(
                                    alpha: .09,
                                  ),
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                child: const Icon(
                                  Icons.campaign_rounded,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(width: 13),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      campaign.name,
                                      style:
                                          Theme.of(
                                            context,
                                          ).textTheme.titleLarge,
                                    ),
                                    const SizedBox(height: 5),
                                    StatusBadge(active: campaign.isActive),
                                  ],
                                ),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (value) async {
                                  if (value == 'edit') {
                                    await showCampaignEditor(
                                      context,
                                      ref,
                                      item: campaign,
                                    );
                                  } else if (await confirmAction(
                                    context,
                                    title: 'Удалить кампанию?',
                                    message:
                                        ads.isEmpty
                                            ? 'Это действие нельзя отменить.'
                                            : 'Сначала удалите ${ads.length} объявлений внутри кампании.',
                                  )) {
                                    if (ads.isNotEmpty && context.mounted) {
                                      showMessage(
                                        context,
                                        'Удалите объявления перед удалением кампании',
                                        error: true,
                                      );
                                      return;
                                    }
                                    try {
                                      await ref
                                          .read(appDataProvider.notifier)
                                          .deleteCampaign(campaign.id);
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
                          const SizedBox(height: 17),
                          const Divider(height: 1),
                          const SizedBox(height: 15),
                          Text(
                            _budgetSummary(campaign.budget),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _scheduleSummary(campaign.schedule),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
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
                          const SizedBox(height: 15),
                          Row(
                            children: [
                              Expanded(
                                child: _CampaignMetric(
                                  icon: Icons.ads_click_rounded,
                                  value: '${ads.length}',
                                  label: 'объявлений',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _CampaignMetric(
                                  icon: Icons.play_circle_outline_rounded,
                                  value:
                                      '${ads.where((item) => item.isActive).length}',
                                  label: 'активных',
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 16,
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CampaignMetric extends StatelessWidget {
  const _CampaignMetric({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 18, color: AppColors.muted),
      const SizedBox(width: 6),
      Text('$value ', style: const TextStyle(fontWeight: FontWeight.w800)),
      Flexible(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
      ),
    ],
  );
}

Future<void> showCampaignEditor(
  BuildContext context,
  WidgetRef ref, {
  Campaign? item,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _CampaignEditor(item: item, parentRef: ref),
);

class _CampaignEditor extends StatefulWidget {
  const _CampaignEditor({required this.item, required this.parentRef});

  final Campaign? item;
  final WidgetRef parentRef;

  @override
  State<_CampaignEditor> createState() => _CampaignEditorState();
}

class _CampaignEditorState extends State<_CampaignEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _budgetTotal;
  late final TextEditingController _dailyLimit;
  late String _status;
  late DateTime? _startsAt;
  late DateTime? _endsAt;
  late Set<int> _days;
  late int _startHour;
  late int _endHour;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.item?.name);
    _budgetTotal = TextEditingController(
      text: _moneyInput(widget.item?.budget.total ?? 0),
    );
    _dailyLimit = TextEditingController(
      text: _moneyInput(widget.item?.budget.dailyLimit ?? 0),
    );
    _status = widget.item?.status ?? 'draft';
    _startsAt = widget.item?.schedule.startsAt;
    _endsAt = widget.item?.schedule.endsAt;
    _days = (widget.item?.schedule.daysOfWeek ?? const <int>[]).toSet();
    _startHour = widget.item?.schedule.startHour ?? 0;
    _endHour = widget.item?.schedule.endHour ?? 24;
  }

  @override
  void dispose() {
    _name.dispose();
    _budgetTotal.dispose();
    _dailyLimit.dispose();
    super.dispose();
  }

  double _amount(TextEditingController controller) =>
      double.tryParse(controller.text.trim().replaceAll(',', '.')) ?? 0;

  Future<void> _pickDate({required bool start}) async {
    final current = start ? _startsAt : _endsAt;
    final selected = await showDatePicker(
      context: context,
      initialDate: current?.toLocal() ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (selected == null) return;
    setState(() {
      final value =
          start
              ? DateTime.utc(selected.year, selected.month, selected.day)
              : DateTime.utc(
                selected.year,
                selected.month,
                selected.day,
                23,
                59,
                59,
              );
      if (start) {
        _startsAt = value;
      } else {
        _endsAt = value;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final controller = widget.parentRef.read(appDataProvider.notifier);
      final budget = CampaignBudget(
        total: _amount(_budgetTotal),
        dailyLimit: _amount(_dailyLimit),
        spentTotal: widget.item?.budget.spentTotal ?? 0,
        spentToday: widget.item?.budget.spentToday ?? 0,
      );
      final schedule = CampaignSchedule(
        startsAt: _startsAt,
        endsAt: _endsAt,
        daysOfWeek: _days.toList()..sort(),
        startHour: _startHour,
        endHour: _endHour,
      );
      if (widget.item == null) {
        await controller.createCampaign(_name.text, _status, budget, schedule);
      } else {
        await controller.updateCampaign(
          widget.item!,
          _name.text,
          _status,
          budget,
          schedule,
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
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .92,
    ),
    padding: EdgeInsets.fromLTRB(
      20,
      12,
      20,
      20 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    decoration: const BoxDecoration(
      color: AppColors.background,
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    child: SingleChildScrollView(
      child: Form(
        key: _formKey,
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
            Text(
              widget.item == null ? 'Новая кампания' : 'Редактировать кампанию',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Название',
                hintText: 'Например, Осенняя распродажа',
              ),
              validator:
                  (value) =>
                      (value?.trim().isEmpty ?? true)
                          ? 'Введите название кампании'
                          : null,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _budgetTotal,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Общий бюджет',
                      helperText: '0 — без лимита',
                    ),
                    validator: _moneyValidator,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _dailyLimit,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Лимит в день',
                      helperText: 'UTC, 0 — без лимита',
                    ),
                    validator: (value) {
                      final error = _moneyValidator(value);
                      if (error != null) return error;
                      final total = _amount(_budgetTotal);
                      final daily =
                          double.tryParse(
                            (value ?? '').trim().replaceAll(',', '.'),
                          ) ??
                          0;
                      return total > 0 && daily > total
                          ? 'Больше общего бюджета'
                          : null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 12),
                leading: const Icon(
                  Icons.schedule_rounded,
                  color: AppColors.primary,
                ),
                title: const Text('Расписание'),
                subtitle: const Text('Даты, дни недели и часы UTC'),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDate(start: true),
                          icon: const Icon(Icons.event_available_rounded),
                          label: Text(
                            _startsAt == null
                                ? 'Дата начала'
                                : 'С ${_dateLabel(_startsAt!)}',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_startsAt != null)
                        IconButton(
                          onPressed: () => setState(() => _startsAt = null),
                          icon: const Icon(Icons.close_rounded),
                          tooltip: 'Убрать дату начала',
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDate(start: false),
                          icon: const Icon(Icons.event_busy_rounded),
                          label: Text(
                            _endsAt == null
                                ? 'Дата окончания'
                                : 'До ${_dateLabel(_endsAt!)}',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_endsAt != null)
                        IconButton(
                          onPressed: () => setState(() => _endsAt = null),
                          icon: const Icon(Icons.close_rounded),
                          tooltip: 'Убрать дату окончания',
                        ),
                    ],
                  ),
                  if (_startsAt != null &&
                      _endsAt != null &&
                      !_endsAt!.isAfter(_startsAt!)) ...[
                    const SizedBox(height: 8),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Окончание должно быть позже начала',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children:
                          const {
                            1: 'Пн',
                            2: 'Вт',
                            3: 'Ср',
                            4: 'Чт',
                            5: 'Пт',
                            6: 'Сб',
                            7: 'Вс',
                          }.entries.map((entry) {
                            final selected = _days.contains(entry.key);
                            return FilterChip(
                              label: Text(entry.value),
                              selected: selected,
                              onSelected:
                                  (enabled) => setState(() {
                                    if (enabled) {
                                      _days.add(entry.key);
                                    } else {
                                      _days.remove(entry.key);
                                    }
                                  }),
                            );
                          }).toList(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _startHour,
                          decoration: const InputDecoration(
                            labelText: 'С часа',
                          ),
                          items: [
                            for (var hour = 0; hour < 24; hour++)
                              DropdownMenuItem(
                                value: hour,
                                child: Text(
                                  '${hour.toString().padLeft(2, '0')}:00',
                                ),
                              ),
                          ],
                          onChanged:
                              (value) =>
                                  setState(() => _startHour = value ?? 0),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _endHour,
                          decoration: const InputDecoration(
                            labelText: 'До часа',
                          ),
                          items: [
                            for (var hour = 1; hour <= 24; hour++)
                              DropdownMenuItem(
                                value: hour,
                                child: Text(
                                  '${hour.toString().padLeft(2, '0')}:00',
                                ),
                              ),
                          ],
                          validator:
                              (value) =>
                                  (value ?? 24) == _startHour
                                      ? 'Выберите другой час'
                                      : null,
                          onChanged:
                              (value) => setState(() => _endHour = value ?? 24),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _status,
              decoration: const InputDecoration(labelText: 'Статус'),
              items: const [
                DropdownMenuItem(value: 'draft', child: Text('Черновик')),
                DropdownMenuItem(value: 'active', child: Text('Активна')),
                DropdownMenuItem(
                  value: 'paused',
                  child: Text('Приостановлена'),
                ),
              ],
              onChanged: (value) => setState(() => _status = value!),
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed:
                  _saving ||
                          (_startsAt != null &&
                              _endsAt != null &&
                              !_endsAt!.isAfter(_startsAt!))
                      ? null
                      : _save,
              child:
                  _saving
                      ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                      : const Text('Сохранить'),
            ),
          ],
        ),
      ),
    ),
  );
}

String? _moneyValidator(String? value) {
  final parsed = double.tryParse((value ?? '').trim().replaceAll(',', '.'));
  return parsed == null || parsed < 0 || parsed > 1000000000
      ? 'Число от 0 до 1 млрд'
      : null;
}

String _moneyInput(double value) => value == 0 ? '0' : value.toStringAsFixed(2);

String _money(double value) => value.toStringAsFixed(2);

String _dateLabel(DateTime value) {
  final date = value.toUtc();
  return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
}

String _budgetSummary(CampaignBudget budget) {
  final total =
      budget.hasTotalLimit
          ? '${_money(budget.spentTotal)} / ${_money(budget.total)}'
          : '${_money(budget.spentTotal)} потрачено · без общего лимита';
  final daily =
      budget.hasDailyLimit
          ? 'сегодня ${_money(budget.spentToday)} / ${_money(budget.dailyLimit)}'
          : 'дневной лимит не задан';
  return '$total · $daily';
}

String _scheduleSummary(CampaignSchedule schedule) {
  const names = {1: 'Пн', 2: 'Вт', 3: 'Ср', 4: 'Чт', 5: 'Пт', 6: 'Сб', 7: 'Вс'};
  final range = <String>[];
  if (schedule.startsAt != null) {
    range.add('с ${_dateLabel(schedule.startsAt!)}');
  }
  if (schedule.endsAt != null) range.add('до ${_dateLabel(schedule.endsAt!)}');
  final days =
      schedule.daysOfWeek.isEmpty
          ? 'ежедневно'
          : schedule.daysOfWeek.map((day) => names[day] ?? '$day').join(', ');
  final hours =
      '${schedule.startHour.toString().padLeft(2, '0')}:00–${schedule.endHour.toString().padLeft(2, '0')}:00 UTC';
  return [
    'Расписание:',
    if (range.isNotEmpty) range.join(' '),
    days,
    hours,
  ].join(' ');
}
