import 'package:ad_platform_mobile/src/core/app_theme.dart';
import 'package:ad_platform_mobile/src/state/providers.dart';
import 'package:ad_platform_mobile/src/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class MfaScreen extends ConsumerStatefulWidget {
  const MfaScreen({super.key});

  @override
  ConsumerState<MfaScreen> createState() => _MfaScreenState();
}

class _MfaScreenState extends ConsumerState<MfaScreen> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_code.text.trim().length < 6) return;
    await ref.read(sessionProvider.notifier).confirmMfa(_code.text);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final challenge = session.mfaChallenge;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: ref.read(sessionProvider.notifier).cancelMfa,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Защищённый вход'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.admin_panel_settings_rounded, size: 52),
                      const SizedBox(height: 18),
                      Text(
                        challenge?.setupRequired == true
                            ? 'Настройте двухфакторную защиту'
                            : 'Подтвердите вход',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        challenge?.setupRequired == true
                            ? 'Добавьте ключ в приложение-аутентификатор и введите полученный код.'
                            : 'Введите код из приложения-аутентификатора или одноразовый recovery-код.',
                        textAlign: TextAlign.center,
                      ),
                      if (challenge?.secret != null) ...[
                        const SizedBox(height: 18),
                        SelectableText(
                          challenge!.secret!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.4,
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      TextField(
                        controller: _code,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _confirm(),
                        decoration: const InputDecoration(
                          labelText: 'Код подтверждения',
                          prefixIcon: Icon(Icons.password_rounded),
                        ),
                      ),
                      if (session.error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          session.error!,
                          style: const TextStyle(color: AppColors.coral),
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: session.submitting ? null : _confirm,
                        icon:
                            session.submitting
                                ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                                : const Icon(Icons.verified_user_rounded),
                        label: const Text('Подтвердить'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final controller = ref.read(sessionProvider.notifier);
    if (_register) {
      await controller.register(_email.text, _password.text);
    } else {
      await controller.login(_email.text, _password.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    return Scaffold(
      body: Stack(
        children: [
          Container(
            height: 310,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF171A3A), Color(0xFF5946D7)],
              ),
            ),
          ),
          Positioned(
            right: -70,
            top: -45,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: .08),
                  width: 32,
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          AppLogo(size: 46, dark: true),
                          SizedBox(width: 13),
                          Text(
                            'AD PLATFORM',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 38),
                      Text(
                        _register
                            ? 'Создайте аккаунт'
                            : 'Управляйте рекламой\nв одном месте',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          height: 1.12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _register
                            ? 'Несколько шагов — и рабочее пространство готово.'
                            : 'Кампании, расходы и аналитика всегда под рукой.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .72),
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 34),
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x1A101828),
                              blurRadius: 30,
                              offset: Offset(0, 14),
                            ),
                          ],
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: AppColors.background,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  children: [
                                    _ModeButton(
                                      label: 'Вход',
                                      selected: !_register,
                                      onTap:
                                          () =>
                                              setState(() => _register = false),
                                    ),
                                    _ModeButton(
                                      label: 'Регистрация',
                                      selected: _register,
                                      onTap:
                                          () =>
                                              setState(() => _register = true),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 22),
                              Text(
                                'Email',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _email,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                autocorrect: false,
                                decoration: const InputDecoration(
                                  hintText: 'name@company.ru',
                                  prefixIcon: Icon(
                                    Icons.alternate_email_rounded,
                                  ),
                                ),
                                validator: (value) {
                                  final text = value?.trim() ?? '';
                                  if (!text.contains('@') ||
                                      !text.contains('.')) {
                                    return 'Введите корректный email';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Пароль',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _password,
                                obscureText: _obscure,
                                onFieldSubmitted: (_) => _submit(),
                                decoration: InputDecoration(
                                  hintText: 'Минимум 6 символов',
                                  prefixIcon: const Icon(
                                    Icons.lock_outline_rounded,
                                  ),
                                  suffixIcon: IconButton(
                                    onPressed:
                                        () => setState(
                                          () => _obscure = !_obscure,
                                        ),
                                    icon: Icon(
                                      _obscure
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                  ),
                                ),
                                validator:
                                    (value) =>
                                        (value?.length ?? 0) < 6
                                            ? 'Пароль должен содержать минимум 6 символов'
                                            : null,
                              ),
                              if (session.error != null) ...[
                                const SizedBox(height: 14),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.coral.withValues(
                                      alpha: .09,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    session.error!,
                                    style: const TextStyle(
                                      color: AppColors.coral,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 22),
                              FilledButton(
                                onPressed: session.submitting ? null : _submit,
                                child:
                                    session.submitting
                                        ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.4,
                                            color: Colors.white,
                                          ),
                                        )
                                        : Text(
                                          _register
                                              ? 'Создать аккаунт'
                                              : 'Войти',
                                        ),
                              ),
                              const SizedBox(height: 16),
                              const Row(
                                children: [
                                  Icon(
                                    Icons.shield_outlined,
                                    size: 16,
                                    color: AppColors.teal,
                                  ),
                                  SizedBox(width: 7),
                                  Expanded(
                                    child: Text(
                                      'Токен хранится в защищённом хранилище устройства',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.muted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          boxShadow:
              selected
                  ? const [BoxShadow(color: Color(0x11000000), blurRadius: 8)]
                  : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? AppColors.ink : AppColors.muted,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
  );
}
