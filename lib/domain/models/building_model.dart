import 'dart:math' as math;

enum BuildingType {
  castle,
  corn,
  barley,
  pasture,
  orchard,
  quarry,
  resinCamp,
  windmill,
  bakery,
  lumberjack,
  sawmill,
  furniture,
  worker,
  watchtower,
  mine,
  bridge,
  fisherman,
  fishermanHut,
  // Özel Çöl Binaları
  oasisCistern,
  caravanserai,
  astrolabe,
  // Özel Tundra Binaları
  reindeerSanctuary,
  geothermalBath,
  permafrostDig,
  // Özel Volkan Binaları
  steamVent,
  obsidianForge,
  // Özel Sazlık Binaları
  herbalistYurt,
  scribeWorkshop,
  // Efsanevi Biyom Binaları
  celestialAnvil,
  ancestralTotem,
  prismaticResonator,
  // 5 Büyük Yeni Mekanik Binaları
  granaryVault,
  kumisYurt,
  feltTentWorkshop,
  damascusForge,
  runicStele,
}

extension BuildingTypeExtension on BuildingType {
  /// Binanın açılması için gereken asgari Şato / Kağan Otağı Seviyesi
  /// 1 -> 2 -> 5 -> 10 -> 15 -> 20 -> 25 -> 30 -> 35 -> 40 -> 45 -> 50 kademeli prestij ve ilerleme hiyerarşisi
  int get requiredCastleLevel {
    switch (this) {
      // Seviye 1: Temel Hayatta Kalma
      case BuildingType.castle:
      case BuildingType.corn:
      case BuildingType.lumberjack:
      case BuildingType.worker:
        return 1;

      // Seviye 2: Gıda ve Depo Genişletme
      case BuildingType.barley:
      case BuildingType.granaryVault:
      case BuildingType.pasture:
        return 2;

      // Seviye 5: İlk Zanaat, Bilgelik, Savunma Kulesi ve Taş Ocağı
      case BuildingType.windmill:
      case BuildingType.sawmill:
      case BuildingType.runicStele:
      case BuildingType.watchtower:
      case BuildingType.quarry:
        return 5;

      // Seviye 10: Keşif ve Şifa
      case BuildingType.orchard:
      case BuildingType.resinCamp:
      case BuildingType.herbalistYurt:
        return 10;

      // Seviye 15: Ağır Maden ve İleri Besin
      case BuildingType.mine:
      case BuildingType.bakery:
      case BuildingType.fisherman:
        return 15;

      // Seviye 20: Ticaret, Zırh ve Lojistik
      case BuildingType.furniture:
      case BuildingType.bridge:
      case BuildingType.feltTentWorkshop:
        return 20;

      // Seviye 25: Çöl ve Tundra Keşfi
      case BuildingType.oasisCistern:
      case BuildingType.caravanserai:
      case BuildingType.reindeerSanctuary:
        return 25;

      // Seviye 30: Kutsal İksir ve Yazıtlar
      case BuildingType.kumisYurt:
      case BuildingType.scribeWorkshop:
        return 30;

      // Seviye 35: Zorlu İklim ve Derin Deniz
      case BuildingType.fishermanHut:
      case BuildingType.geothermalBath:
      case BuildingType.permafrostDig:
        return 35;

      // Seviye 40: Termal Enerji ve Şam Çeliği
      case BuildingType.steamVent:
      case BuildingType.obsidianForge:
      case BuildingType.damascusForge:
        return 40;

      // Seviye 45: Gökbilim ve Yıldızlar
      case BuildingType.astrolabe:
        return 45;

      // Seviye 50: Göksel İmparatorluk ve Kozmik Zirve
      case BuildingType.celestialAnvil:
      case BuildingType.ancestralTotem:
      case BuildingType.prismaticResonator:
        return 50;
    }
  }
}

class BuildingModel {
  final BuildingType type;
  final int level;
  final double accumulatedResource;
  final double totalGathered;
  final int variant;

  const BuildingModel({
    required this.type,
    this.level = 1,
    this.accumulatedResource = 0.0,
    this.totalGathered = 0.0,
    this.variant = 0,
  });

  BuildingModel copyWith({
    BuildingType? type,
    int? level,
    double? accumulatedResource,
    double? totalGathered,
    int? variant,
  }) {
    return BuildingModel(
      type: type ?? this.type,
      level: level ?? this.level,
      accumulatedResource: accumulatedResource ?? this.accumulatedResource,
      totalGathered: totalGathered ?? this.totalGathered,
      variant: variant ?? this.variant,
    );
  }

