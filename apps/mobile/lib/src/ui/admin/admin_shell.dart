import 'package:ad_platform_mobile/src/core/app_theme.dart';
import 'package:ad_platform_mobile/src/domain/models.dart';
import 'package:ad_platform_mobile/src/state/providers.dart';
import 'package:ad_platform_mobile/src/ui/moderation/moderation_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class AdminShell extends ConsumerStatefulWidget {
  const AdminShell({super.key});

  @override
  ConsumerState<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<AdminShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(adminProvider.notifier).load();
      ref.read(moderationProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final destinations = const [
      NavigationDestination(
        icon: Icon(Icons.admin_panel_settings_outlined),
        selectedIcon: Icon(Icons.admin_panel_settings_rounded),
        label: 'Обзор',
      ),
      NavigationDestination(
        icon: Icon(Icons.group_outlined),
        selectedIcon: Icon(Icons.group_rounded),
        label: 'Люди',
      ),
      NavigationDestination(
        icon: Icon(Icons.fact_check_outlined),
        selectedIcon: Icon(Icons.fact_check_rounded),
        label: 'Модерация',
      ),
      NavigationDestination(
        icon: Icon(Icons.history_rounded),
        selectedIcon: Icon(Icons.manage_history_rounded),
        label: 'Аудит',
      ),
      NavigationDestination(
        icon: Icon(Icons.person_outline_rounded),
        selectedIcon: Icon(Icons.person_rounded),
        label: 'Профиль',
      ),
    ];
    final screens = const [
      _AdminOverview(),
      _AdminUsers(),
      ModerationScreen(),
      _AdminAudit(),
      _AdminProfile(),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        final content = IndexedStack(index: _index, children: screens);
        return Scaffold(
          appBar: AppBar(
            title: const Text('AD PLATFORM · ADMIN'),
            actions: [
              IconButton(
                tooltip: 'Обновить',
                onPressed: () => ref.read(adminProvider.notifier).load(),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          body:
              wide
                  ? Row(
                    children: [
                      NavigationRail(
                        selectedIndex: _index,
                        onDestinationSelected:
                            (value) => setState(() => _index = value),
                        extended: constraints.maxWidth >= 1180,
                        destinations:
                            destinations
                                .map(
                                  (item) => NavigationRailDestination(
                                    icon: item.icon,
                                    selectedIcon: item.selectedIcon,
                                    label: Text(item.label),
                                  ),
                                )
                                .toList(),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(child: content),
                    ],
                  )
                  : content,
          bottomNavigationBar:
              wide
                  ? null
                  : NavigationBar(
                    selectedIndex: _index,
                    onDestinationSelected:
                        (value) => setState(() => _index = value),
                    destinations: destinations,
                  ),
        );
      },
    );
  }
}

class _AdminOverview extends ConsumerWidget {
  const _AdminOverview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(adminProvider);
    final data = state.dashboard;
    return RefreshIndicator(
      onRefresh: ref.read(adminProvider.notifier).load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Администрирование',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 6),
          const Text(
            'Пользователи, безопасность и последние системные действия.',
          ),
          if (state.error != null) ...[
            const SizedBox(height: 16),
            _ErrorCard(message: state.error!),
          ],
          const SizedBox(height: 20),
          if (data == null && state.loading)
            const Center(child: CircularProgressIndicator())
          else if (data != null)
            LayoutBuilder(
              builder: (context, constraints) {
                final columns =
                    constraints.maxWidth >= 900
                        ? 4
                        : constraints.maxWidth >= 520
                        ? 2
                        : 1;
                final cards = [
                  _MetricCard('Всего', data.totalUsers, Icons.groups_rounded),
                  _MetricCard(
                    'Активные',
                    data.activeUsers,
                    Icons.verified_user_rounded,
                  ),
                  _MetricCard(
                    'Заблокированные',
                    data.blockedUsers,
                    Icons.block_rounded,
                  ),
                  _MetricCard(
                    'Новые за 7 дней',
                    data.newUsers,
                    Icons.person_add_alt_1_rounded,
                  ),
                  _MetricCard(
                    'Ожидают модерации',
                    data.pendingModeration,
                    Icons.fact_check_rounded,
                  ),
                  _MetricCard(
                    'Fraud-события',
                    data.fraudEvents,
                    Icons.gpp_bad_rounded,
                  ),
                ];
                return GridView.count(
                  crossAxisCount: columns,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: columns == 1 ? 2.35 : 1.65,
                  children: cards,
                );
              },
            ),
          const SizedBox(height: 24),
          Text(
            'Последние действия',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          if (data?.recentAudit.isEmpty ?? true)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('Административных действий пока нет.'),
              ),
            )
          else
            ...data!.recentAudit.map((item) => _AuditTile(item: item)),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(this.label, this.value, this.icon);
  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          CircleAvatar(radius: 25, child: Icon(icon)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$value',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(label),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _AdminUsers extends ConsumerStatefulWidget {
  const _AdminUsers();

  @override
  ConsumerState<_AdminUsers> createState() => _AdminUsersState();
}

class _AdminUsersState extends ConsumerState<_AdminUsers> {
  final _search = TextEditingController();
  String _status = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _searchUsers() => ref
      .read(adminProvider.notifier)
      .load(query: _search.text, status: _status);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(adminProvider);
    final list = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            children: [
              TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _searchUsers(),
                decoration: InputDecoration(
                  hintText: 'Email или ID',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: IconButton(
                    onPressed: _searchUsers,
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: '', label: Text('Все')),
                    ButtonSegment(value: 'active', label: Text('Активные')),
                    ButtonSegment(value: 'blocked', label: Text('Блок')),
                  ],
                  selected: {_status},
                  onSelectionChanged: (value) {
                    setState(() => _status = value.first);
                    _searchUsers();
                  },
                ),
              ),
            ],
          ),
        ),
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: _ErrorCard(message: state.error!),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _searchUsers,
            child:
                state.users.isEmpty
                    ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(child: Text('Пользователи не найдены')),
                      ],
                    )
                    : ListView.builder(
                      itemCount:
                          state.users.length +
                          (state.nextCursor == null ? 0 : 1),
                      itemBuilder: (context, index) {
                        if (index == state.users.length) {
                          return Padding(
                            padding: const EdgeInsets.all(16),
                            child: OutlinedButton(
                              onPressed:
                                  state.loading
                                      ? null
                                      : ref
                                          .read(adminProvider.notifier)
                                          .loadMore,
                              child: const Text('Показать ещё'),
                            ),
                          );
                        }
                        final user = state.users[index];
                        return ListTile(
                          selected: state.selectedUser?.id == user.id,
                          leading: CircleAvatar(
                            child: Text(
                              user.email.substring(0, 1).toUpperCase(),
                            ),
                          ),
                          title: Text(
                            user.email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            'ID ${user.id} · ${user.roles.join(', ')}',
                          ),
                          trailing: _StatusChip(status: user.status),
                          onTap: () async {
                            await ref
                                .read(adminProvider.notifier)
                                .selectUser(user.id);
                            if (context.mounted &&
                                MediaQuery.sizeOf(context).width < 900) {
                              showModalBottomSheet<void>(
                                context: context,
                                isScrollControlled: true,
                                useSafeArea: true,
                                builder:
                                    (_) => const FractionallySizedBox(
                                      heightFactor: .92,
                                      child: _UserDetails(),
                                    ),
                              );
                            }
                          },
                        );
                      },
                    ),
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) return list;
        return Row(
          children: [
            SizedBox(width: 430, child: list),
            const VerticalDivider(width: 1),
            const Expanded(child: _UserDetails()),
          ],
        );
      },
    );
  }
}

