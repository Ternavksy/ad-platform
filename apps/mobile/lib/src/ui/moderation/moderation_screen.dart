import 'package:ad_platform_mobile/src/core/api_config.dart';
import 'package:ad_platform_mobile/src/core/app_theme.dart';
import 'package:ad_platform_mobile/src/domain/models.dart';
import 'package:ad_platform_mobile/src/state/providers.dart';
import 'package:ad_platform_mobile/src/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class ModerationScreen extends ConsumerStatefulWidget {
  const ModerationScreen({super.key});

  @override
  ConsumerState<ModerationScreen> createState() => _ModerationScreenState();
}

class _ModerationScreenState extends ConsumerState<ModerationScreen> {
  static const _statuses = {
    'pending': 'На проверке',
    'approved': 'Одобренные',
    'rejected': 'Отклонённые',
  };

  @override
  void initState() {
    super.initState();
    Future.microtask(ref.read(moderationProvider.notifier).load);
  }

  Future<void> _review(
    Creative creative,
    String decision, {
    String reason = '',
  }) async {
    try {
      await ref
          .read(moderationProvider.notifier)
          .review(creative.id, decision, reason: reason);
      if (mounted) {
        showMessage(
          context,
          decision == 'approved' ? 'Креатив одобрен.' : 'Креатив отклонён.',
        );
      }
    } catch (error) {
      if (mounted) showMessage(context, error.toString(), error: true);
    }
  }

  Future<void> _reject(Creative creative) async {
    final reason = await _askRejectionReason(context);
    if (reason != null) {
      await _review(creative, 'rejected', reason: reason);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(moderationProvider);
    return AdaptivePageBody(
      child: RefreshIndicator(
        onRefresh: ref.read(moderationProvider.notifier).load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            const SliverToBoxAdapter(
              child: PageHeader(
                title: 'Модерация',
                subtitle: 'Проверка рекламных креативов',
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 14),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      _statuses.entries
                          .map(
                            (entry) => ChoiceChip(
                              label: Text(entry.value),
                              selected: state.status == entry.key,
                              onSelected:
                                  state.loading
                                      ? null
                                      : (_) => ref
                                          .read(moderationProvider.notifier)
                                          .load(entry.key),
                            ),
                          )
                          .toList(),
                ),
              ),
            ),
            if (state.loading && state.items.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (state.error != null && state.items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.error_outline,
                  title: 'Не удалось загрузить креативы',
                  message: state.error!,
                  action: FilledButton(
                    onPressed:
                        () => ref.read(moderationProvider.notifier).load(),
                    child: const Text('Повторить'),
                  ),
                ),
              )
            else if (state.items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.fact_check_outlined,
                  title: 'Список пуст',
                  message:
                      state.status == 'pending'
                          ? 'Новых креативов для проверки нет.'
                          : 'В этой категории пока нет креативов.',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 30),
                sliver: SliverList.separated(
                  itemCount: state.items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final creative = state.items[index];
                    return _ModerationCard(
                      creative: creative,
                      processing: state.processingId == creative.id,
                      onApprove: () => _review(creative, 'approved'),
                      onReject: () => _reject(creative),
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

class _ModerationCard extends StatelessWidget {
  const _ModerationCard({
    required this.creative,
    required this.processing,
    required this.onApprove,
    required this.onReject,
  });

  final Creative creative;
  final bool processing;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MediaPreview(media: creative.media),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ModerationBadge(status: creative.moderationStatus),
                  const SizedBox(height: 8),
                  Text(
                    creative.content.isEmpty
                        ? creative.media.fileName
                        : creative.content,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _MetadataRow(
          icon: Icons.campaign_outlined,
          text:
              creative.campaignName.isEmpty
                  ? 'Кампания не указана'
                  : creative.campaignName,
        ),
        const SizedBox(height: 6),
        _MetadataRow(
          icon: Icons.ads_click_outlined,
          text:
              creative.adTitle.isEmpty
                  ? 'Объявление #${creative.adId}'
                  : creative.adTitle,
        ),
        if (creative.submittedAt != null) ...[
          const SizedBox(height: 6),
          _MetadataRow(
            icon: Icons.schedule_outlined,
            text:
                'Отправлен ${DateFormat('dd.MM.yyyy, HH:mm').format(creative.submittedAt!)}',
          ),
        ],
        if (creative.moderationReason.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.coral.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              creative.moderationReason,
              style: const TextStyle(color: AppColors.ink, height: 1.35),
            ),
          ),
        ],
        if (creative.isPending) ...[
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final reject = OutlinedButton.icon(
                onPressed: processing ? null : onReject,
                icon: const Icon(Icons.close_rounded),
                label: const Text('Отклонить'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.coral,
                  minimumSize: const Size(0, 48),
                ),
              );
              final approve = FilledButton.icon(
                onPressed: processing ? null : onApprove,
                icon:
                    processing
                        ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                        : const Icon(Icons.check_rounded),
                label: const Text('Одобрить'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.teal,
                  minimumSize: const Size(0, 48),
                ),
              );
              if (constraints.maxWidth < 300) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [reject, const SizedBox(height: 8), approve],
                );
              }
              return Row(
                children: [
                  Expanded(child: reject),
                  const SizedBox(width: 10),
                  Expanded(child: approve),
                ],
              );
            },
          ),
        ],
      ],
    ),
  );
}

class _MediaPreview extends StatelessWidget {
  const _MediaPreview({required this.media});

  final CreativeMedia media;

  @override
  Widget build(BuildContext context) {
    if (media.isImage && media.url.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.network(
          ApiConfig.resolveAdsUrl(media.url),
          width: 78,
          height: 78,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _placeholder(Icons.broken_image_outlined),
        ),
      );
    }
    return _placeholder(
      media.isVideo ? Icons.play_circle_outline : Icons.text_fields_rounded,
    );
  }

  Widget _placeholder(IconData icon) => Container(
    width: 78,
    height: 78,
    decoration: BoxDecoration(
      color: AppColors.primary.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Icon(icon, color: AppColors.primary, size: 32),
  );
}

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 16, color: AppColors.muted),
      const SizedBox(width: 7),
      Expanded(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
      ),
    ],
  );
}

Future<String?> _askRejectionReason(BuildContext context) async {
  final controller = TextEditingController();
  final formKey = GlobalKey<FormState>();
  final result = await showDialog<String>(
    context: context,
    builder:
        (context) => AlertDialog(
          title: const Text('Причина отклонения'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              autofocus: true,
              minLines: 3,
              maxLines: 5,
              maxLength: 500,
              decoration: const InputDecoration(
                hintText: 'Что нужно исправить в креативе',
              ),
              validator:
                  (value) =>
                      (value?.trim().isEmpty ?? true)
                          ? 'Укажите причину'
                          : null,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context, controller.text.trim());
                }
              },
              style: FilledButton.styleFrom(backgroundColor: AppColors.coral),
              child: const Text('Отклонить'),
            ),
          ],
        ),
  );
  controller.dispose();
  return result;
}
