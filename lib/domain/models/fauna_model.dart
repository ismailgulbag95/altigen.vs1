import 'dart:ui';

/// Bozkır Canlıları ve Fauna Türleri (Fauna Species)
enum FaunaType {
  horse,
  sheep,
  ram,
  lamb,
  steppeWolf,
  mountainIbex,
  camel,
  arcticFox,
  skyEagle,
  crane,
  swallow,
  seagull,
}

/// Fauna Davranış Durum Makinesi (Behavior State Machine)
enum FaunaBehaviorState {
  grazing,
  roaming,
  resting,
  alert,
  fleeing,
  flying,
  winterHuddle,
}

/// Otantik Kürk / Tüy Varyasyonları (Authentic Coat & Plumage Variants)
enum FaunaCoatVariant {
  doru, // Kestane / Kehribar (At)
  yagiz, // Gece Simsiyahı (At)
  kir, // Gümüş Grisi / İpek Beyazı (At)
  alaca, // Benekli / Parçalı (At, Koyun)
  naturalWool, // Doğal Kar Beyazı Yün (Koyun, Kuzu)
  blackWool, // Kara Koyun Yünü (Koyun)
  caramelBrown, // Bozkır Karamel Kahvesi (Koyun, Keçi)
  steppeGrey, // Bozkır Bozkurt Grisi (Kurt, Dağ Keçisi)
  snowWhite, // Kutup Kar Beyazı (Tilki, Turna)
  goldenEagle, // Asil Bozkır Kartalı Kahve-Altın
  crestedCrane, // Telli Turna Beyaz-Gri
  swallowIndigo, // Kırlangıç Gece Laciverti
}

/// Biyom Canlısının Canlı Durum Modeli (Immutable Fauna Entity)
class FaunaEntity {
  final String id;
  final FaunaType type;
  final Offset position;
  final double angle;
  final double animPhase;
  final int seed;
  final FaunaBehaviorState state;
  final FaunaCoatVariant coat;
  final double scale;
  final bool flipX;
  final double headPitch; // Kafa eğilme / otlama açısı
  final double headYaw; // Kafa çevreye bakma açısı
  final double legStride; // 4 eklemli bacak adımlama fazı
  final double tailWag; // Kuyruk salınım açısı
  final double earTwitch; // Kulak seğirme açısı
  final double startleTimer; // Dokunulduğunda irkilme süresi

  const FaunaEntity({
    required this.id,
    required this.type,
    required this.position,
    this.angle = 0.0,
    this.animPhase = 0.0,
    this.seed = 0,
    this.state = FaunaBehaviorState.grazing,
    this.coat = FaunaCoatVariant.doru,
    this.scale = 1.0,
    this.flipX = false,
    this.headPitch = 0.0,
    this.headYaw = 0.0,
    this.legStride = 0.0,
    this.tailWag = 0.0,
    this.earTwitch = 0.0,
    this.startleTimer = 0.0,
  });

  FaunaEntity copyWith({
    String? id,
    FaunaType? type,
    Offset? position,
    double? angle,
    double? animPhase,
    int? seed,
    FaunaBehaviorState? state,
    FaunaCoatVariant? coat,
    double? scale,
    bool? flipX,
    double? headPitch,
    double? headYaw,
    double? legStride,
    double? tailWag,
    double? earTwitch,
    double? startleTimer,
  }) {
    return FaunaEntity(
      id: id ?? this.id,
      type: type ?? this.type,
      position: position ?? this.position,
      angle: angle ?? this.angle,
      animPhase: animPhase ?? this.animPhase,
      seed: seed ?? this.seed,
      state: state ?? this.state,
      coat: coat ?? this.coat,
      scale: scale ?? this.scale,
      flipX: flipX ?? this.flipX,
      headPitch: headPitch ?? this.headPitch,
      headYaw: headYaw ?? this.headYaw,
      legStride: legStride ?? this.legStride,
      tailWag: tailWag ?? this.tailWag,
      earTwitch: earTwitch ?? this.earTwitch,
      startleTimer: startleTimer ?? this.startleTimer,
    );
  }
}