class _UserDetails extends ConsumerWidget {
  const _UserDetails();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(adminProvider).selectedUser;
    final actor = ref.watch(sessionProvider).user;
    if (user == null) return const Center(child: Text('Выберите пользователя'));
    final date = DateFormat('dd.MM.yyyy HH:mm');
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 28,
              child: Text(user.email.substring(0, 1).toUpperCase()),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.email,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text('ID ${user.id} · версия ${user.rowVersion}'),
                ],
              ),
            ),
            _StatusChip(status: user.status),
          ],
        ),
        const SizedBox(height: 20),
        _InfoLine('Роли', user.roles.join(', ')),
        _InfoLine('Регистрация', date.format(user.createdAt)),
        _InfoLine(
          'Последний вход',
          user.lastLoginAt == null
              ? 'Ещё не входил'
              : date.format(user.lastLoginAt!),
        ),
        _InfoLine('Баланс', '${user.balance.toStringAsFixed(2)} ₽'),
        _InfoLine('Кампании', '${user.campaigns}'),
        _InfoLine('Транзакции', '${user.transactions}'),
        _InfoLine('Активные сессии', '${user.activeSessions}'),
        _InfoLine('Fraud-события', '${user.fraudEvents}'),
        if (user.blockReason.isNotEmpty) _InfoLine('Причина', user.blockReason),
        const SizedBox(height: 18),
        if (actor?.can('users.block') == true ||
            actor?.can('users.sessions.revoke') == true ||
            actor?.can('users.roles.manage') == true)
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (actor?.can('users.block') == true) ...[
                if (user.isActive) ...[
                  FilledButton.tonalIcon(
                    onPressed: () => _statusAction(context, ref, user, 'block'),
                    icon: const Icon(Icons.block_rounded),
                    label: const Text('Заблокировать'),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        () => _statusAction(context, ref, user, 'suspend'),
                    icon: const Icon(Icons.timer_off_rounded),
                    label: const Text('Приостановить на 24 часа'),
                  ),
                ] else
                  FilledButton.tonalIcon(
                    onPressed:
                        () => _statusAction(context, ref, user, 'unblock'),
                    icon: const Icon(Icons.lock_open_rounded),
                    label: const Text('Разблокировать'),
                  ),
              ],
              if (actor?.can('users.sessions.revoke') == true)
                OutlinedButton.icon(
                  onPressed:
                      () => _securityAction(context, ref, user, 'sessions'),
                  icon: const Icon(Icons.devices_other_rounded),
                  label: const Text('Отозвать сессии'),
                ),
              if (actor?.can('users.sessions.revoke') == true)
                OutlinedButton.icon(
                  onPressed:
                      () => _securityAction(context, ref, user, 'password'),
                  icon: const Icon(Icons.password_rounded),
                  label: const Text('Сброс пароля'),
                ),
              if (actor?.can('users.roles.manage') == true)
                OutlinedButton.icon(
                  onPressed: () => _roleAction(context, ref, user),
                  icon: const Icon(Icons.manage_accounts_rounded),
                  label: const Text('Роли'),
                ),
            ],
          ),
        if (user.recentAudit.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            'История действий',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ...user.recentAudit.map((item) => _AuditTile(item: item)),
        ],
      ],
    );
  }

  Future<void> _statusAction(
    BuildContext context,
    WidgetRef ref,
    AdminUser user,
    String action,
  ) async {
    final title = switch (action) {
      'block' => 'Блокировка',
      'suspend' => 'Приостановка на 24 часа',
      _ => 'Разблокировка',
    };
    final confirmation = await _commandDialog(context, title);
    if (confirmation == null) return;
    try {
      await ref
          .read(adminProvider.notifier)
          .setStatus(
            user,
            action,
            reason: confirmation.reason,
            mfaCode: confirmation.code,
            suspendedUntil:
                action == 'suspend'
                    ? DateTime.now().toUtc().add(const Duration(hours: 24))
                    : null,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Изменение сохранено')));
      }
    } catch (_) {}
  }

  Future<void> _securityAction(
    BuildContext context,
    WidgetRef ref,
    AdminUser user,
    String action,
  ) async {
    final confirmation = await _commandDialog(
      context,
      action == 'sessions' ? 'Отзыв сессий' : 'Сброс пароля',
    );
    if (confirmation == null) return;
    try {
      if (action == 'sessions') {
        await ref
            .read(adminProvider.notifier)
            .revokeSessions(
              user,
              reason: confirmation.reason,
              mfaCode: confirmation.code,
            );
      } else {
        await ref
            .read(adminProvider.notifier)
            .requestPasswordReset(
              user,
              reason: confirmation.reason,
              mfaCode: confirmation.code,
            );
      }
    } catch (_) {}
  }

  Future<void> _roleAction(
    BuildContext context,
    WidgetRef ref,
    AdminUser user,
  ) async {
    final roles = [...user.roles];
    final selected = await showDialog<List<String>>(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setState) => AlertDialog(
                  title: const Text('Роли пользователя'),
                  content: SingleChildScrollView(
                    child: Column(
                      children:
                          const [
                                'user',
                                'moderator',
                                'support',
                                'finance_admin',
                                'admin',
                                'superadmin',
                              ]
                              .map(
                                (role) => CheckboxListTile(
                                  value: roles.contains(role),
                                  title: Text(role),
                                  onChanged:
                                      (value) => setState(() {
                                        if (value == true) {
                                          roles.add(role);
                                        } else {
                                          roles.remove(role);
                                        }
                                      }),
                                ),
                              )
                              .toList(),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Отмена'),
                    ),
                    FilledButton(
                      onPressed:
                          roles.isEmpty
                              ? null
                              : () => Navigator.pop(context, roles),
                      child: const Text('Продолжить'),
                    ),
                  ],
                ),
          ),
    );
    if (selected == null || !context.mounted) return;
    final confirmation = await _commandDialog(context, 'Изменение ролей');
    if (confirmation == null) return;
    try {
      await ref
          .read(adminProvider.notifier)
          .updateRoles(
            user,
            selected,
            reason: confirmation.reason,
            mfaCode: confirmation.code,
          );
    } catch (_) {}
  }
}