  /// Binaların temel maliyet ve büyüme bilgileri
  double get baseCost {
    switch (type) {
      case BuildingType.castle:
        return 50.0;
      case BuildingType.corn:
        return 10.0;
      case BuildingType.barley:
        return 12.0;
      case BuildingType.pasture:
        return 28.0;
      case BuildingType.orchard:
        return 30.0;
      case BuildingType.quarry:
        return 25.0;
      case BuildingType.resinCamp:
        return 35.0;
      case BuildingType.lumberjack:
        return 15.0;
      case BuildingType.windmill:
        return 25.0;
      case BuildingType.sawmill:
        return 30.0;
      case BuildingType.bakery:
        return 50.0;
      case BuildingType.furniture:
        return 60.0;
      case BuildingType.worker:
        return 35.0;
      case BuildingType.watchtower:
        return 40.0;
      case BuildingType.mine:
        return 55.0;
      case BuildingType.bridge:
        return 20.0;
      case BuildingType.fisherman:
        return 30.0;
      case BuildingType.fishermanHut:
        return 45.0;

      // Özel Binalar
      case BuildingType.oasisCistern:
        return 45.0;
      case BuildingType.caravanserai:
        return 80.0;
      case BuildingType.astrolabe:
        return 120.0;

      case BuildingType.reindeerSanctuary:
        return 60.0;
      case BuildingType.geothermalBath:
        return 90.0;
      case BuildingType.permafrostDig:
        return 130.0;

      case BuildingType.steamVent:
        return 85.0;
      case BuildingType.obsidianForge:
        return 150.0;

      case BuildingType.herbalistYurt:
        return 40.0;
      case BuildingType.scribeWorkshop:
        return 75.0;

      case BuildingType.celestialAnvil:
        return 200.0;
      case BuildingType.ancestralTotem:
        return 250.0;
      case BuildingType.prismaticResonator:
        return 220.0;

      // 5 Büyük Yeni Mekanik Binaları
      case BuildingType.granaryVault:
        return 40.0;
      case BuildingType.kumisYurt:
        return 70.0;
      case BuildingType.feltTentWorkshop:
        return 65.0;
      case BuildingType.damascusForge:
        return 120.0;
      case BuildingType.runicStele:
        return 80.0;
    }
  }

  double get costGrowthFactor => 1.15;

  /// Kilometre taşı seviyeleri (2x üretim artışı, 10x maliyet artışı)
  static const List<int> milestoneLevels = [10, 25, 50, 100, 200];

  /// Şato (Kağan Otağı) görsel evrim kilometre taşları: 5, 15, 30, 50
  static const List<int> castleVisualMilestoneLevels = [5, 15, 30, 50];

  /// Verilen seviyenin ulaştığı kilometre taşı kademesi (0..5)
  static int getMilestoneTier(int lvl) {
    if (lvl >= 200) return 5;
    if (lvl >= 100) return 4;
    if (lvl >= 50) return 3;
    if (lvl >= 25) return 2;
    if (lvl >= 10) return 1;
    return 0;
  }

  /// Yapının görsel evrim kademesi (Visual Tier)
  /// Şato özelinde: Seviye 5, 15, 30, 50 basamaklarında görünüm değişir.
  /// Normal binalarda: Her 2X sıçramadan sonra (Seviye 10, 25, 50, 100, 200) görünüm değişir.
  int get visualTier {
    if (type == BuildingType.castle) {
      if (level >= 50) return 4;
      if (level >= 30) return 3;
      if (level >= 15) return 2;
      if (level >= 5) return 1;
      return 0;
    }
    return getMilestoneTier(level);
  }

  /// Bir sonraki seviyenin kilometre taşı olup olmadığı
  bool get isNextLevelMilestone => milestoneLevels.contains(level + 1);

  /// Seviye yükseltme maliyeti (Hedef seviye kilometre taşlarına ulaştıkça her kademede 10x maliyet artışı)
  double get upgradeCost {
    final int targetMilestoneTier = getMilestoneTier(level + 1);
    final double milestoneCostMultiplier = math.pow(10.0, targetMilestoneTier).toDouble();
    return baseCost * math.pow(costGrowthFactor, level - 1) * milestoneCostMultiplier;
  }

