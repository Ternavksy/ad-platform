import 'package:ad_platform_mobile/src/data/ad_platform_repository.dart';
import 'package:ad_platform_mobile/src/domain/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final repositoryProvider = Provider<AdPlatformRepository>(
  (ref) => AdPlatformRepository(),
);

enum SessionStatus { loading, authenticated, unauthenticated }

class SessionState {
  const SessionState({
    this.status = SessionStatus.loading,
    this.user,
    this.error,
    this.submitting = false,
  });

  final SessionStatus status;
  final AppUser? user;
  final String? error;
  final bool submitting;

  SessionState copyWith({
    SessionStatus? status,
    AppUser? user,
    String? error,
    bool? submitting,
    bool clearError = false,
  }) => SessionState(
    status: status ?? this.status,
    user: user ?? this.user,
    error: clearError ? null : error ?? this.error,
    submitting: submitting ?? this.submitting,
  );
}

class SessionController extends StateNotifier<SessionState> {
  SessionController(this._repository) : super(const SessionState()) {
    _restore();
  }

  final AdPlatformRepository _repository;

  Future<void> _restore() async {
    final user = await _repository.restoreSession();
    state = SessionState(
      status:
          user == null
              ? SessionStatus.unauthenticated
              : SessionStatus.authenticated,
      user: user,
    );
  }

  Future<bool> login(String email, String password) async {
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final user = await _repository.login(email, password);
      state = SessionState(status: SessionStatus.authenticated, user: user);
      return true;
    } catch (error) {
      state = state.copyWith(submitting: false, error: error.toString());
      return false;
    }
  }

  Future<bool> register(String email, String password) async {
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final user = await _repository.register(email, password);
      state = SessionState(status: SessionStatus.authenticated, user: user);
      return true;
    } catch (error) {
      state = state.copyWith(submitting: false, error: error.toString());
      return false;
    }
  }

  Future<void> logout() async {
    await _repository.logout();
    state = const SessionState(status: SessionStatus.unauthenticated);
  }
}

final sessionProvider = StateNotifierProvider<SessionController, SessionState>(
  (ref) => SessionController(ref.watch(repositoryProvider)),
);

class AppDataState {
  const AppDataState({
    this.loading = false,
    this.balance = 0,
    this.campaigns = const [],
    this.adsByCampaign = const {},
    this.creativesByAd = const {},
    this.transactions = const [],
    this.analytics = const [],
    this.sites = const [],
    this.formats = const [],
    this.placementsBySite = const {},
    this.error,
  });

  final bool loading;
  final double balance;
  final List<Campaign> campaigns;
  final Map<int, List<AdItem>> adsByCampaign;
  final Map<int, List<Creative>> creativesByAd;
  final List<BillingTransaction> transactions;
  final List<AnalyticsPoint> analytics;
  final List<Site> sites;
  final List<AdFormat> formats;
  final Map<int, List<Placement>> placementsBySite;
  final String? error;

  List<AdItem> get allAds =>
      adsByCampaign.values.expand((items) => items).toList();
  List<Creative> get allCreatives =>
      creativesByAd.values.expand((items) => items).toList();
  List<Placement> get allPlacements =>
      placementsBySite.values.expand((items) => items).toList();

  AppDataState copyWith({
    bool? loading,
    double? balance,
    List<Campaign>? campaigns,
    Map<int, List<AdItem>>? adsByCampaign,
    Map<int, List<Creative>>? creativesByAd,
    List<BillingTransaction>? transactions,
    List<AnalyticsPoint>? analytics,
    List<Site>? sites,
    List<AdFormat>? formats,
    Map<int, List<Placement>>? placementsBySite,
    String? error,
    bool clearError = false,
  }) => AppDataState(
    loading: loading ?? this.loading,
    balance: balance ?? this.balance,
    campaigns: campaigns ?? this.campaigns,
    adsByCampaign: adsByCampaign ?? this.adsByCampaign,
    creativesByAd: creativesByAd ?? this.creativesByAd,
    transactions: transactions ?? this.transactions,
    analytics: analytics ?? this.analytics,
    sites: sites ?? this.sites,
    formats: formats ?? this.formats,
    placementsBySite: placementsBySite ?? this.placementsBySite,
    error: clearError ? null : error ?? this.error,
  );
}

