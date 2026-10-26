class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.role,
    this.roles = const ['user'],
    this.permissions = const [],
    this.status = 'active',
    this.mfaEnabled = false,
    this.passwordResetRequired = false,
    this.workspaces = const ['advertiser'],
  });

  final int id;
  final String email;
  final String role;
  final List<String> roles;
  final List<String> permissions;
  final String status;
  final bool mfaEnabled;
  final bool passwordResetRequired;
  final List<String> workspaces;

  bool get canAdminister => workspaces.contains('admin');
  bool can(String permission) => permissions.contains(permission);

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: (json['id'] as num).toInt(),
    email: json['email'] as String,
    role: json['role'] as String? ?? 'user',
    roles:
        (json['roles'] as List? ?? [json['role'] ?? 'user'])
            .map((item) => item.toString())
            .toList(),
    permissions:
        (json['permissions'] as List? ?? const [])
            .map((item) => item.toString())
            .toList(),
    status: json['status'] as String? ?? 'active',
    mfaEnabled: json['mfa_enabled'] as bool? ?? false,
    passwordResetRequired: json['password_reset_required'] as bool? ?? false,
    workspaces:
        (json['workspaces'] as List? ?? const ['advertiser'])
            .map((item) => item.toString())
            .toList(),
  );
}

class MfaChallenge {
  const MfaChallenge({
    required this.token,
    this.setupRequired = false,
    this.secret,
    this.otpauthUri,
  });

  final String token;
  final bool setupRequired;
  final String? secret;
  final String? otpauthUri;
}

class AdminDashboard {
  const AdminDashboard({
    required this.totalUsers,
    required this.activeUsers,
    required this.blockedUsers,
    required this.newUsers,
    required this.recentAudit,
    this.pendingModeration = 0,
    this.fraudEvents = 0,
  });

  final int totalUsers;
  final int activeUsers;
  final int blockedUsers;
  final int newUsers;
  final int pendingModeration;
  final int fraudEvents;
  final List<AdminAuditEvent> recentAudit;

