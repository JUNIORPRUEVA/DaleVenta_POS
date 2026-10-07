enum ReleasePlatform { windows }

extension ReleasePlatformApiValue on ReleasePlatform {
  String get apiValue => switch (this) {
    ReleasePlatform.windows => 'windows',
  };

  String get displayName => switch (this) {
    ReleasePlatform.windows => 'Windows',
  };
}

class InstalledReleaseInfo {
  final ReleasePlatform platform;
  final String currentVersion;
  final int currentBuild;

  const InstalledReleaseInfo({
    required this.platform,
    required this.currentVersion,
    required this.currentBuild,
  });
}

enum AppUpdatePhase {
  idle,
  unsupported,
  checking,
  available,
  downloading,
  verifying,
  verifyingSha,
  verifyingSignature,
  readyToInstall,
  installRequested,
  waitingSafeState,
  updaterStarted,
  installFailed,
  installedConfirmed,
}

extension AppUpdatePhasePersistence on AppUpdatePhase {
  String get code => switch (this) {
    AppUpdatePhase.idle => 'IDLE',
    AppUpdatePhase.unsupported => 'UNSUPPORTED',
    AppUpdatePhase.checking => 'CHECKING',
    AppUpdatePhase.available => 'AVAILABLE',
    AppUpdatePhase.downloading => 'DOWNLOADING',
    AppUpdatePhase.verifying => 'VERIFYING',
    AppUpdatePhase.verifyingSha => 'VERIFYING_SHA',
    AppUpdatePhase.verifyingSignature => 'VERIFYING_SIGNATURE',
    AppUpdatePhase.readyToInstall => 'READY_TO_INSTALL',
    AppUpdatePhase.installRequested => 'INSTALL_REQUESTED',
    AppUpdatePhase.waitingSafeState => 'WAITING_SAFE_STATE',
    AppUpdatePhase.updaterStarted => 'UPDATER_STARTED',
    AppUpdatePhase.installFailed => 'INSTALL_FAILED',
    AppUpdatePhase.installedConfirmed => 'INSTALLED_CONFIRMED',
  };

  static AppUpdatePhase fromCode(String? value) {
    final normalized = (value ?? '').trim().toUpperCase();
    return AppUpdatePhase.values.firstWhere(
      (phase) => phase.code == normalized,
      orElse: () => AppUpdatePhase.idle,
    );
  }

  bool get isTransient => switch (this) {
    AppUpdatePhase.checking ||
    AppUpdatePhase.available ||
    AppUpdatePhase.downloading ||
    AppUpdatePhase.verifying ||
    AppUpdatePhase.verifyingSha ||
    AppUpdatePhase.verifyingSignature ||
    AppUpdatePhase.installRequested ||
    AppUpdatePhase.waitingSafeState => true,
    _ => false,
  };
}

class UpdateManifest {
  final bool updateAvailable;
  final String? version;
  final int? buildNumber;
  final String? fileName;
  final int? fileSize;
  final String? sha256;
  final String? downloadUrl;
  final bool mandatory;
  final int? minimumSupportedBuild;
  final List<String> releaseNotes;
  final DateTime? publishedAt;

  const UpdateManifest({
    required this.updateAvailable,
    this.version,
    this.buildNumber,
    this.fileName,
    this.fileSize,
    this.sha256,
    this.downloadUrl,
    this.mandatory = false,
    this.minimumSupportedBuild,
    this.releaseNotes = const [],
    this.publishedAt,
  });

  factory UpdateManifest.noUpdate() {
    return const UpdateManifest(updateAvailable: false);
  }

  factory UpdateManifest.fromJson(Map<String, dynamic> json) {
    final updateAvailable = json['updateAvailable'] == true;
    if (!updateAvailable) return UpdateManifest.noUpdate();

    final version = _asTrimmedString(json['version']);
    final buildNumber = _asInt(json['buildNumber']);
    final fileName = _asTrimmedString(json['fileName']);
    final fileSize = _asInt(json['fileSize']);
    final sha256 = _asTrimmedString(json['sha256']);
    final downloadUrl = _asTrimmedString(json['downloadUrl']);
    final publishedAtRaw = _asTrimmedString(json['publishedAt']);
    final publishedAt = publishedAtRaw == null
        ? null
        : DateTime.tryParse(publishedAtRaw);

    final valid =
        version != null &&
        buildNumber != null &&
        buildNumber > 0 &&
        fileName != null &&
        fileName.isNotEmpty &&
        fileSize != null &&
        fileSize > 0 &&
        sha256 != null &&
        RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha256) &&
        downloadUrl != null &&
        Uri.tryParse(downloadUrl)?.scheme == 'https' &&
        publishedAt != null;

