import 'dart:math' as math;
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../../../core/hex/hex_coordinates.dart';
import '../../../domain/models/fauna_model.dart';
import '../hex_map_game.dart';
import '../renderers/voxel_fauna_renderer.dart';

/// Karolar üzerindeki ve bozkırdaki canlı popülasyonunu yöneten bağımsız Flame bileşeni (Fauna Herd Engine)
class FaunaHerdComponent extends PositionComponent {
  final HexAxial coord;
  final FaunaType primaryType;
  final int seed;
  final List<Offset> neighborOffsets;
  String season;
  bool isZud;
  bool isNight;

  double _time = 0.0;
  double _startleTimer = 0.0;

  FaunaHerdComponent({
    required this.coord,
    this.primaryType = FaunaType.horse,
    required this.seed,
    this.neighborOffsets = const [],
    this.season = 'SPRING',
    this.isZud = false,
    this.isNight = false,
    required Vector2 position,
  }) : super(
          position: position,
          size: Vector2(48, 48),
          anchor: Anchor.center,
          priority: 85,
        );

  void triggerStartle() {
    _startleTimer = 0.65;
  }

  void updateEnvironment({
    required String newSeason,
    required bool newIsZud,
    bool newIsNight = false,
  }) {
    season = newSeason;
    isZud = newIsZud;
    isNight = newIsNight;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
    if (_startleTimer > 0.0) {
      _startleTimer = math.max(0.0, _startleTimer - dt);
    }
  }

  @override
  void render(Canvas canvas) {
    // Frustum / Viewport Culling
    final game = findGame();
    if (game is HexMapGame) {
      final Rect bounds = game.visibleWorldBounds;
      if (position.x < bounds.left - 48 ||
          position.x > bounds.right + 48 ||
          position.y < bounds.top - 48 ||
          position.y > bounds.bottom + 48) {
        return;
      }
    }

    final double animTime = _time + ((coord.q * 37 + coord.r * 19).abs() % 100) * 0.05;
    final bool isWinter = season == 'WINTER' || isZud;
    final double startleProgress = _startleTimer > 0.0 ? (0.65 - _startleTimer) / 0.65 : 0.0;

    final Offset center = Offset(size.x / 2, size.y / 2);

    switch (primaryType) {
      case FaunaType.horse:
        VoxelFaunaRenderer.drawHorse(
          canvas,
          center,
          animTime: animTime,
          scale: isWinter ? 0.90 : 0.95,
          seed: seed,
          flipX: (seed % 2 != 0),
          startleProgress: startleProgress,
        );
        break;

      case FaunaType.sheep:
        VoxelFaunaRenderer.drawSheep(
          canvas,
          center,
          animTime: animTime,
          scale: 0.90,
          seed: seed,
          flipX: (seed % 2 != 0),
        );
        break;

      case FaunaType.ram:
        VoxelFaunaRenderer.drawRam(
          canvas,
          center,
          animTime: animTime,
          scale: 0.92,
          seed: seed,
          flipX: (seed % 2 != 0),
        );
        break;

      case FaunaType.lamb:
        VoxelFaunaRenderer.drawLamb(
          canvas,
          center,
          animTime: animTime,
          scale: 0.72,
          seed: seed,
          flipX: (seed % 2 != 0),
        );
        break;

      case FaunaType.steppeWolf:
        VoxelFaunaRenderer.drawSteppeWolf(
          canvas,
          center,
          animTime: animTime,
          scale: 0.88,
          seed: seed,
          flipX: (seed % 2 != 0),
        );
        break;

      case FaunaType.mountainIbex:
        VoxelFaunaRenderer.drawMountainIbex(
          canvas,
          center,
          animTime: animTime,
          scale: 0.85,
          seed: seed,
          flipX: (seed % 2 != 0),
        );
        break;

      case FaunaType.camel:
        VoxelFaunaRenderer.drawCamel(
          canvas,
          center,
          animTime: animTime,
          scale: 0.88,
          seed: seed,
          flipX: (seed % 2 != 0),
        );
        break;

      case FaunaType.arcticFox:
        VoxelFaunaRenderer.drawArcticFox(
          canvas,
          center,
          animTime: animTime,
          scale: 0.82,
          seed: seed,
          flipX: (seed % 2 != 0),
        );
        break;

      case FaunaType.skyEagle:
      case FaunaType.crane:
      case FaunaType.swallow:
      case FaunaType.seagull:
        VoxelFaunaRenderer.drawSkyBird(
          canvas,
          center,
          wingAnim: animTime * 3.0,
          scale: 0.85,
        );
        break;
    }
  }
}