  factory AdminDashboard.fromJson(Map<String, dynamic> json) => AdminDashboard(
    totalUsers: (json['total_users'] as num?)?.toInt() ?? 0,
    activeUsers: (json['active_users'] as num?)?.toInt() ?? 0,
    blockedUsers: (json['blocked_users'] as num?)?.toInt() ?? 0,
    newUsers: (json['new_users'] as num?)?.toInt() ?? 0,
    pendingModeration: (json['pending_moderation'] as num?)?.toInt() ?? 0,
    fraudEvents: (json['fraud_events'] as num?)?.toInt() ?? 0,
    recentAudit:
        (json['recent_audit'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(AdminAuditEvent.fromJson)
            .toList(),
  );
}

class AdminUser {
  const AdminUser({
    required this.id,
    required this.email,
    required this.status,
    required this.roles,
    required this.permissions,
    required this.rowVersion,
    required this.createdAt,
    this.lastLoginAt,
    this.blockReason = '',
    this.suspendedUntil,
    this.balance = 0,
    this.activeSessions = 0,
    this.campaigns = 0,
    this.transactions = 0,
    this.fraudEvents = 0,
    this.recentAudit = const [],
  });

  final int id;
  final String email;
  final String status;
  final List<String> roles;
  final List<String> permissions;
  final int rowVersion;
  final DateTime createdAt;
  final DateTime? lastLoginAt;
  final String blockReason;
  final DateTime? suspendedUntil;
  final double balance;
  final int activeSessions;
  final int campaigns;
  final int transactions;
  final int fraudEvents;
  final List<AdminAuditEvent> recentAudit;

  bool get isActive => status == 'active';
  bool get isBlocked => status == 'blocked';
  bool get isSuspended => status == 'suspended';

  factory AdminUser.fromJson(Map<String, dynamic> json) => AdminUser(
    id: (json['id'] as num).toInt(),
    email: json['email'] as String,
    status: json['status'] as String? ?? 'active',
    roles:
        (json['roles'] as List? ?? const [])
            .map((item) => item.toString())
            .toList(),
    permissions:
        (json['permissions'] as List? ?? const [])
            .map((item) => item.toString())
            .toList(),
    rowVersion: (json['row_version'] as num?)?.toInt() ?? 1,
    createdAt:
        DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ??
        DateTime.fromMillisecondsSinceEpoch(0),
    lastLoginAt:
        DateTime.tryParse(json['last_login_at'] as String? ?? '')?.toLocal(),
    blockReason: json['block_reason'] as String? ?? '',
    suspendedUntil:
        DateTime.tryParse(json['suspended_until'] as String? ?? '')?.toLocal(),
    balance: (json['balance'] as num?)?.toDouble() ?? 0,
    activeSessions: (json['active_sessions'] as num?)?.toInt() ?? 0,
    campaigns: (json['campaigns'] as num?)?.toInt() ?? 0,
    transactions: (json['transactions'] as num?)?.toInt() ?? 0,
    fraudEvents: (json['fraud_events'] as num?)?.toInt() ?? 0,
    recentAudit:
        (json['recent_audit'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(AdminAuditEvent.fromJson)
            .toList(),
  );
}

class AdminAuditEvent {
  const AdminAuditEvent({
    required this.id,
    required this.actorUserId,
    required this.action,
    required this.targetType,
    required this.targetId,
    required this.reason,
    required this.createdAt,
  });

  final int id;
  final int actorUserId;
  final String action;
  final String targetType;
  final String targetId;
  final String reason;
  final DateTime createdAt;

  factory AdminAuditEvent.fromJson(Map<String, dynamic> json) =>
      AdminAuditEvent(
        id: (json['id'] as num).toInt(),
        actorUserId: (json['actor_user_id'] as num).toInt(),
        action: json['action'] as String,
        targetType: json['target_type'] as String,
        targetId: json['target_id'].toString(),
        reason: json['reason'] as String? ?? '',
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      );
}

class Campaign {
  const Campaign({
    required this.id,
    required this.userId,
    required this.name,
    required this.status,
    this.budget = const CampaignBudget(),
    this.schedule = const CampaignSchedule(),
  });

  final int id;
  final int userId;
  final String name;
  final String status;
  final CampaignBudget budget;
  final CampaignSchedule schedule;

  bool get isActive => status == 'active';

  factory Campaign.fromJson(Map<String, dynamic> json) => Campaign(
    id: (json['id'] as num).toInt(),
    userId: (json['user_id'] as num).toInt(),
    name: json['name'] as String,
    status: json['status'] as String? ?? 'draft',
    budget: CampaignBudget.fromJson(
      (json['budget'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
    schedule: CampaignSchedule.fromJson(
      (json['schedule'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
  );
}

class CampaignBudget {
  const CampaignBudget({
    this.total = 0,
    this.dailyLimit = 0,
    this.spentTotal = 0,
    this.spentToday = 0,
  });

  final double total;
  final double dailyLimit;
  final double spentTotal;
  final double spentToday;

  bool get hasTotalLimit => total > 0;
  bool get hasDailyLimit => dailyLimit > 0;
  double get totalProgress =>
      !hasTotalLimit ? 0 : (spentTotal / total).clamp(0, 1);

  factory CampaignBudget.fromJson(Map<String, dynamic> json) => CampaignBudget(
    total: (json['total'] as num?)?.toDouble() ?? 0,
    dailyLimit: (json['daily_limit'] as num?)?.toDouble() ?? 0,
    spentTotal: (json['spent_total'] as num?)?.toDouble() ?? 0,
    spentToday: (json['spent_today'] as num?)?.toDouble() ?? 0,
  );

  Map<String, dynamic> toJson() => {'total': total, 'daily_limit': dailyLimit};
}

class CampaignSchedule {
  const CampaignSchedule({
    this.startsAt,
    this.endsAt,
    this.daysOfWeek = const [],
    this.startHour = 0,
    this.endHour = 24,
  });

  final DateTime? startsAt;
  final DateTime? endsAt;
  final List<int> daysOfWeek;
  final int startHour;
  final int endHour;

  factory CampaignSchedule.fromJson(Map<String, dynamic> json) =>
      CampaignSchedule(
        startsAt:
            DateTime.tryParse(json['starts_at'] as String? ?? '')?.toUtc(),
        endsAt: DateTime.tryParse(json['ends_at'] as String? ?? '')?.toUtc(),
        daysOfWeek:
            (json['days_of_week'] as List? ?? const [])
                .map((item) => (item as num).toInt())
                .toList(),
        startHour: (json['start_hour'] as num?)?.toInt() ?? 0,
        endHour: (json['end_hour'] as num?)?.toInt() ?? 24,
      );

  Map<String, dynamic> toJson() => {
    'starts_at': startsAt?.toUtc().toIso8601String(),
    'ends_at': endsAt?.toUtc().toIso8601String(),
    'days_of_week': daysOfWeek,
    'start_hour': startHour,
    'end_hour': endHour,
    'timezone': 'UTC',
  };
}

class AdItem {
  const AdItem({
    required this.id,
    required this.campaignId,
    required this.title,
    required this.status,
    required this.placement,
    required this.destinationUrl,
    required this.weight,
    this.bidCpm = 1,
    this.placementId,
    this.targeting = const AdTargeting(),
  });

  final int id;
  final int campaignId;
  final String title;
  final String status;
  final String placement;
  final String destinationUrl;
  final int weight;
  final double bidCpm;
  final int? placementId;
  final AdTargeting targeting;

  bool get isActive => status == 'active';

  factory AdItem.fromJson(Map<String, dynamic> json) => AdItem(
    id: (json['id'] as num).toInt(),
    campaignId: (json['campaign_id'] as num).toInt(),
    title: json['title'] as String,
    status: json['status'] as String? ?? 'draft',
    placement: json['placement'] as String? ?? 'feed',
    destinationUrl: json['destination_url'] as String? ?? '',
    weight: (json['weight'] as num?)?.toInt() ?? 1,
    bidCpm: (json['bid_cpm'] as num?)?.toDouble() ?? 1,
    placementId: (json['placement_id'] as num?)?.toInt(),
    targeting: AdTargeting.fromJson(
      (json['targeting'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
  );
}

class AdTargeting {
  const AdTargeting({
    this.minAge = 0,
    this.maxAge = 0,
    this.genders = const [],
    this.interests = const [],
    this.countries = const [],
    this.regions = const [],
    this.cities = const [],
    this.deviceTypes = const [],
    this.operatingSystems = const [],
  });

  final int minAge;
  final int maxAge;
  final List<String> genders;
  final List<String> interests;
  final List<String> countries;
  final List<String> regions;
  final List<String> cities;
  final List<String> deviceTypes;
  final List<String> operatingSystems;

  bool get hasRules =>
      minAge > 0 ||
      maxAge > 0 ||
      genders.isNotEmpty ||
      interests.isNotEmpty ||
      countries.isNotEmpty ||
      regions.isNotEmpty ||
      cities.isNotEmpty ||
      deviceTypes.isNotEmpty ||
      operatingSystems.isNotEmpty;

  factory AdTargeting.fromJson(Map<String, dynamic> json) {
    final audience =
        (json['audience'] as Map?)?.cast<String, dynamic>() ?? const {};
    final geography =
        (json['geography'] as Map?)?.cast<String, dynamic>() ?? const {};
    final device =
        (json['device'] as Map?)?.cast<String, dynamic>() ?? const {};
    List<String> strings(Map<String, dynamic> source, String key) =>
        (source[key] as List? ?? const []).map((item) => '$item').toList();
    return AdTargeting(
      minAge: (audience['min_age'] as num?)?.toInt() ?? 0,
      maxAge: (audience['max_age'] as num?)?.toInt() ?? 0,
      genders: strings(audience, 'genders'),
      interests: strings(audience, 'interests'),
      countries: strings(geography, 'countries'),
      regions: strings(geography, 'regions'),
      cities: strings(geography, 'cities'),
      deviceTypes: strings(device, 'types'),
      operatingSystems: strings(device, 'operating_systems'),
    );
  }

  Map<String, dynamic> toJson() => {
    'audience': {
      'min_age': minAge,
      'max_age': maxAge,
      'genders': genders,
      'interests': interests,
    },
    'geography': {'countries': countries, 'regions': regions, 'cities': cities},
    'device': {'types': deviceTypes, 'operating_systems': operatingSystems},
  };
}

class Site {
  const Site({
    required this.id,
    required this.userId,
    required this.name,
    required this.domain,
    required this.status,
  });

  final int id;
  final int userId;
  final String name;
  final String domain;
  final String status;

  bool get isActive => status == 'active';

  factory Site.fromJson(Map<String, dynamic> json) => Site(
    id: (json['id'] as num).toInt(),
    userId: (json['user_id'] as num).toInt(),
    name: json['name'] as String,
    domain: json['domain'] as String,
    status: json['status'] as String? ?? 'active',
  );
}

class AdFormat {
  const AdFormat({
    required this.id,
    required this.code,
    required this.name,
    required this.kind,
    required this.width,
    required this.height,
    required this.status,
  });

  final int id;
  final String code;
  final String name;
  final String kind;
  final int width;
  final int height;
  final String status;

  bool get isActive => status == 'active';
  String get sizeLabel =>
      width > 0 && height > 0 ? '$width×$height' : 'Адаптивный';

  factory AdFormat.fromJson(Map<String, dynamic> json) => AdFormat(
    id: (json['id'] as num).toInt(),
    code: json['code'] as String,
    name: json['name'] as String,
    kind: json['kind'] as String,
    width: (json['width'] as num?)?.toInt() ?? 0,
    height: (json['height'] as num?)?.toInt() ?? 0,
    status: json['status'] as String? ?? 'active',
  );
}

class Placement {
  const Placement({
    required this.id,
    required this.siteId,
    required this.formatId,
    required this.name,
    required this.code,
    required this.status,
  });

  final int id;
  final int siteId;
  final int formatId;
  final String name;
  final String code;
  final String status;

  bool get isActive => status == 'active';

  factory Placement.fromJson(Map<String, dynamic> json) => Placement(
    id: (json['id'] as num).toInt(),
    siteId: (json['site_id'] as num).toInt(),
    formatId: (json['format_id'] as num).toInt(),
    name: json['name'] as String,
    code: json['code'] as String,
    status: json['status'] as String? ?? 'active',
  );
}

class CreativeMedia {
  const CreativeMedia({
    this.type = 'text',
    this.url = '',
    this.mimeType = '',
    this.fileName = '',
    this.fileSize = 0,
  });

  final String type;
  final String url;
  final String mimeType;
  final String fileName;
  final int fileSize;

  bool get hasFile => url.isNotEmpty;
  bool get isImage => type == 'image';
  bool get isVideo => type == 'video';

  factory CreativeMedia.fromJson(Map<String, dynamic>? json) => CreativeMedia(
    type: json?['type'] as String? ?? 'text',
    url: json?['url'] as String? ?? '',
    mimeType: json?['mime_type'] as String? ?? '',
    fileName: json?['file_name'] as String? ?? '',
    fileSize: (json?['file_size'] as num?)?.toInt() ?? 0,
  );
}

class Creative {
  const Creative({
    required this.id,
    required this.adId,
    required this.content,
    this.media = const CreativeMedia(),
    this.moderationStatus = 'draft',
    this.moderationReason = '',
    this.submittedAt,
    this.reviewedAt,
    this.reviewedBy,
    this.adTitle = '',
    this.campaignName = '',
    this.ownerUserId = 0,
  });

  final int id;
  final int adId;
  final String content;
  final CreativeMedia media;
  final String moderationStatus;
  final String moderationReason;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;
  final int? reviewedBy;
  final String adTitle;
  final String campaignName;
  final int ownerUserId;

  bool get canSubmitForModeration =>
      moderationStatus == 'draft' || moderationStatus == 'rejected';
  bool get isPending => moderationStatus == 'pending';
  bool get isApproved => moderationStatus == 'approved';
  bool get isRejected => moderationStatus == 'rejected';

  factory Creative.fromJson(Map<String, dynamic> json) => Creative(
    id: (json['id'] as num).toInt(),
    adId: (json['ad_id'] as num).toInt(),
    content: json['content'] as String,
    media: CreativeMedia.fromJson(json['media'] as Map<String, dynamic>?),
    moderationStatus: json['moderation_status'] as String? ?? 'draft',
    moderationReason: json['moderation_reason'] as String? ?? '',
    submittedAt:
        DateTime.tryParse(json['submitted_at'] as String? ?? '')?.toLocal(),
    reviewedAt:
        DateTime.tryParse(json['reviewed_at'] as String? ?? '')?.toLocal(),
    reviewedBy: (json['reviewed_by'] as num?)?.toInt(),
    adTitle: json['ad_title'] as String? ?? '',
    campaignName: json['campaign_name'] as String? ?? '',
    ownerUserId: (json['owner_user_id'] as num?)?.toInt() ?? 0,
  );
}

class AdDelivery {
  const AdDelivery({
    required this.id,
    required this.campaignId,
    required this.adId,
    required this.creativeId,
    required this.title,
    required this.content,
    required this.destinationUrl,
    required this.impressionUrl,
    required this.clickUrl,
    required this.conversionUrl,
    this.media = const CreativeMedia(),
  });

  final String id;
  final int campaignId;
  final int adId;
  final int creativeId;
  final String title;
  final String content;
  final String destinationUrl;
  final String impressionUrl;
  final String clickUrl;
  final String conversionUrl;
  final CreativeMedia media;

  factory AdDelivery.fromJson(Map<String, dynamic> json) => AdDelivery(
    id: json['delivery_id'] as String,
    campaignId: (json['campaign_id'] as num).toInt(),
    adId: (json['ad_id'] as num).toInt(),
    creativeId: (json['creative_id'] as num).toInt(),
    title: json['title'] as String? ?? '',
    content: json['content'] as String? ?? '',
    destinationUrl: json['destination_url'] as String? ?? '',
    impressionUrl: json['impression_url'] as String? ?? '',
    clickUrl: json['click_url'] as String? ?? '',
    conversionUrl: json['conversion_url'] as String? ?? '',
    media: CreativeMedia.fromJson(json['media'] as Map<String, dynamic>?),
  );
}

class TrackingReceipt {
  const TrackingReceipt({
    required this.deliveryId,
    required this.eventId,
    required this.eventType,
    required this.recorded,
    required this.occurredAt,
    this.conversionType = '',
    this.conversionValue = 0,
    this.conversionCurrency = '',
    this.attributionModel = '',
    this.attributionWindowHours = 0,
    this.isFraud = false,
    this.fraudReason = '',
  });

  final String deliveryId;
  final String eventId;
  final String eventType;
  final bool recorded;
  final DateTime occurredAt;
  final String conversionType;
  final double conversionValue;
  final String conversionCurrency;
  final String attributionModel;
  final int attributionWindowHours;
  final bool isFraud;
  final String fraudReason;

  factory TrackingReceipt.fromJson(Map<String, dynamic> json) =>
      TrackingReceipt(
        deliveryId: json['delivery_id'] as String,
        eventId: json['event_id'] as String,
        eventType: json['event_type'] as String,
        recorded: json['recorded'] as bool? ?? false,
        occurredAt: DateTime.parse(json['occurred_at'] as String).toLocal(),
        conversionType: json['conversion_type'] as String? ?? '',
        conversionValue: (json['conversion_value'] as num?)?.toDouble() ?? 0,
        conversionCurrency: json['conversion_currency'] as String? ?? '',
        attributionModel: json['attribution_model'] as String? ?? '',
        attributionWindowHours:
            (json['attribution_window_hours'] as num?)?.toInt() ?? 0,
        isFraud: json['is_fraud'] as bool? ?? false,
        fraudReason: json['fraud_reason'] as String? ?? '',
      );
}

class BillingTransaction {
  const BillingTransaction({
    required this.id,
    required this.amount,
    required this.type,
    required this.description,
    required this.createdAt,
  });

  final int id;
  final double amount;
  final String type;
  final String? description;
  final DateTime createdAt;

  bool get isIncome => type == 'deposit';

  factory BillingTransaction.fromJson(Map<String, dynamic> json) =>
      BillingTransaction(
        id: (json['id'] as num).toInt(),
        amount: (json['amount'] as num).toDouble(),
        type: json['type'] as String,
        description: json['description'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class AnalyticsPoint {
  const AnalyticsPoint({
    required this.date,
    required this.campaignId,
    this.adId,
    this.creativeId,
    required this.impressions,
    required this.clicks,
    required this.conversions,
    required this.conversionValue,
    this.lastClickConversions = 0,
    this.viewThroughConversions = 0,
    this.fraudEvents = 0,
    required this.cost,
  });

  final DateTime date;
  final int campaignId;
  final int? adId;
  final int? creativeId;
  final int impressions;
  final int clicks;
  final int conversions;
  final double conversionValue;
  final int lastClickConversions;
  final int viewThroughConversions;
  final int fraudEvents;
  final double cost;

  double get ctr => impressions == 0 ? 0 : clicks / impressions * 100;
  double get conversionRate => clicks == 0 ? 0 : conversions / clicks * 100;

  factory AnalyticsPoint.fromJson(Map<String, dynamic> json) => AnalyticsPoint(
    date: DateTime.parse(json['date'] as String),
    campaignId: (json['campaign_id'] as num?)?.toInt() ?? 0,
    adId: (json['ad_id'] as num?)?.toInt(),
    creativeId: (json['creative_id'] as num?)?.toInt(),
    impressions: (json['total_impressions'] as num).toInt(),
    clicks: (json['total_clicks'] as num).toInt(),
    conversions: (json['total_conversions'] as num?)?.toInt() ?? 0,
    conversionValue: (json['total_conversion_value'] as num?)?.toDouble() ?? 0,
    lastClickConversions:
        (json['last_click_conversions'] as num?)?.toInt() ?? 0,
    viewThroughConversions:
        (json['view_through_conversions'] as num?)?.toInt() ?? 0,
    fraudEvents: (json['total_fraud_events'] as num?)?.toInt() ?? 0,
    cost: (json['total_cost'] as num).toDouble(),
  );
}