    if (!valid) {
      throw const FormatException('Invalid app update manifest.');
    }

    return UpdateManifest(
      updateAvailable: true,
      version: version,
      buildNumber: buildNumber,
      fileName: fileName,
      fileSize: fileSize,
      sha256: sha256,
      downloadUrl: downloadUrl,
      mandatory: json['mandatory'] == true,
      minimumSupportedBuild: _asInt(json['minimumSupportedBuild']),
      releaseNotes: _asReleaseNotes(json['releaseNotes']),
      publishedAt: publishedAt,
    );
  }

  bool isNewerThan(int localBuild) =>
      updateAvailable && (buildNumber ?? 0) > localBuild;

  bool isDismissedBy(int? dismissedBuild) =>
      updateAvailable && buildNumber != null && buildNumber == dismissedBuild;

  bool get hasDownloadUrl => (downloadUrl ?? '').trim().isNotEmpty;

  bool get update => updateAvailable;

  bool get required => mandatory;

  String? get latestVersion => version;

  int? get latestBuild => buildNumber;

  String? get releaseNotesText =>
      releaseNotes.isEmpty ? null : releaseNotes.join('\n');

  static String? _asTrimmedString(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static List<String> _asReleaseNotes(Object? value) {
    if (value is List) {
      return value
          .map((entry) => entry?.toString().trim() ?? '')
          .where((entry) => entry.isNotEmpty)
          .toList(growable: false);
    }
    if (value is String && value.trim().isNotEmpty) {
      return [value.trim()];
    }
    return const [];
  }
}

typedef AppUpdateInfo = UpdateManifest;

class UpdateDownloadProgress {
  final int bytesDownloaded;
  final int totalBytes;

  const UpdateDownloadProgress({
    required this.bytesDownloaded,
    required this.totalBytes,
  });

  double get percentage {
    if (totalBytes <= 0) return 0;
    return (bytesDownloaded / totalBytes).clamp(0, 1).toDouble();
  }
}

