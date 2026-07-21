import 'body_params.dart';
import 'face_params.dart';
import 'skin_params.dart';
import 'tune_params.dart';

/// Preset composto LUT + beauty (serializável JSON).
class BeautyPreset {
  final String id;
  final String name;
  final String? lutAssetPath;
  final double lutIntensity;
  final TuneParams tune;
  final FaceParams face;
  final BodyParams body;
  final SkinParams skin;
  final int version;
  /// Caminho local do thumbnail JPEG (Sprint 22).
  final String? thumbnailPath;
  /// UUID remoto no Supabase (Sprint 23).
  final String? remoteId;
  /// Dono do preset na nuvem (Sprint 23).
  final String? authorId;
  /// Visível no marketplace (Sprint 24).
  final bool isPublic;
  /// Origem remota ao instalar do marketplace (Sprint 24).
  final String? installedFromRemoteId;
  /// Timestamps para sync last-write-wins (Sprint 23).
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const BeautyPreset({
    required this.id,
    required this.name,
    this.lutAssetPath,
    this.lutIntensity = 1,
    this.tune = const TuneParams(),
    this.face = const FaceParams(),
    this.body = const BodyParams(),
    this.skin = const SkinParams(),
    this.version = 1,
    this.thumbnailPath,
    this.remoteId,
    this.authorId,
    this.isPublic = false,
    this.installedFromRemoteId,
    this.createdAt,
    this.updatedAt,
  });

  BeautyPreset copyWith({
    String? id,
    String? name,
    String? lutAssetPath,
    double? lutIntensity,
    TuneParams? tune,
    FaceParams? face,
    BodyParams? body,
    SkinParams? skin,
    int? version,
    String? thumbnailPath,
    String? remoteId,
    String? authorId,
    bool? isPublic,
    String? installedFromRemoteId,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearLutAssetPath = false,
    bool clearThumbnailPath = false,
    bool clearRemoteId = false,
    bool clearInstalledFromRemoteId = false,
  }) {
    return BeautyPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      lutAssetPath: clearLutAssetPath ? null : (lutAssetPath ?? this.lutAssetPath),
      lutIntensity: lutIntensity ?? this.lutIntensity,
      tune: tune ?? this.tune,
      face: face ?? this.face,
      body: body ?? this.body,
      skin: skin ?? this.skin,
      version: version ?? this.version,
      thumbnailPath:
          clearThumbnailPath ? null : (thumbnailPath ?? this.thumbnailPath),
      remoteId: clearRemoteId ? null : (remoteId ?? this.remoteId),
      authorId: authorId ?? this.authorId,
      isPublic: isPublic ?? this.isPublic,
      installedFromRemoteId: clearInstalledFromRemoteId
          ? null
          : (installedFromRemoteId ?? this.installedFromRemoteId),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Preset pronto para persistência local com timestamp atualizado.
  BeautyPreset withLocalSaveTimestamp({DateTime? at}) {
    final now = (at ?? DateTime.now()).toUtc();
    return copyWith(
      createdAt: createdAt ?? now,
      updatedAt: now,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lutAssetPath': lutAssetPath,
        'lutIntensity': lutIntensity,
        'tune': tune.toJson(),
        'face': face.toJson(),
        'body': body.toJson(),
        'skin': skin.toJson(),
        'version': version,
        if (thumbnailPath != null) 'thumbnailPath': thumbnailPath,
        if (remoteId != null) 'remoteId': remoteId,
        if (authorId != null) 'authorId': authorId,
        if (isPublic) 'isPublic': isPublic,
        if (installedFromRemoteId != null)
          'installedFromRemoteId': installedFromRemoteId,
        if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      };

  factory BeautyPreset.fromJson(Map<String, dynamic> json) {
    return BeautyPreset(
      id: json['id'] as String,
      name: json['name'] as String,
      lutAssetPath: json['lutAssetPath'] as String?,
      lutIntensity: (json['lutIntensity'] as num?)?.toDouble() ?? 1,
      tune: TuneParams.fromJson(
        json['tune'] as Map<String, dynamic>? ?? {},
      ),
      face: FaceParams.fromJson(
        json['face'] as Map<String, dynamic>? ?? {},
      ),
      body: BodyParams.fromJson(
        json['body'] as Map<String, dynamic>? ?? {},
      ),
      skin: SkinParams.fromJson(
        json['skin'] as Map<String, dynamic>? ?? {},
      ),
      version: json['version'] as int? ?? 1,
      thumbnailPath: json['thumbnailPath'] as String?,
      remoteId: json['remoteId'] as String?,
      authorId: json['authorId'] as String?,
      isPublic: json['isPublic'] as bool? ?? false,
      installedFromRemoteId: json['installedFromRemoteId'] as String?,
      createdAt: _parseDateTime(json['createdAt']),
      updatedAt: _parseDateTime(json['updatedAt']),
    );
  }

  static DateTime? _parseDateTime(Object? raw) {
    if (raw is! String || raw.isEmpty) {
      return null;
    }
    return DateTime.parse(raw).toUtc();
  }

  /// Mapa flat para o pipeline de filtros.
  Map<String, double> toParameterMap() {
    return {
      'lut_intensity': lutIntensity,
      'face_slim': face.faceSlim,
      'narrow_face': face.narrowFace,
      'v_face': face.vFace,
      'nose_slim': face.noseSlim,
      'nose_length': face.noseLength,
      'nose_height': face.noseHeight,
      'nose_tip': face.noseTip,
      'nose_bridge': face.noseBridge,
      'eye_scale': face.eyeScale,
      'eye_distance': face.eyeDistance,
      'eye_height': face.eyeHeight,
      'eye_rotation': face.eyeRotation,
      'double_eyelid': face.doubleEyelid,
      'link_eyes': face.linkEyes ? 1.0 : 0.0,
      'jaw': face.jaw,
      'chin': face.chin,
      'cheekbone': face.cheekbone,
      'forehead': face.forehead,
      'temple': face.temple,
      'mouth_width': face.mouthWidth,
      'lip_thickness': face.lipThickness,
      'smile': face.smile,
      'brightness': tune.brightness,
      'contrast': tune.contrast,
      'saturation': tune.saturation,
      'exposure': tune.exposure,
      'temperature': tune.temperature,
      'waist_slim': body.waistSlim,
      'hip': body.hip,
      'body_slim': body.bodySlim,
      'leg_length': body.legLength,
      'leg_slim': body.legSlim,
      'arm_slim': body.armSlim,
      'neck_slim': body.neckSlim,
      'shoulder_width': body.shoulderWidth,
      'head_size': body.headSize,
      'skin_smooth': skin.smooth,
      'skin_whitening': skin.whitening,
      'remove_acne': skin.acne,
      'remove_wrinkles': skin.wrinkles,
      'remove_dark_circles': skin.darkCircles,
      'teeth_whitening': skin.teethWhitening,
      'blush': skin.blush,
      'contour': skin.contour,
      'eyebrows': skin.eyebrows,
      'eyelashes': skin.eyelashes,
    };
  }
}
