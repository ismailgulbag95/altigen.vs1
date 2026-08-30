import 'dart:math' as math;
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../../../core/graphics/hex_shader_service.dart';
import '../../../core/hex/hex_coordinates.dart';
import '../../../core/hex/hex_math.dart';
import '../../../core/theme/neo_brutalist_theme.dart';
import '../../../domain/models/building_model.dart';
import '../../../domain/models/combat_model.dart';
import '../../../domain/models/hex_tile_model.dart';
import '../../../domain/services/symbiosis_engine.dart';
import '../hex_map_game.dart';
import '../renderers/viewport_culling_manager.dart';
import '../renderers/voxel_fauna_renderer.dart';
import '../renderers/voxel_isometric_renderer.dart';

/// Biyom canlılarının dinamik hareket, yön ve animasyon verisi
class FaunaRoamData {
  final Offset offset;
  final bool flipX;
  final double walkAnim;
  final bool isMoving;

  const FaunaRoamData({
    required this.offset,
    required this.flipX,
    required this.walkAnim,
    required this.isMoving,
  });
}

class HexTileComponent extends PositionComponent {
  final HexAxial coord;
  HexTileModel tileModel;
  bool isSelected;
  bool isInWorkerRange;
  bool isHarvestHighlight;
  String season;
  bool isZud;
  bool isNight;
  String themePalette;
  bool isFrenzyActive;

  // Zero-GC Cached Paint Objects
  static final Paint _workerRangeBorderPaint = Paint()
    ..color = const Color(0x9910B981) // Translucent emerald green
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;

  static final Paint _workerRangeFillPaint = Paint()
    ..color = const Color(0x1810B981) // Soft translucent emerald fill
    ..style = PaintingStyle.fill;

  static final Paint _harvestTargetBorderPaint = Paint()
    ..color = const Color(0xFF10B981) // Solid emerald green
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5;

  static final Paint _harvestTargetFillPaint = Paint()
    ..color = const Color(0x3310B981) // Medium emerald fill
    ..style = PaintingStyle.fill;

  final void Function(HexAxial coord)? onTileTapped;

  double _animTimer = 0.0;
  double get tileAnimTime => _animTimer + ((coord.q * 37 + coord.r * 19).abs() % 100) * 0.05;
  double _bounceTimer = 0.0;
  static const double _bounceDuration = 0.25;

  double _buildBounceTimer = 0.0;
  static const double _buildBounceDuration = 0.35;

  // Sis Dağılma & Keşif Efekti (Fog of War Reveal Engine)
  double _revealTimer = 0.0;
  static const double _revealDuration = 0.65;

  // Organik Mevsim Geçişi (Season Cross-Fade & Melting Engine)
  String _previousSeason = 'SPRING';
  String _currentSeason = 'SPRING';
  double _seasonTransitionTimer = 0.0;
  static const double _seasonTransitionDuration = 2.0;

  static const double hexRadius = 52.0;
  static const double baseDepth3D = 20.0;

  // Pre-allocated corner arrays for zero-GC rendering
  final List<Offset> _corners = List.filled(6, Offset.zero);
  final List<Offset> _groundCorners = List.filled(6, Offset.zero);
  final List<Offset> _mistCorners = List.filled(6, Offset.zero);

  // Zero-GC Reusable static drawing tools
  static final Paint _sharedFillPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _sharedStrokePaint = Paint()..style = PaintingStyle.stroke;
  static final Paint _highlightPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;
  static final Paint _selectBorderPaint = Paint()
    ..color = const Color(0xFFFFD700)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3.0;
  static final Paint _warmPaint = Paint()
    ..color = const Color(0xFFF97316)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5;
  static final Paint _warmFillPaint = Paint()
    ..color = const Color(0x22F97316)
    ..style = PaintingStyle.fill;
  static final Paint _badgeShadowPaint = Paint()..color = Colors.black;
  static final Paint _unownedTopScrimPaint = Paint()
    ..color = const Color(0x18020617)
    ..style = PaintingStyle.fill;
  static final Paint _unownedBorderPaint = Paint()
    ..color = const Color(0x3A000000)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;
  static final Paint _ownedTerritoryBorderPaint = Paint()
    ..color = const Color(0x55D97706)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6;

  // Uçurum, Jeolojik Katman ve Kot Farkı Derinlik Araçları (Zero-GC)
  static final Paint _strataDarkPaint = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.2;
  static final Paint _strataLightPaint = Paint()..style = PaintingStyle.stroke..strokeWidth = 0.8;
  static final Paint _cliffLipHighlightPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2
    ..color = const Color(0x33FFFFFF);
  static final Paint _cliffBaseAoPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5
    ..color = const Color(0x55020617);
  static final Paint _cliffCastShadowPaint = Paint()..style = PaintingStyle.fill;
  static final Path _cliffShadowPath = Path();

  // Neo-Brutalist Ada Sınırı ve Uçurum Katmanı (Island Perimeter Diorama Slabs)
  static final Paint _islandPerimeterBorderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.8
    ..color = const Color(0xFF020617);
  static final Paint _islandPerimeterAccentPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2;
  static final Paint _islandPerimeterShadowPaint = Paint()
    ..style = PaintingStyle.fill
    ..color = const Color(0x66000000);
  static final Path _islandShadowPath = Path();

  static final Path _fogPath = Path();
  static final Path _wallPath = Path();
  static final Path _topPath = Path();

  List<Offset> compatibleNeighborOffsets;
  double northWestDeltaElevation;
  int fogNeighborMask;

  HexTileComponent({
    required this.coord,
    required this.tileModel,
    required this.isSelected,
    this.isInWorkerRange = false,
    this.isHarvestHighlight = false,
    required this.season,
    required this.isZud,
    this.isNight = false,
    this.themePalette = 'basalt',
    this.isFrenzyActive = false,
    this.compatibleNeighborOffsets = const [],
    this.northWestDeltaElevation = 0.0,
    this.fogNeighborMask = 0,
    this.onTileTapped,
  })  : _previousSeason = season,
        _currentSeason = season,
        super(
          position: Vector2(
            HexMath.hexToPixel(coord, hexSize: hexRadius).dx,
            HexMath.hexToPixel(coord, hexSize: hexRadius).dy,
          ),
          size: Vector2(hexRadius * 2.2, hexRadius * 2.5),
          anchor: Anchor.center,
        );

  void triggerTapBounce() {
    _bounceTimer = _bounceDuration;
  }

  void updateData({
    required HexTileModel newTileModel,
    required bool newIsSelected,
    bool newIsInWorkerRange = false,
    bool newIsHarvestHighlight = false,
    required String newSeason,
    required bool newIsZud,
    bool? newIsNight,
    String? newThemePalette,
    bool newIsFrenzyActive = false,
    List<Offset>? newCompatibleNeighborOffsets,
    double? newNorthWestDeltaElevation,
    int? newFogNeighborMask,
  }) {
    isFrenzyActive = newIsFrenzyActive;
    if (!isSelected && newIsSelected) {
      triggerTapBounce();
    }
    if (newThemePalette != null) {
      themePalette = newThemePalette;
    }
    if (newCompatibleNeighborOffsets != null) {
      compatibleNeighborOffsets = newCompatibleNeighborOffsets;
    }
    if (newNorthWestDeltaElevation != null) {
      northWestDeltaElevation = newNorthWestDeltaElevation;
    }
    if (newFogNeighborMask != null) {
      fogNeighborMask = newFogNeighborMask;
    }

    final bool buildingAdded = !tileModel.hasBuilding && newTileModel.hasBuilding;
    final bool buildingUpgraded = tileModel.hasBuilding &&
        newTileModel.hasBuilding &&
        newTileModel.building!.level > tileModel.building!.level;
    if (buildingAdded || buildingUpgraded) {
      _buildBounceTimer = _buildBounceDuration;
    }

    // Sis Açılma Geçişi Tespiti (Fog -> Discovered)
    if (tileModel.isFog && !newTileModel.isFog) {
      _revealTimer = _revealDuration;
    }

    // Mevsim Değişimi Geçişi Tespiti (Sezon veya Zud Afeti Geçişi)
    if (newSeason != _currentSeason || newIsZud != isZud) {
      _previousSeason = _currentSeason;
      _currentSeason = newSeason;
      _seasonTransitionTimer = _seasonTransitionDuration;
    }

    tileModel = newTileModel;
    isSelected = newIsSelected;
    isInWorkerRange = newIsInWorkerRange;
    isHarvestHighlight = newIsHarvestHighlight;
    season = newSeason;
    isZud = newIsZud;
    if (newIsNight != null) isNight = newIsNight;
  }