class PersistedUpdateState {
  final int? targetBuild;
  final String? targetVersion;
  final AppUpdatePhase phase;
  final String? artifactRelativePath;
  final int? bytesDownloaded;
  final int? fileSizeExpected;
  final String? sha256Expected;
  final int? dismissedBuild;
  final int attempts;
  final String? lastErrorCode;
  final DateTime? lastUpdateCheckAt;
  final String? lastUpdateResult;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PersistedUpdateState({
    this.targetBuild,
    this.targetVersion,
    required this.phase,
    this.artifactRelativePath,
    this.bytesDownloaded,
    this.fileSizeExpected,
    this.sha256Expected,
    this.dismissedBuild,
    this.attempts = 0,
    this.lastErrorCode,
    this.lastUpdateCheckAt,
    this.lastUpdateResult,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PersistedUpdateState.initial({DateTime? now}) {
    final timestamp = now ?? DateTime.now();
    return PersistedUpdateState(
      phase: AppUpdatePhase.idle,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  factory PersistedUpdateState.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return PersistedUpdateState(
      targetBuild: UpdateManifest._asInt(json['targetBuild']),
      targetVersion: UpdateManifest._asTrimmedString(json['targetVersion']),
      phase: AppUpdatePhasePersistence.fromCode(json['state']?.toString()),
      artifactRelativePath: UpdateManifest._asTrimmedString(
        json['artifactRelativePath'],
      ),
      bytesDownloaded: UpdateManifest._asInt(json['bytesDownloaded']),
      fileSizeExpected: UpdateManifest._asInt(json['fileSizeExpected']),
      sha256Expected: UpdateManifest._asTrimmedString(json['sha256Expected']),
      dismissedBuild: UpdateManifest._asInt(json['dismissedBuild']),
      attempts: UpdateManifest._asInt(json['attempts']) ?? 0,
      lastErrorCode: UpdateManifest._asTrimmedString(json['lastErrorCode']),
      lastUpdateCheckAt: _asDate(json['lastUpdateCheckAt']),
      lastUpdateResult: UpdateManifest._asTrimmedString(
        json['lastUpdateResult'],
      ),
      createdAt: _asDate(json['createdAt']) ?? now,
      updatedAt: _asDate(json['updatedAt']) ?? now,
    );
  }

  PersistedUpdateState normalizeForStartup() {
    if (!phase.isTransient) return this;
    return copyWith(
      phase: AppUpdatePhase.idle,
      lastErrorCode: 'RECOVERED_TRANSIENT_STATE',
    );
  }

  PersistedUpdateState copyWith({
    int? targetBuild,
    String? targetVersion,
    AppUpdatePhase? phase,
    String? artifactRelativePath,
    int? bytesDownloaded,
    int? fileSizeExpected,
    String? sha256Expected,
    int? dismissedBuild,
    int? attempts,
    String? lastErrorCode,
    DateTime? lastUpdateCheckAt,
    String? lastUpdateResult,
    DateTime? updatedAt,
    bool clearTarget = false,
    bool clearArtifact = false,
    bool clearLastError = false,
  }) {
    final timestamp = updatedAt ?? DateTime.now();
    return PersistedUpdateState(
      targetBuild: clearTarget ? null : (targetBuild ?? this.targetBuild),
      targetVersion: clearTarget ? null : (targetVersion ?? this.targetVersion),
      phase: phase ?? this.phase,
      artifactRelativePath: clearTarget
          ? null
          : (clearArtifact
                ? null
                : (artifactRelativePath ?? this.artifactRelativePath)),
      bytesDownloaded: clearTarget
          ? null
          : (bytesDownloaded ?? this.bytesDownloaded),
      fileSizeExpected: clearTarget
          ? null
          : (fileSizeExpected ?? this.fileSizeExpected),
      sha256Expected: clearTarget
          ? null
          : (sha256Expected ?? this.sha256Expected),
      dismissedBuild: dismissedBuild ?? this.dismissedBuild,
      attempts: attempts ?? this.attempts,
      lastErrorCode: clearLastError
          ? null
          : (lastErrorCode ?? this.lastErrorCode),
      lastUpdateCheckAt: lastUpdateCheckAt ?? this.lastUpdateCheckAt,
      lastUpdateResult: lastUpdateResult ?? this.lastUpdateResult,
      createdAt: createdAt,
      updatedAt: timestamp,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'targetBuild': targetBuild,
      'targetVersion': targetVersion,
      'state': phase.code,
      'artifactRelativePath': artifactRelativePath,
      'bytesDownloaded': bytesDownloaded,
      'fileSizeExpected': fileSizeExpected,
      'sha256Expected': sha256Expected,
      'dismissedBuild': dismissedBuild,
      'attempts': attempts,
      'lastErrorCode': lastErrorCode,
      'lastUpdateCheckAt': lastUpdateCheckAt?.toIso8601String(),
      'lastUpdateResult': lastUpdateResult,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  static DateTime? _asDate(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return DateTime.tryParse(value.trim());
  }
}

class AppUpdateState {
  final AppUpdatePhase phase;
  final InstalledReleaseInfo? installedRelease;
  final UpdateManifest? manifest;
  final PersistedUpdateState persisted;
  final String? message;
  final DateTime? checkedAt;
  final UpdateDownloadProgress? progress;

  const AppUpdateState({
    required this.phase,
    this.installedRelease,
    this.manifest,
    required this.persisted,
    this.message,
    this.checkedAt,
    this.progress,
  });

  factory AppUpdateState.initial() {
    return AppUpdateState(
      phase: AppUpdatePhase.idle,
      persisted: PersistedUpdateState.initial(),
    );
  }

  AppUpdateState copyWith({
    AppUpdatePhase? phase,
    InstalledReleaseInfo? installedRelease,
    UpdateManifest? manifest,
    PersistedUpdateState? persisted,
    String? message,
    DateTime? checkedAt,
    UpdateDownloadProgress? progress,
    bool clearManifest = false,
    bool clearMessage = false,
    bool clearProgress = false,
  }) {
    return AppUpdateState(
      phase: phase ?? this.phase,
      installedRelease: installedRelease ?? this.installedRelease,
      manifest: clearManifest ? null : (manifest ?? this.manifest),
      persisted: persisted ?? this.persisted,
      message: clearMessage ? null : (message ?? this.message),
      checkedAt: checkedAt ?? this.checkedAt,
      progress: clearProgress ? null : (progress ?? this.progress),
    );
  }

  AppUpdateInfo? get updateInfo => manifest;

  double? get downloadProgress => progress?.percentage;

  bool get hasVisibleMainPrompt =>
      phase == AppUpdatePhase.readyToInstall &&
      manifest?.isDismissedBy(persisted.dismissedBuild) == false;

  bool get blocksUsage => false;
}

typedef UpdateState = AppUpdateState;
