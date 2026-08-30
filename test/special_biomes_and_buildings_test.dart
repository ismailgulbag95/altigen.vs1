import 'package:flutter_test/flutter_test.dart';
import 'package:hex_rush/core/hex/hex_coordinates.dart';
import 'package:hex_rush/domain/economy/economy_calculator.dart';
import 'package:hex_rush/domain/models/building_model.dart';
import 'package:hex_rush/domain/models/hex_tile_model.dart';
import 'package:hex_rush/presentation/providers/game_state_notifier.dart';

void main() {
  group('Özel Biyomlar ve Binalar Test Paketi', () {
    test('13 Yeni Bina için Castle Level Kilitleri ve Temel Veriler Doğru Olmalıdır', () {
      // Seviye 10 & 25 Binalar
      expect(BuildingType.herbalistYurt.requiredCastleLevel, 10);
      expect(BuildingType.oasisCistern.requiredCastleLevel, 25);
      expect(BuildingType.caravanserai.requiredCastleLevel, 25);
      expect(BuildingType.reindeerSanctuary.requiredCastleLevel, 25);

      // Seviye 30 & 35 Binalar
      expect(BuildingType.scribeWorkshop.requiredCastleLevel, 30);
      expect(BuildingType.geothermalBath.requiredCastleLevel, 35);
      expect(BuildingType.permafrostDig.requiredCastleLevel, 35);

      // Seviye 40 & 45 Binalar
      expect(BuildingType.steamVent.requiredCastleLevel, 40);
      expect(BuildingType.obsidianForge.requiredCastleLevel, 40);
      expect(BuildingType.astrolabe.requiredCastleLevel, 45);

      // Seviye 50 Efsanevi Binalar
      expect(BuildingType.celestialAnvil.requiredCastleLevel, 50);
      expect(BuildingType.ancestralTotem.requiredCastleLevel, 50);
      expect(BuildingType.prismaticResonator.requiredCastleLevel, 50);
    });

    test('Biyomlara Özgü İzin Verilen Binalar Doğru Eşleşmelidir', () {
      // Orman
      final forestBuildings = GameStateNotifier.getAllowedBuildingsForBiome(TileBiome.forest);
      expect(forestBuildings.contains(BuildingType.watchtower), isTrue);
      expect(forestBuildings.contains(BuildingType.lumberjack), isTrue);

      // Dağ
      final mountainBuildings = GameStateNotifier.getAllowedBuildingsForBiome(TileBiome.mountain);
      expect(mountainBuildings.contains(BuildingType.worker), isTrue);
      expect(mountainBuildings.contains(BuildingType.granaryVault), isTrue);
      expect(mountainBuildings.contains(BuildingType.mine), isTrue);
      expect(mountainBuildings.contains(BuildingType.quarry), isTrue);

      // Çöl
      final desertBuildings = GameStateNotifier.getAllowedBuildingsForBiome(TileBiome.desert);
      expect(desertBuildings.contains(BuildingType.oasisCistern), isTrue);
      expect(desertBuildings.contains(BuildingType.caravanserai), isTrue);
      expect(desertBuildings.contains(BuildingType.astrolabe), isTrue);
      expect(desertBuildings.contains(BuildingType.quarry), isFalse);
      expect(desertBuildings.contains(BuildingType.watchtower), isTrue);

      // Tundra
      final tundraBuildings = GameStateNotifier.getAllowedBuildingsForBiome(TileBiome.tundra);
      expect(tundraBuildings.contains(BuildingType.reindeerSanctuary), isTrue);
      expect(tundraBuildings.contains(BuildingType.geothermalBath), isTrue);
      expect(tundraBuildings.contains(BuildingType.permafrostDig), isTrue);
      expect(tundraBuildings.contains(BuildingType.granaryVault), isTrue);
      expect(tundraBuildings.contains(BuildingType.watchtower), isTrue);
      expect(tundraBuildings.contains(BuildingType.runicStele), isTrue);

      // Volkan
      final volcanoBuildings = GameStateNotifier.getAllowedBuildingsForBiome(TileBiome.volcano);
      expect(volcanoBuildings.contains(BuildingType.steamVent), isTrue);
      expect(volcanoBuildings.contains(BuildingType.obsidianForge), isTrue);
      expect(volcanoBuildings.contains(BuildingType.quarry), isFalse);
      expect(volcanoBuildings.contains(BuildingType.granaryVault), isTrue);

      // Sazlık
      final wetlandBuildings = GameStateNotifier.getAllowedBuildingsForBiome(TileBiome.wetland);
      expect(wetlandBuildings.contains(BuildingType.herbalistYurt), isTrue);
      expect(wetlandBuildings.contains(BuildingType.scribeWorkshop), isTrue);
      expect(wetlandBuildings.contains(BuildingType.fisherman), isTrue);
      expect(wetlandBuildings.contains(BuildingType.pasture), isTrue);
      expect(wetlandBuildings.contains(BuildingType.granaryVault), isTrue);

      // Efsanevi Biyomlar
      final craterBuildings = GameStateNotifier.getAllowedBuildingsForBiome(TileBiome.celestialCrater);
      expect(craterBuildings.contains(BuildingType.celestialAnvil), isTrue);
      expect(craterBuildings.contains(BuildingType.granaryVault), isTrue);

      final kurganBuildings = GameStateNotifier.getAllowedBuildingsForBiome(TileBiome.kurganValley);
      expect(kurganBuildings.contains(BuildingType.ancestralTotem), isTrue);
      expect(kurganBuildings.contains(BuildingType.granaryVault), isTrue);

      final chasmBuildings = GameStateNotifier.getAllowedBuildingsForBiome(TileBiome.crystalChasm);
      expect(chasmBuildings.contains(BuildingType.prismaticResonator), isTrue);
      expect(chasmBuildings.contains(BuildingType.granaryVault), isTrue);
    });

    test('Harita Üretimi 3 Efsanevi Biyomu İçermelidir', () {
      final notifier = GameStateNotifier();
      final map = notifier.state.tiles;
      
      final bool hasCrater = map.values.any((t) => t.biome == TileBiome.celestialCrater);
      final bool hasKurgan = map.values.any((t) => t.biome == TileBiome.kurganValley);
      final bool hasChasm = map.values.any((t) => t.biome == TileBiome.crystalChasm);

      expect(hasCrater, isTrue);
      expect(hasKurgan, isTrue);
      expect(hasChasm, isTrue);

      // Merkez kale (0,0) çayır olmalıdır
      expect(map[const HexAxial(0, 0)]?.biome, TileBiome.meadow);
      expect(map[const HexAxial(0, 0)]?.building?.type, BuildingType.castle);
      notifier.dispose();
    });

    test('Efsanevi ve Özel Biyom Sinerjileri Doğru Hesaplanmalıdır', () {
      const center = HexAxial(2, 2);
      const tile = HexTileModel(
        coord: center,
        biome: TileBiome.celestialCrater,
        state: TileState.owned,
        building: BuildingModel(type: BuildingType.celestialAnvil, level: 1),
      );

      final synergy = EconomyCalculator.calculateAdjacencySynergy(
        targetTile: tile,
        neighborTiles: [],
        season: 'SPRING',
        isZud: false,
      );

      // Göksel Krater sinerjisi +%50 (1.50)
      expect(synergy, closeTo(1.50, 0.001));

      final labels = EconomyCalculator.getActiveSynergyLabels(
        targetTile: tile,
        neighborTiles: [],
        season: 'SPRING',
        isZud: false,
      );
      expect(labels.any((l) => l.contains('GÖKSEL CEVHER')), isTrue);
    });

    test('Vaha Sarnıcı Komşulara +%40 Bereket Aurası Vermelidir', () {
      const center = HexAxial(3, 3);
      final farmCoord = center.neighbors.first;

      const cisternTile = HexTileModel(
        coord: center,
        biome: TileBiome.desert,
        state: TileState.owned,
        building: BuildingModel(type: BuildingType.oasisCistern, level: 1),
      );

      final farmTile = HexTileModel(
        coord: farmCoord,
        biome: TileBiome.meadow,
        state: TileState.owned,
        building: const BuildingModel(type: BuildingType.corn, level: 1),
      );

      final synergy = EconomyCalculator.calculateAdjacencySynergy(
        targetTile: farmTile,
        neighborTiles: [cisternTile],
        season: 'SUMMER',
        isZud: false,
      );

      // Çöl vaha sarnıcı aurası +%40 (1.40) ve yaz kuraklığını iptal eder
      expect(synergy >= 1.40, isTrue);
    });

    test('Bina ve Biyom Serileştirme Hatasız Çalışmalıdır', () {
      for (final type in BuildingType.values) {
        final serialized = type.name;
        final deserialized = BuildingType.values.byName(serialized);
        expect(deserialized, type);
      }

      for (final biome in TileBiome.values) {
        final serialized = biome.name;
        final deserialized = TileBiome.values.byName(serialized);
        expect(deserialized, biome);
      }
    });

    test('calculateOfflineGains ve calculateNetRates Tüm Özel Binaları Doğru Hesaplamalıdır', () {
      const coord1 = HexAxial(0, 1);
      const coord2 = HexAxial(0, 2);
      const coord3 = HexAxial(0, 3);
      const coord4 = HexAxial(0, 4);

      final tiles = [
        const HexTileModel(
          coord: HexAxial(0, 0),
          biome: TileBiome.meadow,
          state: TileState.owned,
          building: BuildingModel(type: BuildingType.castle, level: 1),
        ),
        const HexTileModel(
          coord: coord1,
          biome: TileBiome.meadow,
          state: TileState.owned,
          building: BuildingModel(type: BuildingType.kumisYurt, level: 1),
        ),
        const HexTileModel(
          coord: coord2,
          biome: TileBiome.meadow,
          state: TileState.owned,
          building: BuildingModel(type: BuildingType.feltTentWorkshop, level: 1),
        ),
        const HexTileModel(
          coord: coord3,
          biome: TileBiome.mountain,
          state: TileState.owned,
          building: BuildingModel(type: BuildingType.damascusForge, level: 1),
        ),
        const HexTileModel(
          coord: coord4,
          biome: TileBiome.celestialCrater,
          state: TileState.owned,
          building: BuildingModel(type: BuildingType.runicStele, level: 1),
        ),
      ];

      final offline = EconomyCalculator.calculateOfflineGains(
        tiles: tiles,
        elapsedSeconds: 100,
        globalMultiplier: 1.0,
      );

      expect(offline.kumis > 0, isTrue);
      expect(offline.felt > 0, isTrue);
      expect(offline.damascusSteel > 0, isTrue);
      expect(offline.wisdom > 0, isTrue);
      expect(offline.hasGains, isTrue);

      final netRates = EconomyCalculator.calculateNetRates(
        tiles: tiles,
        globalMultiplier: 1.0,
        seasonMultiplier: 1.0,
        shrineMultiplier: 1.0,
      );

      expect(netRates.kumis > 0, isTrue);
      expect(netRates.felt > 0, isTrue);
      expect(netRates.damascusSteel > 0, isTrue);
      expect(netRates.wisdom > 0, isTrue);
    });
  });
}
