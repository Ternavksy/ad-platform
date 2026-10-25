import 'package:ad_platform_mobile/src/core/app_theme.dart';
import 'package:ad_platform_mobile/src/domain/models.dart';
import 'package:ad_platform_mobile/src/state/providers.dart';
import 'package:ad_platform_mobile/src/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SitesScreen extends ConsumerWidget {
  const SitesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appDataProvider);
    final formats = {for (final item in data.formats) item.id: item};
    return Scaffold(
      appBar: AppBar(
        title: const Text('Площадки'),
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showSiteEditor(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Площадка'),
      ),
      body: AdaptivePageBody(
        child: RefreshIndicator(
          onRefresh: ref.read(appDataProvider.notifier).refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
            children: [
              Text(
                'Сайты и приложения, где показывается реклама',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              if (data.sites.isEmpty)
                EmptyState(
                  icon: Icons.language_rounded,
                  title: 'Площадок пока нет',
                  message:
                      'Добавьте сайт, затем создайте рекламные места нужных форматов.',
                  action: FilledButton.icon(
                    onPressed: () => _showSiteEditor(context, ref),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Добавить площадку'),
                  ),
                )
              else
                ...data.sites.map(
                  (site) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _SiteCard(
                      site: site,
                      placements:
                          data.placementsBySite[site.id] ?? const <Placement>[],
                      formats: formats,
                      onAddPlacement:
                          () => _showPlacementEditor(context, ref, site: site),
                      onEdit: () => _showSiteEditor(context, ref, item: site),
                      onDelete: () async {
                        if (!await confirmAction(
                          context,
                          title: 'Удалить площадку?',
                          message:
                              'Все её рекламные места также будут удалены.',
                        )) {
                          return;
                        }
                        try {
                          await ref
                              .read(appDataProvider.notifier)
                              .deleteSite(site.id);
                        } catch (error) {
                          if (context.mounted) {
                            showMessage(context, error.toString(), error: true);
                          }
                        }
                      },
                      onEditPlacement:
                          (item) => _showPlacementEditor(
                            context,
                            ref,
                            site: site,
                            item: item,
                          ),
                      onDeletePlacement: (item) async {
                        if (!await confirmAction(
                          context,
                          title: 'Удалить рекламное место?',
                          message:
                              'Объявления потеряют привязку к этому месту.',
                        )) {
                          return;
                        }
                        try {
                          await ref
                              .read(appDataProvider.notifier)
                              .deletePlacement(item.id);
                        } catch (error) {
                          if (context.mounted) {
                            showMessage(context, error.toString(), error: true);
                          }
                        }
                      },
                    ),
                  ),
                ),
              if (data.formats.isNotEmpty) ...[
                const SizedBox(height: 14),
                const SectionTitle('Доступные форматы'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      data.formats
                          .map(
                            (item) => Chip(
                              avatar: Icon(
                                _formatIcon(item.kind),
                                size: 17,
                                color: AppColors.primary,
                              ),
                              label: Text('${item.name} · ${item.sizeLabel}'),
                            ),
                          )
                          .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SiteCard extends StatelessWidget {
  const _SiteCard({
    required this.site,
    required this.placements,
    required this.formats,
    required this.onAddPlacement,
    required this.onEdit,
    required this.onDelete,
    required this.onEditPlacement,
    required this.onDeletePlacement,
  });

  final Site site;
  final List<Placement> placements;
  final Map<int, AdFormat> formats;
  final VoidCallback onAddPlacement;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<Placement> onEditPlacement;
  final ValueChanged<Placement> onDeletePlacement;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: .09),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.language_rounded,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    site.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 3),
                  Text(site.domain, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            StatusBadge(active: site.isActive),
            PopupMenuButton<String>(
              onSelected: (value) => value == 'edit' ? onEdit() : onDelete(),
              itemBuilder:
                  (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Редактировать')),
                    PopupMenuItem(value: 'delete', child: Text('Удалить')),
                  ],
            ),
          ],
        ),
        const Divider(height: 28),
        Row(
          children: [
            Expanded(
              child: Text(
                'Рекламные места · ${placements.length}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            TextButton.icon(
              onPressed: onAddPlacement,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Добавить'),
            ),
          ],
        ),
        if (placements.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Создайте место и выберите его формат.'),
          )
        else
          ...placements.map((item) {
            final format = formats[item.formatId];
            return Container(
              margin: const EdgeInsets.only(top: 9),
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    _formatIcon(format?.kind ?? 'banner'),
                    size: 20,
                    color: AppColors.teal,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${format?.name ?? 'Формат'} · ${format?.sizeLabel ?? ''}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 2),
                        GestureDetector(
                          onTap: () async {
                            await Clipboard.setData(
                              ClipboardData(text: item.code),
                            );
                            if (context.mounted) {
                              showMessage(context, 'Код места скопирован');
                            }
                          },
                          child: Text(
                            item.code,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  StatusBadge(active: item.isActive),
                  PopupMenuButton<String>(
                    onSelected:
                        (value) =>
                            value == 'edit'
                                ? onEditPlacement(item)
                                : onDeletePlacement(item),
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
            );
          }),
      ],
    ),
  );
}

IconData _formatIcon(String kind) => switch (kind) {
  'native' => Icons.view_stream_outlined,
  'story' => Icons.smartphone_rounded,
  'video' => Icons.play_circle_outline_rounded,
  _ => Icons.crop_landscape_rounded,
};

Future<void> _showSiteEditor(
  BuildContext context,
  WidgetRef ref, {
  Site? item,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _SiteEditor(item: item, parentRef: ref),
);

class _SiteEditor extends StatefulWidget {
  const _SiteEditor({required this.item, required this.parentRef});
  final Site? item;
  final WidgetRef parentRef;

  @override
  State<_SiteEditor> createState() => _SiteEditorState();
}

class _SiteEditorState extends State<_SiteEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _domain;
  late String _status;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.item?.name);
    _domain = TextEditingController(text: widget.item?.domain);
    _status = widget.item?.status ?? 'active';
  }

  @override
  void dispose() {
    _name.dispose();
    _domain.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final controller = widget.parentRef.read(appDataProvider.notifier);
      if (widget.item == null) {
        await controller.createSite(_name.text, _domain.text, _status);
      } else {
        await controller.updateSite(
          widget.item!,
          _name.text,
          _domain.text,
          _status,
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
  Widget build(BuildContext context) => _InventorySheet(
    title: widget.item == null ? 'Новая площадка' : 'Редактировать площадку',
    child: Form(
      key: _formKey,
      child: Column(
        children: [
          TextFormField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Название'),
            validator:
                (value) =>
                    value?.trim().isEmpty ?? true ? 'Введите название' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _domain,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Домен',
              hintText: 'example.com',
            ),
            validator: (value) {
              final domain = value?.trim() ?? '';
              return domain.isEmpty || domain.contains(' ')
                  ? 'Введите домен площадки'
                  : null;
            },
          ),
          const SizedBox(height: 16),
          _StatusField(value: _status, onChanged: (value) => _status = value),
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

Future<void> _showPlacementEditor(
  BuildContext context,
  WidgetRef ref, {
  required Site site,
  Placement? item,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _PlacementEditor(site: site, item: item, parentRef: ref),
);

class _PlacementEditor extends StatefulWidget {
  const _PlacementEditor({
    required this.site,
    required this.item,
    required this.parentRef,
  });
  final Site site;
  final Placement? item;
  final WidgetRef parentRef;

  @override
  State<_PlacementEditor> createState() => _PlacementEditorState();
}

class _PlacementEditorState extends State<_PlacementEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late int? _formatId;
  late String _status;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.item?.name);
    _formatId = widget.item?.formatId;
    _status = widget.item?.status ?? 'active';
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final controller = widget.parentRef.read(appDataProvider.notifier);
      if (widget.item == null) {
        await controller.createPlacement(
          widget.site.id,
          _formatId!,
          _name.text,
          _status,
        );
      } else {
        await controller.updatePlacement(
          widget.item!,
          _formatId!,
          _name.text,
          _status,
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
    final formats = widget.parentRef.read(appDataProvider).formats;
    return _InventorySheet(
      title:
          widget.item == null ? 'Новое рекламное место' : 'Редактировать место',
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            TextFormField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Название места'),
              validator:
                  (value) =>
                      value?.trim().isEmpty ?? true ? 'Введите название' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              value: _formatId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Формат'),
              items:
                  formats
                      .where((item) => item.isActive)
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(
                            '${item.name} · ${item.sizeLabel}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
              onChanged: (value) => setState(() => _formatId = value),
              validator: (value) => value == null ? 'Выберите формат' : null,
            ),
            const SizedBox(height: 16),
            _StatusField(value: _status, onChanged: (value) => _status = value),
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

class _StatusField extends StatelessWidget {
  const _StatusField({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    value: value,
    decoration: const InputDecoration(labelText: 'Статус'),
    items: const [
      DropdownMenuItem(value: 'draft', child: Text('Черновик')),
      DropdownMenuItem(value: 'active', child: Text('Активно')),
      DropdownMenuItem(value: 'paused', child: Text('Приостановлено')),
    ],
    onChanged: (value) => onChanged(value!),
  );
}

class _InventorySheet extends StatelessWidget {
  const _InventorySheet({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        22,
        22,
        22,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 20),
          child,
        ],
      ),
    ),
  );
}