class AppDataController extends StateNotifier<AppDataState> {
  AppDataController(this._repository) : super(const AppDataState());

  final AdPlatformRepository _repository;
  int? _userId;

  Future<void> load(int userId) async {
    _userId = userId;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final results = await Future.wait<dynamic>([
        _repository.getBalance(userId),
        _repository.getTransactions(userId),
        _repository.getCampaigns(userId),
        _repository.getSites(userId),
        _repository.getFormats(),
      ]);
      final campaigns = results[2] as List<Campaign>;
      final sites = results[3] as List<Site>;
      final placementsEntries = await Future.wait(
        sites.map(
          (site) async =>
              MapEntry(site.id, await _repository.getPlacements(site.id)),
        ),
      );
      final adsEntries = await Future.wait(
        campaigns.map(
          (campaign) async =>
              MapEntry(campaign.id, await _repository.getAds(campaign.id)),
        ),
      );
      final adsByCampaign = Map<int, List<AdItem>>.fromEntries(adsEntries);
      final creativesEntries = await Future.wait(
        adsByCampaign.values
            .expand((items) => items)
            .map(
              (ad) async =>
                  MapEntry(ad.id, await _repository.getCreatives(ad.id)),
            ),
      );
      List<AnalyticsPoint> analytics;
      try {
        analytics = await _repository.getCampaignAnalytics();
      } catch (_) {
        analytics = const [];
      }
      state = AppDataState(
        balance: results[0] as double,
        transactions: results[1] as List<BillingTransaction>,
        campaigns: campaigns,
        adsByCampaign: adsByCampaign,
        creativesByAd: Map<int, List<Creative>>.fromEntries(creativesEntries),
        analytics: analytics,
        sites: sites,
        formats: results[4] as List<AdFormat>,
        placementsBySite: Map<int, List<Placement>>.fromEntries(
          placementsEntries,
        ),
      );
    } catch (error) {
      state = state.copyWith(loading: false, error: error.toString());
    }
  }

  Future<void> refresh() async {
    if (_userId != null) await load(_userId!);
  }

  void reset() {
    _userId = null;
    state = const AppDataState();
  }

  Future<void> createCampaign(
    String name,
    String status,
    CampaignBudget budget,
    CampaignSchedule schedule,
  ) async {
    await _repository.createCampaign(_userId!, name, status, budget, schedule);
    await refresh();
  }

  Future<void> updateCampaign(
    Campaign item,
    String name,
    String status,
    CampaignBudget budget,
    CampaignSchedule schedule,
  ) async {
    await _repository.updateCampaign(item, name, status, budget, schedule);
    await refresh();
  }

  Future<void> deleteCampaign(int id) async {
    await _repository.deleteCampaign(id);
    await refresh();
  }

  Future<void> createAd(
    int campaignId,
    String title,
    String status,
    String placement,
    String destinationUrl,
    int weight,
    double bidCpm,
    int? placementId,
    AdTargeting targeting,
  ) async {
    await _repository.createAd(
      campaignId,
      title,
      status,
      placement,
      destinationUrl,
      weight,
      bidCpm,
      placementId,
      targeting,
    );
    await refresh();
  }

  Future<void> updateAd(
    AdItem item,
    String title,
    String status,
    String placement,
    String destinationUrl,
    int weight,
    double bidCpm,
    int? placementId,
    AdTargeting targeting,
  ) async {
    await _repository.updateAd(
      item,
      title,
      status,
      placement,
      destinationUrl,
      weight,
      bidCpm,
      placementId,
      targeting,
    );
    await refresh();
  }

  Future<void> deleteAd(int id) async {
    await _repository.deleteAd(id);
    await refresh();
  }

  Future<void> createSite(String name, String domain, String status) async {
    await _repository.createSite(_userId!, name, domain, status);
    await refresh();
  }

  Future<void> updateSite(
    Site item,
    String name,
    String domain,
    String status,
  ) async {
    await _repository.updateSite(item, name, domain, status);
    await refresh();
  }

  Future<void> deleteSite(int id) async {
    await _repository.deleteSite(id);
    await refresh();
  }

  Future<void> createPlacement(
    int siteId,
    int formatId,
    String name,
    String status,
  ) async {
    await _repository.createPlacement(siteId, formatId, name, status);
    await refresh();
  }

  Future<void> updatePlacement(
    Placement item,
    int formatId,
    String name,
    String status,
  ) async {
    await _repository.updatePlacement(item, formatId, name, status);
    await refresh();
  }

  Future<void> deletePlacement(int id) async {
    await _repository.deletePlacement(id);
    await refresh();
  }

  Future<void> createCreative(int adId, String content) async {
    await _repository.createCreative(adId, content);
    await refresh();
  }

  Future<void> createCreativeWithMedia(
    int adId,
    String content,
    String filePath,
    String fileName,
  ) async {
    await _repository.createCreativeWithMedia(
      adId,
      content,
      filePath,
      fileName,
    );
    await refresh();
  }

  Future<void> updateCreative(Creative item, String content) async {
    await _repository.updateCreative(item, content);
    await refresh();
  }

  Future<void> updateCreativeWithMedia(
    Creative item,
    String content,
    String filePath,
    String fileName,
  ) async {
    await _repository.updateCreativeWithMedia(
      item,
      content,
      filePath,
      fileName,
    );
    await refresh();
  }

  Future<void> deleteCreative(int id) async {
    await _repository.deleteCreative(id);
    await refresh();
  }

  Future<void> submitCreativeForModeration(int id) async {
    await _repository.submitCreativeForModeration(id);
    await refresh();
  }

  Future<void> deposit(double amount, String? description) async {
    await _repository.deposit(_userId!, amount, description);
    await refresh();
  }

  Future<void> withdraw(double amount, String? description) async {
    await _repository.withdraw(_userId!, amount, description);
    await refresh();
  }
}