  /// Temel üretim hızı (birim/saniye)
  double get baseProductionRate {
    switch (type) {
      case BuildingType.castle:
        return 0.10;
      case BuildingType.corn:
        return 0.42;
      case BuildingType.barley:
        return 0.40;
      case BuildingType.pasture:
        return 0.48;
      case BuildingType.orchard:
        return 0.52;
      case BuildingType.quarry:
        return 0.35;
      case BuildingType.resinCamp:
        return 0.32;
      case BuildingType.lumberjack:
        return 0.35;
      case BuildingType.windmill:
        return 0.25;
      case BuildingType.sawmill:
        return 0.20;
      case BuildingType.bakery:
        return 0.25;
      case BuildingType.furniture:
        return 0.20;
      case BuildingType.mine:
        return 0.30;
      case BuildingType.fisherman:
        return 0.35;

      // Özel Binalar
      case BuildingType.oasisCistern:
        return 0.30; // Su ve aura bereketi
      case BuildingType.caravanserai:
        return 0.18; // Altın ve Taç getirisi
      case BuildingType.astrolabe:
        return 0.15; // Töre bilgisi çarpanı
      case BuildingType.reindeerSanctuary:
        return 0.32; // Kürk ve gıda
      case BuildingType.geothermalBath:
        return 0.20; // Buhar ve enerji
      case BuildingType.permafrostDig:
        return 0.22; // Antik kehribar ve maden
      case BuildingType.steamVent:
        return 0.28; // Buhar basıncı
      case BuildingType.obsidianForge:
        return 0.25; // Obsidyen döküm
      case BuildingType.herbalistYurt:
        return 0.35; // Şifa ve bitkisel iksir
      case BuildingType.scribeWorkshop:
        return 0.22; // Parşömen ve yazıt
      case BuildingType.celestialAnvil:
        return 0.16; // Mithril ve Tamga
      case BuildingType.ancestralTotem:
        return 0.20; // Atalar bereketi
      case BuildingType.prismaticResonator:
        return 0.24; // Kristal rezonans

      // 5 Büyük Yeni Mekanik Binaları
      case BuildingType.granaryVault:
        return 0.0; // Ambar üretim yapmaz, lojistik tamponudur
      case BuildingType.kumisYurt:
        return 0.25; // Kımız ve şifa üretimi
      case BuildingType.feltTentWorkshop:
        return 0.22; // Keçe ve zırh üretimi
      case BuildingType.damascusForge:
        return 0.18; // Şam çeliği üretimi
      case BuildingType.runicStele:
        return 0.15; // Saniyelik Bilgelik / Lore üretimi
      default:
        return 0.0;
    }
  }

  /// Temel taşıma kapasitesi (İşçiler için)
  double get baseCarryingCapacity {
    switch (type) {
      case BuildingType.worker:
        return 1.68;
      case BuildingType.fishermanHut:
        return 1.40;
      case BuildingType.granaryVault:
        return 2.50; // Kurgan Mahzeni yüksek lojistik taşıma kapasitesi sunar
      default:
        return 0.0;
    }
  }

  /// Seviyeye göre anlık üretim hızı
  double get currentProductionRate {
    final int k = getMilestoneTier(level);
    final double milestoneBoost = math.pow(2.0, k).toDouble();
    return baseProductionRate * level * milestoneBoost;
  }

  /// Bir sonraki seviyedeki baz üretim hızı (çarpanlar hariç)
  double get nextLevelProductionRate {
    final int nextLvl = level + 1;
    final int k = getMilestoneTier(nextLvl);
    final double milestoneBoost = math.pow(2.0, k).toDouble();
    return baseProductionRate * nextLvl * milestoneBoost;
  }

  /// Seviyeye göre anlık taşıma kapasitesi
  double get currentCarryingCapacity {
    final int k = getMilestoneTier(level);
    final double milestoneBoost = math.pow(2.0, k).toDouble();
    return baseCarryingCapacity * level * milestoneBoost;
  }

  /// Maksimum birikim kapasitesi (otomasyonsuz durumda)
  double get maxCapacity => currentProductionRate * 30.0;

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'level': level,
        'accumulated_resource': accumulatedResource,
        'total_gathered': totalGathered,
        'variant': variant,
      };

  factory BuildingModel.fromJson(Map<String, dynamic> json) {
    final String typeName = json['type'] as String? ?? 'corn';
    final BuildingType bType = BuildingType.values.firstWhere(
      (e) => e.name == typeName,
      orElse: () => BuildingType.corn,
    );
    return BuildingModel(
      type: bType,
      level: json['level'] as int? ?? 1,
      accumulatedResource:
          (json['accumulated_resource'] as num?)?.toDouble() ?? 0.0,
      totalGathered: (json['total_gathered'] as num?)?.toDouble() ?? 0.0,
      variant: json['variant'] as int? ?? 0,
    );
  }

  factory BuildingModel.fromLegacy(String bType, int bLvl, double bAccum) {
    final BuildingType type = BuildingType.values.firstWhere(
      (e) => e.name == bType,
      orElse: () => BuildingType.corn,
    );

    return BuildingModel(
      type: type,
      level: bLvl,
      accumulatedResource: bAccum,
      totalGathered: 0.0,
    );
  }
}
