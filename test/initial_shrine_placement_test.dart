import 'package:flutter_test/flutter_test.dart';
import 'package:hex_rush/core/hex/hex_coordinates.dart';
import 'package:hex_rush/core/hex/hex_math.dart';
import 'package:hex_rush/domain/models/hex_tile_model.dart';
import 'package:hex_rush/presentation/providers/game_state_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Initial Shrine Placement Tests', () {
    test('r=1 ve r=2 halkalarında tapınak bulunmaz, r=3 halkasında (0, 3) karosunda 1 garantili Kutlu Tapınak yer alır', () {
      final notifier = GameStateNotifier();
      final state = notifier.state;

      // 1. r=1 ve r=2 halkalarında tapınak olmadığını doğrula
      const center = HexAxial(0, 0);
      state.tiles.forEach((coord, tile) {
        final dist = HexMath.hexDistance(center, coord);
        if (dist == 1 || dist == 2) {
          expect(tile.hasShrine, isFalse,
              reason: 'r=$dist halkasındaki $coord karosunda tapınak bulunmamalıdır');
        }
      });

      // 2. (0, 3) koordinatındaki r=3 garantili tapınak kontrolü
      const initialShrineCoord = HexAxial(0, 3);
      final initialTile = state.tiles[initialShrineCoord];

      expect(initialTile, isNotNull);
      expect(initialTile!.state, equals(TileState.discovered),
          reason: 'Başlangıçta r=3 tapınak karosu görünür (discovered) olmalıdır');
      expect(initialTile.hasShrine, isTrue,
          reason: 'Başlangıçta (0, 3) karosunda kutlu tapınak bulunmalıdır');
      expect(initialTile.shrine, equals(ShrineType.foodBoost),
          reason: 'Gelişimi hızlandırmak için ilk tapınak Gıda Bereketi olmalıdır');
      expect(initialTile.biome, equals(TileBiome.meadow),
          reason: 'İlk tapınak Çayır biyomunda olmalıdır');

      // 3. Haritada toplam 11 adet Kutlu Tapınak olduğunu doğrula
      final totalShrines = state.tiles.values.where((t) => t.hasShrine).length;
      expect(totalShrines, equals(11),
          reason: 'Harita genelinde toplam 11 adet kutlu tapınak dengesi korunmalıdır');
    });

    test('r=3 tapınağına ulaşıp fethedildiğinde bereket çarpanı devreye girer', () {
      final notifier = GameStateNotifier();
      const initialShrineCoord = HexAxial(0, 3);

      final initialMultiplier = notifier.state.shrineMultiplier;
      expect(initialMultiplier, equals(1.0));

      // (0,1) ve (0,2) fethi ile (0,3)'e hat aç
      notifier.state = notifier.state.copyWith(
        resources: notifier.state.resources.copyWith(food: 5000.0),
        progression: notifier.state.progression.copyWith(castleLevel: 5),
      );

      expect(notifier.conquerTile(const HexAxial(0, 1)), isTrue);
      expect(notifier.conquerTile(const HexAxial(0, 2)), isTrue);
      expect(notifier.conquerTile(initialShrineCoord), isTrue);

      final updatedTile = notifier.state.tiles[initialShrineCoord];
      expect(updatedTile!.isOwned, isTrue);
      expect(notifier.state.shrineMultiplier, greaterThan(1.0));
      expect(notifier.state.shrineMultiplier, closeTo(1.30, 0.001),
          reason: 'Gıda bereketi tapınağı fethiyle çarpan +%30 (1.30) olmalıdır');
    });
  });
}
