import 'package:ad_platform_mobile/src/core/app_theme.dart';
import 'package:ad_platform_mobile/src/domain/models.dart';
import 'package:ad_platform_mobile/src/state/providers.dart';
import 'package:ad_platform_mobile/src/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class BillingScreen extends ConsumerWidget {
  const BillingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appDataProvider);
    return AdaptivePageBody(
      child: RefreshIndicator(
        onRefresh: ref.read(appDataProvider.notifier).refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            const SliverToBoxAdapter(
              child: PageHeader(
                title: 'Финансы',
                subtitle: 'Баланс и история операций',
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              sliver: SliverList.list(
                children: [
                  _WalletCard(
                    balance: data.balance,
                    onDeposit:
                        () => _showMoneySheet(context, ref, deposit: true),
                    onWithdraw:
                        () => _showMoneySheet(context, ref, deposit: false),
                  ),
                  const SizedBox(height: 25),
                  const SectionTitle('История операций'),
                  const SizedBox(height: 12),
                  if (data.transactions.isEmpty)
                    const EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'Операций пока нет',
                      message:
                          'Пополнения и списания будут отображаться здесь.',
                    )
                  else
                    SurfaceCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (
                            var i = 0;
                            i < data.transactions.length;
                            i++
                          ) ...[
                            _TransactionTile(item: data.transactions[i]),
                            if (i != data.transactions.length - 1)
                              const Divider(height: 1, indent: 68),
                          ],
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

class _WalletCard extends StatelessWidget {
  const _WalletCard({
    required this.balance,
    required this.onDeposit,
    required this.onWithdraw,
  });

  final double balance;
  final VoidCallback onDeposit;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(23),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF151936), Color(0xFF3C327D)],
      ),
      borderRadius: BorderRadius.circular(28),
      boxShadow: const [
        BoxShadow(
          color: Color(0x302D246A),
          blurRadius: 30,
          offset: Offset(0, 15),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'РАСЧЁТНЫЙ СЧЁТ',
              style: TextStyle(
                color: Colors.white.withValues(alpha: .58),
                fontSize: 11,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            const Icon(Icons.contactless_rounded, color: Colors.white54),
          ],
        ),
        const SizedBox(height: 27),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            moneyFormat.format(balance),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: -.7,
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Доступно для рекламы',
          style: TextStyle(color: Colors.white.withValues(alpha: .6)),
        ),
        const SizedBox(height: 25),
        LayoutBuilder(
          builder: (context, constraints) {
            final deposit = FilledButton.icon(
              onPressed: onDeposit,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.ink,
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Пополнить'),
            );
            final withdraw = OutlinedButton.icon(
              onPressed: onWithdraw,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: .24)),
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.arrow_upward_rounded),
              label: const Text('Вывести'),
            );
            if (constraints.maxWidth < 300) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [deposit, const SizedBox(height: 10), withdraw],
              );
            }
            return Row(
              children: [
                Expanded(child: deposit),
                const SizedBox(width: 10),
                Expanded(child: withdraw),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.item});

  final BillingTransaction item;

  @override
  Widget build(BuildContext context) {
    final color = item.isIncome ? AppColors.teal : AppColors.coral;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              item.isIncome
                  ? Icons.south_west_rounded
                  : Icons.north_east_rounded,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.description?.isNotEmpty == true
                      ? item.description!
                      : item.isIncome
                      ? 'Пополнение'
                      : 'Списание',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat(
                    'd MMM, HH:mm',
                    'ru_RU',
                  ).format(item.createdAt.toLocal()),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          Flexible(
            child: Text(
              '${item.isIncome ? '+' : '−'}${moneyFormat.format(item.amount)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showMoneySheet(
  BuildContext context,
  WidgetRef ref, {
  required bool deposit,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _MoneySheet(deposit: deposit, parentRef: ref),
);

class _MoneySheet extends StatefulWidget {
  const _MoneySheet({required this.deposit, required this.parentRef});
  final bool deposit;
  final WidgetRef parentRef;

  @override
  State<_MoneySheet> createState() => _MoneySheetState();
}

class _MoneySheetState extends State<_MoneySheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _description = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final amount = double.parse(_amount.text.replaceAll(',', '.'));
      final controller = widget.parentRef.read(appDataProvider.notifier);
      if (widget.deposit) {
        await controller.deposit(amount, _description.text);
      } else {
        await controller.withdraw(amount, _description.text);
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
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Container(
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
              widget.deposit ? 'Пополнить баланс' : 'Вывести средства',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Сумма',
                suffixText: '₽',
              ),
              validator: (value) {
                final parsed = double.tryParse(
                  (value ?? '').replaceAll(',', '.'),
                );
                return parsed == null || parsed <= 0
                    ? 'Введите сумму больше нуля'
                    : null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _description,
              decoration: const InputDecoration(
                labelText: 'Комментарий',
                hintText: 'Необязательно',
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
                      : Text(widget.deposit ? 'Пополнить' : 'Вывести'),
            ),
          ],
        ),
      ),
    ),
  );
}