Future<({String reason, String code})?> _commandDialog(
  BuildContext context,
  String title,
) async {
  final reason = TextEditingController();
  final code = TextEditingController();
  final result = await showDialog<({String reason, String code})>(
    context: context,
    builder:
        (context) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: reason,
                maxLength: 500,
                decoration: const InputDecoration(labelText: 'Причина'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: code,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Код MFA'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                if (reason.text.trim().length >= 3 &&
                    code.text.trim().length >= 6) {
                  Navigator.pop(context, (
                    reason: reason.text.trim(),
                    code: code.text.trim(),
                  ));
                }
              },
              child: const Text('Подтвердить'),
            ),
          ],
        ),
  );
  reason.dispose();
  code.dispose();
  return result;
}

class _AdminAudit extends ConsumerWidget {
  const _AdminAudit();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(adminProvider);
    return RefreshIndicator(
      onRefresh: ref.read(adminProvider.notifier).load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Журнал аудита',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 6),
          const Text('Неизменяемая история административных операций.'),
          const SizedBox(height: 18),
          if (state.audit.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('Записей нет.'),
              ),
            )
          else
            ...state.audit.map((item) => _AuditTile(item: item)),
        ],
      ),
    );
  }
}

class _AuditTile extends StatelessWidget {
  const _AuditTile({required this.item});
  final AdminAuditEvent item;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.security_rounded),
      title: Text(item.action),
      subtitle: Text(
        'Цель: ${item.targetType} #${item.targetId}\n${item.reason}\n'
        '${DateFormat('dd.MM.yyyy HH:mm').format(item.createdAt)}',
      ),
      isThreeLine: true,
    ),
  );
}

