import 'package:flutter_test/flutter_test.dart';
import 'package:hex_rush/core/hex/hex_coordinates.dart';
import 'package:hex_rush/core/hex/hex_math.dart';
import 'package:hex_rush/domain/models/hex_tile_model.dart';
import 'package:hex_rush/domain/models/building_model.dart';
import 'package:hex_rush/presentation/providers/game_state_notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Softlock Prevention and Failsafe Tests', () {
    test('Initial map generation respects distance-based biome constraints', () {
      final notifier = GameStateNotifier();
      final state = notifier.state;

      const center = HexAxial(0, 0);
      expect(state.tiles[center]?.isOwned, true);
      expect(state.tiles[center]?.building?.type, BuildingType.castle);

      state.tiles.forEach((coord, tile) {
        final dist = HexMath.hexDistance(center, coord);

        if (dist == 1) {
          // Radius 1: Yalnızca Çayır ve Orman (Dağ, Tapınak, Deniz, Sazlık, Çöl, Volkan yok)
          expect(tile.biome, isNot(TileBiome.mountain));
          expect(tile.biome, isNot(TileBiome.sea));
          expect(tile.biome, isNot(TileBiome.wetland));
          expect(tile.biome, isNot(TileBiome.desert));
          expect(tile.biome, isNot(TileBiome.volcano));
          expect(tile.hasShrine, isFalse);
        } else if (dist == 2) {
          // Radius 2: Çayır, Orman, Çöl (Dağ, Tapınak, Deniz, Volkan yok)
          expect(tile.biome, isNot(TileBiome.mountain));
          expect(tile.biome, isNot(TileBiome.sea));
          expect(tile.biome, isNot(TileBiome.volcano));
          expect(tile.hasShrine, isFalse);
        } else if (dist == 3) {
          // Radius 3: Deniz yok
          expect(tile.biome, isNot(TileBiome.sea));
        }
      });

      notifier.dispose();
    });

    test('Collecting from Castle provides emergency food rations', () {
      final notifier = GameStateNotifier();
      const center = HexAxial(0, 0);

      // Drain all food to 0 to simulate bankruptcy
      notifier.state = notifier.state.copyWith(
        resources: notifier.state.resources.copyWith(food: 0.0),
      );
      expect(notifier.state.resources.food, 0.0);

      // Tap castle for emergency rations
      final collected = notifier.collectFromTile(center);
      expect(collected, true);
      expect(notifier.state.resources.food, 1.0);

      // Tap 4 more times
      for (int i = 0; i < 4; i++) {
        notifier.collectFromTile(center);
      }
      expect(notifier.state.resources.food, 5.0);

      notifier.dispose();
    });
  });
}