final appDataProvider = StateNotifierProvider<AppDataController, AppDataState>(
  (ref) => AppDataController(ref.watch(repositoryProvider)),
);

class ModerationState {
  const ModerationState({
    this.status = 'pending',
    this.items = const [],
    this.loading = false,
    this.processingId,
    this.error,
  });

  final String status;
  final List<Creative> items;
  final bool loading;
  final int? processingId;
  final String? error;

  ModerationState copyWith({
    String? status,
    List<Creative>? items,
    bool? loading,
    int? processingId,
    bool clearProcessing = false,
    String? error,
    bool clearError = false,
  }) => ModerationState(
    status: status ?? this.status,
    items: items ?? this.items,
    loading: loading ?? this.loading,
    processingId: clearProcessing ? null : processingId ?? this.processingId,
    error: clearError ? null : error ?? this.error,
  );
}

class ModerationController extends StateNotifier<ModerationState> {
  ModerationController(this._repository) : super(const ModerationState());

  final AdPlatformRepository _repository;

  Future<void> load([String? status]) async {
    final selected = status ?? state.status;
    state = state.copyWith(status: selected, loading: true, clearError: true);
    try {
      final items = await _repository.getModerationCreatives(selected);
      state = state.copyWith(
        status: selected,
        items: items,
        loading: false,
        clearProcessing: true,
      );
    } catch (error) {
      state = state.copyWith(
        loading: false,
        error: error.toString(),
        clearProcessing: true,
      );
    }
  }

  Future<void> review(int id, String decision, {String reason = ''}) async {
    state = state.copyWith(processingId: id, clearError: true);
    try {
      await _repository.reviewCreative(id, decision, reason: reason);
      await load();
    } catch (error) {
      state = state.copyWith(error: error.toString(), clearProcessing: true);
      rethrow;
    }
  }
}

final moderationProvider =
    StateNotifierProvider<ModerationController, ModerationState>(
      (ref) => ModerationController(ref.watch(repositoryProvider)),
    );
