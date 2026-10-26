import 'package:ad_platform_mobile/src/core/api_client.dart';
import 'package:ad_platform_mobile/src/data/ad_platform_repository.dart';
import 'package:ad_platform_mobile/src/domain/models.dart';
import 'package:ad_platform_mobile/src/state/providers.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoopTransport implements ApiTransport {
  @override
  Future<void> delete(String path) async => throw UnimplementedError();

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async =>
      throw UnimplementedError();

  @override
  Future<dynamic> post(
    String path, {
    Object? data,
    Map<String, dynamic>? query,
  }) async => throw UnimplementedError();

  @override
  Future<dynamic> put(String path, {Object? data}) async =>
      throw UnimplementedError();

  @override
  void setToken(String? value) {}

  @override
  Future<dynamic> upload(
    String path, {
    required String method,
    required Map<String, String> fields,
    required String filePath,
    required String fileName,
  }) async => throw UnimplementedError();
}

class _SessionRepository extends AdPlatformRepository {
  _SessionRepository({this.admin = false, this.failureStatus})
    : super(
        auth: _NoopTransport(),
        ads: _NoopTransport(),
        analytics: _NoopTransport(),
      );

  final bool admin;
  final int? failureStatus;

  static const administrator = AppUser(
    id: 10,
    email: 'admin@example.com',
    role: 'admin',
    roles: ['admin'],
    permissions: ['users.read'],
    mfaEnabled: true,
    workspaces: ['advertiser', 'admin'],
  );

  static const advertiser = AppUser(
    id: 11,
    email: 'user@example.com',
    role: 'user',
  );

  @override
  Future<AppUser?> restoreSession() async => null;

  @override
  Future<AppUser> login(String email, String password) async {
    if (failureStatus != null) {
      throw ApiException('HTTP $failureStatus', statusCode: failureStatus);
    }
    if (admin) {
      throw const MfaRequiredException(
        MfaChallenge(token: 'challenge', setupRequired: true, secret: 'SECRET'),
      );
    }
    return advertiser;
  }

  @override
  Future<({AppUser user, List<String> recoveryCodes})> confirmMfa(
    MfaChallenge challenge,
    String code,
  ) async => (user: administrator, recoveryCodes: const ['recovery-code']);
}

Future<void> _settleRestore() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'admin login requires MFA and opens admin workspace after confirmation',
    () async {
      final repository = _SessionRepository(admin: true);
      final controller = SessionController(repository);
      await _settleRestore();

      expect(await controller.login('admin@example.com', 'password'), isFalse);
      expect(controller.state.status, SessionStatus.mfaRequired);
      expect(controller.state.mfaChallenge?.setupRequired, isTrue);

      expect(await controller.confirmMfa('123456'), isTrue);
      expect(controller.state.status, SessionStatus.authenticated);
      expect(controller.state.workspace, AppWorkspace.admin);
      expect(controller.state.recoveryCodes, ['recovery-code']);
      controller.dispose();
      repository.dispose();
    },
  );

  test('ordinary user cannot switch into admin workspace', () async {
    final repository = _SessionRepository();
    final controller = SessionController(repository);
    await _settleRestore();

    expect(await controller.login('user@example.com', 'password'), isTrue);
    controller.switchWorkspace(AppWorkspace.admin);
    expect(controller.state.workspace, AppWorkspace.advertiser);
    controller.dispose();
    repository.dispose();
  });

  for (final status in [401, 403, 409]) {
    test('authentication exposes backend error $status', () async {
      final repository = _SessionRepository(failureStatus: status);
      final controller = SessionController(repository);
      await _settleRestore();

      expect(await controller.login('user@example.com', 'password'), isFalse);
      expect(controller.state.error, 'HTTP $status');
      controller.dispose();
      repository.dispose();
    });
  }
}