  /// Canlı Biyom Hayvanlarının Dinamik Gezinme ve Göç Hesabı (Fauna Wandering & Migration Engine)
  FaunaRoamData getFaunaRoamData(int faunaSeed, {double speedMultiplier = 1.0}) {
    final double timeOffset = ((faunaSeed * 5.41).abs() % 40.0);
    final double t = (tileAnimTime * speedMultiplier * 0.45) + timeOffset;

    if (compatibleNeighborOffsets.isNotEmpty) {
      final int n = compatibleNeighborOffsets.length;
      final int cycleIndex = (t / 22.0).floor();
      final int targetIndex = (faunaSeed + cycleIndex) % n;
      final Offset targetOffset = compatibleNeighborOffsets[targetIndex];
      final double cycle = t % 22.0;

      if (cycle < 5.0) {
        // 1. Ana Karoda Otlama / Yavaş Adımlama (0s - 5s)
        final double phaseT = cycle;
        final double ox = math.cos(phaseT * 0.7) * 7.0;
        final double oy = math.sin(phaseT * 0.5) * 4.0;
        final double vx = -math.sin(phaseT * 0.7) * 4.9;
        return FaunaRoamData(
          offset: Offset(ox, oy),
          flipX: vx > 0.15 ? true : (vx < -0.15 ? false : faunaSeed % 2 != 0),
          walkAnim: phaseT < 3.0 ? t * 2.5 : 0.0,
          isMoving: phaseT < 3.0,
        );
      } else if (cycle < 9.5) {
        // 2. Komşu Biyoma Doğru Göç / Yürüme (5s - 9.5s)
        final double progress = (cycle - 5.0) / 4.5;
        final double s = progress * progress * (3.0 - 2.0 * progress);
        final Offset startPt = Offset(math.cos(5.0 * 0.7) * 7.0, math.sin(5.0 * 0.5) * 4.0);
        final Offset endPt = targetOffset * 0.68;
        final Offset currentPos = Offset.lerp(startPt, endPt, s)!;
        final Offset dir = endPt - startPt;
        return FaunaRoamData(
          offset: currentPos,
          flipX: dir.dx > 0, // dx > 0 ise sağa bakar (flipX = true), dx < 0 ise sola bakar (flipX = false)
          walkAnim: t * 3.0,
          isMoving: true,
        );
      } else if (cycle < 15.5) {
        // 3. Komşu Biyomda Otlama ve Keşif (9.5s - 15.5s)
        final double phaseT = cycle - 9.5;
        final Offset neighborBase = targetOffset * 0.68;
        final double ox = math.sin(phaseT * 0.6) * 6.0;
        final double oy = math.cos(phaseT * 0.4) * 3.5;
        final double vx = math.cos(phaseT * 0.6) * 3.6;
        return FaunaRoamData(
          offset: Offset(neighborBase.dx + ox, neighborBase.dy + oy),
          flipX: vx > 0.15 ? true : (vx < -0.15 ? false : faunaSeed % 2 != 0),
          walkAnim: phaseT < 3.5 ? t * 2.2 : 0.0,
          isMoving: phaseT < 3.5,
        );
      } else if (cycle < 20.0) {
        // 4. Ana Karoya Geri Dönüş (15.5s - 20s)
        final double progress = (cycle - 15.5) / 4.5;
        final double s = progress * progress * (3.0 - 2.0 * progress);
        final Offset startPt = targetOffset * 0.68;
        const Offset endPt = Offset.zero;
        final Offset currentPos = Offset.lerp(startPt, endPt, s)!;
        final Offset dir = endPt - startPt;
        return FaunaRoamData(
          offset: currentPos,
          flipX: dir.dx > 0, // Geri dönerken hareket yönüne göre yüzünü dön
          walkAnim: t * 3.0,
          isMoving: true,
        );
      } else {
        // 5. Dinlenme / Çevreye Bakma (20s - 22s)
        return FaunaRoamData(
          offset: Offset.zero,
          flipX: faunaSeed % 2 != 0,
          walkAnim: 0.0,
          isMoving: false,
        );
      }
    } else {
      // Benzer komşu biyom yoksa kendi karosunun içinde devriye döner (16s loop)
      final double cycle = t % 16.0;
      if (cycle < 4.5) {
        final double progress = cycle / 4.5;
        final double s = progress * progress * (3.0 - 2.0 * progress);
        const Offset pA = Offset(-9.0, 4.0);
        const Offset pB = Offset(9.0, -3.0);
        return FaunaRoamData(
          offset: Offset.lerp(pA, pB, s)!,
          flipX: true, // Sağa doğru yürüyor
          walkAnim: t * 2.6,
          isMoving: true,
        );
      } else if (cycle < 8.0) {
        final double sub = cycle - 4.5;
        return FaunaRoamData(
          offset: Offset(9.0 + math.sin(sub * 1.5) * 1.5, -3.0 + math.cos(sub * 1.2) * 1.0),
          flipX: true,
          walkAnim: 0.0,
          isMoving: false,
        );
      } else if (cycle < 12.5) {
        final double progress = (cycle - 8.0) / 4.5;
        final double s = progress * progress * (3.0 - 2.0 * progress);
        const Offset pB = Offset(9.0, -3.0);
        const Offset pC = Offset(-5.0, -6.0);
        return FaunaRoamData(
          offset: Offset.lerp(pB, pC, s)!,
          flipX: false, // Sola doğru yürüyor
          walkAnim: t * 2.6,
          isMoving: true,
        );
      } else {
        final double sub = cycle - 12.5;
        return FaunaRoamData(
          offset: Offset(-5.0 + math.cos(sub * 1.5) * 1.5, -6.0 + math.sin(sub * 1.2) * 1.0),
          flipX: false,
          walkAnim: 0.0,
          isMoving: false,
        );
      }
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _animTimer += dt;
    if (_bounceTimer > 0) {
      _bounceTimer = (_bounceTimer - dt).clamp(0.0, _bounceDuration);
    }
    if (_buildBounceTimer > 0) {
      _buildBounceTimer = (_buildBounceTimer - dt).clamp(0.0, _buildBounceDuration);
    }
    if (_revealTimer > 0) {
      _revealTimer = (_revealTimer - dt).clamp(0.0, _revealDuration);
    }
    if (_seasonTransitionTimer > 0) {
      _seasonTransitionTimer = (_seasonTransitionTimer - dt).clamp(0.0, _seasonTransitionDuration);
    }
  }

  @override
  void render(Canvas canvas) {
    // Frustum / Viewport Culling: Ekran dışındaki karoların render maliyetini sıfırla
    if (!ViewportCullingManager.instance.isRectVisible(
      position.x - hexRadius * 1.3,
      position.y - hexRadius * 1.6,
      position.x + hexRadius * 1.3,
      position.y + hexRadius * 1.6,
    )) {
      return;
    }

    // Dokunsal Pop / Yaylanma zıplaması & İnşaat Düşme Fiziği (Drop & Settle Curve)
    double bounceOffset = 0.0;
    if (_bounceTimer > 0) {
      final double progress = 1.0 - (_bounceTimer / _bounceDuration);
      bounceOffset = math.sin(progress * math.pi) * 8.0;
    } else if (_buildBounceTimer > 0) {
      final double progress = 1.0 - (_buildBounceTimer / _buildBounceDuration);
      if (progress < 0.6) {
        final double dropP = progress / 0.6;
        bounceOffset = -18.0 * (1.0 - dropP) * (1.0 - dropP);
      } else {
        final double settleP = (progress - 0.6) / 0.4;
        bounceOffset = math.sin(settleP * math.pi) * 8.0 * (1.0 - settleP);
      }
    }

    final double elevation = getBiomeElevation(tileModel.biome, isFog: tileModel.isFog) + bounceOffset;
    final Offset center = Offset(size.x / 2, size.y / 2 - elevation);
    HexMath.getHexCornersInto(_corners, center, hexSize: hexRadius, yScale: HexMath.defaultYScale);

    // 1. TAM SİSLİ KARO
    if (tileModel.isFog) {
      _renderVoxelFog(canvas, _corners, center, alpha: 1.0, floatY: 0.0);
      return;
    }

    // 2. SİS DAĞILMA GEÇİŞİ (0.65s Organic Dissolve & Ground Rise)
    if (_revealTimer > 0) {
      final double progress = 1.0 - (_revealTimer / _revealDuration);
      final double eased = Curves.easeOutCubic.transform(progress);

      // Yükselen zemin (Aşağıdan yumuşakça yükselerek belirir)
      final double groundElevation = elevation - (1.0 - eased) * 14.0;
      final Offset groundCenter = Offset(size.x / 2, size.y / 2 - groundElevation);
      HexMath.getHexCornersInto(_groundCorners, groundCenter, hexSize: hexRadius, yScale: HexMath.defaultYScale);

      _render3DExtrudedWalls(canvas, _groundCorners, groundElevation);
      _renderIsometricTopFace(canvas, _groundCorners, groundCenter);
      _renderVoxelObjects(canvas, groundCenter, _groundCorners);
      _renderBrutalistBadges(canvas, groundCenter);

      // Yukarı doğru dağılarak kaybolan sis katmanı
      final double mistAlpha = (1.0 - eased).clamp(0.0, 1.0);
      final double mistFloatY = eased * 30.0;
      _renderVoxelFog(canvas, _corners, center, alpha: mistAlpha, floatY: mistFloatY);
      return;
    }

    // 3. NORMAL AÇIK KARO RENDER (Sahip Olunan Parlak/Canlı, Sahip Olunmayan Karartılmış/Silik)
    _render3DExtrudedWalls(canvas, _corners, elevation);
    _renderIsometricTopFace(canvas, _corners, center);
    _renderVoxelObjects(canvas, center, _corners);

    // İnşaat / Yükseltme Sırasında Voksel Toz Patlaması (Construction Poof)
    if (_buildBounceTimer > 0) {
      final double progress = 1.0 - (_buildBounceTimer / _buildBounceDuration);
      VoxelIsometricRenderer.drawVoxelConstructionPoof(canvas, center, progress);
    }

    _renderBrutalistBadges(canvas, center);
  }

  static double getBiomeElevation(TileBiome biome, {bool isFog = false}) {
    if (isFog) return 0.0;
    switch (biome) {
      case TileBiome.sea:
        return 0.0;
      case TileBiome.wetland:
        return 4.0;
      case TileBiome.crystalChasm:
        return 6.0;
      case TileBiome.desert:
        return 10.0;
      case TileBiome.meadow:
        return 14.0;
      case TileBiome.forest:
        return 20.0;
      case TileBiome.tundra:
        return 24.0;
      case TileBiome.celestialCrater:
        return 28.0;
      case TileBiome.kurganValley:
        return 32.0;
      case TileBiome.volcano:
        return 38.0;
      case TileBiome.mountain:
        return 44.0;
    }
  }

  void _renderVoxelFog(
    Canvas canvas,
    List<Offset> corners,
    Offset center, {
    double alpha = 1.0,
    double floatY = 0.0,
  }) {
    if (alpha <= 0.01) return;

    final Offset mistCenter = Offset(center.dx, center.dy - floatY);
    HexMath.getHexCornersInto(_mistCorners, mistCenter, hexSize: hexRadius, yScale: HexMath.defaultYScale);

    _fogPath
      ..reset()
      ..moveTo(_mistCorners[0].dx, _mistCorners[0].dy);
    for (int i = 1; i < 6; i++) {
      _fogPath.lineTo(_mistCorners[i].dx, _mistCorners[i].dy);
    }
    _fogPath.close();

    // 3D Voksel Canlı Sis Kubbesi, Gizem Işıltıları ve Keşif Fısıltıları
    final int seed = (coord.q * 37 + coord.r * 19).abs();
    final int distFromCenter = HexMath.hexDistance(coord, const HexAxial(0, 0));
    final bool isBorderFog = distFromCenter <= 5;

    // Katı Opaque Bazalt Zemin Katmanı (Arka katmanların görünmesini %100 engeller)
    _sharedFillPaint
      ..color = const Color(0xFF020617)
      ..style = PaintingStyle.fill;
    canvas.drawPath(_fogPath, _sharedFillPaint);

    // GPU Fragment Shader (Eğer destekleniyorsa dinamik gürültü ve parıltı)
    final fogShaderPaint = HexShaderService.getFogShaderPaint(
      resolution: const Size(hexRadius * 2, hexRadius * 2),
      time: _animTimer,
      center: mistCenter,
      alpha: alpha,
      seed: seed.toDouble(),
    );

    if (fogShaderPaint != null) {
      canvas.drawPath(_fogPath, fogShaderPaint);
    }

    _sharedStrokePaint
      ..color = const Color(0xFF0A0F1D).withValues(alpha: (0.45 * alpha).clamp(0.0, 1.0))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawPath(_fogPath, _sharedStrokePaint);

    VoxelIsometricRenderer.drawVoxelMysteryFog(
      canvas,
      mistCenter,
      seed: seed,
      hiddenBiome: tileModel.biome,
      hasShrine: tileModel.hasShrine,
      isBorderFog: isBorderFog,
      animTime: _animTimer,
      alpha: alpha,
      disperseRise: floatY,
    );
  }

  void _render3DExtrudedWalls(Canvas canvas, List<Offset> corners, double elevation) {
    final bool isPerimeter = fogNeighborMask != 0;
    final double wallH = baseDepth3D + elevation + (isPerimeter ? 8.0 : 0.0);
    final (wallLeft, wallRight, bedrock) = _getBiome3DWallColors(tileModel.biome);

    _sharedFillPaint.style = PaintingStyle.fill;
    const List<int> wallToDir = [0, 5, 4, 3];
    for (int i = 1; i <= 3; i++) {
      final pA = corners[i];
      final pB = corners[(i + 1) % 6];

      // Eğer bu yüzey sis/boşluğa bakıyorsa sert 4px neo-brutalist düşen gölge
      final int dir = wallToDir[i];
      final bool facesAbyss = (fogNeighborMask & (1 << dir)) != 0;
      if (facesAbyss) {
        _islandShadowPath
          ..reset()
          ..moveTo(pA.dx, pA.dy + wallH)
          ..lineTo(pB.dx, pB.dy + wallH)
          ..lineTo(pB.dx + 4.0, pB.dy + wallH + 5.0)
          ..lineTo(pA.dx + 4.0, pA.dy + wallH + 5.0)
          ..close();
        canvas.drawPath(_islandShadowPath, _islandPerimeterShadowPaint);
      }

      _wallPath
        ..reset()
        ..moveTo(pA.dx, pA.dy)
        ..lineTo(pB.dx, pB.dy)
        ..lineTo(pB.dx, pB.dy + wallH)
        ..lineTo(pA.dx, pA.dy + wallH)
        ..close();

      final Color col = i == 1
          ? wallLeft
          : (i == 2 ? wallRight : bedrock);

      _sharedFillPaint.color = facesAbyss ? Color.lerp(col, const Color(0xFF020617), 0.25)! : col;
      canvas.drawPath(_wallPath, _sharedFillPaint);

      // Jeolojik Katman Çizgileri (Sedimentary Strata Bands for Elevated Cliffs)
      if (wallH >= 28.0) {
        final double stepCount = wallH >= 46.0 ? 3.0 : 2.0;
        for (double s = 1.0; s < stepCount; s += 1.0) {
          final double hOff = wallH * (s / stepCount);
          final pA1 = Offset(pA.dx, pA.dy + hOff);
          final pB1 = Offset(pB.dx, pB.dy + hOff);

          _strataDarkPaint.color = Colors.black.withValues(alpha: 0.22);
          canvas.drawLine(pA1, pB1, _strataDarkPaint);

          _strataLightPaint.color = Colors.white.withValues(alpha: 0.14);
          canvas.drawLine(Offset(pA1.dx, pA1.dy + 1.0), Offset(pB1.dx, pB1.dy + 1.0), _strataLightPaint);
        }
      }

      // Taban Temas Gölgeleri (Contact Ambient Occlusion at Wall Base)
      canvas.drawLine(
        Offset(pA.dx, pA.dy + wallH),
        Offset(pB.dx, pB.dy + wallH),
        _cliffBaseAoPaint,
      );

      // Uçurum Üst Kenar Işığı (Cliff Lip Specular Highlight)
      canvas.drawLine(pA, pB, _cliffLipHighlightPaint);
    }
  }

  void _renderIsometricTopFace(Canvas canvas, List<Offset> corners, Offset center) {
    _topPath
      ..reset()
      ..moveTo(corners[0].dx, corners[0].dy);
    for (int i = 1; i < 6; i++) {
      _topPath.lineTo(corners[i].dx, corners[i].dy);
    }
    _topPath.close();

    final int seed = (coord.q * 37 + coord.r * 19).abs();
    Color topColor = _getBiomeTopColor(tileModel.biome, seed);
    if (isNight) {
      topColor = Color.lerp(topColor, const Color(0xFF0F172A), 0.45)!;
    }

    // GPU Fragment Shader Zemin Katmanları
    bool didDrawBiomeShader = false;
    if (tileModel.biome == TileBiome.sea || tileModel.biome == TileBiome.wetland) {
      final waterShaderPaint = HexShaderService.getWaterShaderPaint(
        resolution: const Size(hexRadius * 2, hexRadius * 2),
        time: _animTimer,
        center: center,
        alpha: 1.0,
        isNight: isNight,
      );
      if (waterShaderPaint != null) {
        canvas.drawPath(_topPath, waterShaderPaint);
        didDrawBiomeShader = true;
      }
    } else if (tileModel.biome == TileBiome.volcano || (tileModel.building?.type == BuildingType.obsidianForge)) {
      final lavaShaderPaint = HexShaderService.getLavaShaderPaint(
        resolution: const Size(hexRadius * 2, hexRadius * 2),
        time: _animTimer,
        intensity: isNight ? 1.35 : 1.0,
      );
      if (lavaShaderPaint != null) {
        canvas.drawPath(_topPath, lavaShaderPaint);
        didDrawBiomeShader = true;
      }

      // Impeller Sıcaklık Titremesi ve Serap Kırılması (Heat Haze Refraction)
      final heatHazePaint = HexShaderService.getHeatHazeShaderPaint(
        resolution: const Size(hexRadius * 2, hexRadius * 2),
        time: _animTimer,
        center: center,
        intensity: isNight ? 0.75 : 1.1,
      );
      if (heatHazePaint != null) {
        canvas.drawPath(_topPath, heatHazePaint);
      }
    } else if (tileModel.biome == TileBiome.celestialCrater || tileModel.biome == TileBiome.crystalChasm) {
      final crystalShaderPaint = HexShaderService.getCrystalShaderPaint(
        resolution: const Size(hexRadius * 2, hexRadius * 2),
        time: _animTimer,
        prismPower: 1.0,
      );
      if (crystalShaderPaint != null) {
        canvas.drawPath(_topPath, crystalShaderPaint);
        didDrawBiomeShader = true;
      }
    }

    if (!didDrawBiomeShader) {
      _sharedFillPaint
        ..style = PaintingStyle.fill
        ..color = topColor;
      canvas.drawPath(_topPath, _sharedFillPaint);

      // Kutlu Tapınak (Shrine) Üzerine Kristal Prizma Şavkı
      if (tileModel.hasShrine) {
        final shrineShaderPaint = HexShaderService.getCrystalShaderPaint(
          resolution: const Size(hexRadius * 2, hexRadius * 2),
          time: _animTimer,
          prismPower: 0.85,
        );
        if (shrineShaderPaint != null) {
          canvas.drawPath(_topPath, shrineShaderPaint);
        }
      }
    }

    final double highlightAlpha = !tileModel.isOwned
        ? (isNight ? 0.02 : 0.05)
        : (isNight ? 0.05 : 0.12);
    _highlightPaint.color = Colors.white.withValues(alpha: highlightAlpha);
    canvas.drawPath(_topPath, _highlightPaint);

    // Uçurum Düşen Gölgeleri (Cliff Cast Shadow from NW Higher Neighbor)
    if (northWestDeltaElevation > 4.0 && !tileModel.isFog) {
      final double shadowFactor = (northWestDeltaElevation / 50.0).clamp(0.10, 0.40);
      final double shadowAlpha = (0.12 + shadowFactor * 0.25).clamp(0.12, 0.35);

      _cliffShadowPath
        ..reset()
        ..moveTo(corners[4].dx, corners[4].dy)
        ..lineTo(corners[5].dx, corners[5].dy)
        ..lineTo(corners[0].dx, corners[0].dy)
        ..lineTo(corners[1].dx, corners[1].dy)
        ..lineTo(
          corners[1].dx + (center.dx - corners[1].dx) * shadowFactor,
          corners[1].dy + (center.dy - corners[1].dy) * shadowFactor,
        )
        ..lineTo(
          corners[0].dx + (center.dx - corners[0].dx) * shadowFactor,
          corners[0].dy + (center.dy - corners[0].dy) * shadowFactor,
        )
        ..lineTo(
          corners[5].dx + (center.dx - corners[5].dx) * shadowFactor,
          corners[5].dy + (center.dy - corners[5].dy) * shadowFactor,
        )
        ..lineTo(
          corners[4].dx + (center.dx - corners[4].dx) * shadowFactor,
          corners[4].dy + (center.dy - corners[4].dy) * shadowFactor,
        )
        ..close();

      _cliffCastShadowPaint.color = const Color(0xFF020617).withValues(alpha: shadowAlpha);
      canvas.drawPath(_cliffShadowPath, _cliffCastShadowPaint);
    }

    // Hava Perspektifi ve Yükseklik Işığı (Aerial Perspective & Height Luminance)
    final double elevation = getBiomeElevation(tileModel.biome, isFog: tileModel.isFog);
    if (elevation >= 24.0) {
      _sharedFillPaint
        ..style = PaintingStyle.fill
        ..color = const Color(0xFFFDE68A).withValues(alpha: isNight ? 0.03 : 0.09);
      canvas.drawPath(_topPath, _sharedFillPaint);
    } else if (elevation <= 4.0) {
      _sharedFillPaint
        ..style = PaintingStyle.fill
        ..color = const Color(0xFF0F172A).withValues(alpha: isNight ? 0.10 : 0.06);
      canvas.drawPath(_topPath, _sharedFillPaint);
    }

    // Kış ve Zud Ayazında Isınmamış Arazilerde Buzlanma / Kristalleşme Shader'ı
    if ((season == 'WINTER' || isZud) && !tileModel.isWarmed) {
      final frostShaderPaint = HexShaderService.getFrostShaderPaint(
        resolution: const Size(hexRadius * 2, hexRadius * 2),
        time: _animTimer,
        frostProgress: isZud ? 1.0 : 0.75,
      );
      if (frostShaderPaint != null) {
        canvas.drawPath(_topPath, frostShaderPaint);
      }
    }

    // 10x Toy Coşkusu Devredeyken Fethedilmiş Topraklarda Altın Aurası
    if (isFrenzyActive && tileModel.isOwned) {
      final frenzyShaderPaint = HexShaderService.getFrenzyShaderPaint(
        resolution: const Size(hexRadius * 2, hexRadius * 2),
        time: _animTimer,
        intensity: 0.85,
      );
      if (frenzyShaderPaint != null) {
        canvas.drawPath(_topPath, frenzyShaderPaint);
      }
    }

    // Sahipsiz / Keşfedilmiş Arazi: Silikleştirme ve karartma zemin katmanı
    if (!tileModel.isOwned) {
      canvas.drawPath(_topPath, _unownedTopScrimPaint);
      canvas.drawPath(_topPath, _unownedBorderPaint);
    } else if (!isSelected) {
      canvas.drawPath(_topPath, _ownedTerritoryBorderPaint);
    }

    if (tileModel.isWarmed) {
      canvas.drawPath(_topPath, _warmFillPaint);
      canvas.drawPath(_topPath, _warmPaint);
    }

    // İşçi Kulübesi 4 Hex Menzili Aurası (Menzildeki Fethedilmiş Arazi Vurgusu)
    if (isInWorkerRange && !isSelected) {
      canvas.drawPath(_topPath, _workerRangeFillPaint);
      canvas.drawPath(_topPath, _workerRangeBorderPaint);
    }

    // Menzil İçindeki Üretim Yapısı Vurgusu
    if (isHarvestHighlight && !isSelected) {
      canvas.drawPath(_topPath, _harvestTargetFillPaint);
      canvas.drawPath(_topPath, _harvestTargetBorderPaint);
    }

    // Seçili Karo Neo-Brutalist Sarı Vurgusu
    if (isSelected) {
      canvas.drawPath(_topPath, _selectBorderPaint);
    }

    // Sert Neo-Brutalist Ada Sınır Çerçevesi (Island Perimeter Bezel)
    if (fogNeighborMask != 0 && !tileModel.isFog) {
      _islandPerimeterAccentPaint.color = tileModel.isOwned
          ? const Color(0xFFF59E0B).withValues(alpha: isNight ? 0.50 : 0.85)
          : const Color(0xFF475569).withValues(alpha: isNight ? 0.40 : 0.65);

      const List<int> dirStartCorners = [0, 5, 4, 3, 2, 1];
      const List<int> dirEndCorners = [1, 0, 5, 4, 3, 2];

      for (int dir = 0; dir < 6; dir++) {
        if ((fogNeighborMask & (1 << dir)) != 0) {
          final pA = corners[dirStartCorners[dir]];
          final pB = corners[dirEndCorners[dir]];
          // 1. Dış katı koyu taş kenarlık
          canvas.drawLine(pA, pB, _islandPerimeterBorderPaint);
          // 2. İç altın/kehribar taktil hat
          canvas.drawLine(pA, pB, _islandPerimeterAccentPaint);
        }
      }
    }
  }

  void _renderVoxelObjects(Canvas canvas, Offset center, List<Offset> corners) {
    final int seed = (coord.q * 37 + coord.r * 19).abs();
    final double tTime = tileAnimTime;
    final double windWave = VoxelIsometricRenderer.getSteppeWindWave(tTime, coord.q, coord.r);
    final double tapProgress = _bounceTimer > 0 ? (1.0 - (_bounceTimer / _bounceDuration)) : 0.0;

    if (tileModel.hasShrine) {
      VoxelIsometricRenderer.drawVoxelAncientShrine(
        canvas,
        center,
        shrineType: tileModel.shrine,
        animTime: tTime,
        isNight: isNight,
      );
    } else if (tileModel.hasBuilding) {
      final b = tileModel.building!;
      final int bVar = b.variant != 0 ? b.variant : ((tileModel.coord.q * 17 + tileModel.coord.r * 31).abs() % 3);
      final bool isWinter = _currentSeason == 'WINTER' || isZud;
      final int bLvl = b.level;

      switch (b.type) {
        case BuildingType.castle:
          VoxelIsometricRenderer.drawVoxelCastle(canvas, center, b.level, isNight: isNight);
          VoxelIsometricRenderer.drawVoxelSmokePlume(
            canvas,
            Offset(center.dx + 12, center.dy - 26),
            animTime: tTime,
            seed: seed,
            windWave: windWave,
            scale: 1.1,
          );
          if (isNight) {
            VoxelIsometricRenderer.drawVoxelHearthFirelight(
              canvas,
              Offset(center.dx, center.dy - 4),
              animTime: tTime,
              seed: seed,
              radius: 12.0,
            );
          }
          break;
        case BuildingType.corn:
          VoxelIsometricRenderer.drawVoxelCropField(canvas, center, animTime: tTime, variant: bVar);
          break;
        case BuildingType.barley:
          VoxelIsometricRenderer.drawVoxelBarleyField(canvas, center, animTime: tTime, variant: bVar);
          break;
        case BuildingType.pasture:
          VoxelIsometricRenderer.drawVoxelPasture(canvas, center, animTime: tTime, variant: bVar);
          break;
        case BuildingType.orchard:
          VoxelIsometricRenderer.drawVoxelOrchard(canvas, center, animTime: tTime, variant: bVar);
          break;
        case BuildingType.quarry:
          VoxelIsometricRenderer.drawVoxelQuarry(canvas, center, variant: bVar, level: bLvl, isWinter: isWinter);
          break;
        case BuildingType.resinCamp:
          VoxelIsometricRenderer.drawVoxelResinCamp(canvas, center, animTime: tTime, variant: bVar);
          break;
        case BuildingType.lumberjack:
          VoxelIsometricRenderer.drawVoxelLumberjack(canvas, center, variant: bVar, level: bLvl, isWinter: isWinter);
          break;
        case BuildingType.windmill:
          VoxelIsometricRenderer.drawVoxelWindmill(canvas, center, tTime, isNight: isNight, variant: bVar, level: bLvl, isWinter: isWinter);
          break;
        case BuildingType.sawmill:
          VoxelIsometricRenderer.drawVoxelSawmill(canvas, center, variant: bVar, level: bLvl, isWinter: isWinter);
          break;
        case BuildingType.bakery:
          VoxelIsometricRenderer.drawVoxelBakery(canvas, center, tTime, isNight: isNight, variant: bVar, level: bLvl, isWinter: isWinter);
          VoxelIsometricRenderer.drawVoxelSmokePlume(
            canvas,
            Offset(center.dx + 8 * VoxelIsometricRenderer.cosIso, center.dy - 28.0 - 4 * VoxelIsometricRenderer.sinIso),
            animTime: tTime,
            seed: seed,
            windWave: windWave,
            scale: 0.9,
          );
          if (isNight) {
            VoxelIsometricRenderer.drawVoxelHearthFirelight(
              canvas,
              Offset(center.dx, center.dy - 2),
              animTime: tTime,
              seed: seed,
              radius: 8.0,
            );
          }
          break;
        case BuildingType.furniture:
          VoxelIsometricRenderer.drawVoxelFurniture(canvas, center, variant: bVar, level: bLvl, isWinter: isWinter);
          break;
        case BuildingType.worker:
          VoxelIsometricRenderer.drawVoxelWorkerCamp(
            canvas,
            center,
            level: bLvl,
            animTime: tTime,
            isNight: isNight,
          );
          break;
        case BuildingType.watchtower:
          VoxelIsometricRenderer.drawVoxelWatchtower(
            canvas,
            center,
            level: bLvl,
            isNight: isNight,
            animTime: tTime,
          );
          break;
        case BuildingType.mine:
          VoxelIsometricRenderer.drawVoxelMine(canvas, center, animTime: tTime, isNight: isNight, variant: bVar, level: bLvl, isWinter: isWinter);
          break;
        case BuildingType.bridge:
          VoxelIsometricRenderer.drawVoxelBridge(canvas, center);
          break;
        case BuildingType.fisherman:
          VoxelIsometricRenderer.drawVoxelFishermanBoat(
            canvas,
            center,
            level: bLvl,
            animTime: tTime,
            isNight: isNight,
          );
          break;
        case BuildingType.fishermanHut:
          VoxelIsometricRenderer.drawVoxelFishermanHut(
            canvas,
            center,
            level: bLvl,
            animTime: tTime,
            isNight: isNight,
          );
          break;

        // Özel Binalar
        case BuildingType.oasisCistern:
          VoxelIsometricRenderer.drawVoxelOasisCistern(
            canvas,
            center,
            level: bLvl,
            animTime: tTime,
          );
          break;
        case BuildingType.caravanserai:
          VoxelIsometricRenderer.drawVoxelCaravanserai(
            canvas,
            center,
            level: bLvl,
            animTime: tTime,
          );
          break;
        case BuildingType.astrolabe:
          VoxelIsometricRenderer.drawVoxelAstrolabe(
            canvas,
            center,
            level: bLvl,
            animTime: tTime,
          );
          break;
        case BuildingType.reindeerSanctuary:
          VoxelIsometricRenderer.drawVoxelReindeerSanctuary(
            canvas,
            center,
            level: bLvl,
            animTime: tTime,
          );
          break;
        case BuildingType.geothermalBath:
          VoxelIsometricRenderer.drawVoxelGeothermalBath(
            canvas,
            center,
            level: bLvl,
            animTime: tTime,
          );
          break;
        case BuildingType.permafrostDig:
          VoxelIsometricRenderer.drawVoxelPermafrostDig(
            canvas,
            center,
            level: bLvl,
            animTime: tTime,
          );
          break;
        case BuildingType.steamVent:
          VoxelIsometricRenderer.drawVoxelSteamVent(
            canvas,
            center,
            level: bLvl,
            animTime: tTime,
          );
          VoxelIsometricRenderer.drawVoxelGeyserBurst(
            canvas,
            Offset(center.dx, center.dy - 6),
            animTime: tTime,
            seed: seed,
          );
          break;
        case BuildingType.obsidianForge:
          VoxelIsometricRenderer.drawVoxelObsidianForge(
            canvas,
            center,
            level: bLvl,
            animTime: tTime,
          );
          VoxelIsometricRenderer.drawVoxelSmokePlume(
            canvas,
            Offset(center.dx, center.dy - 20),
            animTime: tTime,
            seed: seed,
            windWave: windWave,
            scale: 1.15,
            smokeColor: const Color(0xFF64748B),
          );
          break;
        case BuildingType.herbalistYurt:
          VoxelIsometricRenderer.drawVoxelHerbalistYurt(
            canvas,
            center,
            level: bLvl,
            animTime: tTime,
          );
          if (isNight) {
            VoxelIsometricRenderer.drawVoxelHearthFirelight(
              canvas,
              Offset(center.dx, center.dy - 2),
              animTime: tTime,
              seed: seed,
              radius: 7.0,
            );
          }
          break;
        case BuildingType.scribeWorkshop:
          VoxelIsometricRenderer.drawVoxelScribeWorkshop(
            canvas,
            center,
            level: bLvl,
            animTime: tTime,
          );
          break;
        case BuildingType.celestialAnvil:
          VoxelIsometricRenderer.drawVoxelCelestialAnvil(
            canvas,
            center,
            level: bLvl,
            animTime: tTime,
          );
          break;
        case BuildingType.ancestralTotem:
          VoxelIsometricRenderer.drawVoxelAncestralTotem(
            canvas,
            center,
            level: bLvl,
            animTime: tTime,
          );
          break;
        case BuildingType.prismaticResonator:
          VoxelIsometricRenderer.drawVoxelPrismaticResonator(
            canvas,
            center,
            level: bLvl,
            animTime: tTime,
          );
          break;
        case BuildingType.runicStele:
          VoxelIsometricRenderer.drawVoxelRunicStele(
            canvas,
            center,
            level: bLvl,
            animTime: tTime,
          );
          break;
        case BuildingType.granaryVault:
          VoxelIsometricRenderer.drawVoxelGranaryVault(
            canvas,
            center,
            level: bLvl,
            animTime: tTime,
          );
          break;
        case BuildingType.kumisYurt:
          VoxelIsometricRenderer.drawVoxelKumisYurt(
            canvas,
            center,
            level: bLvl,
            animTime: tTime,
          );
          break;
        case BuildingType.feltTentWorkshop:
          VoxelIsometricRenderer.drawVoxelFeltTentWorkshop(
            canvas,
            center,
            level: bLvl,
            animTime: tTime,
          );
          break;
        case BuildingType.damascusForge:
          VoxelIsometricRenderer.drawVoxelDamascusForge(
            canvas,
            center,
            level: bLvl,
            animTime: tTime,
          );
          break;
      }

      // Binalar için Yaşanmışlık ve Mikro Çevre Detayları (Props, Çuvallar, Tuğlar)
      VoxelIsometricRenderer.drawEnvironmentalClutter(
        canvas,
        center,
        type: b.type,
        scale: 1.0,
        animTime: tTime,
      );
    } else {
      switch (tileModel.biome) {
        case TileBiome.meadow:
          _renderLivingMeadow(canvas, center, seed, windWave: windWave, tapProgress: tapProgress);
          break;
        case TileBiome.forest:
          _renderLivingForest(canvas, center, seed, tapProgress: tapProgress);
          break;
        case TileBiome.mountain:
          _renderLivingMountain(canvas, center, seed, windWave: windWave);
          break;
        case TileBiome.sea:
          _renderLivingSea(canvas, center, corners, seed, tapProgress: tapProgress);
          break;
        case TileBiome.desert:
          _renderLivingDesert(canvas, center, seed);
          break;
        case TileBiome.tundra:
          _renderLivingTundra(canvas, center, seed);
          break;
        case TileBiome.volcano:
          _renderLivingVolcano(canvas, center, seed);
          break;
        case TileBiome.wetland:
          _renderLivingWetland(canvas, center, seed, tapProgress: tapProgress);
          break;
        case TileBiome.celestialCrater:
          _renderLivingCrater(canvas, center, seed);
          break;
        case TileBiome.kurganValley:
          _renderLivingKurgan(canvas, center, seed);
          break;
        case TileBiome.crystalChasm:
          _renderLivingChasm(canvas, center, seed);
          break;
      }
    }

    // 1. Ata Kurganı Balbal Dikilitaşı
    if (tileModel.ancestralKurgan != null) {
      VoxelIsometricRenderer.drawVoxelAncestralBalbal(
        canvas,
        center,
        animTime: tTime,
        level: tileModel.ancestralKurgan!.formerLevel,
      );
    }

    // 2. Ekolojik Biyom Simbiyoz Parçacıkları
    if (tileModel.symbiosis != SymbiosisType.none) {
      VoxelIsometricRenderer.drawVoxelSymbiosisSparks(
        canvas,
        center,
        animTime: tTime,
        type: tileModel.symbiosis,
      );
    }

    // 3. Yaylak-Kışlak Toprak Nefesi ve Bereket Patlaması Aurası
    if (tileModel.isResting) {
      final double breathPulse = 0.35 + 0.25 * math.sin(tTime * 2.0);
      VoxelIsometricRenderer.drawIsoCube(
        canvas,
        Offset(center.dx, center.dy - 2.0),
        w: 12.0,
        d: 12.0,
        h: 1.5,
        topColor: const Color(0xFF22C55E).withValues(alpha: breathPulse),
        leftColor: const Color(0xFF16A34A).withValues(alpha: breathPulse * 0.7),
        rightColor: const Color(0xFF15803D).withValues(alpha: breathPulse * 0.5),
      );
    } else if (tileModel.restTimeAccumulated >= 10.0) {
      final double boostPulse = 0.45 + 0.35 * math.sin(tTime * 4.0);
      VoxelIsometricRenderer.drawIsoCube(
        canvas,
        Offset(center.dx, center.dy - 3.0),
        w: 14.0,
        d: 14.0,
        h: 2.0,
        topColor: const Color(0xFFFACC15).withValues(alpha: boostPulse),
        leftColor: const Color(0xFFEAB308).withValues(alpha: boostPulse * 0.7),
        rightColor: const Color(0xFFCA8A04).withValues(alpha: boostPulse * 0.5),
      );
    }

    // 4. Savunma Suru (Akıllı Kesişim ve Sınır Koruması)
    if (tileModel.hasActiveWall) {
      final wallEdges = _calculateActiveWallEdges();
      VoxelIsometricRenderer.drawVoxelPerimeterWall(
        canvas,
        corners,
        tier: tileModel.wall!.tier,
        activeEdges: wallEdges,
        isNight: isNight,
        animTime: tTime,
      );
    }
  }

  /// Komşu karolardaki sur durumuna göre açık/dış kenarları hesaplar
  /// İki surlu karo birbirine komşu ise aralarındaki iç kenar duvarını kaldırır
  List<bool> _calculateActiveWallEdges() {
    final game = findGame();
    if (game is! HexMapGame) return List.filled(6, true);

    const edgeDirections = [
      HexAxial(1, 0),
      HexAxial(0, 1),
      HexAxial(-1, 1),
      HexAxial(-1, 0),
      HexAxial(0, -1),
      HexAxial(1, -1),
    ];

    final List<bool> activeEdges = [];
    for (int i = 0; i < 6; i++) {
      final neighborCoord = coord + edgeDirections[i];
      final neighborComp = game.getTileComponent(neighborCoord);
      final bool neighborHasWall = neighborComp?.tileModel.hasActiveWall ?? false;
      activeEdges.add(!neighborHasWall);
    }
    return activeEdges;
  }

  void _renderLivingForest(Canvas canvas, Offset center, int seed, {double tapProgress = 0.0}) {
    final int variant = seed % 4;
    final bool isAutumn = season == 'AUTUMN';

    switch (variant) {
      case 0:
        VoxelIsometricRenderer.drawVoxelTree(
          canvas,
          Offset(center.dx - 8, center.dy - 6),
          scale: 1.1,
          animTime: _animTimer,
          season: season,
          isZud: isZud,
        );
        VoxelIsometricRenderer.drawVoxelBirchTree(
          canvas,
          Offset(center.dx + 10, center.dy + 2),
          scale: 0.8,
          animTime: _animTimer,
          season: season,
          isZud: isZud,
        );
        VoxelIsometricRenderer.drawVoxelMushroom(
          canvas,
          Offset(center.dx + 4, center.dy + 8),
          scale: 0.9,
        );
        if (seed % 3 == 0) {
          final roamDeer = getFaunaRoamData(seed * 11 + 5, speedMultiplier: 0.9);
          VoxelIsometricRenderer.drawVoxelDeer(
            canvas,
            Offset(center.dx - 2 + roamDeer.offset.dx, center.dy + 4 + roamDeer.offset.dy),
            animTime: _animTimer + roamDeer.walkAnim,
            scale: 0.8,
            seed: seed * 5 + 1,
            flipX: roamDeer.flipX,
          );
        }
        break;
      case 1:
        VoxelIsometricRenderer.drawVoxelPine(
          canvas,
          Offset(center.dx, center.dy - 6),
          scale: 1.15,
          animTime: _animTimer,
          season: season,
          isZud: isZud,
        );
        if (isAutumn) {
          VoxelIsometricRenderer.drawVoxelAutumnFoliage(canvas, Offset(center.dx + 4, center.dy + 6), scale: 0.85);
        } else {
          VoxelIsometricRenderer.drawVoxelPebbles(canvas, Offset(center.dx + 6, center.dy + 6), scale: 0.85);
        }
        break;
      case 2:
        VoxelIsometricRenderer.drawVoxelPine(
          canvas,
          Offset(center.dx + 10, center.dy - 4),
          scale: 1.0,
          animTime: _animTimer,
          season: season,
          isZud: isZud,
        );
        VoxelIsometricRenderer.drawVoxelPine(
          canvas,
          Offset(center.dx - 12, center.dy - 8),
          scale: 0.7,
          animTime: _animTimer,
          season: season,
          isZud: isZud,
        );
        final roamDeer = getFaunaRoamData(seed * 7 + 2, speedMultiplier: 0.9);
        VoxelIsometricRenderer.drawVoxelDeer(
          canvas,
          Offset(center.dx - 2 + roamDeer.offset.dx, center.dy + 6 + roamDeer.offset.dy),
          animTime: _animTimer + roamDeer.walkAnim,
          seed: seed,
          scale: 0.85,
          flipX: roamDeer.flipX,
        );
        break;
      case 3:
      default:
        VoxelIsometricRenderer.drawVoxelTree(
          canvas,
          Offset(center.dx + 6, center.dy - 4),
          scale: 1.05,
          animTime: tileAnimTime,
          season: season,
          isZud: isZud,
        );
        VoxelIsometricRenderer.drawVoxelPebbles(
          canvas,
          Offset(center.dx - 10, center.dy + 6),
          scale: 0.9,
        );
        break;
    }

    // Dokunulduğunda Savrulan Yapraklar (Tactile Leaf Scatter)
    if (tapProgress > 0.0) {
      VoxelIsometricRenderer.drawVoxelLeafScatter(canvas, center, progress: tapProgress, seed: seed);
    }

    if (isNight && seed % 2 == 0) {
      VoxelIsometricRenderer.drawVoxelFireflies(
        canvas,
        center,
        animTime: tileAnimTime,
        seed: seed,
      );
    }
  }

  void _renderLivingMeadow(
    Canvas canvas,
    Offset center,
    int seed, {
    double windWave = 0.0,
    double tapProgress = 0.0,
  }) {
    final int variant = seed % 8;
    final double tTime = tileAnimTime;
    final bool isSpring = season == 'SPRING';

    void drawGrass(Offset pos, {double scale = 1.0}) {
      Color topGrass = const Color(0xFF65A30D);
      Color leftGrass = const Color(0xFF4D7C0F);
      Color rightGrass = const Color(0xFF3F6212);
      if (season == 'AUTUMN') {
        topGrass = const Color(0xFFF59E0B);
        leftGrass = const Color(0xFFD97706);
        rightGrass = const Color(0xFFB45309);
      } else if (season == 'WINTER' || isZud) {
        topGrass = const Color(0xFFCBD5E1);
        leftGrass = const Color(0xFF94A3B8);
        rightGrass = const Color(0xFF64748B);
      }
      VoxelIsometricRenderer.drawIsoCube(
        canvas,
        pos,
        w: 3.0 * scale,
        d: 3.0 * scale,
        h: 5.0 * scale,
        topColor: topGrass,
        leftColor: leftGrass,
        rightColor: rightGrass,
      );
    }

    switch (variant) {
      case 0:
        // Saf Bozkır & Dinlenen/Gezinen Tek Koyun (0 Çiçek)
        drawGrass(Offset(center.dx + 6, center.dy + 6), scale: 0.9);
        drawGrass(Offset(center.dx - 8, center.dy + 4), scale: 0.8);
        drawGrass(Offset(center.dx - 4, center.dy + 8), scale: 0.75);
        drawGrass(Offset(center.dx + 2, center.dy - 8), scale: 0.85);
        drawGrass(Offset(center.dx - 10, center.dy - 5), scale: 0.7);
        VoxelIsometricRenderer.drawVoxelPebbles(canvas, Offset(center.dx + 8, center.dy - 4), scale: 0.75);

        if (seed % 2 == 0) {
          final roamSheep = getFaunaRoamData(seed * 11 + 3, speedMultiplier: 0.85);
          if (seed % 4 == 0) {
            VoxelFaunaRenderer.drawRam(
              canvas,
              Offset(center.dx - 2 + roamSheep.offset.dx, center.dy - 2 + roamSheep.offset.dy),
              animTime: tTime + roamSheep.walkAnim,
              seed: seed * 11 + 3,
              scale: 0.9,
              flipX: roamSheep.flipX,
            );
          } else {
            VoxelFaunaRenderer.drawSheep(
              canvas,
              Offset(center.dx - 2 + roamSheep.offset.dx, center.dy - 2 + roamSheep.offset.dy),
              animTime: tTime + roamSheep.walkAnim,
              seed: seed * 11 + 3,
              scale: 0.88,
              flipX: roamSheep.flipX,
            );
          }
        }
        break;

      case 1:
        // Nadir Çiçek Vadisi & Koyun Sürüsü (2 Çiçek - Baharda Gelincikli) [Nadir Çiçek 1/8]
        final roamSheep1 = getFaunaRoamData(seed, speedMultiplier: 0.85);
        VoxelFaunaRenderer.drawSheep(
          canvas,
          Offset(center.dx + 6 + roamSheep1.offset.dx, center.dy - 3 + roamSheep1.offset.dy),
          animTime: tTime + roamSheep1.walkAnim,
          seed: seed,
          scale: 0.95,
          flipX: roamSheep1.flipX,
        );
        final roamSheep2 = getFaunaRoamData(seed * 19 + 7, speedMultiplier: 1.05);
        VoxelFaunaRenderer.drawLamb(
          canvas,
          Offset(center.dx - 10 + roamSheep2.offset.dx, center.dy + 5 + roamSheep2.offset.dy),
          animTime: tTime + roamSheep2.walkAnim,
          seed: seed * 19 + 7,
          scale: 0.75,
          flipX: roamSheep2.flipX,
        );
        VoxelIsometricRenderer.drawVoxelFlowers(
          canvas,
          Offset(center.dx + 12, center.dy + 8),
          flowerColor: const Color(0xFF38BDF8),
          scale: 0.8,
        );
        if (isSpring) {
          VoxelIsometricRenderer.drawVoxelSpringPoppies(canvas, Offset(center.dx - 6, center.dy - 8), scale: 0.85);
        } else {
          VoxelIsometricRenderer.drawVoxelFlowers(
            canvas,
            Offset(center.dx - 6, center.dy - 8),
            flowerColor: const Color(0xFFFBBF24),
            scale: 0.75,
          );
        }
        drawGrass(Offset(center.dx - 2, center.dy + 8), scale: 0.85);
        drawGrass(Offset(center.dx + 8, center.dy - 9), scale: 0.9);
        drawGrass(Offset(center.dx - 12, center.dy - 2), scale: 0.75);
        break;

      case 2:
        // Asil Bozkır Yılkı Atı (Tek Başına, Asil, Stabil & Etrafında Hiçbir Canlı Olmadan)
        VoxelFaunaRenderer.drawHorse(
          canvas,
          center,
          animTime: tTime,
          seed: seed,
          scale: 1.0,
          flipX: (seed % 2 != 0),
          startleProgress: tapProgress,
        );
        drawGrass(Offset(center.dx + 10, center.dy - 6), scale: 0.9);
        drawGrass(Offset(center.dx - 10, center.dy + 8), scale: 0.85);
        drawGrass(Offset(center.dx + 8, center.dy + 8), scale: 0.8);
        break;

      case 3:
        // Rüzgarlı Geniş Otlak Örtüsü & Çakıllar (0 Çiçek)
        drawGrass(Offset(center.dx, center.dy), scale: 1.0);
        drawGrass(Offset(center.dx - 10, center.dy - 3), scale: 0.85);
        drawGrass(Offset(center.dx + 11, center.dy - 4), scale: 0.8);
        drawGrass(Offset(center.dx - 5, center.dy + 7), scale: 0.9);
        drawGrass(Offset(center.dx + 7, center.dy + 6), scale: 0.75);
        VoxelIsometricRenderer.drawVoxelPebbles(canvas, Offset(center.dx - 7, center.dy - 5), scale: 0.85);
        VoxelIsometricRenderer.drawVoxelPebbles(canvas, Offset(center.dx + 6, center.dy - 7), scale: 0.7);
        break;

      case 4:
        // Vadi Kıyısı Tekil Kır Çiçeği & Çimen Vadisi (1 Çiçek) [Nadir Çiçek 2/8]
        if (isSpring) {
          VoxelIsometricRenderer.drawVoxelSpringPoppies(canvas, Offset(center.dx - 6, center.dy - 4), scale: 0.85);
        } else {
          VoxelIsometricRenderer.drawVoxelFlowers(
            canvas,
            Offset(center.dx - 6, center.dy - 4),
            flowerColor: seed % 2 == 0 ? const Color(0xFFA855F7) : const Color(0xFF38BDF8),
            scale: 0.8,
          );
        }
        drawGrass(Offset(center.dx, center.dy), scale: 0.95);
        drawGrass(Offset(center.dx - 12, center.dy - 2), scale: 0.85);
        drawGrass(Offset(center.dx + 12, center.dy - 2), scale: 0.75);
        drawGrass(Offset(center.dx + 2, center.dy + 8), scale: 0.8);
        VoxelIsometricRenderer.drawVoxelPebbles(canvas, Offset(center.dx + 8, center.dy + 4), scale: 0.75);
        break;

      case 5:
        // Otlayan Koyun & Çiçeksiz Bozkır (0 Çiçek)
        final roamSheep = getFaunaRoamData(seed * 5 + 3, speedMultiplier: 0.85);
        VoxelFaunaRenderer.drawSheep(
          canvas,
          Offset(center.dx - 3 + roamSheep.offset.dx, center.dy + 2 + roamSheep.offset.dy),
          animTime: tTime + roamSheep.walkAnim,
          seed: seed * 5 + 3,
          scale: 0.9,
          flipX: roamSheep.flipX,
        );
        drawGrass(Offset(center.dx - 8, center.dy - 6), scale: 0.85);
        drawGrass(Offset(center.dx + 10, center.dy + 5), scale: 0.9);
        VoxelIsometricRenderer.drawVoxelPebbles(canvas, Offset(center.dx + 6, center.dy - 7), scale: 0.75);
        break;

      case 6:
        // Saf Bozkır Çimi & Dinlenen Kuzu (0 Çiçek)
        drawGrass(Offset(center.dx - 7, center.dy + 4), scale: 0.95);
        drawGrass(Offset(center.dx + 8, center.dy + 5), scale: 0.8);
        drawGrass(Offset(center.dx - 5, center.dy - 6), scale: 0.75);
        drawGrass(Offset(center.dx + 1, center.dy + 8), scale: 0.85);
        drawGrass(Offset(center.dx + 4, center.dy - 5), scale: 0.8);
        VoxelIsometricRenderer.drawVoxelPebbles(canvas, Offset(center.dx - 8, center.dy - 4), scale: 0.8);

        if (seed % 3 == 1) {
          final roamLamb = getFaunaRoamData(seed * 9 + 4, speedMultiplier: 1.15);
          VoxelFaunaRenderer.drawLamb(
            canvas,
            Offset(center.dx - 1 + roamLamb.offset.dx, center.dy - 1 + roamLamb.offset.dy),
            animTime: tTime + roamLamb.walkAnim,
            seed: seed * 9 + 4,
            scale: 0.8,
            flipX: roamLamb.flipX,
          );
        }
        break;

      case 7:
      default:
        // Bozkır Taş Höyüğü & Yabani Otlar (0 Çiçek)
        VoxelIsometricRenderer.drawVoxelPebbles(canvas, Offset(center.dx - 7, center.dy + 3), scale: 0.85);
        VoxelIsometricRenderer.drawVoxelPebbles(canvas, Offset(center.dx + 9, center.dy - 4), scale: 0.8);
        VoxelIsometricRenderer.drawVoxelPebbles(canvas, Offset(center.dx - 4, center.dy + 8), scale: 0.75);
        drawGrass(Offset(center.dx + 2, center.dy + 7), scale: 0.9);
        drawGrass(Offset(center.dx - 8, center.dy - 6), scale: 0.8);
        drawGrass(Offset(center.dx + 6, center.dy + 2), scale: 0.75);
        drawGrass(Offset(center.dx - 2, center.dy - 2), scale: 0.85);
        break;
    }

    // Bozkırda Yuvarlanan Çalı (Tumbleweed)
    VoxelIsometricRenderer.drawVoxelTumbleweed(
      canvas,
      center,
      animTime: tileAnimTime,
      seed: seed,
      windWave: windWave,
    );

    if (isNight && seed % 4 == 0) {
      VoxelIsometricRenderer.drawVoxelFireflies(
        canvas,
        center,
        animTime: tileAnimTime,
        seed: seed,
      );
    }
  }

  void _renderLivingMountain(Canvas canvas, Offset center, int seed, {double windWave = 0.0}) {
    VoxelIsometricRenderer.drawVoxelMountainVariant(
      canvas,
      center,
      seed,
      season: season,
      isZud: isZud,
      animTime: tileAnimTime,
    );
    // Zirve Toz Kar Sürgünü
    VoxelIsometricRenderer.drawVoxelSnowDrift(
      canvas,
      Offset(center.dx, center.dy - 24),
      animTime: tileAnimTime,
      windWave: windWave,
      seed: seed,
    );

    // Sarp Kayalıklarda Yaban Keçisi veya Bozkır Kurdu
    if (seed % 3 == 0) {
      final roamIbex = getFaunaRoamData(seed * 19 + 4, speedMultiplier: 0.8);
      VoxelFaunaRenderer.drawMountainIbex(
        canvas,
        Offset(center.dx + 10 + roamIbex.offset.dx, center.dy + 4 + roamIbex.offset.dy),
        animTime: tileAnimTime + roamIbex.walkAnim,
        seed: seed,
        scale: 0.82,
        flipX: roamIbex.flipX,
      );
    } else if (seed % 5 == 0) {
      final roamWolf = getFaunaRoamData(seed * 13 + 9, speedMultiplier: 1.1);
      VoxelFaunaRenderer.drawSteppeWolf(
        canvas,
        Offset(center.dx - 8 + roamWolf.offset.dx, center.dy + 6 + roamWolf.offset.dy),
        animTime: tileAnimTime + roamWolf.walkAnim,
        seed: seed * 13 + 9,
        scale: 0.85,
        flipX: roamWolf.flipX,
      );
    } else if (seed % 2 == 0) {
      // 2.5D Çok Katmanlı Yamaç Teras Basamakları
      VoxelIsometricRenderer.drawTerracedCliffSteps(
        canvas,
        Offset(center.dx - 10, center.dy + 6),
        scale: 0.85,
      );
      VoxelIsometricRenderer.drawVoxelPebbles(
        canvas,
        Offset(center.dx + 14, center.dy + 8),
        scale: 0.75,
      );
    }
  }

  void _renderLivingSea(
    Canvas canvas,
    Offset center,
    List<Offset> corners,
    int seed, {
    double tapProgress = 0.0,
  }) {
    final bool isWinter = season == 'WINTER' || isZud;
    if (isWinter) {
      VoxelIsometricRenderer.drawVoxelIceFloes(canvas, center, scale: 0.9, animTime: tileAnimTime);
      return;
    }

    // 2.5D Kıyı Su Yansıması ve Dalga Kırılması
    VoxelIsometricRenderer.drawWaterBankReflections(
      canvas,
      center,
      width: 48.0,
      height: 24.0,
      silhouetteColor: const Color(0xFF0F172A),
      time: tileAnimTime,
    );

    VoxelIsometricRenderer.drawVoxelShorelineWaves(
      canvas,
      center,
      corners,
      animTime: tileAnimTime,
      seed: seed,
    );

    final double waveOffset = math.sin(tileAnimTime * 2.0 + (seed % 5)) * 3.5;
    VoxelIsometricRenderer.drawIsoCube(
      canvas,
      Offset(center.dx + waveOffset, center.dy),
      w: 14.0,
      d: 5.0,
      h: 2.0,
      topColor: const Color(0xFFBAE6FD).withValues(alpha: 0.7),
      leftColor: const Color(0xFF7DD3FC).withValues(alpha: 0.5),
      rightColor: const Color(0xFF38BDF8).withValues(alpha: 0.5),
    );

    if (seed % 3 == 0) {
      VoxelIsometricRenderer.drawVoxelLeapingFish(
        canvas,
        center,
        animTime: tileAnimTime,
        seed: seed,
      );
    }

    // Dokunulduğunda Su Dalgası Halkaları (Tactile Water Ripple)
    if (tapProgress > 0.0) {
      VoxelIsometricRenderer.drawVoxelWaterRipple(canvas, center, progress: tapProgress);
    }
  }

  void _renderLivingDesert(Canvas canvas, Offset center, int seed) {
    final int variant = seed % 4;
    switch (variant) {
      case 0:
        VoxelIsometricRenderer.drawVoxelSandDunes(canvas, Offset(center.dx - 4, center.dy + 2), scale: 0.9);
        VoxelIsometricRenderer.drawVoxelCactus(canvas, Offset(center.dx + 12, center.dy - 6), scale: 0.85);
        if (seed % 3 == 0) {
          final roamCamel = getFaunaRoamData(seed * 13 + 7, speedMultiplier: 0.7);
          VoxelFaunaRenderer.drawCamel(
            canvas,
            Offset(center.dx - 2 + roamCamel.offset.dx, center.dy + 2 + roamCamel.offset.dy),
            animTime: tileAnimTime + roamCamel.walkAnim,
            seed: seed,
            scale: 0.88,
            flipX: roamCamel.flipX,
          );
        }
        break;
      case 1:
        VoxelIsometricRenderer.drawVoxelCactus(canvas, Offset(center.dx - 6, center.dy), scale: 1.05);
        VoxelIsometricRenderer.drawVoxelDesertShrub(canvas, Offset(center.dx + 10, center.dy + 4), scale: 0.9);
        break;
      case 2:
        VoxelIsometricRenderer.drawVoxelSandDunes(canvas, center, scale: 1.1);
        if (seed % 3 == 0) {
          final roamCamel = getFaunaRoamData(seed * 7 + 1, speedMultiplier: 0.72);
          VoxelFaunaRenderer.drawCamel(
            canvas,
            Offset(center.dx + 4 + roamCamel.offset.dx, center.dy - 2 + roamCamel.offset.dy),
            animTime: tileAnimTime + roamCamel.walkAnim,
            seed: seed * 7 + 1,
            scale: 0.92,
            flipX: roamCamel.flipX,
          );
        }
        break;
      case 3:
      default:
        VoxelIsometricRenderer.drawVoxelDesertShrub(canvas, Offset(center.dx - 8, center.dy - 4), scale: 1.0);
        VoxelIsometricRenderer.drawVoxelPebbles(canvas, Offset(center.dx + 8, center.dy + 4), scale: 0.8);
        break;
    }

    // Sıcaklık Serabı
    VoxelIsometricRenderer.drawVoxelDesertHeatShimmer(canvas, center, animTime: tileAnimTime, seed: seed);

    // Her çöl karosunda uçuşan toz parçacığı olmasın, sadece nadir rüzgarlı karolarda (1/5)
    if (seed % 5 == 0) {
      VoxelIsometricRenderer.drawVoxelDesertDust(canvas, center, animTime: tileAnimTime, seed: seed);
    }
  }

  void _renderLivingTundra(Canvas canvas, Offset center, int seed) {
    final int variant = seed % 4;
    switch (variant) {
      case 0:
        VoxelIsometricRenderer.drawVoxelPermafrostSpire(canvas, Offset(center.dx - 4, center.dy - 2), scale: 0.95);
        VoxelIsometricRenderer.drawVoxelLichenRocks(canvas, Offset(center.dx + 10, center.dy + 6), scale: 0.85);
        break;
      case 1:
        VoxelIsometricRenderer.drawVoxelLichenRocks(canvas, Offset(center.dx - 6, center.dy), scale: 1.0);
        if (seed % 2 == 0) {
          final roamFox = getFaunaRoamData(seed * 17 + 2, speedMultiplier: 1.15);
          VoxelFaunaRenderer.drawArcticFox(
            canvas,
            Offset(center.dx + 6 + roamFox.offset.dx, center.dy - 2 + roamFox.offset.dy),
            animTime: tileAnimTime + roamFox.walkAnim,
            seed: seed,
            scale: 0.85,
            flipX: roamFox.flipX,
          );
        } else {
          VoxelIsometricRenderer.drawVoxelPebbles(canvas, Offset(center.dx + 8, center.dy - 6), scale: 0.9);
        }
        break;
      case 2:
        VoxelIsometricRenderer.drawVoxelPermafrostSpire(canvas, center, scale: 1.1);
        break;
      case 3:
      default:
        VoxelIsometricRenderer.drawVoxelPine(canvas, Offset(center.dx - 6, center.dy - 4), scale: 0.65, animTime: tileAnimTime);
        VoxelIsometricRenderer.drawVoxelLichenRocks(canvas, Offset(center.dx + 8, center.dy + 4), scale: 0.8);
        if (seed % 3 == 0) {
          final roamFox = getFaunaRoamData(seed * 5 + 3, speedMultiplier: 1.15);
          VoxelFaunaRenderer.drawArcticFox(
            canvas,
            Offset(center.dx - 2 + roamFox.offset.dx, center.dy + 5 + roamFox.offset.dy),
            animTime: tileAnimTime + roamFox.walkAnim,
            seed: seed * 5 + 3,
            scale: 0.8,
            flipX: roamFox.flipX,
          );
        }
        break;
    }
    // Her tundra karosunda parıltı olmasın, sadece nadir buzul karolarında (1/5)
    if (seed % 5 == 0) {
      VoxelIsometricRenderer.drawVoxelIceSparkles(canvas, center, animTime: tileAnimTime, seed: seed);
    }
  }

  void _renderLivingVolcano(Canvas canvas, Offset center, int seed) {
    final int variant = seed % 4;
    switch (variant) {
      case 0:
        VoxelIsometricRenderer.drawVoxelObsidianPillars(canvas, Offset(center.dx - 6, center.dy - 2), scale: 0.95, animTime: tileAnimTime);
        VoxelIsometricRenderer.drawVoxelMagmaVent(canvas, Offset(center.dx + 8, center.dy + 4), scale: 0.85, animTime: tileAnimTime);
        VoxelIsometricRenderer.drawVoxelGeyserBurst(canvas, Offset(center.dx + 8, center.dy - 8), animTime: tileAnimTime, seed: seed);
        break;
      case 1:
        VoxelIsometricRenderer.drawVoxelMagmaVent(canvas, center, scale: 1.1, animTime: tileAnimTime);
        VoxelIsometricRenderer.drawVoxelGeyserBurst(canvas, Offset(center.dx, center.dy - 12), animTime: tileAnimTime, seed: seed);
        break;
      case 2:
        VoxelIsometricRenderer.drawVoxelObsidianPillars(canvas, center, scale: 1.15, animTime: tileAnimTime);
        break;
      case 3:
      default:
        VoxelIsometricRenderer.drawVoxelObsidianPillars(canvas, Offset(center.dx + 6, center.dy - 4), scale: 0.9, animTime: tileAnimTime);
        VoxelIsometricRenderer.drawVoxelPebbles(canvas, Offset(center.dx - 8, center.dy + 4), scale: 0.8);
        break;
    }
    VoxelIsometricRenderer.drawVoxelVolcanoEmbers(canvas, center, animTime: tileAnimTime, seed: seed);
  }

  void _renderLivingWetland(Canvas canvas, Offset center, int seed, {double tapProgress = 0.0}) {
    final int variant = seed % 4;
    switch (variant) {
      case 0:
        VoxelIsometricRenderer.drawVoxelReeds(canvas, Offset(center.dx - 6, center.dy - 2), scale: 0.95, animTime: tileAnimTime);
        VoxelIsometricRenderer.drawVoxelWaterLilies(canvas, Offset(center.dx + 8, center.dy + 4), scale: 0.85);
        break;
      case 1:
        VoxelIsometricRenderer.drawVoxelReeds(canvas, center, scale: 1.1, animTime: tileAnimTime);
        break;
      case 2:
        VoxelIsometricRenderer.drawVoxelWaterLilies(canvas, Offset(center.dx - 4, center.dy), scale: 1.0);
        VoxelIsometricRenderer.drawVoxelLeapingFish(canvas, Offset(center.dx + 8, center.dy + 4), animTime: tileAnimTime, seed: seed);
        break;
      case 3:
      default:
        VoxelIsometricRenderer.drawVoxelReeds(canvas, Offset(center.dx + 6, center.dy - 4), scale: 0.9, animTime: tileAnimTime);
        VoxelIsometricRenderer.drawVoxelBirchTree(canvas, Offset(center.dx - 8, center.dy + 4), scale: 0.6, animTime: tileAnimTime);
        break;
    }
    VoxelIsometricRenderer.drawVoxelDragonflies(canvas, center, animTime: tileAnimTime, seed: seed);

    // Dokunulduğunda Su Dalgası Halkaları (Tactile Water Ripple)
    if (tapProgress > 0.0) {
      VoxelIsometricRenderer.drawVoxelWaterRipple(canvas, center, progress: tapProgress);
    }
  }

  void _renderLivingCrater(Canvas canvas, Offset center, int seed) {
    final double tTime = tileAnimTime;
    VoxelIsometricRenderer.drawVoxelCelestialCraterGround(canvas, center, scale: 1.0, animTime: tTime);
    VoxelIsometricRenderer.drawVoxelCelestialStardust(canvas, center, animTime: tTime, seed: seed);
  }

  void _renderLivingKurgan(Canvas canvas, Offset center, int seed) {
    final double tTime = tileAnimTime;
    VoxelIsometricRenderer.drawVoxelKurganBalbals(canvas, center, scale: 1.0, animTime: tTime);
    if (seed % 2 == 0) {
      VoxelIsometricRenderer.drawVoxelPebbles(canvas, Offset(center.dx + 10, center.dy + 6), scale: 0.9);
    }
  }

  void _renderLivingChasm(Canvas canvas, Offset center, int seed) {
    final double tTime = tileAnimTime;
    VoxelIsometricRenderer.drawVoxelCrystalChasmGround(canvas, center, scale: 1.0, animTime: tTime);
    VoxelIsometricRenderer.drawVoxelCelestialStardust(canvas, center, animTime: tTime, seed: seed + 3);
  }

  void _renderBrutalistBadges(Canvas canvas, Offset center) {
    if (!tileModel.hasBuilding) return;
    final b = tileModel.building!;

    if (b.type != BuildingType.bridge) {
      _drawBadge(
        canvas,
        center.dx,
        center.dy + 16,
        'LV.${b.level}',
        const Color(0xFF0F172A),
        const Color(0xFFFFD700),
      );
    }

    if (b.accumulatedResource > 0) {
      _drawBadge(
        canvas,
        center.dx + 20,
        center.dy - 22,
        '+${b.accumulatedResource.toInt()}',
        const Color(0xFF10B981),
        Colors.black,
      );
    }
  }

  static final Map<String, TextPainter> _badgePainterCache = {};

  static TextPainter _getOrCreateBadgePainter(String text, Color textCol) {
    final String key = '$text-$textCol';
    return _badgePainterCache.putIfAbsent(key, () {
      final textSpan = TextSpan(
        text: text,
        style: TextStyle(
          color: textCol,
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.2,
        ),
      );
      return TextPainter(text: textSpan, textDirection: TextDirection.ltr)..layout();
    });
  }

  void _drawBadge(Canvas canvas, double x, double y, String text, Color bg, Color textCol) {
    const double w = 36.0;
    const double h = 16.0;
    final Rect rect = Rect.fromCenter(center: Offset(x, y), width: w, height: h);

    canvas.drawRect(rect.shift(const Offset(2, 2)), _badgeShadowPaint);
    _sharedFillPaint
      ..style = PaintingStyle.fill
      ..color = bg;
    canvas.drawRect(rect, _sharedFillPaint);
    _sharedStrokePaint
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawRect(rect, _sharedStrokePaint);

    final textPainter = _getOrCreateBadgePainter(text, textCol);
    textPainter.paint(canvas, Offset(x - textPainter.width / 2, y - textPainter.height / 2));
  }

  Color _getBiomeTopColor(TileBiome biome, int seed) {
    final double blend = _seasonTransitionTimer > 0
        ? (1.0 - (_seasonTransitionTimer / _seasonTransitionDuration)).clamp(0.0, 1.0)
        : 1.0;

    final Color fromColor = _getBiomeTopColorForSeason(biome, _previousSeason, false, seed);
    final Color toColor = _getBiomeTopColorForSeason(biome, _currentSeason, isZud, seed);

    Color topColor = Color.lerp(fromColor, toColor, blend) ?? toColor;

    // Sahipsiz / Keşfedilmiş Arazi: Hafif atmosferik sis tonlaması
    if (!tileModel.isOwned) {
      topColor = Color.lerp(topColor, const Color(0xFF0F172A), 0.14)!;
    }

    return topColor;
  }

  Color _getBiomeTopColorForSeason(TileBiome biome, String targetSeason, bool targetZud, int seed) {
    final bool isWinter = targetSeason == 'WINTER' || targetZud;
    final bool isAutumn = targetSeason == 'AUTUMN';
    final bool isSummer = targetSeason == 'SUMMER';

    Color baseColor;
    switch (biome) {
      case TileBiome.meadow:
        if (isWinter) {
          baseColor = const Color(0xFFE2E8F0);
        } else if (isAutumn) {
          baseColor = const Color(0xFFD97706);
        } else if (isSummer) {
          baseColor = const Color(0xFF65A30D);
        } else {
          baseColor = const Color(0xFF2E7D32);
        }
        break;

      case TileBiome.forest:
        if (isWinter) {
          baseColor = const Color(0xFF94A3B8);
        } else if (isAutumn) {
          baseColor = const Color(0xFFEA580C);
        } else if (isSummer) {
          baseColor = const Color(0xFF14532D);
        } else {
          baseColor = const Color(0xFF15803D);
        }
        break;

      case TileBiome.mountain:
        if (isWinter) {
          baseColor = const Color(0xFFF1F5F9);
        } else if (isAutumn) {
          baseColor = const Color(0xFF78350F);
        } else {
          baseColor = const Color(0xFF64748B);
        }
        break;

      case TileBiome.sea:
        if (isWinter) {
          baseColor = const Color(0xFFBAE6FD);
        } else if (isAutumn) {
          baseColor = const Color(0xFF0369A1);
        } else {
          baseColor = const Color(0xFF0284C7);
        }
        break;

      case TileBiome.desert:
        if (isWinter) {
          baseColor = const Color(0xFFFEF08A);
        } else if (isAutumn) {
          baseColor = const Color(0xFFD97706);
        } else if (isSummer) {
          baseColor = const Color(0xFFF59E0B);
        } else {
          baseColor = const Color(0xFFFBBF24);
        }
        break;

      case TileBiome.tundra:
        if (isWinter) {
          baseColor = const Color(0xFFE0F2FE);
        } else if (isAutumn) {
          baseColor = const Color(0xFFC084FC);
        } else {
          baseColor = const Color(0xFF93C5FD);
        }
        break;

      case TileBiome.volcano:
        baseColor = const Color(0xFF1E293B);
        break;

      case TileBiome.wetland:
        if (isWinter) {
          baseColor = const Color(0xFF64748B);
        } else if (isAutumn) {
          baseColor = const Color(0xFF84CC16);
        } else {
          baseColor = const Color(0xFF0D9488);
        }
        break;

      case TileBiome.celestialCrater:
        baseColor = const Color(0xFF1E1B4B);
        break;

      case TileBiome.kurganValley:
        baseColor = const Color(0xFF475569);
        break;

      case TileBiome.crystalChasm:
        baseColor = const Color(0xFF065F46);
        break;
    }

    // Aktif tema paleti atmosferik harmanlama (Zero-GC deterministik tonlama)
    final theme = NeoBrutalistTheme.getTheme(themePalette);
    if (theme.id != 'basalt') {
      switch (theme.id) {
        case 'kurgan':
          baseColor = Color.lerp(baseColor, const Color(0xFFB91C1C), 0.08)!;
          break;
        case 'jade':
          baseColor = Color.lerp(baseColor, const Color(0xFF059669), 0.07)!;
          break;
        case 'tengri':
          baseColor = Color.lerp(baseColor, const Color(0xFF0284C7), 0.07)!;
          break;
        case 'khagan':
          baseColor = Color.lerp(baseColor, const Color(0xFFD97706), 0.07)!;
          break;
      }
    }

    final int shadeVariant = seed % 4;
    switch (shadeVariant) {
      case 0:
        return baseColor;
      case 1:
        return Color.lerp(baseColor, Colors.white, 0.09)!;
      case 2:
        return Color.lerp(baseColor, const Color(0xFF0F172A), 0.08)!;
      case 3:
      default:
        return Color.lerp(baseColor, const Color(0xFFFDE047), 0.07)!;
    }
  }

  (Color, Color, Color) _getBiome3DWallColors(TileBiome biome) {
    final double blend = _seasonTransitionTimer > 0
        ? (1.0 - (_seasonTransitionTimer / _seasonTransitionDuration)).clamp(0.0, 1.0)
        : 1.0;

    final (fL, fR, fB) = _getBiome3DWallColorsForSeason(biome, _previousSeason, false);
    final (tL, tR, tB) = _getBiome3DWallColorsForSeason(biome, _currentSeason, isZud);

    var (wL, wR, wB) = (
      Color.lerp(fL, tL, blend) ?? tL,
      Color.lerp(fR, tR, blend) ?? tR,
      Color.lerp(fB, tB, blend) ?? tB,
    );

    // Sahipsiz / Keşfedilmiş Arazi: 3D duvarlarda kapalı/derinlik tonlaması
    if (!tileModel.isOwned) {
      wL = Color.lerp(wL, const Color(0xFF0F172A), 0.35)!;
      wR = Color.lerp(wR, const Color(0xFF0F172A), 0.35)!;
      wB = Color.lerp(wB, const Color(0xFF020617), 0.35)!;
    }

    final theme = NeoBrutalistTheme.getTheme(themePalette);
    if (theme.id != 'basalt') {
      wB = Color.lerp(wB, theme.slateBorder, 0.18)!;
      wL = Color.lerp(wL, theme.surfaceLight, 0.12)!;
      wR = Color.lerp(wR, theme.surface, 0.12)!;
    }

    return (wL, wR, wB);
  }

  (Color, Color, Color) _getBiome3DWallColorsForSeason(TileBiome biome, String targetSeason, bool targetZud) {
    final bool isWinter = targetSeason == 'WINTER' || targetZud;
    switch (biome) {
      case TileBiome.meadow:
        if (isWinter) {
          return (const Color(0xFFCBD5E1), const Color(0xFF94A3B8), const Color(0xFF475569));
        }
        return (const Color(0xFF4D7C0F), const Color(0xFF3F6212), const Color(0xFF5C3A21));

      case TileBiome.forest:
        if (isWinter) {
          return (const Color(0xFFCBD5E1), const Color(0xFF94A3B8), const Color(0xFF475569));
        }
        return (const Color(0xFF166534), const Color(0xFF14532D), const Color(0xFF451A03));

      case TileBiome.mountain:
        if (isWinter) {
          return (const Color(0xFF94A3B8), const Color(0xFF64748B), const Color(0xFF334155));
        }
        return (const Color(0xFF64748B), const Color(0xFF475569), const Color(0xFF334155));

      case TileBiome.sea:
        return (const Color(0xFF0284C7), const Color(0xFF0369A1), const Color(0xFF075985));

      case TileBiome.desert:
        return (const Color(0xFFD97706), const Color(0xFFB45309), const Color(0xFF78350F));

      case TileBiome.tundra:
        return (const Color(0xFF60A5FA), const Color(0xFF3B82F6), const Color(0xFF1D4ED8));

      case TileBiome.volcano:
        return (const Color(0xFF0F172A), const Color(0xFF020617), const Color(0xFF450A0A));

      case TileBiome.wetland:
        return (const Color(0xFF059669), const Color(0xFF047857), const Color(0xFF064E3B));

      case TileBiome.celestialCrater:
        return (const Color(0xFF312E81), const Color(0xFF1E1B4B), const Color(0xFF0F0E2A));

      case TileBiome.kurganValley:
        return (const Color(0xFF334155), const Color(0xFF1E293B), const Color(0xFF0F172A));

      case TileBiome.crystalChasm:
        return (const Color(0xFF047857), const Color(0xFF065F46), const Color(0xFF022C22));
    }
  }
}