class _AdminProfile extends ConsumerWidget {
  const _AdminProfile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final user = session.user!;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Администратор',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.email, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('Роли: ${user.roles.join(', ')}'),
                Text(
                  'MFA: ${user.mfaEnabled ? 'подключена' : 'не подключена'}',
                ),
              ],
            ),
          ),
        ),
        if (session.recoveryCodes.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            color: AppColors.coral.withValues(alpha: .08),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Сохраните recovery-коды',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(session.recoveryCodes.join('\n')),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed:
              () => ref
                  .read(sessionProvider.notifier)
                  .switchWorkspace(AppWorkspace.advertiser),
          icon: const Icon(Icons.campaign_outlined),
          label: const Text('Рабочее пространство рекламодателя'),
        ),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          onPressed: ref.read(sessionProvider.notifier).logoutAll,
          icon: const Icon(Icons.phonelink_erase_rounded),
          label: const Text('Выйти на всех устройствах'),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'active' => AppColors.teal,
      'blocked' => AppColors.coral,
      'suspended' => Colors.orange,
      _ => Colors.grey,
    };
    return Chip(
      visualDensity: VisualDensity.compact,
      backgroundColor: color.withValues(alpha: .12),
      label: Text(
        status,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(label, style: const TextStyle(color: Colors.black54)),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Card(
    color: AppColors.coral.withValues(alpha: .08),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Text(message, style: const TextStyle(color: AppColors.coral)),
    ),
  );
}
