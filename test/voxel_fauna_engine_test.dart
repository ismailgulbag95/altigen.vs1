import 'dart:ui';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex_rush/core/hex/hex_coordinates.dart';
import 'package:hex_rush/domain/models/fauna_model.dart';
import 'package:hex_rush/presentation/flame/components/fauna_herd_component.dart';
import 'package:hex_rush/presentation/flame/renderers/voxel_fauna_renderer.dart';
import 'package:hex_rush/presentation/flame/renderers/voxel_isometric_renderer.dart';

void main() {
  group('Fauna & Voxel Living World Engine Tests', () {
    test('FaunaEntity initializes and copies with immutability', () {
      const entity = FaunaEntity(
        id: 'fauna_1',
        type: FaunaType.horse,
        position: Offset(10, 20),
        coat: FaunaCoatVariant.doru,
        state: FaunaBehaviorState.grazing,
      );

      expect(entity.id, 'fauna_1');
      expect(entity.type, FaunaType.horse);
      expect(entity.coat, FaunaCoatVariant.doru);
      expect(entity.state, FaunaBehaviorState.grazing);

      final updated = entity.copyWith(
        state: FaunaBehaviorState.roaming,
        position: const Offset(15, 25),
        startleTimer: 0.5,
      );

      expect(updated.state, FaunaBehaviorState.roaming);
      expect(updated.position, const Offset(15, 25));
      expect(updated.startleTimer, 0.5);
      expect(entity.state, FaunaBehaviorState.grazing); // Immutable check
    });

    test('VoxelFaunaRenderer renders all animal species without throwing', () {
      final PictureRecorder recorder = PictureRecorder();
      final Canvas canvas = Canvas(recorder);

      // 1. At (Tüm 4 Don Varyantı & İrkilme)
      for (int seed = 0; seed < 4; seed++) {
        VoxelFaunaRenderer.drawHorse(
          canvas,
          const Offset(100, 100),
          animTime: 1.5,
          scale: 1.0,
          seed: seed,
          flipX: seed % 2 != 0,
          startleProgress: 0.3,
        );
      }

      // 2. Koyun (Tüm 4 Kürk & Davranış Modu)
      for (int seed = 0; seed < 4; seed++) {
        VoxelFaunaRenderer.drawSheep(
          canvas,
          const Offset(100, 100),
          animTime: 2.0,
          scale: 0.9,
          seed: seed,
          flipX: seed % 2 != 0,
        );
      }

      // 3. Koç
      VoxelFaunaRenderer.drawRam(
        canvas,
        const Offset(100, 100),
        animTime: 1.0,
        scale: 1.0,
        seed: 7,
      );

      // 4. Kuzu
      VoxelFaunaRenderer.drawLamb(
        canvas,
        const Offset(100, 100),
        animTime: 1.2,
        scale: 0.72,
        seed: 3,
      );

      // 5. Bozkır Kurdu
      VoxelFaunaRenderer.drawSteppeWolf(
        canvas,
        const Offset(100, 100),
        animTime: 3.0,
        scale: 1.0,
        seed: 11,
      );

      // 6. Dağ Yaban Keçisi
      VoxelFaunaRenderer.drawMountainIbex(
        canvas,
        const Offset(100, 100),
        animTime: 2.5,
        scale: 0.85,
        seed: 19,
      );

      // 7. Kutup Beyaz Tilkisi
      VoxelFaunaRenderer.drawArcticFox(
        canvas,
        const Offset(100, 100),
        animTime: 1.8,
        scale: 0.8,
        seed: 5,
      );

      // 8. İki Hörgüçlü Çöl Devesi
      VoxelFaunaRenderer.drawCamel(
        canvas,
        const Offset(100, 100),
        animTime: 2.2,
        scale: 1.0,
        seed: 13,
      );

      // 9. Kervan Yük Devesi
      VoxelFaunaRenderer.drawCaravanCamel(
        canvas,
        const Offset(100, 100),
        animTime: 3.5,
        walkCycle: 0.5,
        flipX: true,
      );

      // 10. Gökyüzü Kuşu
      VoxelFaunaRenderer.drawSkyBird(
        canvas,
        const Offset(100, 100),
        wingAnim: 0.5,
        scale: 1.2,
      );

      final picture = recorder.endRecording();
      expect(picture, isNotNull);
    });

    test('FaunaHerdComponent updates, responds to startle and renders', () {
      final herd = FaunaHerdComponent(
        coord: const HexAxial(1, 2),
        primaryType: FaunaType.horse,
        seed: 42,
        position: Vector2(50, 50),
      );

      herd.update(0.1);
      herd.triggerStartle();
      expect(herd.isMounted, false);

      final PictureRecorder recorder = PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      herd.render(canvas);

      final picture = recorder.endRecording();
      expect(picture, isNotNull);
    });

    test('VoxelIsometricRenderer bridge delegations work seamlessly', () {
      final PictureRecorder recorder = PictureRecorder();
      final Canvas canvas = Canvas(recorder);

      VoxelIsometricRenderer.drawVoxelHorse(canvas, const Offset(50, 50), animTime: 1.0, seed: 1);
      VoxelIsometricRenderer.drawVoxelSheep(canvas, const Offset(50, 50), animTime: 1.0, seed: 2);
      VoxelIsometricRenderer.drawVoxelDeer(canvas, const Offset(50, 50), animTime: 1.0, seed: 3);
      VoxelIsometricRenderer.drawVoxelCamel(canvas, const Offset(50, 50), animTime: 1.0, seed: 4);
      VoxelIsometricRenderer.drawVoxelArcticFox(canvas, const Offset(50, 50), animTime: 1.0, seed: 5);
      VoxelIsometricRenderer.drawVoxelMountainIbex(canvas, const Offset(50, 50), animTime: 1.0, seed: 6);
      VoxelIsometricRenderer.drawVoxelBird(canvas, const Offset(50, 50), wingAnim: 1.0);
      VoxelIsometricRenderer.drawVoxelCaravanCamel(canvas, const Offset(50, 50), animTime: 1.0);

      final picture = recorder.endRecording();
      expect(picture, isNotNull);
    });
  });
}
