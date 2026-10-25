import 'package:ad_platform_mobile/src/core/app_theme.dart';
import 'package:ad_platform_mobile/src/state/providers.dart';
import 'package:ad_platform_mobile/src/ui/auth/auth_screen.dart';
import 'package:ad_platform_mobile/src/ui/home/home_shell.dart';
import 'package:ad_platform_mobile/src/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AdPlatformApp extends ConsumerWidget {
  const AdPlatformApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return MaterialApp(
      title: 'Ad Platform',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: switch (session.status) {
        SessionStatus.loading => const _SplashScreen(),
        SessionStatus.authenticated => const HomeShell(),
        SessionStatus.unauthenticated => const AuthScreen(),
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: AppColors.ink,
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppLogo(size: 72, dark: true),
          SizedBox(height: 22),
          Text(
            'AD PLATFORM',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.4,
            ),
          ),
          SizedBox(height: 28),
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppColors.teal,
            ),
          ),
        ],
      ),
    ),
  );
}
