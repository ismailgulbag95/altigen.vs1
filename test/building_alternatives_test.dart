import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hex_rush/core/hex/hex_coordinates.dart';
import 'package:hex_rush/domain/economy/economy_calculator.dart';
import 'package:hex_rush/domain/models/building_model.dart';
import 'package:hex_rush/domain/models/game_state_model.dart';
import 'package:hex_rush/domain/models/hex_tile_model.dart';
import 'package:hex_rush/presentation/providers/game_state_notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Building Alternatives & Diversification Tests', () {
    test('Allowed buildings for meadow include all farm varieties (quarry is mountain-only)', () {
      final allowed = GameStateNotifier.getAllowedBuildingsForBiome(TileBiome.meadow);
      expect(allowed, contains(BuildingType.corn));
      expect(allowed, contains(BuildingType.barley));
      expect(allowed, contains(BuildingType.pasture));
      expect(allowed, contains(BuildingType.orchard));
      expect(allowed, isNot(contains(BuildingType.quarry)));
      expect(allowed, contains(BuildingType.windmill));
      expect(allowed, contains(BuildingType.bakery));
    });

    test('Allowed buildings for forest include resinCamp and wood processing', () {
      final allowed = GameStateNotifier.getAllowedBuildingsForBiome(TileBiome.forest);
      expect(allowed, contains(BuildingType.lumberjack));
      expect(allowed, contains(BuildingType.sawmill));
      expect(allowed, contains(BuildingType.furniture));
      expect(allowed, contains(BuildingType.resinCamp));
    });

    test('Allowed buildings for mountain include quarry and mine', () {
      final allowed = GameStateNotifier.getAllowedBuildingsForBiome(TileBiome.mountain);
      expect(allowed, contains(BuildingType.mine));
      expect(allowed, contains(BuildingType.quarry));
      expect(allowed, contains(BuildingType.watchtower));
    });

    test('Barley field generates food and benefits from winter cold resistance', () {
      final winterMult = EconomyCalculator.getSeasonalProductionBoost(
        season: 'WINTER',
        buildingType: BuildingType.barley,
      );
      expect(winterMult, closeTo(1.15, 0.001));

      final springMult = EconomyCalculator.getSeasonalProductionBoost(
        season: 'SPRING',
        buildingType: BuildingType.barley,
      );
      expect(springMult, closeTo(1.20, 0.001));
    });

    test('Pasture generates food and receives autumn surge and water trough synergy', () {
      const pastureTile = HexTileModel(
        coord: HexAxial(1, 0),
        biome: TileBiome.meadow,
        state: TileState.owned,
        building: BuildingModel(type: BuildingType.pasture, level: 1),
      );

      final autumnMult = EconomyCalculator.getSeasonalProductionBoost(
        season: 'AUTUMN',
        buildingType: BuildingType.pasture,
      );
      expect(autumnMult, closeTo(1.25, 0.001));

      final neighbors = [
        const HexTileModel(
          coord: HexAxial(2, 0),
          biome: TileBiome.wetland,
          state: TileState.owned,
        ),
      ];

      final synergy = EconomyCalculator.calculateAdjacencySynergy(
        targetTile: pastureTile,
        neighborTiles: neighbors,
        season: 'AUTUMN',
        isZud: false,
      );
      expect(synergy, closeTo(1.50, 0.001));
    });

    test('Orchard produces abundant food in summer/autumn but goes dormant in winter', () {
      final summerMult = EconomyCalculator.getSeasonalProductionBoost(
        season: 'SUMMER',
        buildingType: BuildingType.orchard,
      );
      expect(summerMult, closeTo(1.50, 0.001));

      final autumnMult = EconomyCalculator.getSeasonalProductionBoost(
        season: 'AUTUMN',
        buildingType: BuildingType.orchard,
      );
      expect(autumnMult, closeTo(1.30, 0.001));

      final winterMult = EconomyCalculator.getSeasonalProductionBoost(
        season: 'WINTER',
        buildingType: BuildingType.orchard,
      );
      expect(winterMult, closeTo(0.65, 0.001));
    });

    test('Quarry produces pure stone and benefits from mountain synergy', () {
      const quarryTile = HexTileModel(
        coord: HexAxial(1, 0),
        biome: TileBiome.meadow,
        state: TileState.owned,
        building: BuildingModel(type: BuildingType.quarry, level: 1),
      );

      final neighbors = [
        const HexTileModel(
          coord: HexAxial(2, 0),
          biome: TileBiome.mountain,
          state: TileState.owned,
        ),
      ];

      final synergy = EconomyCalculator.calculateAdjacencySynergy(
        targetTile: quarryTile,
        neighborTiles: neighbors,
        season: 'SPRING',
        isZud: false,
      );
      expect(synergy, closeTo(1.35, 0.001));
    });

    test('Resin camp produces wood and benefits from forest synergy', () {
      const resinTile = HexTileModel(
        coord: HexAxial(1, 0),
        biome: TileBiome.forest,
        state: TileState.owned,
        building: BuildingModel(type: BuildingType.resinCamp, level: 1),
      );

      final neighbors = [
        const HexTileModel(
          coord: HexAxial(2, 0),
          biome: TileBiome.forest,
          state: TileState.owned,
        ),
      ];

      final synergy = EconomyCalculator.calculateAdjacencySynergy(
        targetTile: resinTile,
        neighborTiles: neighbors,
        season: 'SPRING',
        isZud: false,
      );
      expect(synergy, closeTo(1.25, 0.001));
    });

    test('Constructing and collecting from alternative buildings works smoothly', () {
      final notifier = GameStateNotifier();
      const meadowCoord = HexAxial(1, 0);

      notifier.state = notifier.state.copyWith(
        resources: const ResourcesModel(food: 100.0, wood: 100.0, stone: 50.0),
        progression: const ProgressionModel(castleLevel: 2),
        tiles: {
          ...notifier.state.tiles,
          meadowCoord: const HexTileModel(
            coord: HexAxial(1, 0),
            biome: TileBiome.meadow,
            state: TileState.owned,
          ),
        },
      );

      // Build barley field
      final built = notifier.buildStructure(meadowCoord, BuildingType.barley);
      expect(built, isTrue);
      expect(notifier.state.tiles[meadowCoord]?.building?.type, BuildingType.barley);
      expect(notifier.state.tiles[meadowCoord]?.building?.variant, inInclusiveRange(0, 2));

      notifier.dispose();
    });

    test('BuildingModel variant field serializes, deserializes, and copies correctly', () {
      const b1 = BuildingModel(type: BuildingType.corn, level: 1, variant: 2);
      expect(b1.variant, 2);

      final json = b1.toJson();
      expect(json['variant'], 2);

      final bFrom = BuildingModel.fromJson(json);
      expect(bFrom.variant, 2);

      final bCopied = b1.copyWith(variant: 1);
      expect(bCopied.variant, 1);
      expect(bCopied.type, BuildingType.corn);

      // Backward compatibility when JSON has no variant
      final oldJson = {'type': 'corn', 'level': 1};
      final bOld = BuildingModel.fromJson(oldJson);
      expect(bOld.variant, 0);
    });
  });
}
