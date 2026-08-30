import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../../domain/models/building_model.dart';
import '../../../domain/models/combat_model.dart';
import '../../../domain/models/hex_tile_model.dart';
import '../../../domain/services/symbiosis_engine.dart';
import 'voxel_fauna_renderer.dart';

/// 3D Voxel / Isometric Canlı Diorama Çizim Motoru
/// Rüzgar salınımı, gece pencereleri, ateşböcekleri, sıçrayan balıklar, taş patikalar ve partiküller.
class VoxelIsometricRenderer {
  static const double isoAngle = 30.0 * (math.pi / 180.0);
  static final double cosIso = math.cos(isoAngle);
  static final double sinIso = math.sin(isoAngle);

  // Reusable Zero-GC rendering pools
  static final Paint _sharedFillPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _sharedStrokePaint = Paint()..style = PaintingStyle.stroke;
  static final Paint _cubeShadowPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _cubePenumbraPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _cubeSpecularPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;

  static final Path _cubeShadowPath = Path();
  static final Path _cubePenumbraPath = Path();
  static final Path _cubeSpecularPath = Path();
  static final Path _cubeLeftPath = Path();
  static final Path _cubeRightPath = Path();
  static final Path _cubeTopPath = Path();
  static final Path _sharedPath = Path();
  static final Path _sharedPath2 = Path();

  /// 3D İzometrik Küp / Prizma çizer (Zero-GC, Zero-Heap-Allocations)
  /// Donanım hızlandırmalı kenar ışığı (specular highlight) ve çift katmanlı yumuşak temas gölgesi içerir.
  static void drawIsoCube(
    Canvas canvas,
    Offset baseCenter, {
    required double w,
    required double d,
    required double h,
    required Color topColor,
    required Color leftColor,
    required Color rightColor,
    bool drawShadow = false,
    double shadowOpacity = 0.30,
    bool specularHighlight = true,
  }) {
    final double dxR = (w * 0.5) * cosIso;
    final double dyR = (w * 0.5) * sinIso;
    final double dxL = -(d * 0.5) * cosIso;
    final double dyL = (d * 0.5) * sinIso;

    final double bx = baseCenter.dx;
    final double by = baseCenter.dy;

    final double bFrontX = bx;
    final double bFrontY = by + dyR + dyL;
    final double bRightX = bx + dxR;
    final double bRightY = by + dyR - dyL;
    final double bLeftX = bx + dxL;
    final double bLeftY = by - dyR + dyL;
    final double bBackX = bx + dxR + dxL;
    final double bBackY = by - dyR - dyL;

    // Zemin temas gölgesi (İzometrik 45° Yönlü Çift Katmanlı Penumbra Yayılımı)
    if (drawShadow) {
      final double sOffset = math.min(16.0, h * 0.42);

      // 1. Katman: Geniş yumuşak dış penumbra gölgesi (45° Işık İzdüşümü)
      _cubePenumbraPaint.color = Colors.black.withValues(alpha: shadowOpacity * 0.35);
      _cubePenumbraPath
        ..reset()
        ..moveTo(bFrontX + 1.0, bFrontY + 2.0)
        ..lineTo(bRightX + 6.0 + sOffset * cosIso, bRightY + 2.5 - sOffset * 0.5 * sinIso)
        ..lineTo(bBackX + 6.0 + sOffset * cosIso, bBackY + 2.5 - sOffset * 0.5 * sinIso)
        ..lineTo(bLeftX - 3.5, bLeftY + 2.0)
        ..close();
      canvas.drawPath(_cubePenumbraPath, _cubePenumbraPaint);

      // 2. Katman: Yoğun taban temas gölgesi (Sert Göbek)
      _cubeShadowPaint.color = Colors.black.withValues(alpha: shadowOpacity);
      _cubeShadowPath
        ..reset()
        ..moveTo(bFrontX, bFrontY + 1.5)
        ..lineTo(bRightX + 3.5 + sOffset * 0.7 * cosIso, bRightY + 1.5 - sOffset * 0.35 * sinIso)
        ..lineTo(bBackX + 3.5 + sOffset * 0.7 * cosIso, bBackY + 1.5 - sOffset * 0.35 * sinIso)
        ..lineTo(bLeftX - 2.5, bLeftY + 1.5)
        ..close();
      canvas.drawPath(_cubeShadowPath, _cubeShadowPaint);
    }

    final double tFrontY = bFrontY - h;
    final double tRightY = bRightY - h;
    final double tLeftY = bLeftY - h;
    final double tBackY = bBackY - h;

    // 1. Sol Yüzey (Orta Işık / Dolaylı Gün Işığı)
    _cubeLeftPath
      ..reset()
      ..moveTo(bLeftX, bLeftY)
      ..lineTo(bFrontX, bFrontY)
      ..lineTo(bFrontX, tFrontY)
      ..lineTo(bLeftX, tLeftY)
      ..close();
    _sharedFillPaint.color = leftColor;
    canvas.drawPath(_cubeLeftPath, _sharedFillPaint);

    // 2. Sağ Yüzey (Ana Gölge Tarafı)
    _cubeRightPath
      ..reset()
      ..moveTo(bFrontX, bFrontY)
      ..lineTo(bRightX, bRightY)
      ..lineTo(bRightX, tRightY)
      ..lineTo(bFrontX, tFrontY)
      ..close();
    _sharedFillPaint.color = rightColor;
    canvas.drawPath(_cubeRightPath, _sharedFillPaint);

    // 3. Üst Yüzey (Doğrudan Güneş Işığı)
    _cubeTopPath
      ..reset()
      ..moveTo(bFrontX, tFrontY)
      ..lineTo(bRightX, tRightY)
      ..lineTo(bBackX, tBackY)
      ..lineTo(bLeftX, tLeftY)
      ..close();
    _sharedFillPaint.color = topColor;
    canvas.drawPath(_cubeTopPath, _sharedFillPaint);

    // 4. Kenar Işığı, Pah Vurgusu ve Taban Temas Çizgileri (Specular Edge Chamfer & Contact AO)
    if (specularHighlight && w >= 2.5 && h >= 1.5) {
      // Üst ve arka kenarlar parlak pah çizgisi (Rim Light)
      _cubeSpecularPaint
        ..color = Colors.white.withValues(alpha: 0.32)
        ..strokeWidth = 1.0;
      _cubeSpecularPath
        ..reset()
        ..moveTo(bLeftX, tLeftY)
        ..lineTo(bBackX, tBackY)
        ..lineTo(bRightX, tRightY);
      canvas.drawPath(_cubeSpecularPath, _cubeSpecularPaint);

      // Ön köşe dikey ışık kırılma çizgisi
      _cubeSpecularPaint.color = Colors.white.withValues(alpha: 0.18);
      canvas.drawLine(
        Offset(bFrontX, tFrontY),
        Offset(bFrontX, bFrontY),
        _cubeSpecularPaint,
      );

      // Alt taban temas kararması (Ambient Occlusion Contact Line)
      _cubeSpecularPaint.color = Colors.black.withValues(alpha: 0.26);
      canvas.drawLine(
        Offset(bLeftX, bLeftY),
        Offset(bFrontX, bFrontY),
        _cubeSpecularPaint,
      );
      canvas.drawLine(
        Offset(bFrontX, bFrontY),
        Offset(bRightX, bRightY),
        _cubeSpecularPaint,
      );
    }
  }

  /// 3D İzometrik Voksel Küpünü Donanım Hızlandırmalı Mesh (Canvas.drawVertices) ile çizer
  static void drawIsoCubeMesh(
    Canvas canvas,
    Offset baseCenter, {
    required double w,
    required double d,
    required double h,
    required Color topColor,
    required Color leftColor,
    required Color rightColor,
  }) {
    final double dxR = (w * 0.5) * cosIso;
    final double dyR = (w * 0.5) * sinIso;
    final double dxL = -(d * 0.5) * cosIso;
    final double dyL = (d * 0.5) * sinIso;

    final double bx = baseCenter.dx;
    final double by = baseCenter.dy;

    final double bFrontX = bx;
    final double bFrontY = by + dyR + dyL;
    final double bRightX = bx + dxR;
    final double bRightY = by + dyR - dyL;
    final double bLeftX = bx + dxL;
    final double bLeftY = by - dyR + dyL;
    final double bBackX = bx + dxR + dxL;
    final double bBackY = by - dyR - dyL;

    final double tFrontY = bFrontY - h;
    final double tRightY = bRightY - h;
    final double tLeftY = bLeftY - h;
    final double tBackY = bBackY - h;

    final positions = <Offset>[
      // Sol Yüzey (2 üçgen)
      Offset(bLeftX, bLeftY), Offset(bFrontX, bFrontY), Offset(bFrontX, tFrontY),
      Offset(bLeftX, bLeftY), Offset(bFrontX, tFrontY), Offset(bLeftX, tLeftY),
      // Sağ Yüzey (2 üçgen)
      Offset(bFrontX, bFrontY), Offset(bRightX, bRightY), Offset(bRightX, tRightY),
      Offset(bFrontX, bFrontY), Offset(bRightX, tRightY), Offset(bFrontX, tFrontY),
      // Üst Yüzey (2 üçgen)
      Offset(bFrontX, tFrontY), Offset(bRightX, tRightY), Offset(bBackX, tBackY),
      Offset(bFrontX, tFrontY), Offset(bBackX, tBackY), Offset(bLeftX, tLeftY),
    ];

    final colors = <Color>[
      // Sol Yüzey
      leftColor, leftColor, leftColor,
      leftColor, leftColor, leftColor,
      // Sağ Yüzey
      rightColor, rightColor, rightColor,
      rightColor, rightColor, rightColor,
      // Üst Yüzey
      topColor, topColor, topColor,
      topColor, topColor, topColor,
    ];

    final vertices = ui.Vertices(
      VertexMode.triangles,
      positions,
      colors: colors,
    );

    canvas.drawVertices(vertices, BlendMode.srcOver, _sharedFillPaint);
  }

  /// Impeller Donanım Hızlandırmalı Taban Ambient Occlusion (AO) Temas Gölgesi (Canvas.drawVertices)
  static void drawVertexAmbientOcclusion(
    Canvas canvas,
    Offset baseCenter, {
    required double w,
    required double d,
    double spread = 4.0,
    double maxOpacity = 0.38,
  }) {
    final double dxR = (w * 0.5) * cosIso;
    final double dyR = (w * 0.5) * sinIso;
    final double dxL = -(d * 0.5) * cosIso;
    final double dyL = (d * 0.5) * sinIso;

    final double bx = baseCenter.dx;
    final double by = baseCenter.dy;

    final double bFrontX = bx;
    final double bFrontY = by + dyR + dyL;
    final double bRightX = bx + dxR;
    final double bRightY = by + dyR - dyL;
    final double bLeftX = bx + dxL;
    final double bLeftY = by - dyR + dyL;
    final double bBackX = bx + dxR + dxL;
    final double bBackY = by - dyR - dyL;

    final Color innerAo = Colors.black.withValues(alpha: maxOpacity);
    const Color outerAo = Color(0x00000000);

    // Taban merkezinden dışarıya doğru gradyanlı 4 üçgenlik AO eteği
    final positions = <Offset>[
      // Ön etek
      Offset(bFrontX, bFrontY), Offset(bRightX, bRightY), Offset(bRightX + spread * cosIso, bRightY + spread * sinIso),
      Offset(bFrontX, bFrontY), Offset(bRightX + spread * cosIso, bRightY + spread * sinIso), Offset(bFrontX, bFrontY + spread),
      // Sol etek
      Offset(bFrontX, bFrontY), Offset(bLeftX, bLeftY), Offset(bLeftX - spread * cosIso, bLeftY + spread * sinIso),
      Offset(bFrontX, bFrontY), Offset(bLeftX - spread * cosIso, bLeftY + spread * sinIso), Offset(bFrontX, bFrontY + spread),
      // Arka/Sağ etek
      Offset(bRightX, bRightY), Offset(bBackX, bBackY), Offset(bBackX + spread * cosIso, bBackY - spread * sinIso),
      Offset(bRightX, bRightY), Offset(bBackX + spread * cosIso, bBackY - spread * sinIso), Offset(bRightX + spread * cosIso, bRightY + spread * sinIso),
    ];

    final colors = <Color>[
      innerAo, innerAo, outerAo,
      innerAo, outerAo, outerAo,
      innerAo, innerAo, outerAo,
      innerAo, outerAo, outerAo,
      innerAo, innerAo, outerAo,
      innerAo, outerAo, outerAo,
    ];

    final vertices = ui.Vertices(
      VertexMode.triangles,
      positions,
      colors: colors,
    );

    canvas.drawVertices(vertices, BlendMode.srcOver, _sharedFillPaint);
  }

  /// Çok Katmanlı Topoğrafik Yamaç Basamakları ve İstinat Duvarı (Terraced Cliff Stepping)
  static void drawTerracedCliffSteps(
    Canvas canvas,
    Offset baseCenter, {
    double scale = 1.0,
    Color stoneTop = const Color(0xFF64748B),
    Color stoneLeft = const Color(0xFF475569),
    Color stoneRight = const Color(0xFF334155),
  }) {
    // 1. Alt Teras Basamağı
    drawIsoCube(
      canvas,
      Offset(baseCenter.dx - 8 * scale * cosIso, baseCenter.dy + 4 * scale * sinIso),
      w: 12.0 * scale,
      d: 7.0 * scale,
      h: 3.5 * scale,
      topColor: stoneTop,
      leftColor: stoneLeft,
      rightColor: stoneRight,
      specularHighlight: true,
    );

    // 2. Orta Teras ve Taş Merdiven Sahanlığı
    drawIsoCube(
      canvas,
      Offset(baseCenter.dx - 2 * scale * cosIso, baseCenter.dy + 1 * scale * sinIso),
      w: 9.0 * scale,
      d: 6.0 * scale,
      h: 5.5 * scale,
      topColor: stoneTop,
      leftColor: stoneLeft,
      rightColor: stoneRight,
      specularHighlight: true,
    );

    // 3. Ahşap İstinat Destek Kazığı (Wood Retaining Stake)
    drawIsoCube(
      canvas,
      Offset(baseCenter.dx + 6 * scale * cosIso, baseCenter.dy + 3 * scale * sinIso),
      w: 2.2 * scale,
      d: 2.2 * scale,
      h: 7.0 * scale,
      topColor: const Color(0xFF92400E),
      leftColor: const Color(0xFF78350F),
      rightColor: const Color(0xFF451A03),
      drawShadow: true,
      shadowOpacity: 0.22,
    );
  }

  /// Su Yüzeyi Dikey Ters Yansıma ve Dalgalanma Efekti (Planar Water Bank Reflections)
  static void drawWaterBankReflections(
    Canvas canvas,
    Offset waterCenter, {
    required double width,
    required double height,
    required Color silhouetteColor,
    double time = 0.0,
    double opacity = 0.18,
  }) {
    final double wave = math.sin(time * 2.0 + waterCenter.dx * 0.1) * 2.5;
    final Rect refRect = Rect.fromCenter(
      center: Offset(waterCenter.dx + wave * 0.5, waterCenter.dy + (height * 0.45)),
      width: width * 0.85,
      height: height * 0.75,
    );

    final shader = ui.Gradient.linear(
      refRect.topCenter,
      refRect.bottomCenter,
      [
        silhouetteColor.withValues(alpha: opacity),
        silhouetteColor.withValues(alpha: opacity * 0.35),
        Colors.transparent,
      ],
      [0.0, 0.65, 1.0],
    );

    _sharedFillPaint.shader = shader;
    _sharedPath
      ..reset()
      ..moveTo(refRect.left, refRect.top)
      ..lineTo(refRect.right, refRect.top)
      ..lineTo(refRect.right - (width * 0.15) + wave, refRect.bottom)
      ..lineTo(refRect.left + (width * 0.15) - wave, refRect.bottom)
      ..close();

    canvas.drawPath(_sharedPath, _sharedFillPaint);
    _sharedFillPaint.shader = null;
  }

  /// Binalar için Yaşanmışlık ve Mikro Çevre Detayları (Environmental Clutter & Props)
  static void drawEnvironmentalClutter(
    Canvas canvas,
    Offset buildingBase, {
    required BuildingType type,
    double scale = 1.0,
    double animTime = 0.0,
  }) {
    switch (type) {
      case BuildingType.windmill:
      case BuildingType.bakery:
        // 1. Un Çuvalları ve Ahşap Tahıl Fıçısı
        drawIsoCube(
          canvas,
          Offset(buildingBase.dx - 9.0 * scale, buildingBase.dy + 3.0 * scale),
          w: 3.2 * scale,
          d: 3.2 * scale,
          h: 4.5 * scale,
          topColor: const Color(0xFFF1F5F9),
          leftColor: const Color(0xFFE2E8F0),
          rightColor: const Color(0xFFCBD5E1),
          drawShadow: true,
          shadowOpacity: 0.2,
        );
        drawIsoCube(
          canvas,
          Offset(buildingBase.dx - 6.5 * scale, buildingBase.dy + 4.5 * scale),
          w: 2.8 * scale,
          d: 2.8 * scale,
          h: 3.5 * scale,
          topColor: const Color(0xFFE2E8F0),
          leftColor: const Color(0xFFCBD5E1),
          rightColor: const Color(0xFF94A3B8),
        );
        break;

      case BuildingType.quarry:
      case BuildingType.mine:
      case BuildingType.obsidianForge:
        // 2. Maden Cevheri ve Ahşap Ray Kütükleri
        drawIsoCube(
          canvas,
          Offset(buildingBase.dx + 8.0 * scale, buildingBase.dy + 4.0 * scale),
          w: 3.5 * scale,
          d: 3.5 * scale,
          h: 2.8 * scale,
          topColor: const Color(0xFF64748B),
          leftColor: const Color(0xFF475569),
          rightColor: const Color(0xFF334155),
          drawShadow: true,
        );
        drawIsoCube(
          canvas,
          Offset(buildingBase.dx + 11.5 * scale, buildingBase.dy + 2.5 * scale),
          w: 2.5 * scale,
          d: 2.5 * scale,
          h: 2.0 * scale,
          topColor: const Color(0xFF94A3B8),
          leftColor: const Color(0xFF64748B),
          rightColor: const Color(0xFF475569),
        );
        break;

      case BuildingType.lumberjack:
      case BuildingType.sawmill:
        // 3. İstiflenmiş Kütükler (Timber Stacks)
        drawIsoCube(
          canvas,
          Offset(buildingBase.dx - 8.0 * scale, buildingBase.dy + 3.5 * scale),
          w: 2.4 * scale,
          d: 6.5 * scale,
          h: 2.2 * scale,
          topColor: const Color(0xFFB45309),
          leftColor: const Color(0xFF92400E),
          rightColor: const Color(0xFF78350F),
          drawShadow: true,
          shadowOpacity: 0.22,
        );
        drawIsoCube(
          canvas,
          Offset(buildingBase.dx - 8.0 * scale, buildingBase.dy + 3.5 * scale - 2.0 * scale),
          w: 2.2 * scale,
          d: 5.5 * scale,
          h: 2.0 * scale,
          topColor: const Color(0xFFD97706),
          leftColor: const Color(0xFFB45309),
          rightColor: const Color(0xFF92400E),
        );
        break;

      case BuildingType.castle:
        // 4. At Kılı Kadim Tuğ / Sancak (Ancient Steppe Tug Banner with Sway)
        final double sway = math.sin(animTime * 1.8) * 1.5 * scale;
        // Tuğ Direği
        drawIsoCube(
          canvas,
          Offset(buildingBase.dx - 12.0 * scale, buildingBase.dy - 1.0 * scale),
          w: 1.2 * scale,
          d: 1.2 * scale,
          h: 12.0 * scale,
          topColor: const Color(0xFFF59E0B),
          leftColor: const Color(0xFFD97706),
          rightColor: const Color(0xFFB45309),
          drawShadow: true,
        );
        // Dalgalanan Kırmızı/Altın Sancak
        drawIsoCube(
          canvas,
          Offset(buildingBase.dx - 12.0 * scale + sway, buildingBase.dy - 1.0 * scale - 8.0 * scale),
          w: 1.5 * scale,
          d: 4.5 * scale,
          h: 3.5 * scale,
          topColor: const Color(0xFFEF4444),
          leftColor: const Color(0xFFDC2626),
          rightColor: const Color(0xFFB91C1C),
        );
        break;

      default:
        break;
    }
  }

  // --- RÜZGARLA SALINAN AĞAÇLAR (WIND SWAY) ---

  /// Rüzgarla hafifçe salınan Meşe Ağacı (Mevsim Duyarlı: Güzün Kızıl/Bakır, Kışın Karlı, Baharda Taze)
  static void drawVoxelTree(
    Canvas canvas,
    Offset baseCenter, {
    double scale = 1.0,
    Color? foliageTint,
    double animTime = 0.0,
    double windFactor = 1.0,
    String? season,
    bool isZud = false,
  }) {
    final double windSway = math.sin(animTime * 2.5 + baseCenter.dx * 0.04) * (2.2 * windFactor * scale);

    final double trunkW = 6.0 * scale;
    final double trunkH = 16.0 * scale;
    drawIsoCube(
      canvas,
      baseCenter,
      w: trunkW,
      d: trunkW,
      h: trunkH,
      topColor: const Color(0xFFB45309),
      leftColor: const Color(0xFF78350F),
      rightColor: const Color(0xFF451A03),
      drawShadow: true,
      shadowOpacity: 0.35,
    );

    final Offset foliageCenter = Offset(baseCenter.dx + windSway * 0.5, baseCenter.dy - trunkH + 4 * scale);

    Color top;
    Color mid;
    Color dark;

    if (foliageTint != null) {
      top = foliageTint;
      mid = foliageTint.withValues(alpha: 0.78);
      dark = foliageTint.withValues(alpha: 0.50);
    } else if (season == 'AUTUMN') {
      top = const Color(0xFFFB923C);
      mid = const Color(0xFFC2410C);
      dark = const Color(0xFF7C2D12);
    } else if (season == 'WINTER' || isZud) {
      top = const Color(0xFFFFFFFF);
      mid = const Color(0xFF94A3B8);
      dark = const Color(0xFF475569);
    } else if (season == 'SUMMER') {
      top = const Color(0xFF4ADE80);
      mid = const Color(0xFF15803D);
      dark = const Color(0xFF052E16);
    } else {
      // Spring
      top = const Color(0xFF86EFAC);
      mid = const Color(0xFF16A34A);
      dark = const Color(0xFF14532D);
    }

    // 1. Katman: Geniş Alt Kanopi (Gövdeye ve Zemine Gölge Düşürür)
    drawIsoCube(
      canvas,
      foliageCenter,
      w: 24.0 * scale,
      d: 24.0 * scale,
      h: 12.0 * scale,
      topColor: top,
      leftColor: mid,
      rightColor: dark,
      drawShadow: true,
      shadowOpacity: 0.28,
    );

    // 2. Katman: Orta Kanopi
    drawIsoCube(
      canvas,
      Offset(foliageCenter.dx + windSway * 0.3, foliageCenter.dy - 10 * scale),
      w: 17.0 * scale,
      d: 17.0 * scale,
      h: 10.0 * scale,
      topColor: top,
      leftColor: mid,
      rightColor: dark,
      drawShadow: true,
      shadowOpacity: 0.20,
    );

    // 3. Katman: Tepe Kanopi Taç Bloğu (En Güneşli Tepe Noktası)
    drawIsoCube(
      canvas,
      Offset(foliageCenter.dx + windSway * 0.6, foliageCenter.dy - 18 * scale),
      w: 11.0 * scale,
      d: 11.0 * scale,
      h: 8.0 * scale,
      topColor: (season == 'WINTER' || isZud) ? const Color(0xFFFFFFFF) : (season == 'AUTUMN' ? const Color(0xFFFDE047) : const Color(0xFFBBF7D0)),
      leftColor: mid,
      rightColor: dark,
      specularHighlight: true,
    );
  }

  /// Rüzgarla salınan Beyaz Huş Ağacı (Mevsim Duyarlı: Güzün Altın Kehribar, Kışın Kırağılı)
  static void drawVoxelBirchTree(
    Canvas canvas,
    Offset baseCenter, {
    double scale = 1.0,
    double animTime = 0.0,
    double windFactor = 1.0,
    String? season,
    bool isZud = false,
  }) {
    final double windSway = math.sin(animTime * 3.0 + baseCenter.dx * 0.05) * (2.8 * windFactor * scale);

    final double trunkW = 5.0 * scale;
    final double trunkH = 20.0 * scale;
    drawIsoCube(
      canvas,
      baseCenter,
      w: trunkW,
      d: trunkW,
      h: trunkH,
      topColor: const Color(0xFFFFFFFF),
      leftColor: const Color(0xFFCBD5E1),
      rightColor: const Color(0xFF64748B),
      drawShadow: true,
      shadowOpacity: 0.32,
    );

    Color folTop;
    Color folMid;
    Color folDark;
    Color capTop;

    if (season == 'AUTUMN') {
      folTop = const Color(0xFFFDE047);
      folMid = const Color(0xFFD97706);
      folDark = const Color(0xFF92400E);
      capTop = const Color(0xFFFEF08A);
    } else if (season == 'WINTER' || isZud) {
      folTop = const Color(0xFFFFFFFF);
      folMid = const Color(0xFF94A3B8);
      folDark = const Color(0xFF475569);
      capTop = const Color(0xFFFFFFFF);
    } else if (season == 'SUMMER') {
      folTop = const Color(0xFFBEF264);
      folMid = const Color(0xFF65A30D);
      folDark = const Color(0xFF365314);
      capTop = const Color(0xFFD9F99D);
    } else {
      // Spring
      folTop = const Color(0xFFD9F99D);
      folMid = const Color(0xFF84CC16);
      folDark = const Color(0xFF4D7C0F);
      capTop = const Color(0xFFECFCCB);
    }

    final Offset folBase = Offset(baseCenter.dx + windSway * 0.5, baseCenter.dy - trunkH + 4 * scale);
    drawIsoCube(
      canvas,
      folBase,
      w: 17.0 * scale,
      d: 17.0 * scale,
      h: 14.0 * scale,
      topColor: folTop,
      leftColor: folMid,
      rightColor: folDark,
      drawShadow: true,
      shadowOpacity: 0.25,
    );

    drawIsoCube(
      canvas,
      Offset(folBase.dx + windSway * 0.5, folBase.dy - 12 * scale),
      w: 11.0 * scale,
      d: 11.0 * scale,
      h: 10.0 * scale,
      topColor: capTop,
      leftColor: folMid,
      rightColor: folDark,
      specularHighlight: true,
    );
  }

  /// Rüzgarla salınan Bozkır Çam Ağacı (Evergreen Taiga Pine)
  static void drawVoxelPine(
    Canvas canvas,
    Offset baseCenter, {
    double scale = 1.0,
    double animTime = 0.0,
    double windFactor = 1.0,
    String? season,
    bool isZud = false,
  }) {
    final double windSway = math.sin(animTime * 2.0 + baseCenter.dy * 0.04) * (1.6 * windFactor * scale);

    drawIsoCube(
      canvas,
      baseCenter,
      w: 5.0 * scale,
      d: 5.0 * scale,
      h: 12.0 * scale,
      topColor: const Color(0xFF92400E),
      leftColor: const Color(0xFF78350F),
      rightColor: const Color(0xFF451A03),
      drawShadow: true,
      shadowOpacity: 0.35,
    );

    final bool isWinterOrZud = season == 'WINTER' || isZud;
    final double startY = baseCenter.dy - 8 * scale;

    for (int i = 0; i < 3; i++) {
      final double size = (20.0 - i * 6.0) * scale;
      final double h = 8.0 * scale;
      final double sway = windSway * (i + 1) * 0.35;
      final Offset c = Offset(baseCenter.dx + sway, startY - (i * 7.0 * scale));

      final Color pineTop = isWinterOrZud
          ? const Color(0xFFFFFFFF)
          : (season == 'AUTUMN' ? const Color(0xFF14B8A6) : const Color(0xFF34D399));
      final Color pineLeft = isWinterOrZud
          ? const Color(0xFF94A3B8)
          : (season == 'AUTUMN' ? const Color(0xFF0F766E) : const Color(0xFF059669));
      final Color pineRight = isWinterOrZud
          ? const Color(0xFF475569)
          : (season == 'AUTUMN' ? const Color(0xFF115E59) : const Color(0xFF064E3B));

      drawIsoCube(
        canvas,
        c,
        w: size,
        d: size,
        h: h,
        topColor: pineTop,
        leftColor: pineLeft,
        rightColor: pineRight,
        drawShadow: i == 0,
        shadowOpacity: 0.28,
        specularHighlight: true,
      );

      // Kışın katmanların tepesinde ince kar şapkası (Snowcap frosting)
      if (isWinterOrZud) {
        drawIsoCube(
          canvas,
          Offset(c.dx, c.dy - h + 1.0),
          w: size * 0.65,
          d: size * 0.65,
          h: 2.0 * scale,
          topColor: const Color(0xFFFFFFFF),
          leftColor: const Color(0xFFE2E8F0),
          rightColor: const Color(0xFF94A3B8),
          specularHighlight: true,
        );
      }
    }
  }

  // --- HAYVANLAR, BALIKLAR & ATEŞBÖCEKLERİ ---

  /// Sıçrayan 3D Voxel Balık & Su Köpükleri
  static void drawVoxelLeapingFish(Canvas canvas, Offset seaCenter, {required double animTime, required int seed}) {
    final double cycle = (animTime * 0.8 + seed * 1.7) % 4.0;
    if (cycle > 1.2) return; // Arada bir sıçrar

    final double progress = cycle / 1.2; // 0.0 -> 1.0
    final double jumpHeight = math.sin(progress * math.pi) * 22.0;
    final double jumpX = (progress - 0.5) * 26.0;

    final Offset fishPos = Offset(seaCenter.dx + jumpX, seaCenter.dy - jumpHeight);

    // Su Halka Köpüğü (Splash ring)
    if (progress < 0.2 || progress > 0.8) {
      _sharedStrokePaint
        ..color = Colors.white.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(seaCenter.dx + jumpX, seaCenter.dy), width: 14.0, height: 7.0),
        _sharedStrokePaint,
      );
    }

    // Minik Gümüş Voxel Balık
    drawIsoCube(
      canvas,
      fishPos,
      w: 4.0,
      d: 7.0,
      h: 3.0,
      topColor: const Color(0xFFF1F5F9),
      leftColor: const Color(0xFF38BDF8),
      rightColor: const Color(0xFF0284C7),
      drawShadow: true,
      shadowOpacity: 0.15,
    );
  }

  /// Geceleyin Parıldayan 3D Voxel Ateşböcekleri
  static void drawVoxelFireflies(Canvas canvas, Offset center, {required double animTime, required int seed}) {
    for (int i = 0; i < 3; i++) {
      final double t = animTime * 2.0 + (seed * 1.5) + (i * 2.1);
      final double fx = center.dx + math.cos(t * 1.2) * 16.0;
      final double fy = center.dy - 12.0 + math.sin(t * 1.5) * 10.0;
      final double glow = (math.sin(t * 3.0) + 1.0) * 0.5;

      final Color fireflyColor = Color.lerp(
        const Color(0xFF84CC16),
        const Color(0xFFFEF08A),
        glow,
      )!;

      // Glow aurası
      _sharedFillPaint
        ..color = fireflyColor.withValues(alpha: 0.4 * glow)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(fx, fy), 4.0, _sharedFillPaint);

      // Çekirdek Voxel
      drawIsoCube(
        canvas,
        Offset(fx, fy),
        w: 2.0,
        d: 2.0,
        h: 2.0,
        topColor: Colors.white,
        leftColor: fireflyColor,
        rightColor: fireflyColor.withValues(alpha: 0.8),
      );
    }
  }

  /// 3D Voxel Koyun (VoxelFaunaRenderer Köprüsü)
  static void drawVoxelSheep(
    Canvas canvas,
    Offset pos, {
    double animTime = 0.0,
    double scale = 1.0,
    int seed = 0,
    bool flipX = false,
  }) {
    VoxelFaunaRenderer.drawSheep(
      canvas,
      pos,
      animTime: animTime,
      scale: scale,
      seed: seed,
      flipX: flipX,
    );
  }

  /// 3D Voxel Karaca / Dağ Keçisi (VoxelFaunaRenderer Köprüsü)
  static void drawVoxelDeer(
    Canvas canvas,
    Offset pos, {
    double animTime = 0.0,
    double scale = 1.0,
    int seed = 0,
    bool flipX = false,
  }) {
    VoxelFaunaRenderer.drawMountainIbex(
      canvas,
      pos,
      animTime: animTime,
      scale: scale,
      seed: seed,
      flipX: flipX,
    );
  }

  /// 3D Voxel Çöl Devesi (VoxelFaunaRenderer Köprüsü)
  static void drawVoxelCamel(
    Canvas canvas,
    Offset pos, {
    double animTime = 0.0,
    double scale = 1.0,
    int seed = 0,
    bool flipX = false,
  }) {
    VoxelFaunaRenderer.drawCamel(
      canvas,
      pos,
      animTime: animTime,
      scale: scale,
      seed: seed,
      flipX: flipX,
    );
  }

  /// 3D Voxel Kutup Tilkisi (VoxelFaunaRenderer Köprüsü)
  static void drawVoxelArcticFox(
    Canvas canvas,
    Offset pos, {
    double animTime = 0.0,
    double scale = 1.0,
    int seed = 0,
    bool flipX = false,
  }) {
    VoxelFaunaRenderer.drawArcticFox(
      canvas,
      pos,
      animTime: animTime,
      scale: scale,
      seed: seed,
      flipX: flipX,
    );
  }

  /// 3D Voxel Dağ Yaban Keçisi (VoxelFaunaRenderer Köprüsü)
  static void drawVoxelMountainIbex(
    Canvas canvas,
    Offset pos, {
    double animTime = 0.0,
    double scale = 1.0,
    int seed = 0,
    bool flipX = false,
  }) {
    VoxelFaunaRenderer.drawMountainIbex(
      canvas,
      pos,
      animTime: animTime,
      scale: scale,
      seed: seed,
      flipX: flipX,
    );
  }

  /// 3D Voxel Gökyüzü Kuşu (VoxelFaunaRenderer Köprüsü)
  static void drawVoxelBird(
    Canvas canvas,
    Offset pos, {
    required double wingAnim,
    double scale = 1.0,
    Color bodyColor = const Color(0xFFFFFFFF),
    Color wingColor = const Color(0xFFF8FAFC),
    Color wingTipColor = const Color(0xFF94A3B8),
  }) {
    VoxelFaunaRenderer.drawSkyBird(
      canvas,
      pos,
      wingAnim: wingAnim,
      scale: scale,
      bodyColor: bodyColor,
      wingColor: wingColor,
      wingTipColor: wingTipColor,
    );
  }

  /// 3D Voxel Asil Bozkır Yılkı Atı (VoxelFaunaRenderer Köprüsü)
  static void drawVoxelHorse(
    Canvas canvas,
    Offset pos, {
    double animTime = 0.0,
    double scale = 1.0,
    int seed = 0,
    bool flipX = false,
    double startleProgress = 0.0,
  }) {
    VoxelFaunaRenderer.drawHorse(
      canvas,
      pos,
      animTime: animTime,
      scale: scale,
      seed: seed,
      flipX: flipX,
      startleProgress: startleProgress,
    );
  }

  // --- PATİKA YOLLAR (ROADS) ---

  /// Karolar Arası 3D Doğal Taş / Arnavut Kaldırımı Patika Çizer
  static void drawVoxelRoadSegment(Canvas canvas, Offset start, Offset end) {
    const int steps = 5;
    for (int i = 0; i <= steps; i++) {
      final double t = i / steps;
      final Offset pt = Offset.lerp(start, end, t)!;
      final double jitter = (i % 2 == 0 ? 1.0 : -1.0) * 1.5;
      final Offset stonePos = Offset(pt.dx + jitter * sinIso, pt.dy - jitter * cosIso);

      final Color stoneTop = i % 2 == 0 ? const Color(0xFFE2E8F0) : const Color(0xFFCBD5E1);
      final Color stoneLeft = i % 2 == 0 ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
      final Color stoneRight = i % 2 == 0 ? const Color(0xFF64748B) : const Color(0xFF475569);

      drawIsoCube(
        canvas,
        stonePos,
        w: 7.0,
        d: 7.0,
        h: 1.5,
        topColor: stoneTop,
        leftColor: stoneLeft,
        rightColor: stoneRight,
        drawShadow: true,
        shadowOpacity: 0.15,
      );
    }
  }

  /// Doğal Kıyı Şeridi, Kumsal Saçakları ve Dinamik Beyaz Dalga Köpükleri
  static void drawVoxelShorelineWaves(
    Canvas canvas,
    Offset center,
    List<Offset> corners, {
    required double animTime,
    int seed = 0,
  }) {
    // 1. Kumsal Saçak Kenarlığı (Açık Kum Taşı Rengi)
    _sharedStrokePaint
      ..color = const Color(0xFFFDE68A).withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    _sharedPath
      ..reset()
      ..moveTo(corners[0].dx, corners[0].dy);
    for (int i = 1; i < 6; i++) {
      _sharedPath.lineTo(corners[i].dx, corners[i].dy);
    }
    _sharedPath.close();
    canvas.drawPath(_sharedPath, _sharedStrokePaint);

    // 2. Dinamik Sinüs Salınımlı Beyaz Dalga Köpüğü
    final double wavePulse1 = 0.5 + 0.5 * math.sin(animTime * 2.8 + seed);
    final double wavePulse2 = 0.5 + 0.5 * math.cos(animTime * 2.1 + seed);

    _sharedStrokePaint
      ..color = Colors.white.withValues(alpha: 0.75 * wavePulse1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    _sharedPath2.reset();
    for (int i = 0; i < 6; i++) {
      final pA = corners[i];
      final pB = corners[(i + 1) % 6];
      final mid = Offset((pA.dx + pB.dx) / 2, (pA.dy + pB.dy) / 2);
      final offsetMid = Offset(
        mid.dx + (center.dx - mid.dx) * (0.15 + 0.1 * wavePulse1),
        mid.dy + (center.dy - mid.dy) * (0.15 + 0.1 * wavePulse1),
      );
      _sharedPath2.moveTo(pA.dx + (center.dx - pA.dx) * 0.1, pA.dy + (center.dy - pA.dy) * 0.1);
      _sharedPath2.quadraticBezierTo(offsetMid.dx, offsetMid.dy, pB.dx + (center.dx - pB.dx) * 0.1, pB.dy + (center.dy - pB.dy) * 0.1);
    }
    canvas.drawPath(_sharedPath2, _sharedStrokePaint);

    // 3. Merkezde Dalgalanan Köpük Parçaları
    drawIsoCube(
      canvas,
      Offset(center.dx - 12 + wavePulse2 * 4.0, center.dy - 6),
      w: 8.0,
      d: 3.0,
      h: 1.2,
      topColor: Colors.white.withValues(alpha: 0.8),
      leftColor: const Color(0xFFBAE6FD),
      rightColor: const Color(0xFF7DD3FC),
    );
  }

  // --- ÇİÇEKLER, ÇAKILLAR & MANTARLAR ---

  static void drawVoxelPebbles(Canvas canvas, Offset pos, {double scale = 1.0}) {
    drawIsoCube(
      canvas,
      pos,
      w: 6.0 * scale,
      d: 6.0 * scale,
      h: 4.0 * scale,
      topColor: const Color(0xFF94A3B8),
      leftColor: const Color(0xFF64748B),
      rightColor: const Color(0xFF475569),
      drawShadow: true,
      shadowOpacity: 0.2,
    );

    drawIsoCube(
      canvas,
      Offset(pos.dx + 6 * cosIso * scale, pos.dy + 4 * sinIso * scale),
      w: 4.0 * scale,
      d: 4.0 * scale,
      h: 2.5 * scale,
      topColor: const Color(0xFFCBD5E1),
      leftColor: const Color(0xFF94A3B8),
      rightColor: const Color(0xFF64748B),
    );
  }

  static void drawVoxelFlowers(Canvas canvas, Offset pos, {required Color flowerColor, double scale = 1.0}) {
    drawIsoCube(
      canvas,
      pos,
      w: 2.0 * scale,
      d: 2.0 * scale,
      h: 5.0 * scale,
      topColor: const Color(0xFF4ADE80),
      leftColor: const Color(0xFF22C55E),
      rightColor: const Color(0xFF16A34A),
    );

    drawIsoCube(
      canvas,
      Offset(pos.dx, pos.dy - 5.0 * scale),
      w: 4.0 * scale,
      d: 4.0 * scale,
      h: 3.0 * scale,
      topColor: flowerColor,
      leftColor: flowerColor.withValues(alpha: 0.8),
      rightColor: flowerColor.withValues(alpha: 0.6),
    );
  }

  static void drawVoxelMushroom(Canvas canvas, Offset pos, {double scale = 1.0}) {
    drawIsoCube(
      canvas,
      pos,
      w: 3.0 * scale,
      d: 3.0 * scale,
      h: 5.0 * scale,
      topColor: const Color(0xFFF1F5F9),
      leftColor: const Color(0xFFE2E8F0),
      rightColor: const Color(0xFFCBD5E1),
    );

    drawIsoCube(
      canvas,
      Offset(pos.dx, pos.dy - 5.0 * scale),
      w: 7.0 * scale,
      d: 7.0 * scale,
      h: 4.0 * scale,
      topColor: const Color(0xFFEF4444),
      leftColor: const Color(0xFFDC2626),
      rightColor: const Color(0xFFB91C1C),
    );
  }

  // --- BİNALAR & GECE IŞIKLANDIRMASI (GLOWING WINDOWS) ---

  /// 3D Voxel Ekin / Buğday Tarlası (Çoklu Görsel Varyantlar & Rüzgar Salınımlı)
  static void drawVoxelCropField(Canvas canvas, Offset baseCenter, {double animTime = 0.0, int variant = 0}) {
    drawIsoCube(
      canvas,
      baseCenter,
      w: 38.0,
      d: 38.0,
      h: 4.0,
      topColor: const Color(0xFF854D0E),
      leftColor: const Color(0xFF713F12),
      rightColor: const Color(0xFF522C0A),
      drawShadow: true,
    );

    final Offset fieldTop = Offset(baseCenter.dx, baseCenter.dy - 4.0);
    final int v = variant % 3;

    if (v == 1) {
      // Varyant 1: Çapraz Ekinler & Saman Balyaları
      // 2 Köşede Saman Balyası
      drawIsoCube(
        canvas,
        Offset(fieldTop.dx - 12.0 * cosIso, fieldTop.dy - 12.0 * sinIso),
        w: 7.0,
        d: 7.0,
        h: 6.0,
        topColor: const Color(0xFFFACC15),
        leftColor: const Color(0xFFEAB308),
        rightColor: const Color(0xFFCA8A04),
      );
      drawIsoCube(
        canvas,
        Offset(fieldTop.dx + 12.0 * cosIso, fieldTop.dy + 8.0 * sinIso),
        w: 6.0,
        d: 6.0,
        h: 5.0,
        topColor: const Color(0xFFFEF08A),
        leftColor: const Color(0xFFFACC15),
        rightColor: const Color(0xFFCA8A04),
      );

      // Çapraz ekin sıraları
      for (int i = -1; i <= 1; i++) {
        for (int j = -1; j <= 1; j++) {
          if (i == -1 && j == -1) continue; // Saman balyası yeri
          final double windSway = math.sin(animTime * 3.0 + i * 1.1 + j * 0.7) * 1.6;
          final double offX = (i * 9.0 * cosIso) - (j * 7.0 * cosIso) + windSway;
          final double offY = (i * 9.0 * sinIso) + (j * 7.0 * sinIso);
          drawIsoCube(
            canvas,
            Offset(fieldTop.dx + offX, fieldTop.dy + offY),
            w: 4.5,
            d: 4.5,
            h: 8.0 + ((i + j + 3) % 2) * 2.5,
            topColor: const Color(0xFFFEF08A),
            leftColor: const Color(0xFFFACC15),
            rightColor: const Color(0xFFCA8A04),
          );
        }
      }
    } else if (v == 2) {
      // Varyant 2: Sulama Arkı & İkiz Ekin Yatağı
      // Ortadan geçen mavi sulama arkı
      drawIsoCube(
        canvas,
        Offset(fieldTop.dx, fieldTop.dy),
        w: 36.0,
        d: 5.0,
        h: 1.0,
        topColor: const Color(0xFF38BDF8),
        leftColor: const Color(0xFF0284C7),
        rightColor: const Color(0xFF0369A1),
      );

      // Sağ ve Sol yakadaki ekin dizileri
      for (int side in [-1, 1]) {
        for (int c = -1; c <= 1; c++) {
          final double windSway = math.sin(animTime * 2.8 + side * 1.5 + c * 0.9) * 1.4;
          final double offX = (c * 9.0 * cosIso) + (side * 8.0 * sinIso) + windSway;
          final double offY = (c * 9.0 * sinIso) + (side * 8.0 * cosIso);
          drawIsoCube(
            canvas,
            Offset(fieldTop.dx + offX, fieldTop.dy + offY),
            w: 4.0,
            d: 4.0,
            h: 8.5 + ((c + 2) % 2) * 2.0,
            topColor: side == 1 ? const Color(0xFFFEF08A) : const Color(0xFF86EFAC),
            leftColor: side == 1 ? const Color(0xFFFACC15) : const Color(0xFF4ADE80),
            rightColor: side == 1 ? const Color(0xFFCA8A04) : const Color(0xFF22C55E),
          );
        }
      }
    } else {
      // Varyant 0: 3x3 Klasik Sıralar & Ahşap Korkuluk Haçı
      const int rows = 3;
      const int cols = 3;

      for (int r = 0; r < rows; r++) {
        for (int c = 0; c < cols; c++) {
          if (r == 1 && c == 1) continue; // Ortada korkuluk
          final double windSway = math.sin(animTime * 3.0 + (r * 0.8) + (c * 0.6)) * 1.5;
          final double offX = (c - 1) * 8.0 * cosIso - (r - 1) * 8.0 * cosIso + windSway;
          final double offY = (c - 1) * 8.0 * sinIso + (r - 1) * 8.0 * sinIso;
          final Offset cropPos = Offset(fieldTop.dx + offX, fieldTop.dy + offY);

          drawIsoCube(
            canvas,
            cropPos,
            w: 4.0,
            d: 4.0,
            h: 8.0 + ((r + c) % 2) * 2.0,
            topColor: const Color(0xFFFEF08A),
            leftColor: const Color(0xFFFACC15),
            rightColor: const Color(0xFFCA8A04),
          );
        }
      }

      // Ortada Korkuluk Haçı
      drawIsoCube(
        canvas,
        fieldTop,
        w: 2.5,
        d: 2.5,
        h: 11.0,
        topColor: const Color(0xFF92400E),
        leftColor: const Color(0xFF78350F),
        rightColor: const Color(0xFF451A03),
      );
      drawIsoCube(
        canvas,
        Offset(fieldTop.dx, fieldTop.dy - 7.0),
        w: 8.0,
        d: 2.0,
        h: 2.0,
        topColor: const Color(0xFFB45309),
        leftColor: const Color(0xFF92400E),
        rightColor: const Color(0xFF78350F),
      );
      drawIsoCube(
        canvas,
        Offset(fieldTop.dx, fieldTop.dy - 11.0),
        w: 3.5,
        d: 3.5,
        h: 3.0,
        topColor: const Color(0xFFFEF08A),
        leftColor: const Color(0xFFFACC15),
        rightColor: const Color(0xFFCA8A04),
      );
    }
  }

  /// 3D Voxel Arpa / Darı Tarlası (Çoklu Görsel Varyantlar)
  static void drawVoxelBarleyField(Canvas canvas, Offset baseCenter, {double animTime = 0.0, int variant = 0}) {
    drawIsoCube(
      canvas,
      baseCenter,
      w: 38.0,
      d: 38.0,
      h: 4.0,
      topColor: const Color(0xFF78350F),
      leftColor: const Color(0xFF5A2508),
      rightColor: const Color(0xFF451A03),
      drawShadow: true,
    );

    final Offset fieldTop = Offset(baseCenter.dx, baseCenter.dy - 4.0);
    final int v = variant % 3;

    if (v == 1) {
      // Varyant 1: Ahşap Çitler & Rüzgar Flama Direği
      // Kenar ahşap çitler
      for (double side in [-1.0, 1.0]) {
        drawIsoCube(
          canvas,
          Offset(fieldTop.dx + side * 14.0 * cosIso, fieldTop.dy + side * 14.0 * sinIso),
          w: 26.0,
          d: 2.5,
          h: 4.0,
          topColor: const Color(0xFFB45309),
          leftColor: const Color(0xFF92400E),
          rightColor: const Color(0xFF78350F),
        );
      }

      // Rüzgar Flama Direği
      final Offset flagPos = Offset(fieldTop.dx - 12.0 * cosIso, fieldTop.dy - 12.0 * sinIso);
      drawIsoCube(
        canvas,
        flagPos,
        w: 2.5,
        d: 2.5,
        h: 14.0,
        topColor: const Color(0xFFCBD5E1),
        leftColor: const Color(0xFF94A3B8),
        rightColor: const Color(0xFF64748B),
      );
      final double flagWave = math.sin(animTime * 4.0) * 1.5;
      drawIsoCube(
        canvas,
        Offset(flagPos.dx + 4.0 + flagWave, flagPos.dy - 12.0),
        w: 6.0,
        d: 1.5,
        h: 3.5,
        topColor: const Color(0xFFDC2626),
        leftColor: const Color(0xFFB91C1C),
        rightColor: const Color(0xFF991B1B),
      );

      // Gür arpa başakları
      for (int r = -1; r <= 1; r++) {
        for (int c = -1; c <= 1; c++) {
          final double windSway = math.sin(animTime * 2.6 + r * 1.0 + c * 0.8) * 1.6;
          final double offX = (c * 7.5 * cosIso) - (r * 7.5 * cosIso) + windSway;
          final double offY = (c * 7.5 * sinIso) + (r * 7.5 * sinIso);
          drawIsoCube(
            canvas,
            Offset(fieldTop.dx + offX, fieldTop.dy + offY),
            w: 3.5,
            d: 3.5,
            h: 9.5 + ((r * 2 + c + 4) % 3) * 1.5,
            topColor: const Color(0xFFFDE047),
            leftColor: const Color(0xFFEAB308),
            rightColor: const Color(0xFFB45309),
          );
        }
      }
    } else if (v == 2) {
      // Varyant 2: Keten Tahıl Çuvalları & Eğimli Arpa Demetleri
      // 2 Keten Çuval
      final Offset sackPos = Offset(fieldTop.dx + 11.0 * cosIso, fieldTop.dy - 10.0 * sinIso);
      drawIsoCube(
        canvas,
        sackPos,
        w: 6.0,
        d: 6.0,
        h: 6.0,
        topColor: const Color(0xFFD97706),
        leftColor: const Color(0xFFB45309),
        rightColor: const Color(0xFF92400E),
      );
      drawIsoCube(
        canvas,
        Offset(sackPos.dx - 4.0 * cosIso, sackPos.dy + 4.0 * sinIso),
        w: 5.0,
        d: 5.0,
        h: 5.0,
        topColor: const Color(0xFFF59E0B),
        leftColor: const Color(0xFFD97706),
        rightColor: const Color(0xFFB45309),
      );

      // Eğimli arpa demetleri
      for (int i = 0; i < 7; i++) {
        final double a = i * (math.pi / 3.5);
        final double windSway = math.sin(animTime * 2.5 + i) * 1.5;
        final double px = fieldTop.dx + math.cos(a) * 10.0 * cosIso + windSway;
        final double py = fieldTop.dy + math.sin(a) * 10.0 * sinIso;
        drawIsoCube(
          canvas,
          Offset(px, py),
          w: 4.0,
          d: 4.0,
          h: 9.0 + (i % 3) * 1.5,
          topColor: const Color(0xFFFDE047),
          leftColor: const Color(0xFFEAB308),
          rightColor: const Color(0xFFB45309),
        );
      }
    } else {
      // Varyant 0: 4 Köşede Dikili Yontma Taş Sınır İşaretleri & Kehribar Başaklar
      for (final signX in [-1.0, 1.0]) {
        for (final signY in [-1.0, 1.0]) {
          final double sx = baseCenter.dx + (signX * 14.0 * cosIso) - (signY * 14.0 * cosIso);
          final double sy = baseCenter.dy + (signX * 14.0 * sinIso) + (signY * 14.0 * sinIso) - 4.0;
          drawIsoCube(
            canvas,
            Offset(sx, sy),
            w: 4.0,
            d: 4.0,
            h: 6.0,
            topColor: const Color(0xFF94A3B8),
            leftColor: const Color(0xFF64748B),
            rightColor: const Color(0xFF475569),
          );
        }
      }

      const int rows = 3;
      const int cols = 3;
      for (int r = 0; r < rows; r++) {
        for (int c = 0; c < cols; c++) {
          final double windSway = math.sin(animTime * 2.5 + (r * 0.9) + (c * 0.7)) * 1.8;
          final double offX = (c - 1) * 7.5 * cosIso - (r - 1) * 7.5 * cosIso + windSway;
          final double offY = (c - 1) * 7.5 * sinIso + (r - 1) * 7.5 * sinIso;
          final Offset cropPos = Offset(fieldTop.dx + offX, fieldTop.dy + offY);

          drawIsoCube(
            canvas,
            cropPos,
            w: 3.5,
            d: 3.5,
            h: 9.0 + ((r * 2 + c) % 3) * 1.5,
            topColor: const Color(0xFFFDE047),
            leftColor: const Color(0xFFEAB308),
            rightColor: const Color(0xFFB45309),
          );
        }
      }
    }
  }

  /// 3D Voxel Bozkır Otlağı / At Harası (Çoklu Görsel Varyantlar)
  static void drawVoxelPasture(Canvas canvas, Offset baseCenter, {double animTime = 0.0, int variant = 0}) {
    // Çim zemin
    drawIsoCube(
      canvas,
      baseCenter,
      w: 40.0,
      d: 40.0,
      h: 3.0,
      topColor: const Color(0xFF15803D),
      leftColor: const Color(0xFF166534),
      rightColor: const Color(0xFF14532D),
      drawShadow: true,
    );

    final Offset topCenter = Offset(baseCenter.dx, baseCenter.dy - 3.0);
    final int v = variant % 3;

    if (v == 1) {
      // Varyant 1: Alçak Taş Örgü Ağıl & İkili Otlayan Koyun Sürüsü
      // Taş örgü ağıl duvarları
      for (double side in [-1.0, 1.0]) {
        drawIsoCube(
          canvas,
          Offset(topCenter.dx + side * 14.0 * cosIso, topCenter.dy - 6.0 * sinIso),
          w: 22.0,
          d: 3.0,
          h: 4.5,
          topColor: const Color(0xFF94A3B8),
          leftColor: const Color(0xFF64748B),
          rightColor: const Color(0xFF475569),
        );
      }

      // Kuru ot yığını
      drawIsoCube(
        canvas,
        Offset(topCenter.dx - 10.0 * cosIso, topCenter.dy - 10.0 * sinIso),
        w: 8.0,
        d: 8.0,
        h: 5.0,
        topColor: const Color(0xFFFEF08A),
        leftColor: const Color(0xFFFACC15),
        rightColor: const Color(0xFFCA8A04),
      );

      // 2 Otlayan Koyun
      final double sheepBob = math.sin(animTime * 2.5) * 0.8;
      // Koyun 1
      drawIsoCube(
        canvas,
        Offset(topCenter.dx + 2.0 * cosIso, topCenter.dy + 4.0 * sinIso + sheepBob),
        w: 6.0,
        d: 5.0,
        h: 4.5,
        topColor: const Color(0xFFF8FAFC),
        leftColor: const Color(0xFFE2E8F0),
        rightColor: const Color(0xFFCBD5E1),
      );
      // Koyun 2
      drawIsoCube(
        canvas,
        Offset(topCenter.dx + 10.0 * cosIso, topCenter.dy + 8.0 * sinIso - sheepBob),
        w: 5.0,
        d: 4.0,
        h: 4.0,
        topColor: const Color(0xFFF1F5F9),
        leftColor: const Color(0xFFCBD5E1),
        rightColor: const Color(0xFF94A3B8),
      );
    } else if (v == 2) {
      // Varyant 2: Kubbeli Keçe Çoban Barınağı Otağı & Dinlenen At
      // Küçük Keçe Çadır
      final Offset tentPos = Offset(topCenter.dx - 8.0 * cosIso, topCenter.dy - 8.0 * sinIso);
      drawIsoCube(
        canvas,
        tentPos,
        w: 12.0,
        d: 12.0,
        h: 7.0,
        topColor: const Color(0xFFF1F5F9),
        leftColor: const Color(0xFFE2E8F0),
        rightColor: const Color(0xFFCBD5E1),
      );
      drawIsoCube(
        canvas,
        Offset(tentPos.dx, tentPos.dy - 7.0),
        w: 7.0,
        d: 7.0,
        h: 4.0,
        topColor: const Color(0xFFE2E8F0),
        leftColor: const Color(0xFFCBD5E1),
        rightColor: const Color(0xFF94A3B8),
      );

      // Yalama Tuz Taşı Bloğu
      drawIsoCube(
        canvas,
        Offset(topCenter.dx + 8.0 * cosIso, topCenter.dy - 8.0 * sinIso),
        w: 4.5,
        d: 4.5,
        h: 4.0,
        topColor: const Color(0xFFE0F2FE),
        leftColor: const Color(0xFFBAE6FD),
        rightColor: const Color(0xFF7DD3FC),
      );

      // Dinlenen Bozkır Atı
      final Offset horsePos = Offset(topCenter.dx + 6.0 * cosIso, topCenter.dy + 6.0 * sinIso);
      drawIsoCube(
        canvas,
        horsePos,
        w: 9.0,
        d: 5.0,
        h: 4.5,
        topColor: const Color(0xFF92400E),
        leftColor: const Color(0xFF78350F),
        rightColor: const Color(0xFF451A03),
      );
    } else {
      // Varyant 0: Ahşap Çitler, Su Yalağı & Otlayan Bozkır Atı
      for (int i = 0; i < 4; i++) {
        final double angle = i * (math.pi / 2.0) + (math.pi / 4.0);
        final double px = topCenter.dx + math.cos(angle) * 16.0 * cosIso;
        final double py = topCenter.dy + math.sin(angle) * 16.0 * sinIso;
        drawIsoCube(
          canvas,
          Offset(px, py),
          w: 3.0,
          d: 3.0,
          h: 7.0,
          topColor: const Color(0xFFB45309),
          leftColor: const Color(0xFF92400E),
          rightColor: const Color(0xFF78350F),
        );
      }

      // Su yalağı
      final Offset troughPos = Offset(topCenter.dx - 10.0 * cosIso, topCenter.dy - 10.0 * sinIso);
      drawIsoCube(
        canvas,
        troughPos,
        w: 8.0,
        d: 5.0,
        h: 4.0,
        topColor: const Color(0xFF38BDF8),
        leftColor: const Color(0xFF78350F),
        rightColor: const Color(0xFF451A03),
      );

      // Otlayan bozkır atı
      final double grazeBob = math.sin(animTime * 2.0) * 1.0;
      final Offset animalPos = Offset(topCenter.dx + 4.0 * cosIso, topCenter.dy + 4.0 * sinIso);

      drawIsoCube(
        canvas,
        animalPos,
        w: 8.0,
        d: 5.0,
        h: 6.0,
        topColor: const Color(0xFFF1F5F9),
        leftColor: const Color(0xFFCBD5E1),
        rightColor: const Color(0xFF94A3B8),
      );
      drawIsoCube(
        canvas,
        Offset(animalPos.dx + 4.0 * cosIso, animalPos.dy + 4.0 * sinIso + grazeBob),
        w: 4.0,
        d: 4.0,
        h: 4.0,
        topColor: const Color(0xFFE2E8F0),
        leftColor: const Color(0xFFCBD5E1),
        rightColor: const Color(0xFF64748B),
      );
    }
  }

  /// 3D Voxel Yemişlik / Meyve Bahçesi (Çoklu Görsel Varyantlar)
  static void drawVoxelOrchard(Canvas canvas, Offset baseCenter, {double animTime = 0.0, int variant = 0}) {
    drawIsoCube(
      canvas,
      baseCenter,
      w: 38.0,
      d: 38.0,
      h: 3.5,
      topColor: const Color(0xFF166534),
      leftColor: const Color(0xFF14532D),
      rightColor: const Color(0xFF0F3D20),
      drawShadow: true,
    );

    final Offset fieldTop = Offset(baseCenter.dx, baseCenter.dy - 3.5);
    final int v = variant % 3;

    if (v == 1) {
      // Varyant 1: Ahşap Çardak / Asma Düzeni & Turuncu Kayısılar + Hasat Sepeti
      // Ahşap Çardak Sırıkları
      for (double side in [-1.0, 1.0]) {
        drawIsoCube(
          canvas,
          Offset(fieldTop.dx + side * 10.0 * cosIso, fieldTop.dy - 4.0),
          w: 20.0,
          d: 2.5,
          h: 9.0,
          topColor: const Color(0xFF78350F),
          leftColor: const Color(0xFF5A2508),
          rightColor: const Color(0xFF451A03),
        );
      }

      // 2 Yayvan Ağaç
      final List<Offset> treeOffsets = [
        Offset(-8.0 * cosIso, -4.0 * sinIso),
        Offset(8.0 * cosIso, 4.0 * sinIso),
      ];
      for (int i = 0; i < treeOffsets.length; i++) {
        final double sway = math.sin(animTime * 2.2 + i * 2.0) * 1.2;
        final Offset crownPos = Offset(fieldTop.dx + treeOffsets[i].dx + sway, fieldTop.dy + treeOffsets[i].dy - 9.0);
        drawIsoCube(
          canvas,
          crownPos,
          w: 14.0,
          d: 14.0,
          h: 8.0,
          topColor: const Color(0xFF22C55E),
          leftColor: const Color(0xFF16A34A),
          rightColor: const Color(0xFF15803D),
        );
        // Turuncu Meyveler
        drawIsoCube(
          canvas,
          Offset(crownPos.dx + 2.0, crownPos.dy - 2.0),
          w: 3.0,
          d: 3.0,
          h: 3.0,
          topColor: const Color(0xFFF97316),
          leftColor: const Color(0xFFEA580C),
          rightColor: const Color(0xFFC2410C),
        );
      }

      // Hasat Sepeti
      drawIsoCube(
        canvas,
        Offset(fieldTop.dx + 10.0 * cosIso, fieldTop.dy + 8.0 * sinIso),
        w: 5.0,
        d: 5.0,
        h: 4.5,
        topColor: const Color(0xFFD97706),
        leftColor: const Color(0xFFB45309),
        rightColor: const Color(0xFF92400E),
      );
    } else if (v == 2) {
      // Varyant 2: Heybetli Ulu Meyve Ağacı & Ahşap Meyve Kasaları
      final double sway = math.sin(animTime * 1.8) * 1.5;
      final Offset trunkPos = Offset(fieldTop.dx - 2.0 * cosIso, fieldTop.dy - 2.0 * sinIso);

      // Kalın Ağaç Gövdesi
      drawIsoCube(
        canvas,
        trunkPos,
        w: 6.0,
        d: 6.0,
        h: 9.0,
        topColor: const Color(0xFF78350F),
        leftColor: const Color(0xFF5A2508),
        rightColor: const Color(0xFF451A03),
      );

      // Geniş Heybetli Taç
      final Offset bigCrown = Offset(trunkPos.dx + sway, trunkPos.dy - 9.0);
      drawIsoCube(
        canvas,
        bigCrown,
        w: 18.0,
        d: 18.0,
        h: 12.0,
        topColor: const Color(0xFF16A34A),
        leftColor: const Color(0xFF15803D),
        rightColor: const Color(0xFF14532D),
      );

      // Meyveler
      for (int f = 0; f < 3; f++) {
        final double fx = (f - 1) * 5.0;
        final Color fCol = f % 2 == 0 ? const Color(0xFFEF4444) : const Color(0xFFF59E0B);
        drawIsoCube(
          canvas,
          Offset(bigCrown.dx + fx, bigCrown.dy - 2.0 - (f % 2) * 3.0),
          w: 3.0,
          d: 3.0,
          h: 3.0,
          topColor: fCol,
          leftColor: fCol,
          rightColor: fCol,
        );
      }

      // 2 Ahşap Meyve Kasası
      final Offset cratePos = Offset(fieldTop.dx + 10.0 * cosIso, fieldTop.dy + 8.0 * sinIso);
      drawIsoCube(
        canvas,
        cratePos,
        w: 7.0,
        d: 6.0,
        h: 4.5,
        topColor: const Color(0xFFB45309),
        leftColor: const Color(0xFF92400E),
        rightColor: const Color(0xFF78350F),
      );
      drawIsoCube(
        canvas,
        Offset(cratePos.dx, cratePos.dy - 4.5),
        w: 5.5,
        d: 5.0,
        h: 4.0,
        topColor: const Color(0xFFD97706),
        leftColor: const Color(0xFFB45309),
        rightColor: const Color(0xFF92400E),
      );
    } else {
      // Varyant 0: 3 Bodur Dağ Meyve Ağacı
      final List<Offset> treeOffsets = [
        Offset(-10.0 * cosIso + 6.0 * cosIso, -10.0 * sinIso - 6.0 * sinIso),
        Offset(8.0 * cosIso - 8.0 * cosIso, 8.0 * sinIso + 8.0 * sinIso),
        Offset(10.0 * cosIso + 6.0 * cosIso, 10.0 * sinIso - 6.0 * sinIso),
      ];

      for (int i = 0; i < treeOffsets.length; i++) {
        final double sway = math.sin(animTime * 2.0 + i * 1.5) * 1.2;
        final Offset trunkPos = Offset(fieldTop.dx + treeOffsets[i].dx, fieldTop.dy + treeOffsets[i].dy);

        drawIsoCube(
          canvas,
          trunkPos,
          w: 3.5,
          d: 3.5,
          h: 6.0,
          topColor: const Color(0xFF78350F),
          leftColor: const Color(0xFF5A2508),
          rightColor: const Color(0xFF451A03),
        );

        final Offset crownPos = Offset(trunkPos.dx + sway, trunkPos.dy - 6.0);
        drawIsoCube(
          canvas,
          crownPos,
          w: 12.0,
          d: 12.0,
          h: 9.0,
          topColor: const Color(0xFF22C55E),
          leftColor: const Color(0xFF16A34A),
          rightColor: const Color(0xFF15803D),
        );

        final Color fruitColor = (i % 2 == 0) ? const Color(0xFFEF4444) : const Color(0xFFF97316);
        drawIsoCube(
          canvas,
          Offset(crownPos.dx + 2.0, crownPos.dy - 3.0),
          w: 3.0,
          d: 3.0,
          h: 3.0,
          topColor: fruitColor,
          leftColor: fruitColor,
          rightColor: fruitColor,
        );
        drawIsoCube(
          canvas,
          Offset(crownPos.dx - 3.0, crownPos.dy + 1.0),
          w: 2.5,
          d: 2.5,
          h: 2.5,
          topColor: fruitColor,
          leftColor: fruitColor,
          rightColor: fruitColor,
        );
      }
    }
  }

  /// 3D Voxel Taş Yonma Ocağı (Seviye Kademeli & Çoklu Görsel Varyantlar)
  static void drawVoxelQuarry(
    Canvas canvas,
    Offset baseCenter, {
    int variant = 0,
    int level = 1,
    bool isWinter = false,
  }) {
    // Taş Ocağı Basamağı 1 (Her 2X sıçramadan sonra: Seviye 10 ve 25)
    final Color baseTop = level >= 25
        ? const Color(0xFF334155)
        : (level >= 10 ? const Color(0xFF475569) : const Color(0xFF64748B));
    final Color baseLeft = level >= 25
        ? const Color(0xFF1E293B)
        : (level >= 10 ? const Color(0xFF334155) : const Color(0xFF475569));
    final Color baseRight = level >= 25
        ? const Color(0xFF0F172A)
        : (level >= 10 ? const Color(0xFF1E293B) : const Color(0xFF334155));

    drawIsoCube(
      canvas,
      baseCenter,
      w: level >= 25 ? 44.0 : 40.0,
      d: level >= 25 ? 44.0 : 40.0,
      h: level >= 25 ? 8.0 : 6.0,
      topColor: baseTop,
      leftColor: baseLeft,
      rightColor: baseRight,
      drawShadow: true,
    );

    if (isWinter) {
      drawIsoCube(
        canvas,
        Offset(baseCenter.dx, baseCenter.dy - (level >= 25 ? 8.0 : 6.0)),
        w: 38.0,
        d: 38.0,
        h: 2.0,
        topColor: Colors.white,
        leftColor: const Color(0xFFE2E8F0),
        rightColor: const Color(0xFFCBD5E1),
      );
    }

    final int v = variant % 3;

    if (level >= 8) {
      // Seviye 8+: İmparatorluk Mermer & Altın Damarlı Taş Fabrikası
      final Offset terracePos = Offset(baseCenter.dx - 6.0 * cosIso, baseCenter.dy - 8.0 - 6.0 * sinIso);
      drawIsoCube(
        canvas,
        terracePos,
        w: 24.0,
        d: 24.0,
        h: 14.0,
        topColor: const Color(0xFFF8FAFC),
        leftColor: const Color(0xFFE2E8F0),
        rightColor: const Color(0xFFCBD5E1),
      );
      // Altın Maden Damarı Çizgisi
      drawIsoCube(
        canvas,
        Offset(terracePos.dx + 4 * cosIso, terracePos.dy - 14.0 + 4 * sinIso),
        w: 12.0,
        d: 4.0,
        h: 2.5,
        topColor: const Color(0xFFFBBF24),
        leftColor: const Color(0xFFF59E0B),
        rightColor: const Color(0xFFD97706),
      );
      // Kesilmiş Beyaz Mermer Blok İstifleri
      final Offset stackPos = Offset(baseCenter.dx + 12.0 * cosIso, baseCenter.dy - 6.0 + 8.0 * sinIso);
      drawIsoCube(
        canvas,
        stackPos,
        w: 10.0,
        d: 10.0,
        h: 10.0,
        topColor: const Color(0xFFFFFFFF),
        leftColor: const Color(0xFFF1F5F9),
        rightColor: const Color(0xFFE2E8F0),
      );
    } else if (v == 1) {
      // Varyant 1: Ahşap Çıkrık Vinç / İskele & Dev Bazalt Kaya Kütlesi
      // Dev Bazalt Kaya Kütlesi
      final Offset rockPos = Offset(baseCenter.dx - 6.0 * cosIso, baseCenter.dy - 6.0 - 6.0 * sinIso);
      drawIsoCube(
        canvas,
        rockPos,
        w: 18.0,
        d: 18.0,
        h: 12.0,
        topColor: const Color(0xFF334155),
        leftColor: const Color(0xFF1E293B),
        rightColor: const Color(0xFF0F172A),
      );

      // Ahşap Vinç Direği & Bom Kolu
      final Offset cranePos = Offset(baseCenter.dx + 10.0 * cosIso, baseCenter.dy - 6.0 + 8.0 * sinIso);
      drawIsoCube(
        canvas,
        cranePos,
        w: 3.0,
        d: 3.0,
        h: 16.0,
        topColor: const Color(0xFFB45309),
        leftColor: const Color(0xFF92400E),
        rightColor: const Color(0xFF78350F),
      );
      drawIsoCube(
        canvas,
        Offset(cranePos.dx - 6.0 * cosIso, cranePos.dy - 16.0 - 6.0 * sinIso),
        w: 14.0,
        d: 2.5,
        h: 2.5,
        topColor: const Color(0xFFD97706),
        leftColor: const Color(0xFFB45309),
        rightColor: const Color(0xFF92400E),
      );

      // Kırılmış Taş Yongaları
      drawIsoCube(
        canvas,
        Offset(baseCenter.dx + 4.0 * cosIso, baseCenter.dy - 6.0),
        w: 5.0,
        d: 5.0,
        h: 3.0,
        topColor: const Color(0xFF94A3B8),
        leftColor: const Color(0xFF64748B),
        rightColor: const Color(0xFF475569),
      );
    } else if (v == 2) {
      // Varyant 2: Kemerli Maden Tüneli Girişi & Taş Arabası
      // Tünel Kemer Bloğu
      final Offset tunnelPos = Offset(baseCenter.dx - 4.0 * cosIso, baseCenter.dy - 6.0 - 4.0 * sinIso);
      drawIsoCube(
        canvas,
        tunnelPos,
        w: 20.0,
        d: 14.0,
        h: 10.0,
        topColor: const Color(0xFF64748B),
        leftColor: const Color(0xFF475569),
        rightColor: const Color(0xFF334155),
      );
      // Tünel Boşluğu (Kara Delik)
      drawIsoCube(
        canvas,
        Offset(tunnelPos.dx + 2.0 * cosIso, tunnelPos.dy + 2.0 * sinIso),
        w: 10.0,
        d: 8.0,
        h: 7.0,
        topColor: const Color(0xFF0F172A),
        leftColor: const Color(0xFF020617),
        rightColor: const Color(0xFF000000),
      );

      // Taş Yüklü El Arabası / Vagon
      final Offset cartPos = Offset(baseCenter.dx + 10.0 * cosIso, baseCenter.dy - 6.0 + 8.0 * sinIso);
      drawIsoCube(
        canvas,
        cartPos,
        w: 8.0,
        d: 6.0,
        h: 5.0,
        topColor: const Color(0xFFCBD5E1),
        leftColor: const Color(0xFF78350F),
        rightColor: const Color(0xFF5A2508),
      );
    } else {
      // Varyant 0: Kademeli Teras & İstiflenmiş Kesme Taş Blokları
      final Offset step2 = Offset(baseCenter.dx - 4.0 * cosIso, baseCenter.dy - 6.0 - 4.0 * sinIso);
      drawIsoCube(
        canvas,
        step2,
        w: 24.0,
        d: 24.0,
        h: 8.0,
        topColor: const Color(0xFF64748B),
        leftColor: const Color(0xFF475569),
        rightColor: const Color(0xFF334155),
      );

      final Offset stackPos = Offset(baseCenter.dx + 10.0 * cosIso, baseCenter.dy - 6.0 + 10.0 * sinIso);
      drawIsoCube(
        canvas,
        stackPos,
        w: 8.0,
        d: 8.0,
        h: 8.0,
        topColor: const Color(0xFFCBD5E1),
        leftColor: const Color(0xFF94A3B8),
        rightColor: const Color(0xFF64748B),
      );
      drawIsoCube(
        canvas,
        Offset(stackPos.dx, stackPos.dy - 8.0),
        w: 6.0,
        d: 6.0,
        h: 5.0,
        topColor: const Color(0xFFE2E8F0),
        leftColor: const Color(0xFFCBD5E1),
        rightColor: const Color(0xFF94A3B8),
      );
    }
  }

  /// 3D Voxel Katran & Huş Otağı (Çoklu Görsel Varyantlar)
  static void drawVoxelResinCamp(Canvas canvas, Offset baseCenter, {double animTime = 0.0, int variant = 0}) {
    drawIsoCube(
      canvas,
      baseCenter,
      w: 38.0,
      d: 38.0,
      h: 3.0,
      topColor: const Color(0xFF14532D),
      leftColor: const Color(0xFF0F3D20),
      rightColor: const Color(0xFF0A2915),
      drawShadow: true,
    );

    final Offset topCenter = Offset(baseCenter.dx, baseCenter.dy - 3.0);
    final int v = variant % 3;

    if (v == 1) {
      // Varyant 1: 2 Beyaz Huş Ağacı & Taş Damıtma Fırını + Reçine Fıçıları
      // 2 Huş Ağacı (Beyaz Gövde, Yeşil Taç)
      final List<Offset> birchTrees = [
        Offset(topCenter.dx - 10.0 * cosIso, topCenter.dy - 6.0 * sinIso),
        Offset(topCenter.dx - 4.0 * cosIso, topCenter.dy - 12.0 * sinIso),
      ];
      for (final bp in birchTrees) {
        drawIsoCube(
          canvas,
          bp,
          w: 3.0,
          d: 3.0,
          h: 12.0,
          topColor: const Color(0xFFF8FAFC),
          leftColor: const Color(0xFFE2E8F0),
          rightColor: const Color(0xFF94A3B8),
        );
        drawIsoCube(
          canvas,
          Offset(bp.dx, bp.dy - 12.0),
          w: 10.0,
          d: 10.0,
          h: 8.0,
          topColor: const Color(0xFF4ADE80),
          leftColor: const Color(0xFF22C55E),
          rightColor: const Color(0xFF16A34A),
        );
      }

      // Taş Damıtma Fırını
      final Offset kilnPos = Offset(topCenter.dx + 8.0 * cosIso, topCenter.dy + 6.0 * sinIso);
      drawIsoCube(
        canvas,
        kilnPos,
        w: 10.0,
        d: 10.0,
        h: 7.0,
        topColor: const Color(0xFF64748B),
        leftColor: const Color(0xFF475569),
        rightColor: const Color(0xFF334155),
      );
      // Reçine Fıçısı
      drawIsoCube(
        canvas,
        Offset(topCenter.dx + 11.0 * cosIso, topCenter.dy - 6.0 * sinIso),
        w: 5.0,
        d: 5.0,
        h: 6.0,
        topColor: const Color(0xFF78350F),
        leftColor: const Color(0xFF5A2508),
        rightColor: const Color(0xFF451A03),
      );
    } else if (v == 2) {
      // Varyant 2: 4 Direkli Ahşap Hızar Sundurması & Kereste İstifi
      // Ahşap Sundurma Direkleri & Çatı
      final Offset shedPos = Offset(topCenter.dx - 4.0 * cosIso, topCenter.dy - 4.0 * sinIso);
      for (double dx in [-6.0, 6.0]) {
        for (double dy in [-6.0, 6.0]) {
          drawIsoCube(
            canvas,
            Offset(shedPos.dx + dx * cosIso, shedPos.dy + dy * sinIso),
            w: 2.0,
            d: 2.0,
            h: 9.0,
            topColor: const Color(0xFF92400E),
            leftColor: const Color(0xFF78350F),
            rightColor: const Color(0xFF5A2508),
          );
        }
      }
      // Sundurma Çatısı
      drawIsoCube(
        canvas,
        Offset(shedPos.dx, shedPos.dy - 9.0),
        w: 16.0,
        d: 16.0,
        h: 2.5,
        topColor: const Color(0xFFB45309),
        leftColor: const Color(0xFF92400E),
        rightColor: const Color(0xFF78350F),
      );

      // Huş Kereste Tomruk İstifi
      final Offset logPos = Offset(topCenter.dx + 10.0 * cosIso, topCenter.dy + 8.0 * sinIso);
      drawIsoCube(
        canvas,
        logPos,
        w: 10.0,
        d: 5.0,
        h: 4.5,
        topColor: const Color(0xFFF8FAFC),
        leftColor: const Color(0xFFCBD5E1),
        rightColor: const Color(0xFF94A3B8),
      );
    } else {
      // Varyant 0: Beyaz Huş Kabuklu Yurt, Tüten Katran Kazanı & İstiflenmiş Huş Kütükleri
      final Offset yurtPos = Offset(topCenter.dx - 6.0 * cosIso, topCenter.dy - 6.0 * sinIso);
      drawIsoCube(
        canvas,
        yurtPos,
        w: 18.0,
        d: 18.0,
        h: 8.0,
        topColor: const Color(0xFFF1F5F9),
        leftColor: const Color(0xFFE2E8F0),
        rightColor: const Color(0xFFCBD5E1),
      );
      drawIsoCube(
        canvas,
        Offset(yurtPos.dx, yurtPos.dy - 8.0),
        w: 12.0,
        d: 12.0,
        h: 5.0,
        topColor: const Color(0xFFE2E8F0),
        leftColor: const Color(0xFFCBD5E1),
        rightColor: const Color(0xFF94A3B8),
      );

      final Offset cauldronPos = Offset(topCenter.dx + 8.0 * cosIso, topCenter.dy + 8.0 * sinIso);
      final double emberGlow = 0.7 + 0.3 * math.sin(animTime * 5.0);
      drawIsoCube(
        canvas,
        cauldronPos,
        w: 6.0,
        d: 6.0,
        h: 5.0,
        topColor: const Color(0xFF0F172A),
        leftColor: const Color(0xFF020617),
        rightColor: const Color(0xFF000000),
      );
      drawIsoCube(
        canvas,
        Offset(cauldronPos.dx, cauldronPos.dy + 2.0),
        w: 7.0,
        d: 7.0,
        h: 1.5,
        topColor: Color.fromRGBO(249, 115, 22, emberGlow),
        leftColor: const Color(0xFFEA580C),
        rightColor: const Color(0xFFC2410C),
      );

      final Offset logPos = Offset(topCenter.dx + 10.0 * cosIso, topCenter.dy - 8.0 * sinIso);
      drawIsoCube(
        canvas,
        logPos,
        w: 8.0,
        d: 5.0,
        h: 4.0,
        topColor: const Color(0xFFF8FAFC),
        leftColor: const Color(0xFF78350F),
        rightColor: const Color(0xFF5A2508),
      );
    }
  }

  /// 3D Voxel Hex Çevre Suru / Savunma Duvarı (Akıllı Kesişim ve Sınır Koruması)
  /// Altıgenin 6 kenarına duvar çeker; iki surlu hex komşu olduğunda aralarındaki kesişim kenarına duvar koymaz!
  static void drawVoxelPerimeterWall(
    Canvas canvas,
    List<Offset> corners, {
    required WallTier tier,
    required List<bool> activeEdges,
    bool isNight = false,
    double animTime = 0.0,
  }) {
    if (corners.length < 6) return;

    for (int i = 0; i < 6; i++) {
      if (i >= activeEdges.length || !activeEdges[i]) continue;

      final Offset cA = corners[i];
      final Offset cB = corners[(i + 1) % 6];

      // Kenar boyunca 3 voksel duvar bloğu yerleştir
      for (int step = 0; step < 3; step++) {
        final double t = (step + 0.5) / 3.0;
        final Offset blockPos = Offset(
          cA.dx + (cB.dx - cA.dx) * t,
          cA.dy + (cB.dy - cA.dy) * t,
        );

        switch (tier) {
          case WallTier.woodenPalisade:
            _drawVoxelPalisadeSegment(canvas, blockPos, isNight: isNight);
            break;
          case WallTier.stoneRampart:
            _drawVoxelStoneWallSegment(canvas, blockPos, isNight: isNight, isCrenel: step == 1);
            break;
          case WallTier.ironFortification:
            _drawVoxelIronWallSegment(canvas, blockPos, isNight: isNight, animTime: animTime, isSpike: step != 1);
            break;
        }
      }
    }

    // Aktif kenarların köşe burçları / kulecikleri
    for (int i = 0; i < 6; i++) {
      final int prevEdge = (i + 5) % 6;
      final bool hasCorner = (i < activeEdges.length && activeEdges[i]) ||
          (prevEdge < activeEdges.length && activeEdges[prevEdge]);
      if (hasCorner) {
        final Offset cornerPos = corners[i];
        switch (tier) {
          case WallTier.woodenPalisade:
            _drawVoxelPalisadeBastion(canvas, cornerPos, isNight: isNight);
            break;
          case WallTier.stoneRampart:
            _drawVoxelStoneBastion(canvas, cornerPos, isNight: isNight);
            break;
          case WallTier.ironFortification:
            _drawVoxelIronBastion(canvas, cornerPos, isNight: isNight, animTime: animTime);
            break;
        }
      }
    }
  }

  // --- SEVİYE 1: AHŞAP ÇİT / PALİSADE ---
  static void _drawVoxelPalisadeSegment(Canvas canvas, Offset pos, {bool isNight = false}) {
    drawIsoCube(
      canvas,
      pos,
      w: 8.0,
      d: 8.0,
      h: 9.0,
      topColor: const Color(0xFFB45309),
      leftColor: const Color(0xFF92400E),
      rightColor: const Color(0xFF78350F),
    );
    drawIsoCube(
      canvas,
      Offset(pos.dx, pos.dy - 9.0),
      w: 4.0,
      d: 4.0,
      h: 3.5,
      topColor: const Color(0xFFD97706),
      leftColor: const Color(0xFFB45309),
      rightColor: const Color(0xFF92400E),
    );
  }

  static void _drawVoxelPalisadeBastion(Canvas canvas, Offset pos, {bool isNight = false}) {
    drawIsoCube(
      canvas,
      pos,
      w: 10.0,
      d: 10.0,
      h: 12.0,
      topColor: const Color(0xFFD97706),
      leftColor: const Color(0xFFB45309),
      rightColor: const Color(0xFF78350F),
      drawShadow: true,
    );
  }

  // --- SEVİYE 2: TAŞ SUR / STONE RAMPART ---
  static void _drawVoxelStoneWallSegment(Canvas canvas, Offset pos, {bool isNight = false, bool isCrenel = false}) {
    final double h = isCrenel ? 14.0 : 11.0;
    drawIsoCube(
      canvas,
      pos,
      w: 10.0,
      d: 10.0,
      h: h,
      topColor: const Color(0xFF94A3B8),
      leftColor: const Color(0xFF64748B),
      rightColor: const Color(0xFF475569),
    );
    drawIsoCube(
      canvas,
      Offset(pos.dx, pos.dy - 5.0),
      w: 11.0,
      d: 11.0,
      h: 1.5,
      topColor: const Color(0xFFCBD5E1),
      leftColor: const Color(0xFF94A3B8),
      rightColor: const Color(0xFF64748B),
    );
  }

  static void _drawVoxelStoneBastion(Canvas canvas, Offset pos, {bool isNight = false}) {
    drawIsoCube(
      canvas,
      pos,
      w: 13.0,
      d: 13.0,
      h: 16.0,
      topColor: const Color(0xFFCBD5E1),
      leftColor: const Color(0xFF94A3B8),
      rightColor: const Color(0xFF64748B),
      drawShadow: true,
    );
    drawIsoCube(
      canvas,
      Offset(pos.dx, pos.dy - 16.0),
      w: 8.0,
      d: 8.0,
      h: 3.5,
      topColor: const Color(0xFFE2E8F0),
      leftColor: const Color(0xFFCBD5E1),
      rightColor: const Color(0xFF94A3B8),
    );
  }

  // --- SEVİYE 3: DEMİR TAHKİMAT / IRON FORTIFICATION ---
  static void _drawVoxelIronWallSegment(
    Canvas canvas,
    Offset pos, {
    bool isNight = false,
    double animTime = 0.0,
    bool isSpike = false,
  }) {
    drawIsoCube(
      canvas,
      pos,
      w: 11.0,
      d: 11.0,
      h: 14.0,
      topColor: const Color(0xFF334155),
      leftColor: const Color(0xFF1E293B),
      rightColor: const Color(0xFF0F172A),
    );
    drawIsoCube(
      canvas,
      Offset(pos.dx, pos.dy - 6.0),
      w: 12.0,
      d: 12.0,
      h: 2.0,
      topColor: const Color(0xFF64748B),
      leftColor: const Color(0xFF475569),
      rightColor: const Color(0xFF334155),
    );
    if (isSpike) {
      drawIsoCube(
        canvas,
        Offset(pos.dx, pos.dy - 14.0),
        w: 3.0,
        d: 3.0,
        h: 5.0,
        topColor: const Color(0xFFDC2626),
        leftColor: const Color(0xFF991B1B),
        rightColor: const Color(0xFF7F1D1D),
      );
    }
  }

  static void _drawVoxelIronBastion(Canvas canvas, Offset pos, {bool isNight = false, double animTime = 0.0}) {
    drawIsoCube(
      canvas,
      pos,
      w: 14.0,
      d: 14.0,
      h: 18.0,
      topColor: const Color(0xFF475569),
      leftColor: const Color(0xFF334155),
      rightColor: const Color(0xFF1E293B),
      drawShadow: true,
    );
    drawIsoCube(
      canvas,
      Offset(pos.dx, pos.dy - 18.0),
      w: 10.0,
      d: 10.0,
      h: 4.0,
      topColor: const Color(0xFFEF4444),
      leftColor: const Color(0xFFDC2626),
      rightColor: const Color(0xFFB91C1C),
    );

    if (isNight) {
      final double flicker = 0.75 + 0.25 * math.sin(animTime * 10.0);
      drawIsoCube(
        canvas,
        Offset(pos.dx, pos.dy - 23.0),
        w: 4.0,
        d: 4.0,
        h: 4.0,
        topColor: Color.fromRGBO(245, 158, 11, flicker),
        leftColor: const Color(0xFFD97706),
        rightColor: const Color(0xFFB45309),
      );
    }
  }

  /// 3D Voxel Bozkır Savunma ve Gözcü Kulesi (Archer Defense Watchtower)
  /// R=3 menzilli, seviyeye göre taş/ahşap takviyeli, tepe okçu mazgallı ve gece meşaleli savunma yapısı.
  static void drawVoxelWatchtower(
    Canvas canvas,
    Offset baseCenter, {
    int level = 1,
    bool isNight = false,
    double animTime = 0.0,
  }) {
    final int safeLevel = math.max(1, level);
    final bool isAdvanced = safeLevel >= 5; // Seviye 5+ taş tahkimatlı & alevli

    // 1. Zemin Kaidesi (Ahşap & Taş Tahkimat)
    drawIsoCube(
      canvas,
      baseCenter,
      w: 24.0,
      d: 24.0,
      h: isAdvanced ? 6.0 : 4.0,
      topColor: isAdvanced ? const Color(0xFF64748B) : const Color(0xFF78350F),
      leftColor: isAdvanced ? const Color(0xFF475569) : const Color(0xFF5A2508),
      rightColor: isAdvanced ? const Color(0xFF334155) : const Color(0xFF451A03),
      drawShadow: true,
    );

    final double baseH = isAdvanced ? 6.0 : 4.0;
    final Offset towerBase = Offset(baseCenter.dx, baseCenter.dy - baseH);

    // 2. Kule Ana Gövdesi (Yüksek Taş/Ahşap Sütun Gövde)
    const double mainH = 22.0;
    drawIsoCube(
      canvas,
      towerBase,
      w: 16.0,
      d: 16.0,
      h: mainH,
      topColor: isAdvanced ? const Color(0xFF94A3B8) : const Color(0xFF92400E),
      leftColor: isAdvanced ? const Color(0xFF64748B) : const Color(0xFF78350F),
      rightColor: isAdvanced ? const Color(0xFF475569) : const Color(0xFF5A2508),
    );

    // Çapraz ahşap payandalar
    for (double dx in [-7.0, 7.0]) {
      drawIsoCube(
        canvas,
        Offset(towerBase.dx + dx * cosIso, towerBase.dy + 4.0),
        w: 2.5,
        d: 2.5,
        h: mainH * 0.75,
        topColor: const Color(0xFFB45309),
        leftColor: const Color(0xFF92400E),
        rightColor: const Color(0xFF78350F),
      );
    }

    // 3. Üst Okçu Platformu (Balkon & Siperlik Mazgalları)
    final Offset platformTop = Offset(towerBase.dx, towerBase.dy - mainH);
    drawIsoCube(
      canvas,
      platformTop,
      w: 22.0,
      d: 22.0,
      h: 3.5,
      topColor: const Color(0xFFD97706),
      leftColor: const Color(0xFFB45309),
      rightColor: const Color(0xFF92400E),
    );

    // Mazgal siperlikleri (4 Köşe Koruması)
    final Offset platformRoof = Offset(platformTop.dx, platformTop.dy - 3.5);
    for (double dx in [-8.0, 8.0]) {
      for (double dy in [-8.0, 8.0]) {
        drawIsoCube(
          canvas,
          Offset(platformRoof.dx + dx * cosIso, platformRoof.dy + dy * sinIso),
          w: 3.5,
          d: 3.5,
          h: 4.5,
          topColor: isAdvanced ? const Color(0xFFE2E8F0) : const Color(0xFFB45309),
          leftColor: isAdvanced ? const Color(0xFFCBD5E1) : const Color(0xFF92400E),
          rightColor: isAdvanced ? const Color(0xFF94A3B8) : const Color(0xFF78350F),
        );
      }
    }

    // 4. Kule Çatısı (Konik / Piramidal Ahşap Çatı)
    final Offset roofBase = Offset(platformRoof.dx, platformRoof.dy - 6.0);
    drawIsoCube(
      canvas,
      roofBase,
      w: 20.0,
      d: 20.0,
      h: 3.0,
      topColor: isAdvanced ? const Color(0xFFDC2626) : const Color(0xFFB45309),
      leftColor: isAdvanced ? const Color(0xFFB91C1C) : const Color(0xFF92400E),
      rightColor: isAdvanced ? const Color(0xFF991B1B) : const Color(0xFF78350F),
    );
    drawIsoCube(
      canvas,
      Offset(roofBase.dx, roofBase.dy - 3.0),
      w: 12.0,
      d: 12.0,
      h: 4.0,
      topColor: isAdvanced ? const Color(0xFFEF4444) : const Color(0xFFD97706),
      leftColor: isAdvanced ? const Color(0xFFDC2626) : const Color(0xFFB45309),
      rightColor: isAdvanced ? const Color(0xFFB91C1C) : const Color(0xFF92400E),
    );

    // Tepe Tuğu / Sancağı
    drawIsoCube(
      canvas,
      Offset(roofBase.dx, roofBase.dy - 7.0),
      w: 2.0,
      d: 2.0,
      h: 7.0,
      topColor: const Color(0xFFFDE047),
      leftColor: const Color(0xFFF59E0B),
      rightColor: const Color(0xFFD97706),
    );

    // 5. Gece Nöbet Meşalesi (Night Torchlight)
    if (isNight) {
      final double flicker = 0.8 + 0.2 * math.sin(animTime * 8.0);
      drawIsoCube(
        canvas,
        Offset(platformRoof.dx + 7.0 * cosIso, platformRoof.dy - 5.0),
        w: 3.0,
        d: 3.0,
        h: 3.0,
        topColor: Color.fromRGBO(251, 191, 36, flicker),
        leftColor: const Color(0xFFF59E0B),
        rightColor: const Color(0xFFD97706),
      );
    }
  }

  /// 3D Voxel Şato / Kağan Otağı (Görsel Evrim Kademeleri: 5, 15, 30, 50 & Gece Işıkları)
  static void drawVoxelCastle(Canvas canvas, Offset baseCenter, int level, {bool isNight = false}) {
    final int safeLevel = math.max(1, level);
    // Görsel Kademe: 0 (1-4), 1 (5-14), 2 (15-29), 3 (30-49), 4 (50+)
    final int tier = safeLevel >= 50 ? 4 : (safeLevel >= 30 ? 3 : (safeLevel >= 15 ? 2 : (safeLevel >= 5 ? 1 : 0)));

    final double extraH = tier * 3.5;
    final double mainHeight = 18.0 + extraH;
    final double towerHeight = 24.0 + extraH * 1.25;

    // 1. Ana Saray / Taş Monolit Kaide
    final Color wallTop = tier >= 3
        ? const Color(0xFFFFFFFF)
        : (tier >= 2 ? const Color(0xFFF1F5F9) : (tier >= 1 ? const Color(0xFFE2E8F0) : const Color(0xFFCBD5E1)));
    final Color wallLeft = tier >= 3
        ? const Color(0xFFCBD5E1)
        : (tier >= 2 ? const Color(0xFF94A3B8) : (tier >= 1 ? const Color(0xFF94A3B8) : const Color(0xFF64748B)));
    final Color wallRight = tier >= 3
        ? const Color(0xFF64748B)
        : (tier >= 2 ? const Color(0xFF475569) : (tier >= 1 ? const Color(0xFF475569) : const Color(0xFF1E293B)));

    drawIsoCube(
      canvas,
      baseCenter,
      w: 36.0 + (tier >= 3 ? 4.0 : 0.0),
      d: 36.0 + (tier >= 3 ? 4.0 : 0.0),
      h: mainHeight,
      topColor: wallTop,
      leftColor: wallLeft,
      rightColor: wallRight,
      drawShadow: true,
      shadowOpacity: 0.42,
    );

    // 2. Ana Kapı & Portal (Seviye 5+ Altın Kemerli, Seviye 30+ Çift Katlı Anıtsal Taç Kapı)
    final bool hasGoldPortal = tier >= 1;
    drawIsoCube(
      canvas,
      Offset(baseCenter.dx, baseCenter.dy + 8),
      w: 10.0 + (tier >= 3 ? 2.0 : 0.0),
      d: 4.0,
      h: 10.0 + tier * 2.0,
      topColor: hasGoldPortal ? const Color(0xFFF59E0B) : const Color(0xFF1E293B),
      leftColor: hasGoldPortal ? const Color(0xFFD97706) : const Color(0xFF0F172A),
      rightColor: hasGoldPortal ? const Color(0xFFB45309) : const Color(0xFF020617),
    );

    // 3. Kule Çatı Renkleri:
    // Tier 0 (1-4): Kızıl Bozkır Keçesi
    // Tier 1 (5-14): Altın Sarısı Tuğlu Çatı
    // Tier 2 (15-29): Gök Mavisi & Altın Saray Kuleleri
    // Tier 3 (30-49): Arduvaz Monolit & Altın Kubbe
    // Tier 4 (50+): Göksel Kozmik Zümrüt & Saf Altın
    final Color roofTop = tier >= 4
        ? const Color(0xFFFDE047)
        : (tier >= 3
            ? const Color(0xFF38BDF8)
            : (tier >= 2
                ? const Color(0xFF60A5FA)
                : (tier >= 1 ? const Color(0xFFFBBF24) : const Color(0xFFEF4444))));
    final Color roofLeft = tier >= 4
        ? const Color(0xFFF59E0B)
        : (tier >= 3
            ? const Color(0xFF0284C7)
            : (tier >= 2
                ? const Color(0xFF3B82F6)
                : (tier >= 1 ? const Color(0xFFF59E0B) : const Color(0xFFDC2626))));
    final Color roofRight = tier >= 4
        ? const Color(0xFFD97706)
        : (tier >= 3
            ? const Color(0xFF0369A1)
            : (tier >= 2
                ? const Color(0xFF1D4ED8)
                : (tier >= 1 ? const Color(0xFFD97706) : const Color(0xFF991B1B))));

    // 4. Kuleler (Yan Kuleler)
    for (final xSign in [-1.0, 1.0]) {
      final double tx = baseCenter.dx + xSign * 16.0 * cosIso;
      final double ty = baseCenter.dy - mainHeight + xSign * 16.0 * sinIso;

      // Kule Gövdesi
      drawIsoCube(
        canvas,
        Offset(tx, ty + 12),
        w: 12.0,
        d: 12.0,
        h: towerHeight,
        topColor: wallTop,
        leftColor: wallLeft,
        rightColor: wallRight,
      );

      // Gece Kule Penceresi Işığı
      if (isNight) {
        drawIsoCube(
          canvas,
          Offset(tx, ty + 2),
          w: 4.0,
          d: 4.0,
          h: 4.0,
          topColor: const Color(0xFFFEF08A),
          leftColor: const Color(0xFFFBBF24),
          rightColor: const Color(0xFFF59E0B),
        );
      }

      // Kule Çatısı
      drawIsoCube(
        canvas,
        Offset(tx, ty - (towerHeight - 12.0)),
        w: 14.0,
        d: 14.0,
        h: 8.0 + (tier >= 2 ? 3.0 : 0.0),
        topColor: roofTop,
        leftColor: roofLeft,
        rightColor: roofRight,
      );

      // Seviye 5+ Kule Üstü Kağanlık Tuğları / Sancakları
      if (tier >= 1) {
        drawIsoCube(
          canvas,
          Offset(tx, ty - (towerHeight - 4.0)),
          w: 2.0,
          d: 2.0,
          h: 10.0 + (tier >= 3 ? 4.0 : 0.0),
          topColor: const Color(0xFFFEF08A),
          leftColor: const Color(0xFFEAB308),
          rightColor: const Color(0xFFCA8A04),
        );
        drawIsoCube(
          canvas,
          Offset(tx + 3 * cosIso, ty - (towerHeight + 2.0)),
          w: 5.0 + (tier >= 3 ? 2.0 : 0.0),
          d: 1.5,
          h: 4.0 + (tier >= 3 ? 1.5 : 0.0),
          topColor: tier >= 3 ? const Color(0xFF38BDF8) : const Color(0xFFEF4444),
          leftColor: tier >= 3 ? const Color(0xFF0284C7) : const Color(0xFFDC2626),
          rightColor: tier >= 3 ? const Color(0xFF0369A1) : const Color(0xFFB91C1C),
        );
      }
    }

    // 5. Merkez Kağan Otağı / Baş Kule
    final Offset keepTop = Offset(baseCenter.dx, baseCenter.dy - mainHeight);

    if (tier >= 2) {
      // Seviye 15+ Merkez İmparatorluk Kubbesi
      drawIsoCube(
        canvas,
        keepTop,
        w: 16.0 + (tier >= 4 ? 4.0 : 0.0),
        d: 16.0 + (tier >= 4 ? 4.0 : 0.0),
        h: 8.0 + (tier >= 3 ? 5.0 : 0.0),
        topColor: const Color(0xFFFEF08A),
        leftColor: const Color(0xFFEAB308),
        rightColor: const Color(0xFFCA8A04),
      );
    }

    // 6. Merkez Altın Tamga Sancağı / Zirve Direği
    final double spireBaseY = tier >= 2 ? keepTop.dy - 8.0 : keepTop.dy;
    drawIsoCube(
      canvas,
      Offset(keepTop.dx, spireBaseY),
      w: tier >= 3 ? 4.0 : 3.0,
      d: tier >= 3 ? 4.0 : 3.0,
      h: 14.0 + tier * 3.0,
      topColor: const Color(0xFFFDE047),
      leftColor: const Color(0xFFEAB308),
      rightColor: const Color(0xFFCA8A04),
    );

    // 7. Seviye 30+ ve Seviye 50+ Göksel Kağanlık Zirve Tacı
    if (tier >= 3) {
      drawIsoCube(
        canvas,
        Offset(keepTop.dx, spireBaseY - 14.0 - tier * 2.0),
        w: tier >= 4 ? 12.0 : 8.0,
        d: tier >= 4 ? 12.0 : 8.0,
        h: tier >= 4 ? 6.0 : 4.0,
        topColor: const Color(0xFFFACC15),
        leftColor: const Color(0xFFEAB308),
        rightColor: const Color(0xFFB45309),
      );
    }
  }

  /// 3D Voxel Dönen Değirmen (Seviye Kademeli & Çoklu Görsel Varyantlar)
  static void drawVoxelWindmill(
    Canvas canvas,
    Offset baseCenter,
    double animTime, {
    bool isNight = false,
    int variant = 0,
    int level = 1,
    bool isWinter = false,
  }) {
    final int v = variant % 3;

    // Seviye Kademeleri: Lv 1-9 (Ahşap), Lv 10-24 (Taş Arduvaz), Lv 25+ (İmparatorluk Altın Monolit)
    final Color towerTop;
    final Color towerLeft;
    final Color towerRight;
    final double towerH;

    if (level >= 25) {
      towerTop = const Color(0xFF475569);
      towerLeft = const Color(0xFF1E293B);
      towerRight = const Color(0xFF020617);
      towerH = 32.0;
    } else if (level >= 10) {
      towerTop = v == 1 ? const Color(0xFFE2E8F0) : const Color(0xFFFFFFFF);
      towerLeft = v == 1 ? const Color(0xFF94A3B8) : const Color(0xFFCBD5E1);
      towerRight = v == 1 ? const Color(0xFF475569) : const Color(0xFF64748B);
      towerH = 26.0;
    } else {
      towerTop = const Color(0xFFD97706);
      towerLeft = const Color(0xFF92400E);
      towerRight = const Color(0xFF451A03);
      towerH = 22.0;
    }

    drawIsoCube(
      canvas,
      baseCenter,
      w: level >= 25 ? 28.0 : 24.0,
      d: level >= 25 ? 28.0 : 24.0,
      h: towerH,
      topColor: towerTop,
      leftColor: towerLeft,
      rightColor: towerRight,
      drawShadow: true,
      shadowOpacity: 0.38,
    );

    // Lv 25+ İmparatorluk Altın Kaide Süslemesi
    if (level >= 25) {
      drawIsoCube(
        canvas,
        Offset(baseCenter.dx, baseCenter.dy - towerH + 2),
        w: 26.0,
        d: 26.0,
        h: 3.0,
        topColor: const Color(0xFFFBBF24),
        leftColor: const Color(0xFFF59E0B),
        rightColor: const Color(0xFFD97706),
      );
    }

    if (level >= 10 || v == 1) {
      // Önünde un çuvalları
      final Offset sackPos = Offset(baseCenter.dx + 12 * cosIso, baseCenter.dy + 8 * sinIso);
      drawIsoCube(
        canvas,
        sackPos,
        w: 6.0,
        d: 6.0,
        h: 5.0,
        topColor: const Color(0xFFFEF08A),
        leftColor: const Color(0xFFFACC15),
        rightColor: const Color(0xFFCA8A04),
      );
    }
    if (level >= 8 || v == 2) {
      // Ahşap tahıl ambarı sundurması
      final Offset shedPos = Offset(baseCenter.dx + 12 * cosIso, baseCenter.dy - 6 * sinIso);
      drawIsoCube(
        canvas,
        shedPos,
        w: 10.0,
        d: 8.0,
        h: 12.0,
        topColor: const Color(0xFFB45309),
        leftColor: const Color(0xFF92400E),
        rightColor: const Color(0xFF78350F),
      );
      if (isWinter) {
        drawIsoCube(
          canvas,
          Offset(shedPos.dx, shedPos.dy - 12.0),
          w: 10.0,
          d: 8.0,
          h: 2.0,
          topColor: Colors.white,
          leftColor: const Color(0xFFE2E8F0),
          rightColor: const Color(0xFFCBD5E1),
        );
      }
    }

    if (isNight) {
      drawIsoCube(
        canvas,
        Offset(baseCenter.dx + 4 * cosIso, baseCenter.dy - 10),
        w: 4.0,
        d: 3.0,
        h: 4.0,
        topColor: const Color(0xFFFEF08A),
        leftColor: const Color(0xFFFBBF24),
        rightColor: const Color(0xFFF59E0B),
      );
    }

    final Offset roofBase = Offset(baseCenter.dx, baseCenter.dy - towerH);
    final Color roofTop = level >= 8
        ? const Color(0xFFD97706)
        : (v == 1 ? const Color(0xFFB45309) : const Color(0xFFF87171));
    final Color roofLeft = level >= 8
        ? const Color(0xFFB45309)
        : (v == 1 ? const Color(0xFF92400E) : const Color(0xFFEF4444));
    final Color roofRight = level >= 8
        ? const Color(0xFF92400E)
        : (v == 1 ? const Color(0xFF78350F) : const Color(0xFFB91C1C));

    drawIsoCube(
      canvas,
      roofBase,
      w: 20.0,
      d: 20.0,
      h: 10.0,
      topColor: roofTop,
      leftColor: roofLeft,
      rightColor: roofRight,
    );

    // Kış Çatı Kar Sırtı
    if (isWinter) {
      drawIsoCube(
        canvas,
        Offset(roofBase.dx, roofBase.dy - 10.0),
        w: 16.0,
        d: 16.0,
        h: 2.5,
        topColor: Colors.white,
        leftColor: const Color(0xFFE2E8F0),
        rightColor: const Color(0xFFCBD5E1),
      );
    }

    final Offset rotorHub = Offset(baseCenter.dx - 8 * cosIso, baseCenter.dy - (towerH - 6.0) + 8 * sinIso);
    final double angle = animTime * (level >= 8 ? 3.8 : (v == 2 ? 3.5 : 2.8));
    final int bladeCount = level >= 8 ? 6 : (v == 2 ? 6 : 4);
    final double bLen = level >= 8 ? 19.0 : 16.0;

    for (int i = 0; i < bladeCount; i++) {
      final double a = angle + i * (2 * math.pi / bladeCount);
      final double bx = rotorHub.dx + bLen * math.cos(a);
      final double by = rotorHub.dy + bLen * math.sin(a) * 0.8;

      _sharedFillPaint
        ..color = level >= 8 ? const Color(0xFFFDE047) : const Color(0xFFFEF08A)
        ..style = PaintingStyle.fill;
      _sharedStrokePaint
        ..color = level >= 8 ? const Color(0xFFB45309) : const Color(0xFF78350F)
        ..style = PaintingStyle.stroke
        ..strokeWidth = level >= 8 ? 2.4 : 2.0;

      canvas.drawLine(rotorHub, Offset(bx, by), _sharedStrokePaint);
      canvas.drawCircle(Offset(bx, by), level >= 8 ? 3.5 : 3.0, _sharedFillPaint);
    }
    _sharedFillPaint
      ..color = level >= 8 ? const Color(0xFFD97706) : const Color(0xFF451A03)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(rotorHub, 4.0, _sharedFillPaint);

    // Kinetik Un Tozu Zerrecikleri (Swirling Flour Dust)
    for (int d = 0; d < 3; d++) {
      final double dProgress = ((animTime * 1.6 + d * 0.33) % 1.0);
      final double dX = rotorHub.dx + math.cos(animTime * 2.2 + d * 2.0) * 10.0;
      final double dY = rotorHub.dy + 8.0 + dProgress * 14.0;
      final double dAlpha = (1.0 - dProgress) * 0.65;
      drawIsoCube(
        canvas,
        Offset(dX, dY),
        w: 2.2,
        d: 2.2,
        h: 2.2,
        topColor: const Color(0xFFFEF08A).withValues(alpha: dAlpha),
        leftColor: const Color(0xFFFDE047).withValues(alpha: dAlpha * 0.8),
        rightColor: const Color(0xFFFACC15).withValues(alpha: dAlpha * 0.6),
        drawShadow: false,
      );
    }
  }

  /// 3D Voxel Fırın (Seviye Kademeli & Çoklu Görsel Varyantlar)
  static void drawVoxelBakery(
    Canvas canvas,
    Offset baseCenter,
    double animTime, {
    bool isNight = false,
    int variant = 0,
    int level = 1,
    bool isWinter = false,
  }) {
    final int v = variant % 3;

    final Color wallTop = level >= 8
        ? const Color(0xFFF8FAFC)
        : (level >= 4 ? const Color(0xFFE2E8F0) : const Color(0xFFCBD5E1));
    final Color wallLeft = level >= 8
        ? const Color(0xFFCBD5E1)
        : (level >= 4 ? const Color(0xFF94A3B8) : const Color(0xFF94A3B8));
    final Color wallRight = level >= 8
        ? const Color(0xFF94A3B8)
        : (level >= 4 ? const Color(0xFF64748B) : const Color(0xFF64748B));
    final double h = level >= 8 ? 20.0 : 16.0;

    drawIsoCube(
      canvas,
      baseCenter,
      w: level >= 8 ? 30.0 : 28.0,
      d: level >= 8 ? 30.0 : 28.0,
      h: h,
      topColor: wallTop,
      leftColor: wallLeft,
      rightColor: wallRight,
      drawShadow: true,
    );

    // Kış Çatı Kar Sırtı
    if (isWinter) {
      drawIsoCube(
        canvas,
        Offset(baseCenter.dx, baseCenter.dy - h),
        w: level >= 8 ? 28.0 : 26.0,
        d: level >= 8 ? 28.0 : 26.0,
        h: 2.2,
        topColor: Colors.white,
        leftColor: const Color(0xFFE2E8F0),
        rightColor: const Color(0xFFCBD5E1),
      );
    }

    if (level >= 8) {
      // Seviye 8+: Altın Buğday Rozetli Giriş Kemeri
      drawIsoCube(
        canvas,
        Offset(baseCenter.dx, baseCenter.dy + 4),
        w: 10.0,
        d: 5.0,
        h: 12.0,
        topColor: const Color(0xFFFBBF24),
        leftColor: const Color(0xFFF59E0B),
        rightColor: const Color(0xFFD97706),
      );
    }

    if (level >= 4 || v == 1) {
      // Ekmek sergileme tezgahı & odun yığını
      final Offset benchPos = Offset(baseCenter.dx + 12 * cosIso, baseCenter.dy + 8 * sinIso);
      drawIsoCube(
        canvas,
        benchPos,
        w: 8.0,
        d: 5.0,
        h: 5.0,
        topColor: const Color(0xFFF59E0B),
        leftColor: const Color(0xFFD97706),
        rightColor: const Color(0xFFB45309),
      );
    }
    if (v == 2) {
      // Un deposu yan sundurması
      final Offset flourPos = Offset(baseCenter.dx - 10 * cosIso, baseCenter.dy + 8 * sinIso);
      drawIsoCube(
        canvas,
        flourPos,
        w: 7.0,
        d: 7.0,
        h: 6.0,
        topColor: const Color(0xFFFEF08A),
        leftColor: const Color(0xFFFDE047),
        rightColor: const Color(0xFFCA8A04),
      );
    }

    final Offset chimneyBase = Offset(baseCenter.dx + 8 * cosIso, baseCenter.dy - h - 4 * sinIso);
    drawIsoCube(
      canvas,
      chimneyBase,
      w: 8.0,
      d: 8.0,
      h: 12.0,
      topColor: const Color(0xFFF97316),
      leftColor: const Color(0xFFEA580C),
      rightColor: const Color(0xFFC2410C),
    );

    final double puffY = (animTime * 20.0) % 24.0;
    final double alpha = (1.0 - (puffY / 24.0)).clamp(0.0, 1.0);
    final double puffScale = 0.6 + (puffY / 24.0) * 0.8;

    drawIsoCube(
      canvas,
      Offset(chimneyBase.dx, chimneyBase.dy - 12.0 - puffY),
      w: 8.0 * puffScale,
      d: 8.0 * puffScale,
      h: 6.0 * puffScale,
      topColor: Colors.white.withValues(alpha: alpha * 0.9),
      leftColor: const Color(0xFFE2E8F0).withValues(alpha: alpha * 0.8),
      rightColor: const Color(0xFFCBD5E1).withValues(alpha: alpha * 0.7),
    );
  }

  /// 3D Voxel Dağ - Çoklu Prosedürel Morfoloji
  static void drawVoxelMountainVariant(
    Canvas canvas,
    Offset baseCenter,
    int variant, {
    String season = 'SPRING',
    bool isZud = false,
    double scale = 1.0,
    double animTime = 0.0,
  }) {
    final bool isWinter = season == 'WINTER' || isZud;
    final bool isSummer = season == 'SUMMER';

    final Color snowTop = isZud ? const Color(0xFFBAE6FD) : const Color(0xFFFFFFFF);
    final Color snowLeft = isZud ? const Color(0xFF7DD3FC) : const Color(0xFFE2E8F0);
    final Color snowRight = isZud ? const Color(0xFF38BDF8) : const Color(0xFFCBD5E1);

    final int type = variant % 4;
    switch (type) {
      case 0:
        // Variant 0: Çift Zirveli Sivri Masif (Twin Sharp Peaks)
        drawIsoCube(
          canvas,
          baseCenter,
          w: 38.0 * scale,
          d: 38.0 * scale,
          h: 10.0 * scale,
          topColor: isWinter ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          leftColor: const Color(0xFF475569),
          rightColor: const Color(0xFF334155),
          drawShadow: true,
        );
        final Offset leftMid = Offset(baseCenter.dx - 8.0 * scale, baseCenter.dy - 10.0 * scale);
        drawIsoCube(
          canvas,
          leftMid,
          w: 18.0 * scale,
          d: 18.0 * scale,
          h: 14.0 * scale,
          topColor: const Color(0xFF94A3B8),
          leftColor: const Color(0xFF64748B),
          rightColor: const Color(0xFF475569),
        );
        final Offset leftTop = Offset(leftMid.dx, leftMid.dy - 14.0 * scale);
        drawIsoCube(
          canvas,
          leftTop,
          w: 10.0 * scale,
          d: 10.0 * scale,
          h: isSummer ? 8.0 * scale : 14.0 * scale,
          topColor: snowTop,
          leftColor: snowLeft,
          rightColor: snowRight,
        );
        final Offset rightMid = Offset(baseCenter.dx + 10.0 * scale, baseCenter.dy - 8.0 * scale);
        drawIsoCube(
          canvas,
          rightMid,
          w: 16.0 * scale,
          d: 16.0 * scale,
          h: 11.0 * scale,
          topColor: const Color(0xFF94A3B8),
          leftColor: const Color(0xFF64748B),
          rightColor: const Color(0xFF475569),
        );
        final Offset rightTop = Offset(rightMid.dx, rightMid.dy - 11.0 * scale);
        drawIsoCube(
          canvas,
          rightTop,
          w: 8.0 * scale,
          d: 8.0 * scale,
          h: isSummer ? 6.0 * scale : 10.0 * scale,
          topColor: snowTop,
          leftColor: snowLeft,
          rightColor: snowRight,
        );
        break;

      case 1:
        // Variant 1: Katmanlı Demir Kanyonu / Kızıl Mesa (Stratified Red Mesa)
        drawIsoCube(
          canvas,
          baseCenter,
          w: 40.0 * scale,
          d: 36.0 * scale,
          h: 9.0 * scale,
          topColor: const Color(0xFF78350F),
          leftColor: const Color(0xFF5C2B09),
          rightColor: const Color(0xFF451A03),
          drawShadow: true,
        );
        final Offset step1 = Offset(baseCenter.dx, baseCenter.dy - 9.0 * scale);
        drawIsoCube(
          canvas,
          step1,
          w: 28.0 * scale,
          d: 26.0 * scale,
          h: 9.0 * scale,
          topColor: const Color(0xFFB45309),
          leftColor: const Color(0xFF92400E),
          rightColor: const Color(0xFF78350F),
        );
        final Offset step2 = Offset(baseCenter.dx, step1.dy - 9.0 * scale);
        drawIsoCube(
          canvas,
          step2,
          w: 18.0 * scale,
          d: 16.0 * scale,
          h: 8.0 * scale,
          topColor: isWinter ? snowTop : const Color(0xFFD97706),
          leftColor: isWinter ? snowLeft : const Color(0xFFB45309),
          rightColor: isWinter ? snowRight : const Color(0xFF92400E),
        );
        drawIsoCube(
          canvas,
          Offset(step2.dx + 4.0 * scale, step2.dy - 8.0 * scale),
          w: 4.0 * scale,
          d: 4.0 * scale,
          h: 3.0 * scale,
          topColor: const Color(0xFFFBBF24),
          leftColor: const Color(0xFFF59E0B),
          rightColor: const Color(0xFFD97706),
        );
        break;

      case 2:
        // Variant 2: Kraterli Volkanik Masif (Volcanic Caldera)
        drawIsoCube(
          canvas,
          baseCenter,
          w: 36.0 * scale,
          d: 36.0 * scale,
          h: 12.0 * scale,
          topColor: const Color(0xFF334155),
          leftColor: const Color(0xFF1E293B),
          rightColor: const Color(0xFF0F172A),
          drawShadow: true,
        );
        final Offset midCaldera = Offset(baseCenter.dx, baseCenter.dy - 12.0 * scale);
        drawIsoCube(
          canvas,
          midCaldera,
          w: 24.0 * scale,
          d: 24.0 * scale,
          h: 12.0 * scale,
          topColor: const Color(0xFF475569),
          leftColor: const Color(0xFF334155),
          rightColor: const Color(0xFF1E293B),
        );
        final Offset craterBase = Offset(baseCenter.dx, midCaldera.dy - 12.0 * scale);
        drawIsoCube(
          canvas,
          craterBase,
          w: 12.0 * scale,
          d: 12.0 * scale,
          h: 3.0 * scale,
          topColor: const Color(0xFFDC2626),
          leftColor: const Color(0xFFB91C1C),
          rightColor: const Color(0xFF991B1B),
        );
        drawIsoCube(
          canvas,
          Offset(craterBase.dx, craterBase.dy - 3.0 * scale),
          w: 6.0 * scale,
          d: 6.0 * scale,
          h: 2.0 * scale,
          topColor: const Color(0xFFFBBF24),
          leftColor: const Color(0xFFF59E0B),
          rightColor: const Color(0xFFD97706),
        );
        break;

      case 3:
      default:
        // Variant 3: Tekil Sarp Boynuz Zirve (Matterhorn Needle Crag)
        drawIsoCube(
          canvas,
          baseCenter,
          w: 34.0 * scale,
          d: 34.0 * scale,
          h: 10.0 * scale,
          topColor: const Color(0xFF64748B),
          leftColor: const Color(0xFF475569),
          rightColor: const Color(0xFF334155),
          drawShadow: true,
        );
        final Offset midSpire = Offset(baseCenter.dx + 2.0 * scale, baseCenter.dy - 10.0 * scale);
        drawIsoCube(
          canvas,
          midSpire,
          w: 20.0 * scale,
          d: 20.0 * scale,
          h: 16.0 * scale,
          topColor: const Color(0xFF94A3B8),
          leftColor: const Color(0xFF64748B),
          rightColor: const Color(0xFF475569),
        );
        final Offset topSpire = Offset(midSpire.dx, midSpire.dy - 16.0 * scale);
        drawIsoCube(
          canvas,
          topSpire,
          w: 10.0 * scale,
          d: 10.0 * scale,
          h: 18.0 * scale,
          topColor: snowTop,
          leftColor: snowLeft,
          rightColor: snowRight,
        );
        break;
    }
  }

  /// 3D Voxel Oduncu Kulübesi (Seviye Kademeli & Çoklu Görsel Varyantlar)
  static void drawVoxelLumberjack(
    Canvas canvas,
    Offset baseCenter, {
    int variant = 0,
    int level = 1,
    bool isWinter = false,
  }) {
    final int v = variant % 3;

    if (level >= 10) {
      // Seviye 10+ (1. Sıçrama): Baş Ormancı Konağı (Çift Çatılı & Vinçli İleri Yapı)
      drawIsoCube(
        canvas,
        baseCenter,
        w: 30.0,
        d: 30.0,
        h: 18.0,
        topColor: const Color(0xFF78350F),
        leftColor: const Color(0xFF5A2508),
        rightColor: const Color(0xFF451A03),
        drawShadow: true,
      );
      // Altın Balta Rozetli Giriş
      drawIsoCube(
        canvas,
        Offset(baseCenter.dx, baseCenter.dy + 4),
        w: 8.0,
        d: 4.0,
        h: 12.0,
        topColor: const Color(0xFFFBBF24),
        leftColor: const Color(0xFFF59E0B),
        rightColor: const Color(0xFFD97706),
      );
      if (isWinter) {
        drawIsoCube(
          canvas,
          Offset(baseCenter.dx, baseCenter.dy - 18.0),
          w: 28.0,
          d: 28.0,
          h: 2.2,
          topColor: Colors.white,
          leftColor: const Color(0xFFE2E8F0),
          rightColor: const Color(0xFFCBD5E1),
        );
      }
    } else if (v == 1) {
      // Varyant 1: Oduncu Çadırı & Dev Ulu Tomruk
      final Offset tentPos = Offset(baseCenter.dx - 4 * cosIso, baseCenter.dy - 4 * sinIso);
      drawIsoCube(
        canvas,
        tentPos,
        w: 20.0,
        d: 20.0,
        h: 12.0,
        topColor: const Color(0xFFD97706),
        leftColor: const Color(0xFFB45309),
        rightColor: const Color(0xFF92400E),
        drawShadow: true,
      );
      // Dev Devrilmiş Tomruk
      drawIsoCube(
        canvas,
        Offset(baseCenter.dx + 10 * cosIso, baseCenter.dy + 8 * sinIso),
        w: 16.0,
        d: 6.0,
        h: 6.0,
        topColor: const Color(0xFF92400E),
        leftColor: const Color(0xFF78350F),
        rightColor: const Color(0xFF451A03),
      );
    } else if (v == 2) {
      // Varyant 2: Piramit Kütük İstifleri & Testere Sehpası
      drawIsoCube(
        canvas,
        baseCenter,
        w: 22.0,
        d: 22.0,
        h: 10.0,
        topColor: const Color(0xFF92400E),
        leftColor: const Color(0xFF78350F),
        rightColor: const Color(0xFF451A03),
        drawShadow: true,
      );
      // Piramit Tomruk Yığını
      final Offset stackPos = Offset(baseCenter.dx + 10 * cosIso, baseCenter.dy + 10 * sinIso);
      drawIsoCube(
        canvas,
        stackPos,
        w: 12.0,
        d: 8.0,
        h: 6.0,
        topColor: const Color(0xFFFDE68A),
        leftColor: const Color(0xFFD97706),
        rightColor: const Color(0xFF92400E),
      );
      drawIsoCube(
        canvas,
        Offset(stackPos.dx, stackPos.dy - 6.0),
        w: 8.0,
        d: 6.0,
        h: 5.0,
        topColor: const Color(0xFFFEF3C7),
        leftColor: const Color(0xFFFDE68A),
        rightColor: const Color(0xFFD97706),
      );
    } else {
      // Varyant 0: Klasik Kütük Kulübe & Kütük Üzerinde Balta
      drawIsoCube(
        canvas,
        baseCenter,
        w: 26.0,
        d: 26.0,
        h: 14.0,
        topColor: const Color(0xFFB45309),
        leftColor: const Color(0xFF92400E),
        rightColor: const Color(0xFF78350F),
        drawShadow: true,
      );

      drawIsoCube(
        canvas,
        Offset(baseCenter.dx + 12 * cosIso, baseCenter.dy + 12 * sinIso),
        w: 12.0,
        d: 6.0,
        h: 6.0,
        topColor: const Color(0xFFFDE68A),
        leftColor: const Color(0xFFD97706),
        rightColor: const Color(0xFF92400E),
      );
    }
  }

  /// 3D Voxel Hızarhane (Seviye Kademeli & Çoklu Görsel Varyantlar)
  static void drawVoxelSawmill(
    Canvas canvas,
    Offset baseCenter, {
    int variant = 0,
    int level = 1,
    bool isWinter = false,
  }) {
    final int v = variant % 3;
    final double h = level >= 8 ? 18.0 : 14.0;

    drawIsoCube(
      canvas,
      baseCenter,
      w: level >= 8 ? 32.0 : 28.0,
      d: level >= 8 ? 32.0 : 28.0,
      h: h,
      topColor: level >= 8 ? const Color(0xFF78350F) : const Color(0xFF92400E),
      leftColor: level >= 8 ? const Color(0xFF5A2508) : const Color(0xFF78350F),
      rightColor: level >= 8 ? const Color(0xFF331400) : const Color(0xFF451A03),
      drawShadow: true,
    );

    if (isWinter) {
      drawIsoCube(
        canvas,
        Offset(baseCenter.dx, baseCenter.dy - h),
        w: level >= 8 ? 30.0 : 26.0,
        d: level >= 8 ? 30.0 : 26.0,
        h: 2.2,
        topColor: Colors.white,
        leftColor: const Color(0xFFE2E8F0),
        rightColor: const Color(0xFFCBD5E1),
      );
    }

    if (level >= 8) {
      // Seviye 8+: Hidrolik Çift Döner Testere Masası
      drawIsoCube(
        canvas,
        Offset(baseCenter.dx - 6, baseCenter.dy - h),
        w: 5.0,
        d: 14.0,
        h: 12.0,
        topColor: const Color(0xFFF1F5F9),
        leftColor: const Color(0xFFCBD5E1),
        rightColor: const Color(0xFF94A3B8),
      );
      drawIsoCube(
        canvas,
        Offset(baseCenter.dx + 8, baseCenter.dy - h),
        w: 5.0,
        d: 14.0,
        h: 12.0,
        topColor: const Color(0xFFF1F5F9),
        leftColor: const Color(0xFFCBD5E1),
        rightColor: const Color(0xFF94A3B8),
      );
    } else if (v == 1) {
      // Varyant 1: Çift Bıçaklı Açık Kesim Tezgahı & Kalas İstifleri
      drawIsoCube(
        canvas,
        Offset(baseCenter.dx - 4, baseCenter.dy - 14.0),
        w: 4.0,
        d: 12.0,
        h: 9.0,
        topColor: const Color(0xFFF1F5F9),
        leftColor: const Color(0xFFCBD5E1),
        rightColor: const Color(0xFF94A3B8),
      );
      drawIsoCube(
        canvas,
        Offset(baseCenter.dx + 8, baseCenter.dy - 14.0),
        w: 4.0,
        d: 12.0,
        h: 9.0,
        topColor: const Color(0xFFF1F5F9),
        leftColor: const Color(0xFFCBD5E1),
        rightColor: const Color(0xFF94A3B8),
      );
      // Kalas İstifi
      drawIsoCube(
        canvas,
        Offset(baseCenter.dx + 12 * cosIso, baseCenter.dy + 8 * sinIso),
        w: 12.0,
        d: 6.0,
        h: 6.0,
        topColor: const Color(0xFFFDE68A),
        leftColor: const Color(0xFFD97706),
        rightColor: const Color(0xFFB45309),
      );
    } else if (v == 2) {
      // Varyant 2: Hızar Kulesi Sundurması
      drawIsoCube(
        canvas,
        Offset(baseCenter.dx - 6 * cosIso, baseCenter.dy - 14.0 - 6 * sinIso),
        w: 12.0,
        d: 12.0,
        h: 12.0,
        topColor: const Color(0xFFB45309),
        leftColor: const Color(0xFF92400E),
        rightColor: const Color(0xFF78350F),
      );
    } else {
      // Varyant 0: Tek Bıçaklı Hızar
      drawIsoCube(
        canvas,
        Offset(baseCenter.dx + 6, baseCenter.dy - 14.0),
        w: 4.0,
        d: 12.0,
        h: 8.0,
        topColor: const Color(0xFFF1F5F9),
        leftColor: const Color(0xFFCBD5E1),
        rightColor: const Color(0xFF94A3B8),
      );
    }
  }

  /// 3D Voxel Mobilya Atölyesi (Seviye Kademeli & Çoklu Görsel Varyantlar)
  static void drawVoxelFurniture(
    Canvas canvas,
    Offset baseCenter, {
    int variant = 0,
    int level = 1,
    bool isWinter = false,
  }) {
    final int v = variant % 3;

    drawIsoCube(
      canvas,
      baseCenter,
      w: 28.0,
      d: 28.0,
      h: 14.0,
      topColor: const Color(0xFFD97706),
      leftColor: const Color(0xFFB45309),
      rightColor: const Color(0xFF78350F),
      drawShadow: true,
    );

    if (isWinter) {
      drawIsoCube(
        canvas,
        Offset(baseCenter.dx, baseCenter.dy - 14.0),
        w: 26.0,
        d: 26.0,
        h: 2.0,
        topColor: Colors.white,
        leftColor: const Color(0xFFE2E8F0),
        rightColor: const Color(0xFFCBD5E1),
      );
    }

    if (v == 1) {
      // Varyant 1: Ahşap Oyma Tezgahı & Vernik Fıçısı
      drawIsoCube(
        canvas,
        Offset(baseCenter.dx + 4, baseCenter.dy - 14.0),
        w: 12.0,
        d: 6.0,
        h: 6.0,
        topColor: const Color(0xFFFEF3C7),
        leftColor: const Color(0xFFFDE68A),
        rightColor: const Color(0xFFD97706),
      );
      // Vernik Fıçısı
      drawIsoCube(
        canvas,
        Offset(baseCenter.dx + 12 * cosIso, baseCenter.dy + 8 * sinIso),
        w: 5.0,
        d: 5.0,
        h: 6.0,
        topColor: const Color(0xFF78350F),
        leftColor: const Color(0xFF5A2508),
        rightColor: const Color(0xFF451A03),
      );
    } else if (v == 2) {
      // Varyant 2: Otağ Sandığı & Oyma Taht
      drawIsoCube(
        canvas,
        Offset(baseCenter.dx - 2, baseCenter.dy - 14.0),
        w: 10.0,
        d: 10.0,
        h: 12.0,
        topColor: const Color(0xFFFBBF24),
        leftColor: const Color(0xFFF59E0B),
        rightColor: const Color(0xFFD97706),
      );
    } else {
      // Varyant 0: Bitmiş Dolap & Tezgah
      drawIsoCube(
        canvas,
        Offset(baseCenter.dx, baseCenter.dy - 14.0),
        w: 8.0,
        d: 8.0,
        h: 10.0,
        topColor: const Color(0xFFFEF3C7),
        leftColor: const Color(0xFFFDE68A),
        rightColor: const Color(0xFFD97706),
      );
    }
  }

  /// 3D Voxel Maden ve Demir Döküm Ocağı (Seviye Kademeli & Çoklu Görsel Varyantlar)
  static void drawVoxelMine(
    Canvas canvas,
    Offset baseCenter, {
    double animTime = 0.0,
    bool isNight = false,
    int variant = 0,
    int level = 1,
    bool isWinter = false,
  }) {
    final int v = variant % 3;

    final Color mineTop = level >= 8
        ? const Color(0xFF1E293B)
        : (level >= 4 ? const Color(0xFF475569) : const Color(0xFF64748B));
    final Color mineLeft = level >= 8
        ? const Color(0xFF0F172A)
        : (level >= 4 ? const Color(0xFF334155) : const Color(0xFF475569));
    final Color mineRight = level >= 8
        ? const Color(0xFF020617)
        : (level >= 4 ? const Color(0xFF1E293B) : const Color(0xFF334155));
    final double h = level >= 8 ? 20.0 : 16.0;

    drawIsoCube(
      canvas,
      baseCenter,
      w: level >= 8 ? 32.0 : 28.0,
      d: level >= 8 ? 32.0 : 28.0,
      h: h,
      topColor: mineTop,
      leftColor: mineLeft,
      rightColor: mineRight,
      drawShadow: true,
    );

    if (isWinter) {
      drawIsoCube(
        canvas,
        Offset(baseCenter.dx, baseCenter.dy - h),
        w: level >= 8 ? 30.0 : 26.0,
        d: level >= 8 ? 30.0 : 26.0,
        h: 2.2,
        topColor: Colors.white,
        leftColor: const Color(0xFFE2E8F0),
        rightColor: const Color(0xFFCBD5E1),
      );
    }

    if (level >= 8) {
      // Seviye 8+: Çift Akkor Dökümhane Havuzu & Tünel
      drawIsoCube(
        canvas,
        Offset(baseCenter.dx, baseCenter.dy + 4),
        w: 14.0,
        d: 6.0,
        h: 12.0,
        topColor: const Color(0xFF0F172A),
        leftColor: Colors.black,
        rightColor: Colors.black,
      );
      // Dökümhane Lav/Demir Akışı
      final double lavaPulse = 0.75 + 0.25 * math.sin(animTime * 5.0);
      drawIsoCube(
        canvas,
        Offset(baseCenter.dx, baseCenter.dy + 7),
        w: 10.0,
        d: 4.0,
        h: 2.5,
        topColor: Color.fromRGBO(251, 146, 60, lavaPulse),
        leftColor: const Color(0xFFEA580C),
        rightColor: const Color(0xFFC2410C),
        drawShadow: false,
      );
    } else if (level >= 4 || v == 1) {
      // Ahşap Tahkimatlı Asansör Kulesi & Ray
      final Offset towerPos = Offset(baseCenter.dx - 4 * cosIso, baseCenter.dy - 16.0 - 4 * sinIso);
      drawIsoCube(
        canvas,
        towerPos,
        w: 10.0,
        d: 10.0,
        h: 16.0,
        topColor: const Color(0xFFB45309),
        leftColor: const Color(0xFF92400E),
        rightColor: const Color(0xFF78350F),
      );
    } else if (v == 2) {
      // İkiz Maden Tüneli Girişi
      drawIsoCube(
        canvas,
        Offset(baseCenter.dx - 4 * cosIso, baseCenter.dy + 4),
        w: 8.0,
        d: 5.0,
        h: 8.0,
        topColor: const Color(0xFF0F172A),
        leftColor: Colors.black,
        rightColor: Colors.black,
      );
      drawIsoCube(
        canvas,
        Offset(baseCenter.dx + 6 * cosIso, baseCenter.dy + 4),
        w: 8.0,
        d: 5.0,
        h: 8.0,
        topColor: const Color(0xFF0F172A),
        leftColor: Colors.black,
        rightColor: Colors.black,
      );
    } else {
      // Maden Giriş Tüneli
      drawIsoCube(
        canvas,
        Offset(baseCenter.dx, baseCenter.dy + 4),
        w: 12.0,
        d: 6.0,
        h: 10.0,
        topColor: const Color(0xFF0F172A),
        leftColor: Colors.black,
        rightColor: Colors.black,
      );
      // Ocak İçi Akkor Demir/Köz Parıltısı
      final double emberPulse = 0.65 + 0.35 * math.sin(animTime * 4.0);
      drawIsoCube(
        canvas,
        Offset(baseCenter.dx, baseCenter.dy + 6),
        w: 6.0,
        d: 3.0,
        h: 2.0,
        topColor: Color.fromRGBO(249, 115, 22, emberPulse),
        leftColor: const Color(0xFFEA580C),
        rightColor: const Color(0xFFC2410C),
        drawShadow: false,
      );
    }

    // Altın / Demir Cevheri Yığını
    drawIsoCube(
      canvas,
      Offset(baseCenter.dx + 10 * cosIso, baseCenter.dy + 8 * sinIso),
      w: 8.0,
      d: 8.0,
      h: 6.0,
      topColor: const Color(0xFFFFD700),
      leftColor: const Color(0xFFEAB308),
      rightColor: const Color(0xFFCA8A04),
    );

    // Maden Havalandırma Bacası (Lv 8+'da Çift Baca)
    final Offset ventBase = Offset(baseCenter.dx - 6 * cosIso, baseCenter.dy - h - 4 * sinIso);
    drawIsoCube(
      canvas,
      ventBase,
      w: 6.0,
      d: 6.0,
      h: 8.0,
      topColor: const Color(0xFF334155),
      leftColor: const Color(0xFF1E293B),
      rightColor: const Color(0xFF0F172A),
    );

    if (level >= 8) {
      final Offset ventBase2 = Offset(baseCenter.dx + 6 * cosIso, baseCenter.dy - h - 4 * sinIso);
      drawIsoCube(
        canvas,
        ventBase2,
        w: 6.0,
        d: 6.0,
        h: 8.0,
        topColor: const Color(0xFF334155),
        leftColor: const Color(0xFF1E293B),
        rightColor: const Color(0xFF0F172A),
      );
    }

    // Yükselen Voksel Kömür Dumanı
    if (animTime > 0) {
      final double puffY = (animTime * 16.0) % 20.0;
      final double alpha = (1.0 - (puffY / 20.0)).clamp(0.0, 1.0);
      drawIsoCube(
        canvas,
        Offset(ventBase.dx + math.sin(animTime * 2.5) * 2.0, ventBase.dy - 8.0 - puffY),
        w: 5.0 + (puffY / 20.0) * 3.0,
        d: 5.0 + (puffY / 20.0) * 3.0,
        h: 4.0,
        topColor: const Color(0xFF94A3B8).withValues(alpha: alpha * 0.7),
        leftColor: const Color(0xFF64748B).withValues(alpha: alpha * 0.6),
        rightColor: const Color(0xFF475569).withValues(alpha: alpha * 0.5),
      );
    }
  }

  /// Sis İçinde Seyrek Kadim Rünler, Sunak ve Efsanevi Biyom Fısıltıları (Clean & Sparse)
  static void drawVoxelMysteryFog(
    Canvas canvas,
    Offset center, {
    required int seed,
    required TileBiome hiddenBiome,
    required bool hasShrine,
    required bool isBorderFog,
    double animTime = 0.0,
    double alpha = 1.0,
    double disperseRise = 0.0,
  }) {
    if (alpha <= 0.01) return;

    final Offset mistCenter = Offset(center.dx, center.dy - disperseRise);

    // 1. Kadim Sunak (Shrine) Keşif Rünü
    if (hasShrine) {
      final double shrinePulse = 0.65 + 0.35 * math.sin(animTime * 1.5 + seed);
      _sharedStrokePaint
        ..color = const Color(0xFF38BDF8).withValues(alpha: (shrinePulse * alpha).clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(Offset(mistCenter.dx, mistCenter.dy - 2), 7.0, _sharedStrokePaint);
      canvas.drawLine(Offset(mistCenter.dx - 4, mistCenter.dy - 2), Offset(mistCenter.dx + 4, mistCenter.dy - 2), _sharedStrokePaint);
      return;
    }

    // 2. Efsanevi Biyom Rünik Tamgaları
    if (hiddenBiome == TileBiome.celestialCrater) {
      final double starPulse = 0.6 + 0.35 * math.sin(animTime * 1.8 + seed);
      _sharedStrokePaint
        ..color = const Color(0xFFA855F7).withValues(alpha: (starPulse * alpha).clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8;
      canvas.drawLine(Offset(mistCenter.dx - 5, mistCenter.dy - 2), Offset(mistCenter.dx + 5, mistCenter.dy - 2), _sharedStrokePaint);
      canvas.drawLine(Offset(mistCenter.dx, mistCenter.dy - 7), Offset(mistCenter.dx, mistCenter.dy + 3), _sharedStrokePaint);
      return;
    } else if (hiddenBiome == TileBiome.kurganValley) {
      final double kurganPulse = 0.6 + 0.35 * math.sin(animTime * 2.0 + seed);
      _sharedStrokePaint
        ..color = const Color(0xFFF59E0B).withValues(alpha: (kurganPulse * alpha).clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(Offset(mistCenter.dx, mistCenter.dy - 2), 5.0, _sharedStrokePaint);
      return;
    } else if (hiddenBiome == TileBiome.crystalChasm) {
      final double crystalPulse = 0.6 + 0.35 * math.sin(animTime * 2.2 + seed);
      _sharedStrokePaint
        ..color = const Color(0xFFEC4899).withValues(alpha: (crystalPulse * alpha).clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8;
      canvas.drawLine(Offset(mistCenter.dx - 4, mistCenter.dy + 2), Offset(mistCenter.dx, mistCenter.dy - 6), _sharedStrokePaint);
      canvas.drawLine(Offset(mistCenter.dx, mistCenter.dy - 6), Offset(mistCenter.dx + 4, mistCenter.dy + 2), _sharedStrokePaint);
      return;
    }

    // 3. %5 Seyrek Rastgele Bozkır Tamgası / Rünik Keşif Fısıltısı
    final bool isRareMystery = (seed % 20 == 0);
    if (isRareMystery) {
      drawVoxelPetroglyph(
        canvas,
        Offset(mistCenter.dx, mistCenter.dy - 2),
        seed: seed,
        animTime: animTime,
        isBorderFog: isBorderFog,
      );
    }
  }

  /// Antik Bozkır Petroglif & Tamga Kazıma Çizgileri (Sis Karoları İçin)
  static void drawVoxelPetroglyph(
    Canvas canvas,
    Offset center, {
    required int seed,
    double animTime = 0.0,
    bool isBorderFog = false,
  }) {
    final int variant = seed % 4;
    final double runeBrightness = isBorderFog ? 0.75 : 0.25;
    final double runePulse = runeBrightness + 0.2 * math.sin(animTime * 2.5 + (seed % 5));

    _sharedStrokePaint
      ..color = isBorderFog
          ? const Color(0xFFFBBF24).withValues(alpha: runePulse.clamp(0.0, 1.0))
          : const Color(0xFFD97706).withValues(alpha: runePulse.clamp(0.0, 1.0))
      ..style = PaintingStyle.stroke
      ..strokeWidth = isBorderFog ? 2.2 : 1.5
      ..strokeCap = StrokeCap.round;

    _cubeShadowPaint
      ..color = const Color(0xFFFBBF24).withValues(alpha: (runePulse * 0.4).clamp(0.0, 1.0))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    _sharedPath.reset();

    switch (variant) {
      case 0:
        // Variant 0: Bozkır Boynuz / Geyik Tamgası
        _sharedPath.moveTo(center.dx - 8, center.dy - 4);
        _sharedPath.lineTo(center.dx, center.dy + 4);
        _sharedPath.lineTo(center.dx + 8, center.dy - 4);
        _sharedPath.moveTo(center.dx, center.dy + 4);
        _sharedPath.lineTo(center.dx, center.dy + 10);
        _sharedPath.moveTo(center.dx - 5, center.dy - 1);
        _sharedPath.lineTo(center.dx + 5, center.dy - 1);
        break;
      case 1:
        // Variant 1: Dört Yön Kağan Tamgası (Güneş Rünü)
        _sharedPath.moveTo(center.dx, center.dy - 8);
        _sharedPath.lineTo(center.dx, center.dy + 8);
        _sharedPath.moveTo(center.dx - 8, center.dy);
        _sharedPath.lineTo(center.dx + 8, center.dy);
        _sharedPath.addOval(Rect.fromCircle(center: center, radius: 4.0));
        break;
      case 2:
        // Variant 2: Bozkır Dağ Keçisi Rünü
        _sharedPath.moveTo(center.dx - 6, center.dy - 6);
        _sharedPath.quadraticBezierTo(center.dx - 2, center.dy - 10, center.dx, center.dy - 4);
        _sharedPath.lineTo(center.dx, center.dy + 6);
        _sharedPath.lineTo(center.dx - 4, center.dy + 10);
        _sharedPath.moveTo(center.dx, center.dy + 6);
        _sharedPath.lineTo(center.dx + 4, center.dy + 10);
        break;
      case 3:
      default:
        // Variant 3: Ok ve Yay / And İmzası
        _sharedPath.moveTo(center.dx - 7, center.dy + 6);
        _sharedPath.lineTo(center.dx + 7, center.dy - 6);
        _sharedPath.moveTo(center.dx + 7, center.dy - 6);
        _sharedPath.lineTo(center.dx + 2, center.dy - 6);
        _sharedPath.moveTo(center.dx + 7, center.dy - 6);
        _sharedPath.lineTo(center.dx + 7, center.dy - 1);
        _sharedPath.moveTo(center.dx - 2, center.dy + 1);
        _sharedPath.lineTo(center.dx + 2, center.dy - 3);
        break;
    }

    canvas.drawPath(_sharedPath, _cubeShadowPaint);
    canvas.drawPath(_sharedPath, _sharedStrokePaint);
  }

  /// 3D Voxel İşçi Otağı & Taşıyıcı Karargahı (Nomad Worker Camp & Logistics Hub)
  static void drawVoxelWorkerCamp(
    Canvas canvas,
    Offset baseCenter, {
    int level = 1,
    double animTime = 0.0,
    bool isNight = false,
  }) {
    final int safeLevel = math.max(1, level);
    final double scale = safeLevel >= 25 ? 1.15 : (safeLevel >= 10 ? 1.05 : 1.0);

    // Taş / Ahşap Zemin Kaidesi
    drawIsoCube(
      canvas,
      baseCenter,
      w: 22.0 * scale,
      d: 20.0 * scale,
      h: safeLevel >= 10 ? 4.0 : 2.5,
      topColor: safeLevel >= 25 ? const Color(0xFF64748B) : const Color(0xFF78350F),
      leftColor: safeLevel >= 25 ? const Color(0xFF475569) : const Color(0xFF5A2408),
      rightColor: safeLevel >= 25 ? const Color(0xFF334155) : const Color(0xFF451A03),
      drawShadow: true,
    );

    // İşçi Keçe Otağı (Yurt)
    final Offset yurtPos = Offset(baseCenter.dx - 4 * cosIso * scale, baseCenter.dy - 2 * scale);
    drawIsoCube(
      canvas,
      yurtPos,
      w: 14.0 * scale,
      d: 14.0 * scale,
      h: (8.0 + (safeLevel >= 10 ? 2.0 : 0.0)) * scale,
      topColor: const Color(0xFFF8FAFC),
      leftColor: const Color(0xFFE2E8F0),
      rightColor: const Color(0xFFCBD5E1),
    );

    // Otağ Göçebe Kırmızı Kuşağı
    _sharedFillPaint.color = safeLevel >= 25 ? const Color(0xFFF59E0B) : const Color(0xFFDC2626);
    canvas.drawRect(
      Rect.fromCenter(center: Offset(yurtPos.dx, yurtPos.dy - 3 * scale), width: 10.0 * scale, height: 1.6),
      _sharedFillPaint,
    );

    // Ahşap Göçebe Kağnı Arabası (Nomad Wooden Logistics Cart)
    final Offset cartPos = Offset(baseCenter.dx + 8 * cosIso * scale, baseCenter.dy + 4 * sinIso * scale);
    drawIsoCube(
      canvas,
      cartPos,
      w: 8.0 * scale,
      d: 6.0 * scale,
      h: 4.0 * scale,
      topColor: const Color(0xFFB45309),
      leftColor: const Color(0xFF92400E),
      rightColor: const Color(0xFF78350F),
    );

    // Kağnı Tekerlekleri
    _sharedFillPaint.color = const Color(0xFF451A03);
    canvas.drawCircle(Offset(cartPos.dx - 3 * scale, cartPos.dy + 2 * scale), 2.2 * scale, _sharedFillPaint);
    canvas.drawCircle(Offset(cartPos.dx + 3 * scale, cartPos.dy + 2 * scale), 2.2 * scale, _sharedFillPaint);

    // Arabadaki Yük Sandıkları & Heybeler
    drawIsoCube(
      canvas,
      Offset(cartPos.dx, cartPos.dy - 4 * scale),
      w: 5.0 * scale,
      d: 5.0 * scale,
      h: 4.0 * scale,
      topColor: safeLevel >= 10 ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
      leftColor: safeLevel >= 10 ? const Color(0xFFF59E0B) : const Color(0xFFB45309),
      rightColor: safeLevel >= 10 ? const Color(0xFFD97706) : const Color(0xFF92400E),
    );

    // Seviye 10+ (1. Sıçrama) Çift Yük Sandığı & Kazma/Kürek Standı
    if (safeLevel >= 10) {
      drawIsoCube(
        canvas,
        Offset(baseCenter.dx - 7 * scale, baseCenter.dy + 5 * scale),
        w: 4.0 * scale,
        d: 4.0 * scale,
        h: 6.0 * scale,
        topColor: const Color(0xFF94A3B8),
        leftColor: const Color(0xFF64748B),
        rightColor: const Color(0xFF475569),
      );
    }

    // Seviye 25+ (2. Sıçrama) Kağanlık Lojistik Tuğu / Bayrağı
    if (safeLevel >= 25) {
      drawIsoCube(
        canvas,
        Offset(yurtPos.dx, yurtPos.dy - 12 * scale),
        w: 2.0,
        d: 2.0,
        h: 8.0,
        topColor: const Color(0xFFFBBF24),
        leftColor: const Color(0xFFF59E0B),
        rightColor: const Color(0xFFD97706),
      );
      drawIsoCube(
        canvas,
        Offset(yurtPos.dx + 2 * cosIso, yurtPos.dy - 16 * scale),
        w: 4.0,
        d: 1.2,
        h: 3.0,
        topColor: const Color(0xFFEF4444),
        leftColor: const Color(0xFFDC2626),
        rightColor: const Color(0xFFB91C1C),
      );
    }

    // Gece Kamp Ateşi
    if (isNight) {
      final double flicker = 0.7 + 0.3 * math.sin(animTime * 5.0);
      _sharedFillPaint.color = const Color(0xFFF59E0B).withValues(alpha: 0.6 * flicker);
      canvas.drawCircle(Offset(baseCenter.dx + 2 * scale, baseCenter.dy + 8 * scale), 4.0 * flicker, _sharedFillPaint);
    }
  }

  /// İnşaat ve Geliştirme Anında Patlayan Voksel Harç & Çakıl Parçacıkları (Construction Poof)
  static void drawVoxelConstructionPoof(Canvas canvas, Offset center, double progress) {
    if (progress <= 0.0 || progress >= 1.0) return;
    const int count = 8;
    final double alpha = (1.0 - progress).clamp(0.0, 1.0);

    for (int i = 0; i < count; i++) {
      final double angle = (i / count) * 2 * math.pi;
      final double dist = progress * 28.0;
      final double arcY = -math.sin(progress * math.pi) * 18.0;

      final Offset pPos = Offset(
        center.dx + math.cos(angle) * dist,
        center.dy + math.sin(angle) * dist * sinIso + arcY,
      );

      final Color pColor = i % 2 == 0 ? const Color(0xFFFFD700) : const Color(0xFFE2E8F0);

      drawIsoCube(
        canvas,
        pPos,
        w: 5.0 * (1.0 - progress * 0.5),
        d: 5.0 * (1.0 - progress * 0.5),
        h: 4.0 * (1.0 - progress * 0.5),
        topColor: pColor.withValues(alpha: alpha),
        leftColor: pColor.withValues(alpha: alpha * 0.8),
        rightColor: pColor.withValues(alpha: alpha * 0.6),
      );
    }
  }

  /// 3D Voxel Ahşap Kazıklı Köprü (Yan trabzanlar ve su üstü kazıkları)
  static void drawVoxelBridge(Canvas canvas, Offset baseCenter) {
    // 1. Su üstü destek kazıkları
    drawIsoCube(
      canvas,
      Offset(baseCenter.dx - 10 * cosIso, baseCenter.dy + 8 * sinIso + 4),
      w: 4.0,
      d: 4.0,
      h: 10.0,
      topColor: const Color(0xFF78350F),
      leftColor: const Color(0xFF5A270B),
      rightColor: const Color(0xFF3F1905),
    );
    drawIsoCube(
      canvas,
      Offset(baseCenter.dx + 10 * cosIso, baseCenter.dy + 8 * sinIso + 4),
      w: 4.0,
      d: 4.0,
      h: 10.0,
      topColor: const Color(0xFF78350F),
      leftColor: const Color(0xFF5A270B),
      rightColor: const Color(0xFF3F1905),
    );

    // 2. Ana Ahşap Platform Tabliyesi
    drawIsoCube(
      canvas,
      baseCenter,
      w: 34.0,
      d: 14.0,
      h: 5.0,
      topColor: const Color(0xFFD97706),
      leftColor: const Color(0xFFB45309),
      rightColor: const Color(0xFF78350F),
      drawShadow: true,
      shadowOpacity: 0.35,
    );

    // 3. Yan Ahşap Korkuluklar / Trabzanlar
    drawIsoCube(
      canvas,
      Offset(baseCenter.dx - 4 * sinIso, baseCenter.dy - 5 - 4 * cosIso),
      w: 34.0,
      d: 2.0,
      h: 4.0,
      topColor: const Color(0xFFFDE68A),
      leftColor: const Color(0xFFD97706),
      rightColor: const Color(0xFFB45309),
    );
    drawIsoCube(
      canvas,
      Offset(baseCenter.dx + 4 * sinIso, baseCenter.dy - 5 + 4 * cosIso),
      w: 34.0,
      d: 2.0,
      h: 4.0,
      topColor: const Color(0xFFFDE68A),
      leftColor: const Color(0xFFD97706),
      rightColor: const Color(0xFFB45309),
    );
  }

  /// 3D Voxel Balıkçı Teknesi (Su üstü salınımı, pruva feneri, ağ ve fıçı - Seviye Kademeli)
  static void drawVoxelFishermanBoat(
    Canvas canvas,
    Offset baseCenter, {
    int level = 1,
    required double animTime,
    bool isNight = false,
  }) {
    final int safeLevel = math.max(1, level);
    final double bobWater = math.sin(animTime * 2.2) * 1.5;
    final Offset pos = Offset(baseCenter.dx, baseCenter.dy + bobWater);

    // İskele Destek Kazığı
    drawIsoCube(
      canvas,
      Offset(pos.dx + 8 * cosIso, pos.dy + 8 * sinIso + 4),
      w: 4.0,
      d: 4.0,
      h: 8.0,
      topColor: const Color(0xFF78350F),
      leftColor: const Color(0xFF5A270B),
      rightColor: const Color(0xFF3F1905),
    );

    // Tekne Gövdesi (Lv 1-2 Meşe, Lv 3-5 Güçlendirilmiş Gövde, Lv 6+ Kağanlık Yelkenlisi)
    final double boatW = safeLevel >= 6 ? 26.0 : (safeLevel >= 3 ? 24.0 : 22.0);
    drawIsoCube(
      canvas,
      pos,
      w: boatW,
      d: 12.0,
      h: (safeLevel >= 3 ? 6.0 : 5.0),
      topColor: safeLevel >= 6 ? const Color(0xFFB45309) : const Color(0xFF92400E),
      leftColor: safeLevel >= 6 ? const Color(0xFF92400E) : const Color(0xFF78350F),
      rightColor: safeLevel >= 6 ? const Color(0xFF78350F) : const Color(0xFF5A270B),
      drawShadow: true,
      shadowOpacity: 0.25,
    );

    // Pruva / Ön Sivri Burun
    drawIsoCube(
      canvas,
      Offset(pos.dx - 8 * cosIso, pos.dy - 3),
      w: 8.0,
      d: 8.0,
      h: 4.0,
      topColor: safeLevel >= 6 ? const Color(0xFFF59E0B) : const Color(0xFFB45309),
      leftColor: safeLevel >= 6 ? const Color(0xFFD97706) : const Color(0xFF92400E),
      rightColor: safeLevel >= 6 ? const Color(0xFFB45309) : const Color(0xFF78350F),
    );

    // Balıkçı Direği / Yelken
    drawIsoCube(
      canvas,
      Offset(pos.dx + 2, pos.dy - 5),
      w: 2.5,
      d: 2.5,
      h: (14.0 + (safeLevel >= 3 ? 4.0 : 0.0)),
      topColor: const Color(0xFFFDE68A),
      leftColor: const Color(0xFFD97706),
      rightColor: const Color(0xFFB45309),
    );

    // Seviye 3+ Beyaz Balıkçı Yelkeni
    if (safeLevel >= 3) {
      drawIsoCube(
        canvas,
        Offset(pos.dx + 4, pos.dy - 12),
        w: 6.0,
        d: 1.5,
        h: 8.0,
        topColor: const Color(0xFFF8FAFC),
        leftColor: const Color(0xFFE2E8F0),
        rightColor: const Color(0xFFCBD5E1),
      );
    }

    // Direk Ucu Fener (Gece parıldayan sarı ışık)
    drawIsoCube(
      canvas,
      Offset(pos.dx + 2, pos.dy - (19 + (safeLevel >= 3 ? 4.0 : 0.0))),
      w: 4.0,
      d: 4.0,
      h: 4.0,
      topColor: isNight ? const Color(0xFFFEF08A) : const Color(0xFFFDE047),
      leftColor: isNight ? const Color(0xFFFACC15) : const Color(0xFFEAB308),
      rightColor: isNight ? const Color(0xFFEAB308) : const Color(0xFFCA8A04),
    );

    // Balık Ağı / Varil
    drawIsoCube(
      canvas,
      Offset(pos.dx + 6 * cosIso, pos.dy - 4 + 3 * sinIso),
      w: 5.0,
      d: 5.0,
      h: 4.0,
      topColor: const Color(0xFF0284C7),
      leftColor: const Color(0xFF0369A1),
      rightColor: const Color(0xFF075985),
    );

    // Seviye 6+ İkinci Balık Sepeti & Altın Ejder/Kartal Pruva Başı
    if (safeLevel >= 6) {
      drawIsoCube(
        canvas,
        Offset(pos.dx - 12 * cosIso, pos.dy - 6),
        w: 4.0,
        d: 4.0,
        h: 5.0,
        topColor: const Color(0xFFFDE047),
        leftColor: const Color(0xFFEAB308),
        rightColor: const Color(0xFFCA8A04),
      );
    }
  }

  /// 3D Voxel Balıkçı Kulübesi & İskele (Sazdan çatı, iskele platformu ve fıçı - Seviye Kademeli)
  static void drawVoxelFishermanHut(
    Canvas canvas,
    Offset baseCenter, {
    int level = 1,
    required double animTime,
    bool isNight = false,
  }) {
    final int safeLevel = math.max(1, level);
    final double pierW = safeLevel >= 6 ? 28.0 : (safeLevel >= 3 ? 26.0 : 24.0);

    // 1. İskele Platformu
    drawIsoCube(
      canvas,
      baseCenter,
      w: pierW,
      d: 20.0,
      h: 4.0,
      topColor: const Color(0xFFB45309),
      leftColor: const Color(0xFF92400E),
      rightColor: const Color(0xFF78350F),
      drawShadow: true,
      shadowOpacity: 0.3,
    );

    // İskele Destek Kazıkları
    drawIsoCube(
      canvas,
      Offset(baseCenter.dx - 8 * cosIso, baseCenter.dy + 8 * sinIso + 4),
      w: 3.5,
      d: 3.5,
      h: 8.0,
      topColor: const Color(0xFF78350F),
      leftColor: const Color(0xFF5A270B),
      rightColor: const Color(0xFF3F1905),
    );
    drawIsoCube(
      canvas,
      Offset(baseCenter.dx + 8 * cosIso, baseCenter.dy + 8 * sinIso + 4),
      w: 3.5,
      d: 3.5,
      h: 8.0,
      topColor: const Color(0xFF78350F),
      leftColor: const Color(0xFF5A270B),
      rightColor: const Color(0xFF3F1905),
    );

    // 2. Ahşap Kulübe Gövdesi
    drawIsoCube(
      canvas,
      Offset(baseCenter.dx - 2, baseCenter.dy - 4),
      w: (14.0 + (safeLevel >= 3 ? 2.0 : 0.0)),
      d: 14.0,
      h: (12.0 + (safeLevel >= 3 ? 2.0 : 0.0)),
      topColor: const Color(0xFFD97706),
      leftColor: const Color(0xFFB45309),
      rightColor: const Color(0xFF92400E),
    );

    // 3. Saz / Saman / Kiremit Çatı
    drawIsoCube(
      canvas,
      Offset(baseCenter.dx - 2, baseCenter.dy - (16 + (safeLevel >= 3 ? 2.0 : 0.0))),
      w: (16.0 + (safeLevel >= 3 ? 2.0 : 0.0)),
      d: 16.0,
      h: 6.0,
      topColor: safeLevel >= 6 ? const Color(0xFFDC2626) : const Color(0xFFFEF08A),
      leftColor: safeLevel >= 6 ? const Color(0xFFB91C1C) : const Color(0xFFFDE047),
      rightColor: safeLevel >= 6 ? const Color(0xFF991B1B) : const Color(0xFFEAB308),
    );

    // 4. Balık Varili
    drawIsoCube(
      canvas,
      Offset(baseCenter.dx + 7 * cosIso, baseCenter.dy - 4 + 6 * sinIso),
      w: 4.5,
      d: 4.5,
      h: 6.0,
      topColor: const Color(0xFF0284C7),
      leftColor: const Color(0xFF0369A1),
      rightColor: const Color(0xFF075985),
    );

    // Seviye 3+ Balık Kurutma Askısı
    if (safeLevel >= 3) {
      drawIsoCube(
        canvas,
        Offset(baseCenter.dx - 8 * cosIso, baseCenter.dy - 8),
        w: 4.0,
        d: 8.0,
        h: 6.0,
        topColor: const Color(0xFFFDE68A),
        leftColor: const Color(0xFFF59E0B),
        rightColor: const Color(0xFFD97706),
      );
    }

    // Seviye 6+ Liman Vinci & Kule
    if (safeLevel >= 6) {
      drawIsoCube(
        canvas,
        Offset(baseCenter.dx + 10 * cosIso, baseCenter.dy - 10),
        w: 4.0,
        d: 4.0,
        h: 12.0,
        topColor: const Color(0xFF78350F),
        leftColor: const Color(0xFF5A270B),
        rightColor: const Color(0xFF3F1905),
      );
    }

    // Gece Feneri
    if (isNight) {
      drawIsoCube(
        canvas,
        Offset(baseCenter.dx - 6, baseCenter.dy - 12),
        w: 3.0,
        d: 3.0,
        h: 3.0,
        topColor: const Color(0xFFFFE066),
        leftColor: const Color(0xFFFACC15),
        rightColor: const Color(0xFFEAB308),
      );
    }
  }

  /// 3D Voxel Kadim Göktürk Rünik Dikilitaş / Sunak
  /// Türüne göre parıldayan rünik çekirdek ve havada asılı mistik faset bloklar
  static void drawVoxelAncientShrine(
    Canvas canvas,
    Offset baseCenter, {
    required ShrineType shrineType,
    required double animTime,
    bool isNight = false,
  }) {
    // 1. Granit Taş Kaide
    drawIsoCube(
      canvas,
      baseCenter,
      w: 22.0,
      d: 22.0,
      h: 5.0,
      topColor: const Color(0xFF334155),
      leftColor: const Color(0xFF1E293B),
      rightColor: const Color(0xFF0F172A),
      drawShadow: true,
      shadowOpacity: 0.4,
    );

    // 2. Monolitik Dikilitaş Gövdesi (Orhun Taşları Formu)
    drawIsoCube(
      canvas,
      Offset(baseCenter.dx, baseCenter.dy - 5),
      w: 12.0,
      d: 12.0,
      h: 24.0,
      topColor: const Color(0xFF1E293B),
      leftColor: const Color(0xFF0F172A),
      rightColor: const Color(0xFF020617),
    );

    // 3. Rünik Çekirdek Rengi Belirleme
    Color runeTop;
    Color runeLeft;
    Color runeRight;
    switch (shrineType) {
      case ShrineType.foodBoost:
        runeTop = const Color(0xFF34D399);
        runeLeft = const Color(0xFF10B981);
        runeRight = const Color(0xFF059669);
        break;
      case ShrineType.woodBoost:
        runeTop = const Color(0xFFFBBF24);
        runeLeft = const Color(0xFFF59E0B);
        runeRight = const Color(0xFFD97706);
        break;
      case ShrineType.speedBoost:
      case ShrineType.none:
        runeTop = const Color(0xFF38BDF8);
        runeLeft = const Color(0xFF0EA5E9);
        runeRight = const Color(0xFF0284C7);
        break;
    }

    // Gövde Üzerindeki Parlayan Rün Yuvası
    drawIsoCube(
      canvas,
      Offset(baseCenter.dx, baseCenter.dy - 17),
      w: 6.0,
      d: 6.0,
      h: 6.0,
      topColor: runeTop,
      leftColor: runeLeft,
      rightColor: runeRight,
    );

    // 4. Havada Asılı Mistik Süzülen Rünik Parçacıklar (Levitating Voxel Runes)
    final double float1 = math.sin(animTime * 2.5) * 3.5;
    final double float2 = math.cos(animTime * 2.0 + 1.0) * 3.0;

    drawIsoCube(
      canvas,
      Offset(baseCenter.dx - 10 * cosIso, baseCenter.dy - 28 + float1),
      w: 4.0,
      d: 4.0,
      h: 4.0,
      topColor: runeTop,
      leftColor: runeLeft,
      rightColor: runeRight,
    );

    drawIsoCube(
      canvas,
      Offset(baseCenter.dx + 10 * cosIso, baseCenter.dy - 30 + float2),
      w: 4.0,
      d: 4.0,
      h: 4.0,
      topColor: runeTop,
      leftColor: runeLeft,
      rightColor: runeRight,
    );
  }

  /// 3D Voxel Bulut
  static void drawVoxelCloud(Canvas canvas, Offset pos, {double scale = 1.0}) {
    drawIsoCube(
      canvas,
      pos,
      w: 24.0 * scale,
      d: 18.0 * scale,
      h: 10.0 * scale,
      topColor: Colors.white,
      leftColor: const Color(0xFFF1F5F9),
      rightColor: const Color(0xFFE2E8F0),
    );

    drawIsoCube(
      canvas,
      Offset(pos.dx + 12 * cosIso * scale, pos.dy + 6 * sinIso * scale),
      w: 16.0 * scale,
      d: 14.0 * scale,
      h: 8.0 * scale,
      topColor: Colors.white,
      leftColor: const Color(0xFFF8FAFC),
      rightColor: const Color(0xFFE2E8F0),
    );
  }

  /// 3D Voxel İnsan / İşçi (Yön Tayini, Kıyafet & Başlık Varyantları, Çalışma/Taşıma/Dinlenme Animasyonları)
  static void drawVoxelWorker(
    Canvas canvas,
    Offset pos, {
    required Color cargoColor,
    required double walkAnim,
    bool hasCargo = true,
    bool facingLeft = false,
    int seed = 0,
    int actionState = 0, // 0: walking, 1: working/loading, 2: unloading/resting
  }) {
    final double flipX = facingLeft ? -1.0 : 1.0;
    final int archetype = seed % 4;

    // Giysi ve Başlık Renk Paletleri
    Color clothesTop;
    Color clothesLeft;
    Color clothesRight;
    Color hatTop;
    Color hatLeft;
    Color hatRight;

    switch (archetype) {
      case 0: // Bozkır Göçeri (Turkuaz Kaftan + Sivri Keçe Börk)
        clothesTop = const Color(0xFF0284C7);
        clothesLeft = const Color(0xFF0369A1);
        clothesRight = const Color(0xFF075985);
        hatTop = const Color(0xFF92400E);
        hatLeft = const Color(0xFF78350F);
        hatRight = const Color(0xFF451A03);
        break;
      case 1: // Usta / Demirci (Koyu Deri Önlük + Kırmızı Bandana)
        clothesTop = const Color(0xFF475569);
        clothesLeft = const Color(0xFF334155);
        clothesRight = const Color(0xFF1E293B);
        hatTop = const Color(0xFFDC2626);
        hatLeft = const Color(0xFFB91C1C);
        hatRight = const Color(0xFF991B1B);
        break;
      case 2: // Hasatçı / Çiftçi (Doğal Keten Gömlek + Hasır Şapka)
        clothesTop = const Color(0xFFF1F5F9);
        clothesLeft = const Color(0xFFE2E8F0);
        clothesRight = const Color(0xFFCBD5E1);
        hatTop = const Color(0xFFFBBF24);
        hatLeft = const Color(0xFFD97706);
        hatRight = const Color(0xFFB45309);
        break;
      case 3: // Ormancı / Avcı (Orman Yeşili Giysi + Kahve Başlık)
      default:
        clothesTop = const Color(0xFF15803D);
        clothesLeft = const Color(0xFF166534);
        clothesRight = const Color(0xFF14532D);
        hatTop = const Color(0xFF78350F);
        hatLeft = const Color(0xFF5A270B);
        hatRight = const Color(0xFF3F1905);
        break;
    }

    double bobY = 0.0;
    double bodyTilt = 0.0;
    double armSwing = 0.0;
    double toolMotion = 0.0;

    if (actionState == 0) {
      // YÜRÜME: İki zamanlı gerçek adım yaylanması
      bobY = math.sin(walkAnim * 2.0).abs() * 2.8;
      armSwing = math.sin(walkAnim) * 3.0;
      bodyTilt = math.sin(walkAnim) * 0.6 * flipX;
    } else if (actionState == 1) {
      // ÇALIŞMA / YÜKLEME: Eğilme ve alet sallama ritmi
      toolMotion = math.sin(walkAnim * 2.5).abs() * 5.0;
      bobY = math.sin(walkAnim * 2.5).abs() * 1.5;
      bodyTilt = 1.5 * flipX;
    } else {
      // BOŞALTMA / ALIN TERİNİ SİLME / ESNEME:
      final double breath = math.sin(walkAnim * 1.5) * 0.8;
      bobY = breath;
      armSwing = math.sin(walkAnim * 1.2) * 2.0;
    }

    // 1. Ayaklar / Adımlar (Feet Stride Voxels)
    if (actionState == 0) {
      final double leftStep = math.sin(walkAnim) * 2.5;
      final double rightStep = -leftStep;

      // Sol Ayak
      drawIsoCube(
        canvas,
        Offset(pos.dx + (leftStep - 1.5) * flipX, pos.dy + 1.0 - (leftStep > 0 ? leftStep * 0.5 : 0)),
        w: 2.5,
        d: 2.5,
        h: 3.0,
        topColor: const Color(0xFF1E293B),
        leftColor: const Color(0xFF0F172A),
        rightColor: const Color(0xFF020617),
      );
      // Sağ Ayak
      drawIsoCube(
        canvas,
        Offset(pos.dx + (rightStep + 1.5) * flipX, pos.dy + 1.0 - (rightStep > 0 ? rightStep * 0.5 : 0)),
        w: 2.5,
        d: 2.5,
        h: 3.0,
        topColor: const Color(0xFF1E293B),
        leftColor: const Color(0xFF0F172A),
        rightColor: const Color(0xFF020617),
      );
    }

    // 2. Gövde (Body / Kaftan)
    drawIsoCube(
      canvas,
      Offset(pos.dx + bodyTilt, pos.dy - bobY),
      w: 6.0,
      d: 6.0,
      h: 8.0,
      topColor: clothesTop,
      leftColor: clothesLeft,
      rightColor: clothesRight,
      drawShadow: true,
      shadowOpacity: 0.35,
    );

    // Kollar (Arms)
    if (hasCargo) {
      // Yük taşırken kollar kargo kutusunu tutar
      drawIsoCube(
        canvas,
        Offset(pos.dx + (3.5 * flipX) + bodyTilt, pos.dy - 3.0 - bobY),
        w: 2.0,
        d: 2.0,
        h: 4.0,
        topColor: clothesTop,
        leftColor: clothesLeft,
        rightColor: clothesRight,
      );
    } else if (actionState == 1) {
      // Çalışırken alet tutan el yukarı aşağı hareket eder
      drawIsoCube(
        canvas,
        Offset(pos.dx + (4.0 * flipX) + bodyTilt, pos.dy - 6.0 - bobY - toolMotion),
        w: 2.0,
        d: 2.0,
        h: 4.0,
        topColor: const Color(0xFFFED7AA),
        leftColor: const Color(0xFFFDBA74),
        rightColor: const Color(0xFFFB923C),
      );
      // Minik Kazma / Balta Aleti (Voxel Tool)
      drawIsoCube(
        canvas,
        Offset(pos.dx + (6.0 * flipX) + bodyTilt, pos.dy - 9.0 - bobY - toolMotion),
        w: 2.0,
        d: 4.5,
        h: 2.0,
        topColor: const Color(0xFF94A3B8),
        leftColor: const Color(0xFF64748B),
        rightColor: const Color(0xFF475569),
      );
    } else {
      // Boş yürürken kollar ters salınır
      drawIsoCube(
        canvas,
        Offset(pos.dx - (3.5 * flipX) - armSwing, pos.dy - 2.0 - bobY),
        w: 2.0,
        d: 2.0,
        h: 4.0,
        topColor: clothesTop,
        leftColor: clothesLeft,
        rightColor: clothesRight,
      );
    }

    // 3. Kafa (Head)
    final Offset headPos = Offset(pos.dx + (bodyTilt * 1.5), pos.dy - 8.0 - bobY);
    drawIsoCube(
      canvas,
      headPos,
      w: 5.5,
      d: 5.5,
      h: 5.5,
      topColor: const Color(0xFFFED7AA),
      leftColor: const Color(0xFFFDBA74),
      rightColor: const Color(0xFFFB923C),
    );

    // 4. Başlık / Şapka / Börk (Hat / Cap)
    drawIsoCube(
      canvas,
      Offset(headPos.dx, headPos.dy - 4.5),
      w: 6.0,
      d: 6.0,
      h: 3.5,
      topColor: hatTop,
      leftColor: hatLeft,
      rightColor: hatRight,
    );
    // Börk Sivri Tepesi
    if (archetype == 0 || archetype == 3) {
      drawIsoCube(
        canvas,
        Offset(headPos.dx, headPos.dy - 7.0),
        w: 3.0,
        d: 3.0,
        h: 2.5,
        topColor: hatTop,
        leftColor: hatLeft,
        rightColor: hatRight,
      );
    }

    // 5. Kargo / Sırt Yükü (Cargo Cube)
    if (hasCargo) {
      drawIsoCube(
        canvas,
        Offset(pos.dx + (4.5 * flipX) * cosIso, pos.dy - 4.0 - bobY + 4.0 * sinIso),
        w: 5.5,
        d: 5.5,
        h: 5.5,
        topColor: cargoColor,
        leftColor: cargoColor.withValues(alpha: 0.85),
        rightColor: cargoColor.withValues(alpha: 0.65),
      );
    }
  }

  // ==========================================
  // YENİ BİYOM VOKSEL ÇİZİCİLERİ & DETAYLARI
  // ==========================================

  /// Çöl (Karakum): Katmanlı Kum Tepesi
  static void drawVoxelSandDunes(Canvas canvas, Offset center, {double scale = 1.0}) {
    drawIsoCube(
      canvas,
      center,
      w: 26.0 * scale,
      d: 18.0 * scale,
      h: 5.0 * scale,
      topColor: const Color(0xFFFDE68A),
      leftColor: const Color(0xFFF59E0B),
      rightColor: const Color(0xFFD97706),
      drawShadow: true,
      shadowOpacity: 0.25,
    );
    drawIsoCube(
      canvas,
      Offset(center.dx + 4 * scale, center.dy - 5.0 * scale),
      w: 16.0 * scale,
      d: 12.0 * scale,
      h: 4.0 * scale,
      topColor: const Color(0xFFFEF08A),
      leftColor: const Color(0xFFFBBF24),
      rightColor: const Color(0xFFF59E0B),
    );
  }

  /// Çöl: Voksel Bozkır Kaktüsü / Kurak Diken
  static void drawVoxelCactus(Canvas canvas, Offset center, {double scale = 1.0}) {
    // Gövde
    drawIsoCube(
      canvas,
      center,
      w: 6.0 * scale,
      d: 6.0 * scale,
      h: 16.0 * scale,
      topColor: const Color(0xFF15803D),
      leftColor: const Color(0xFF166534),
      rightColor: const Color(0xFF14532D),
      drawShadow: true,
      shadowOpacity: 0.3,
    );
    // Sol Dal
    drawIsoCube(
      canvas,
      Offset(center.dx - 5.0 * scale, center.dy - 6.0 * scale),
      w: 4.0 * scale,
      d: 4.0 * scale,
      h: 8.0 * scale,
      topColor: const Color(0xFF16A34A),
      leftColor: const Color(0xFF15803D),
      rightColor: const Color(0xFF166534),
    );
    // Sağ Dal
    drawIsoCube(
      canvas,
      Offset(center.dx + 5.0 * scale, center.dy - 9.0 * scale),
      w: 4.0 * scale,
      d: 4.0 * scale,
      h: 7.0 * scale,
      topColor: const Color(0xFF16A34A),
      leftColor: const Color(0xFF15803D),
      rightColor: const Color(0xFF166534),
    );
  }

  /// Çöl: Kurak Bozkır Çalısı
  static void drawVoxelDesertShrub(Canvas canvas, Offset center, {double scale = 1.0}) {
    drawIsoCube(
      canvas,
      center,
      w: 8.0 * scale,
      d: 8.0 * scale,
      h: 6.0 * scale,
      topColor: const Color(0xFFCA8A04),
      leftColor: const Color(0xFFA16207),
      rightColor: const Color(0xFF854D0E),
    );
  }

  /// Tundra: Donmuş Kaya Sütunu / Dikilitaş (Permafrost Spire)
  static void drawVoxelPermafrostSpire(Canvas canvas, Offset center, {double scale = 1.0}) {
    drawIsoCube(
      canvas,
      center,
      w: 14.0 * scale,
      d: 14.0 * scale,
      h: 8.0 * scale,
      topColor: const Color(0xFF64748B),
      leftColor: const Color(0xFF475569),
      rightColor: const Color(0xFF334155),
      drawShadow: true,
    );
    drawIsoCube(
      canvas,
      Offset(center.dx, center.dy - 8.0 * scale),
      w: 8.0 * scale,
      d: 8.0 * scale,
      h: 12.0 * scale,
      topColor: const Color(0xFF93C5FD),
      leftColor: const Color(0xFF60A5FA),
      rightColor: const Color(0xFF3B82F6),
    );
  }

  /// Tundra: Yosunlu Arktik Taşlar
  static void drawVoxelLichenRocks(Canvas canvas, Offset center, {double scale = 1.0}) {
    drawIsoCube(
      canvas,
      center,
      w: 10.0 * scale,
      d: 10.0 * scale,
      h: 5.0 * scale,
      topColor: const Color(0xFF65A30D),
      leftColor: const Color(0xFF475569),
      rightColor: const Color(0xFF334155),
    );
    drawIsoCube(
      canvas,
      Offset(center.dx + 8 * scale, center.dy + 3 * scale),
      w: 7.0 * scale,
      d: 7.0 * scale,
      h: 4.0 * scale,
      topColor: const Color(0xFF84CC16),
      leftColor: const Color(0xFF64748B),
      rightColor: const Color(0xFF475569),
    );
  }

  /// Volkan: Obsidiyen Masif Sütunları
  static void drawVoxelObsidianPillars(Canvas canvas, Offset center, {double scale = 1.0, double animTime = 0.0}) {
    drawIsoCube(
      canvas,
      center,
      w: 16.0 * scale,
      d: 16.0 * scale,
      h: 12.0 * scale,
      topColor: const Color(0xFF1E293B),
      leftColor: const Color(0xFF0F172A),
      rightColor: const Color(0xFF020617),
      drawShadow: true,
    );
    // Siyah Sivri Prizma
    drawIsoCube(
      canvas,
      Offset(center.dx + 4 * scale, center.dy - 12.0 * scale),
      w: 8.0 * scale,
      d: 8.0 * scale,
      h: 14.0 * scale,
      topColor: const Color(0xFF334155),
      leftColor: const Color(0xFF1E293B),
      rightColor: const Color(0xFF0F172A),
    );
  }

  /// Volkan: Lav Çatlağı / Magma Menfezi
  static void drawVoxelMagmaVent(Canvas canvas, Offset center, {double scale = 1.0, double animTime = 0.0}) {
    final double pulse = (math.sin(animTime * 3.0) + 1.0) * 0.5;
    final Color magmaColor = Color.lerp(const Color(0xFFEA580C), const Color(0xFFFBBF24), pulse)!;

    drawIsoCube(
      canvas,
      center,
      w: 12.0 * scale,
      d: 12.0 * scale,
      h: 3.0 * scale,
      topColor: magmaColor,
      leftColor: const Color(0xFFDC2626),
      rightColor: const Color(0xFF991B1B),
    );
  }

  /// Sazlık: Bozkır Kamışları & Sazlar
  static void drawVoxelReeds(Canvas canvas, Offset center, {double scale = 1.0, double animTime = 0.0}) {
    final double windSway = math.sin(animTime * 2.5) * 1.5 * scale;

    drawIsoCube(
      canvas,
      Offset(center.dx - 4 * scale + windSway, center.dy),
      w: 3.0 * scale,
      d: 3.0 * scale,
      h: 14.0 * scale,
      topColor: const Color(0xFF65A30D),
      leftColor: const Color(0xFF4D7C0F),
      rightColor: const Color(0xFF3F6212),
    );
    drawIsoCube(
      canvas,
      Offset(center.dx + 3 * scale + windSway * 0.8, center.dy + 2 * scale),
      w: 3.0 * scale,
      d: 3.0 * scale,
      h: 16.0 * scale,
      topColor: const Color(0xFF84CC16),
      leftColor: const Color(0xFF65A30D),
      rightColor: const Color(0xFF4D7C0F),
    );
    drawIsoCube(
      canvas,
      Offset(center.dx - 1 * scale, center.dy + 4 * scale),
      w: 3.0 * scale,
      d: 3.0 * scale,
      h: 11.0 * scale,
      topColor: const Color(0xFF4D7C0F),
      leftColor: const Color(0xFF3F6212),
      rightColor: const Color(0xFF365314),
    );
  }

  /// Sazlık: Nilüfer Yaprağı ve Çiçeği
  static void drawVoxelWaterLilies(Canvas canvas, Offset center, {double scale = 1.0}) {
    drawIsoCube(
      canvas,
      center,
      w: 8.0 * scale,
      d: 8.0 * scale,
      h: 1.5 * scale,
      topColor: const Color(0xFF10B981),
      leftColor: const Color(0xFF059669),
      rightColor: const Color(0xFF047857),
    );
    drawIsoCube(
      canvas,
      Offset(center.dx, center.dy - 1.5 * scale),
      w: 3.0 * scale,
      d: 3.0 * scale,
      h: 2.5 * scale,
      topColor: const Color(0xFFF472B6),
      leftColor: const Color(0xFFEC4899),
      rightColor: const Color(0xFFDB2777),
    );
  }

  /// Mevsimsel: Bahar Gelincikleri / Kır Laleleri
  static void drawVoxelSpringPoppies(Canvas canvas, Offset center, {double scale = 1.0}) {
    drawIsoCube(
      canvas,
      center,
      w: 4.0 * scale,
      d: 4.0 * scale,
      h: 4.0 * scale,
      topColor: const Color(0xFFEF4444),
      leftColor: const Color(0xFFDC2626),
      rightColor: const Color(0xFFB91C1C),
    );
    drawIsoCube(
      canvas,
      Offset(center.dx + 6 * scale, center.dy + 4 * scale),
      w: 3.0 * scale,
      d: 3.0 * scale,
      h: 3.0 * scale,
      topColor: const Color(0xFFF59E0B),
      leftColor: const Color(0xFFD97706),
      rightColor: const Color(0xFFB45309),
    );
  }

  /// Mevsimsel: Sonbahar Kızıl Yaprak Kümesi
  static void drawVoxelAutumnFoliage(Canvas canvas, Offset center, {double scale = 1.0}) {
    drawIsoCube(
      canvas,
      center,
      w: 8.0 * scale,
      d: 8.0 * scale,
      h: 3.0 * scale,
      topColor: const Color(0xFFEA580C),
      leftColor: const Color(0xFFC2410C),
      rightColor: const Color(0xFF9A3412),
    );
  }

  /// Mevsimsel: Kış Kıyı Buz Kütleleri (Ice Floes)
  static void drawVoxelIceFloes(Canvas canvas, Offset center, {double scale = 1.0, double animTime = 0.0}) {
    final double bob = math.sin(animTime * 1.5) * 1.0;
    drawIsoCube(
      canvas,
      Offset(center.dx, center.dy + bob),
      w: 12.0 * scale,
      d: 8.0 * scale,
      h: 2.0 * scale,
      topColor: const Color(0xFFE0F2FE),
      leftColor: const Color(0xFFBAE6FD),
      rightColor: const Color(0xFF7DD3FC),
    );
  }

  // ==========================================
  // ÖZEL ÇÖL BİNALARI (DESERT EXCLUSIVES)
  // ==========================================

  /// Vaha Sarnıcı (Oasis Cistern - Seviye Kademeli)
  static void drawVoxelOasisCistern(
    Canvas canvas,
    Offset center, {
    int level = 1,
    double scale = 1.0,
    double animTime = 0.0,
  }) {
    final int safeLevel = math.max(1, level);
    final double poolW = safeLevel >= 6 ? 22.0 : (safeLevel >= 3 ? 20.0 : 18.0);

    // Taş taban havuzu (Lv 1-2 Kumtaşı, Lv 3-5 Taş Su Arkı, Lv 6+ Mermer Mozaik)
    drawIsoCube(
      canvas,
      Offset(center.dx, center.dy + 4 * scale),
      w: poolW * scale,
      d: poolW * scale,
      h: (safeLevel >= 3 ? 5.0 : 4.0) * scale,
      topColor: safeLevel >= 6 ? const Color(0xFFF1F5F9) : const Color(0xFFD97706),
      leftColor: safeLevel >= 6 ? const Color(0xFFCBD5E1) : const Color(0xFFB45309),
      rightColor: safeLevel >= 6 ? const Color(0xFF94A3B8) : const Color(0xFF92400E),
    );
    // Berrak turkuaz su
    final double ripple = math.sin(animTime * 2.0) * 0.5;
    drawIsoCube(
      canvas,
      Offset(center.dx, center.dy + (2 + ripple) * scale),
      w: (poolW - 6.0) * scale,
      d: (poolW - 6.0) * scale,
      h: 2.0 * scale,
      topColor: const Color(0xFF38BDF8),
      leftColor: const Color(0xFF0284C7),
      rightColor: const Color(0xFF0369A1),
    );
    // Hurma ağacı 1 (Ana Palmiye)
    drawIsoCube(
      canvas,
      Offset(center.dx - 8 * scale, center.dy - 6 * scale),
      w: 3.0 * scale,
      d: 3.0 * scale,
      h: (12.0 + (safeLevel >= 3 ? 3.0 : 0.0)) * scale,
      topColor: const Color(0xFF78350F),
      leftColor: const Color(0xFF5A2408),
      rightColor: const Color(0xFF451A03),
    );
    drawIsoCube(
      canvas,
      Offset(center.dx - 8 * scale, center.dy - (18 + (safeLevel >= 3 ? 3.0 : 0.0)) * scale),
      w: 10.0 * scale,
      d: 10.0 * scale,
      h: 4.0 * scale,
      topColor: const Color(0xFF65A30D),
      leftColor: const Color(0xFF4D7C0F),
      rightColor: const Color(0xFF3F6212),
    );

    // Seviye 3+ İkinci Palmiye & Testi/Kupa Standı
    if (safeLevel >= 3) {
      drawIsoCube(
        canvas,
        Offset(center.dx + 8 * scale, center.dy - 2 * scale),
        w: 2.5 * scale,
        d: 2.5 * scale,
        h: 10.0 * scale,
        topColor: const Color(0xFF78350F),
        leftColor: const Color(0xFF5A2408),
        rightColor: const Color(0xFF451A03),
      );
      drawIsoCube(
        canvas,
        Offset(center.dx + 8 * scale, center.dy - 12 * scale),
        w: 8.0 * scale,
        d: 8.0 * scale,
        h: 3.5 * scale,
        topColor: const Color(0xFF84CC16),
        leftColor: const Color(0xFF65A30D),
        rightColor: const Color(0xFF4D7C0F),
      );
    }

    // Seviye 6+ Altın Fıskiye ve Gölgelik
    if (safeLevel >= 6) {
      drawIsoCube(
        canvas,
        Offset(center.dx, center.dy - 4 * scale),
        w: 4.0 * scale,
        d: 4.0 * scale,
        h: 6.0 * scale,
        topColor: const Color(0xFFFDE047),
        leftColor: const Color(0xFFEAB308),
        rightColor: const Color(0xFFCA8A04),
      );
    }
  }

  /// İpek Yolu Kervansarayı (Silk Road Caravanserai - Seviye Kademeli)
  static void drawVoxelCaravanserai(
    Canvas canvas,
    Offset center, {
    int level = 1,
    double scale = 1.0,
    double animTime = 0.0,
  }) {
    final int safeLevel = math.max(1, level);
    final double fortW = safeLevel >= 6 ? 26.0 : (safeLevel >= 3 ? 24.0 : 22.0);

    // Kumtaşı kale avlusu
    drawIsoCube(
      canvas,
      Offset(center.dx, center.dy + 2 * scale),
      w: fortW * scale,
      d: fortW * scale,
      h: (safeLevel >= 3 ? 10.0 : 8.0) * scale,
      topColor: safeLevel >= 6 ? const Color(0xFFFDE68A) : const Color(0xFFFDE68A),
      leftColor: safeLevel >= 6 ? const Color(0xFFD97706) : const Color(0xFFF59E0B),
      rightColor: safeLevel >= 6 ? const Color(0xFFB45309) : const Color(0xFFD97706),
    );
    // İç avlu kumaş gölgeliği (Kırmızı-Sarı Tente)
    final double sway = math.sin(animTime * 1.8) * 0.6;
    drawIsoCube(
      canvas,
      Offset(center.dx, center.dy - (6 + sway) * scale),
      w: 12.0 * scale,
      d: 12.0 * scale,
      h: 2.0 * scale,
      topColor: const Color(0xFFDC2626),
      leftColor: const Color(0xFFB91C1C),
      rightColor: const Color(0xFF991B1B),
    );
    // Ahşap kervan kapısı kulesi
    drawIsoCube(
      canvas,
      Offset(center.dx, center.dy - 10 * scale),
      w: 6.0 * scale,
      d: 6.0 * scale,
      h: (8.0 + (safeLevel >= 3 ? 4.0 : 0.0)) * scale,
      topColor: const Color(0xFFFBBF24),
      leftColor: const Color(0xFFD97706),
      rightColor: const Color(0xFFB45309),
    );

    // Seviye 3+ Çift Gözcü Kulesi
    if (safeLevel >= 3) {
      drawIsoCube(
        canvas,
        Offset(center.dx - 10 * scale, center.dy - 4 * scale),
        w: 5.0 * scale,
        d: 5.0 * scale,
        h: 12.0 * scale,
        topColor: const Color(0xFFFDE68A),
        leftColor: const Color(0xFFF59E0B),
        rightColor: const Color(0xFFD97706),
      );
      drawIsoCube(
        canvas,
        Offset(center.dx + 10 * scale, center.dy - 4 * scale),
        w: 5.0 * scale,
        d: 5.0 * scale,
        h: 12.0 * scale,
        topColor: const Color(0xFFFDE68A),
        leftColor: const Color(0xFFF59E0B),
        rightColor: const Color(0xFFD97706),
      );
    }

    // Seviye 6+ Altın Kubbe ve Tüccar Bayrakları
    if (safeLevel >= 6) {
      drawIsoCube(
        canvas,
        Offset(center.dx, center.dy - 16 * scale),
        w: 8.0 * scale,
        d: 8.0 * scale,
        h: 5.0 * scale,
        topColor: const Color(0xFFFDE047),
        leftColor: const Color(0xFFEAB308),
        rightColor: const Color(0xFFCA8A04),
      );
    }
  }

  /// Gök Gözlemevi (Desert Astrolabe - Seviye Kademeli)
  static void drawVoxelAstrolabe(
    Canvas canvas,
    Offset center, {
    int level = 1,
    double scale = 1.0,
    double animTime = 0.0,
  }) {
    final int safeLevel = math.max(1, level);
    final double baseW = safeLevel >= 6 ? 18.0 : (safeLevel >= 3 ? 16.0 : 14.0);

    // Silindirik mermer/pirinç taban
    drawIsoCube(
      canvas,
      Offset(center.dx, center.dy + 4 * scale),
      w: baseW * scale,
      d: baseW * scale,
      h: (10.0 + (safeLevel >= 3 ? 3.0 : 0.0)) * scale,
      topColor: safeLevel >= 6 ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
      leftColor: safeLevel >= 6 ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1),
      rightColor: safeLevel >= 6 ? const Color(0xFF020617) : const Color(0xFF94A3B8),
    );
    // Dönen göksel pirinç halkalar
    final double spin = math.sin(animTime * 2.2) * 2.0;
    drawIsoCube(
      canvas,
      Offset(center.dx + spin * scale, center.dy - (8 + (safeLevel >= 3 ? 3.0 : 0.0)) * scale),
      w: (8.0 + (safeLevel >= 3 ? 2.0 : 0.0)) * scale,
      d: (8.0 + (safeLevel >= 3 ? 2.0 : 0.0)) * scale,
      h: 8.0 * scale,
      topColor: const Color(0xFFFBBF24),
      leftColor: const Color(0xFFD97706),
      rightColor: const Color(0xFFB45309),
    );
    // Mistik parıltı küresi
    drawIsoCube(
      canvas,
      Offset(center.dx, center.dy - (16 + (safeLevel >= 3 ? 3.0 : 0.0)) * scale),
      w: (4.0 + (safeLevel >= 6 ? 2.0 : 0.0)) * scale,
      d: (4.0 + (safeLevel >= 6 ? 2.0 : 0.0)) * scale,
      h: 4.0 * scale,
      topColor: safeLevel >= 6 ? const Color(0xFFA855F7) : const Color(0xFF67E8F9),
      leftColor: safeLevel >= 6 ? const Color(0xFF9333EA) : const Color(0xFF06B6D4),
      rightColor: safeLevel >= 6 ? const Color(0xFF7E22CE) : const Color(0xFF0891B2),
    );

    // Seviye 6+ Üçlü Dönen Kristal Mercekler
    if (safeLevel >= 6) {
      final double lAngle = animTime * 3.0;
      final double lx = center.dx + math.cos(lAngle) * 10 * scale;
      final double ly = center.dy - 12 * scale + math.sin(lAngle) * 5 * scale;
      _sharedFillPaint.color = const Color(0xFF38BDF8).withValues(alpha: 0.8);
      canvas.drawCircle(Offset(lx, ly), 2.5 * scale, _sharedFillPaint);
    }
  }

  // ==========================================
  // ÖZEL TUNDRA BİNALARI (TUNDRA EXCLUSIVES)
  // ==========================================

  /// Geyik Otağı & Kürk Loncası (Reindeer Sanctuary - Seviye Kademeli)
  static void drawVoxelReindeerSanctuary(
    Canvas canvas,
    Offset center, {
    int level = 1,
    double scale = 1.0,
    double animTime = 0.0,
  }) {
    final int safeLevel = math.max(1, level);

    // Ahşap çit ve barınak
    drawIsoCube(
      canvas,
      Offset(center.dx, center.dy + 2 * scale),
      w: (16.0 + (safeLevel >= 3 ? 4.0 : 0.0)) * scale,
      d: (16.0 + (safeLevel >= 3 ? 4.0 : 0.0)) * scale,
      h: 6.0 * scale,
      topColor: const Color(0xFF78350F),
      leftColor: const Color(0xFF5A2408),
      rightColor: const Color(0xFF451A03),
    );
    // Kürk kaplı sivri çadır (Chum / Yurt)
    drawIsoCube(
      canvas,
      Offset(center.dx - 4 * scale, center.dy - 8 * scale),
      w: (10.0 + (safeLevel >= 6 ? 3.0 : 0.0)) * scale,
      d: (10.0 + (safeLevel >= 6 ? 3.0 : 0.0)) * scale,
      h: (12.0 + (safeLevel >= 3 ? 3.0 : 0.0)) * scale,
      topColor: safeLevel >= 6 ? const Color(0xFFFEF3C7) : const Color(0xFFD6D3D1),
      leftColor: safeLevel >= 6 ? const Color(0xFFFDE68A) : const Color(0xFFA8A29E),
      rightColor: safeLevel >= 6 ? const Color(0xFFF59E0B) : const Color(0xFF78716C),
    );
    // Otlayan boynuzlu geyik
    final double headBob = math.sin(animTime * 2.0) * 0.8;
    drawIsoCube(
      canvas,
      Offset(center.dx + 6 * scale, center.dy + headBob * scale),
      w: 5.0 * scale,
      d: 7.0 * scale,
      h: 5.0 * scale,
      topColor: const Color(0xFF9A3412),
      leftColor: const Color(0xFF7C2D12),
      rightColor: const Color(0xFF5B21B6),
    );

    // Seviye 3+ İkinci Geyik
    if (safeLevel >= 3) {
      drawIsoCube(
        canvas,
        Offset(center.dx + 8 * scale, center.dy - 5 * scale),
        w: 4.0 * scale,
        d: 5.0 * scale,
        h: 4.0 * scale,
        topColor: const Color(0xFFB45309),
        leftColor: const Color(0xFF92400E),
        rightColor: const Color(0xFF78350F),
      );
    }

    // Seviye 6+ Şamanik Boynuz Totem Direği
    if (safeLevel >= 6) {
      drawIsoCube(
        canvas,
        Offset(center.dx - 8 * scale, center.dy - 2 * scale),
        w: 2.5 * scale,
        d: 2.5 * scale,
        h: 12.0 * scale,
        topColor: const Color(0xFFF59E0B),
        leftColor: const Color(0xFFD97706),
        rightColor: const Color(0xFFB45309),
      );
    }
  }

  /// Jeotermal Kaplıca (Geothermal Bath - Seviye Kademeli)
  static void drawVoxelGeothermalBath(
    Canvas canvas,
    Offset center, {
    int level = 1,
    double scale = 1.0,
    double animTime = 0.0,
  }) {
    final int safeLevel = math.max(1, level);
    final double poolW = safeLevel >= 6 ? 20.0 : (safeLevel >= 3 ? 18.0 : 16.0);

    // Ahşap/Taş setli sıcak su havuzu
    drawIsoCube(
      canvas,
      Offset(center.dx, center.dy + 3 * scale),
      w: poolW * scale,
      d: poolW * scale,
      h: (safeLevel >= 3 ? 6.0 : 5.0) * scale,
      topColor: safeLevel >= 6 ? const Color(0xFF475569) : const Color(0xFF78716C),
      leftColor: safeLevel >= 6 ? const Color(0xFF334155) : const Color(0xFF57534E),
      rightColor: safeLevel >= 6 ? const Color(0xFF1E293B) : const Color(0xFF44403C),
    );
    // Sıcak turkuaz-yeşil mineral suyu
    drawIsoCube(
      canvas,
      Offset(center.dx, center.dy + 1 * scale),
      w: (poolW - 4.0) * scale,
      d: (poolW - 4.0) * scale,
      h: 2.0 * scale,
      topColor: const Color(0xFF2DD4BF),
      leftColor: const Color(0xFF0D9488),
      rightColor: const Color(0xFF0F766E),
    );
    // Yükselen buhar küpü
    final double steamY = (animTime * 10.0) % 16.0;
    _sharedFillPaint.color = const Color(0xFFE0F2FE).withValues(alpha: (1.0 - steamY / 16.0).clamp(0.0, 0.7));
    canvas.drawCircle(Offset(center.dx, center.dy - 6 * scale - steamY), (safeLevel >= 3 ? 4.0 : 3.0) * scale, _sharedFillPaint);

    // Seviye 3+ Ahşap Köşk / Dinlenme Sundurması
    if (safeLevel >= 3) {
      drawIsoCube(
        canvas,
        Offset(center.dx - 7 * scale, center.dy - 6 * scale),
        w: 6.0 * scale,
        d: 6.0 * scale,
        h: 8.0 * scale,
        topColor: const Color(0xFFB45309),
        leftColor: const Color(0xFF92400E),
        rightColor: const Color(0xFF78350F),
      );
    }
  }

  /// Mamut & Kehribar Sondajı (Permafrost Dig - Seviye Kademeli)
  static void drawVoxelPermafrostDig(
    Canvas canvas,
    Offset center, {
    int level = 1,
    double scale = 1.0,
    double animTime = 0.0,
  }) {
    final int safeLevel = math.max(1, level);

    // Ahşap vinç kulesi
    drawIsoCube(
      canvas,
      Offset(center.dx, center.dy),
      w: 14.0 * scale,
      d: 14.0 * scale,
      h: 6.0 * scale,
      topColor: safeLevel >= 6 ? const Color(0xFF1E293B) : const Color(0xFF475569),
      leftColor: safeLevel >= 6 ? const Color(0xFF0F172A) : const Color(0xFF334155),
      rightColor: safeLevel >= 6 ? const Color(0xFF020617) : const Color(0xFF1E293B),
    );
    drawIsoCube(
      canvas,
      Offset(center.dx - 3 * scale, center.dy - (10 + (safeLevel >= 3 ? 3.0 : 0.0)) * scale),
      w: 4.0 * scale,
      d: 4.0 * scale,
      h: (14.0 + (safeLevel >= 3 ? 4.0 : 0.0)) * scale,
      topColor: const Color(0xFFB45309),
      leftColor: const Color(0xFF92400E),
      rightColor: const Color(0xFF78350F),
    );
    // Kehribar ve mamut dişi sandığı
    drawIsoCube(
      canvas,
      Offset(center.dx + 5 * scale, center.dy - 4 * scale),
      w: (6.0 + (safeLevel >= 3 ? 2.0 : 0.0)) * scale,
      d: (6.0 + (safeLevel >= 3 ? 2.0 : 0.0)) * scale,
      h: 5.0 * scale,
      topColor: const Color(0xFFFBBF24),
      leftColor: const Color(0xFFF59E0B),
      rightColor: const Color(0xFFD97706),
    );

    // Seviye 6+ Çıkarılmış Devasa Mamut Dişi Fosil Vokselleri
    if (safeLevel >= 6) {
      drawIsoCube(
        canvas,
        Offset(center.dx + 7 * scale, center.dy - 10 * scale),
        w: 3.0 * scale,
        d: 8.0 * scale,
        h: 8.0 * scale,
        topColor: const Color(0xFFFEF3C7),
        leftColor: const Color(0xFFFDE68A),
        rightColor: const Color(0xFFFCD34D),
      );
    }
  }

  // ==========================================
  // ÖZEL VOLKAN BİNALARI (VOLCANO EXCLUSIVES)
  // ==========================================

  /// Jeotermal Buhar Bacası (Steam Vent Dynamo - Seviye Kademeli)
  static void drawVoxelSteamVent(
    Canvas canvas,
    Offset center, {
    int level = 1,
    double scale = 1.0,
    double animTime = 0.0,
  }) {
    final int safeLevel = math.max(1, level);

    // Obsidyen taban
    drawIsoCube(
      canvas,
      Offset(center.dx, center.dy + 3 * scale),
      w: (16.0 + (safeLevel >= 3 ? 4.0 : 0.0)) * scale,
      d: (16.0 + (safeLevel >= 3 ? 4.0 : 0.0)) * scale,
      h: 5.0 * scale,
      topColor: const Color(0xFF1E293B),
      leftColor: const Color(0xFF0F172A),
      rightColor: const Color(0xFF020617),
    );
    // Pirinç buhar borusu
    drawIsoCube(
      canvas,
      Offset(center.dx, center.dy - (8 + (safeLevel >= 3 ? 2.0 : 0.0)) * scale),
      w: (6.0 + (safeLevel >= 3 ? 2.0 : 0.0)) * scale,
      d: (6.0 + (safeLevel >= 3 ? 2.0 : 0.0)) * scale,
      h: (12.0 + (safeLevel >= 3 ? 4.0 : 0.0)) * scale,
      topColor: safeLevel >= 6 ? const Color(0xFFF59E0B) : const Color(0xFFD97706),
      leftColor: safeLevel >= 6 ? const Color(0xFFD97706) : const Color(0xFFB45309),
      rightColor: safeLevel >= 6 ? const Color(0xFFB45309) : const Color(0xFF92400E),
    );
    // Basınç vanası
    final double vRotate = math.sin(animTime * 3.0) * 1.5;
    drawIsoCube(
      canvas,
      Offset(center.dx + vRotate * scale, center.dy - (16 + (safeLevel >= 3 ? 6.0 : 0.0)) * scale),
      w: 8.0 * scale,
      d: 4.0 * scale,
      h: 2.0 * scale,
      topColor: const Color(0xFFEF4444),
      leftColor: const Color(0xFFDC2626),
      rightColor: const Color(0xFFB91C1C),
    );
  }

  /// Kadim Obsidyen Dökümhanesi (Obsidian Master Forge - Seviye Kademeli)
  static void drawVoxelObsidianForge(
    Canvas canvas,
    Offset center, {
    int level = 1,
    double scale = 1.0,
    double animTime = 0.0,
  }) {
    final int safeLevel = math.max(1, level);

    // Lav oluklu döküm tabanı
    drawIsoCube(
      canvas,
      Offset(center.dx, center.dy + 2 * scale),
      w: (20.0 + (safeLevel >= 3 ? 4.0 : 0.0)) * scale,
      d: (20.0 + (safeLevel >= 3 ? 4.0 : 0.0)) * scale,
      h: (7.0 + (safeLevel >= 3 ? 2.0 : 0.0)) * scale,
      topColor: const Color(0xFF0F172A),
      leftColor: const Color(0xFF020617),
      rightColor: const Color(0xFF000000),
    );
    // Kor lav kanalı
    drawIsoCube(
      canvas,
      Offset(center.dx, center.dy + 1 * scale),
      w: 12.0 * scale,
      d: 4.0 * scale,
      h: 2.0 * scale,
      topColor: const Color(0xFFEF4444),
      leftColor: const Color(0xFFDC2626),
      rightColor: const Color(0xFFB91C1C),
    );
    // Büyük obsidyen örs
    drawIsoCube(
      canvas,
      Offset(center.dx, center.dy - 8 * scale),
      w: (8.0 + (safeLevel >= 3 ? 2.0 : 0.0)) * scale,
      d: (8.0 + (safeLevel >= 3 ? 2.0 : 0.0)) * scale,
      h: (9.0 + (safeLevel >= 3 ? 2.0 : 0.0)) * scale,
      topColor: const Color(0xFF334155),
      leftColor: const Color(0xFF1E293B),
      rightColor: const Color(0xFF0F172A),
    );
    // Ateş kıvılcımı puf
    final double flamePulse = 0.5 + 0.5 * math.sin(animTime * 4.0);
    _sharedFillPaint.color = (safeLevel >= 6 ? const Color(0xFFFDE047) : const Color(0xFFF59E0B)).withValues(alpha: flamePulse);
    canvas.drawCircle(Offset(center.dx, center.dy - 18 * scale), (safeLevel >= 3 ? 4.0 : 3.0) * scale, _sharedFillPaint);

    // Seviye 6+ İkinci Döküm Ocağı & Kor Külçeler
    if (safeLevel >= 6) {
      drawIsoCube(
        canvas,
        Offset(center.dx + 8 * scale, center.dy - 4 * scale),
        w: 5.0 * scale,
        d: 5.0 * scale,
        h: 6.0 * scale,
        topColor: const Color(0xFFEA580C),
        leftColor: const Color(0xFFC2410C),
        rightColor: const Color(0xFF9A3412),
      );
    }
  }

  // ==========================================
  // ÖZEL SAZLIK BİNALARI (WETLAND EXCLUSIVES)
  // ==========================================

  /// Bozkır Şifacı Otağı (Herbalist Yurt - Seviye Kademeli)
  static void drawVoxelHerbalistYurt(
    Canvas canvas,
    Offset center, {
    int level = 1,
    double scale = 1.0,
    double animTime = 0.0,
  }) {
    final int safeLevel = math.max(1, level);

    // Sazlık kazıkları üstünde ahşap platform
    drawIsoCube(
      canvas,
      Offset(center.dx, center.dy + 4 * scale),
      w: (16.0 + (safeLevel >= 3 ? 4.0 : 0.0)) * scale,
      d: (16.0 + (safeLevel >= 3 ? 4.0 : 0.0)) * scale,
      h: 4.0 * scale,
      topColor: const Color(0xFF78350F),
      leftColor: const Color(0xFF5A2408),
      rightColor: const Color(0xFF451A03),
    );
    // Yeşil otlarla kaplı şifa çadırı
    drawIsoCube(
      canvas,
      Offset(center.dx, center.dy - 6 * scale),
      w: (12.0 + (safeLevel >= 3 ? 2.0 : 0.0)) * scale,
      d: (12.0 + (safeLevel >= 3 ? 2.0 : 0.0)) * scale,
      h: (10.0 + (safeLevel >= 3 ? 2.0 : 0.0)) * scale,
      topColor: const Color(0xFF84CC16),
      leftColor: const Color(0xFF65A30D),
      rightColor: const Color(0xFF4D7C0F),
    );
    // Kaynayan şifa kazanı
    drawIsoCube(
      canvas,
      Offset(center.dx + 6 * scale, center.dy),
      w: (4.0 + (safeLevel >= 3 ? 1.5 : 0.0)) * scale,
      d: (4.0 + (safeLevel >= 3 ? 1.5 : 0.0)) * scale,
      h: 4.0 * scale,
      topColor: const Color(0xFF10B981),
      leftColor: const Color(0xFF059669),
      rightColor: const Color(0xFF047857),
    );

    // Seviye 6+ Şifalı Ot Kurutma Çardağı
    if (safeLevel >= 6) {
      drawIsoCube(
        canvas,
        Offset(center.dx - 7 * scale, center.dy - 2 * scale),
        w: 4.0 * scale,
        d: 6.0 * scale,
        h: 6.0 * scale,
        topColor: const Color(0xFFFDE68A),
        leftColor: const Color(0xFFF59E0B),
        rightColor: const Color(0xFFD97706),
      );
    }
  }

  /// Kamış & Yazıt Atölyesi (Reed Scribe Workshop - Seviye Kademeli)
  static void drawVoxelScribeWorkshop(
    Canvas canvas,
    Offset center, {
    int level = 1,
    double scale = 1.0,
    double animTime = 0.0,
  }) {
    final int safeLevel = math.max(1, level);

    // Ahşap tezgah ve kurutma iskeleti
    drawIsoCube(
      canvas,
      Offset(center.dx, center.dy + 2 * scale),
      w: (18.0 + (safeLevel >= 3 ? 4.0 : 0.0)) * scale,
      d: (14.0 + (safeLevel >= 3 ? 4.0 : 0.0)) * scale,
      h: 5.0 * scale,
      topColor: const Color(0xFFB45309),
      leftColor: const Color(0xFF92400E),
      rightColor: const Color(0xFF78350F),
    );
    // Parşömen kurutma askıları
    final double paperSway = math.sin(animTime * 1.6) * 0.5;
    drawIsoCube(
      canvas,
      Offset(center.dx - 4 * scale, center.dy - (6 + paperSway) * scale),
      w: 3.0 * scale,
      d: 10.0 * scale,
      h: 8.0 * scale,
      topColor: const Color(0xFFFEF3C7),
      leftColor: const Color(0xFFFDE68A),
      rightColor: const Color(0xFFFCD34D),
    );
    // Rün ve mühür masası
    drawIsoCube(
      canvas,
      Offset(center.dx + 4 * scale, center.dy - 4 * scale),
      w: (6.0 + (safeLevel >= 3 ? 2.0 : 0.0)) * scale,
      d: (6.0 + (safeLevel >= 3 ? 2.0 : 0.0)) * scale,
      h: 6.0 * scale,
      topColor: const Color(0xFFD97706),
      leftColor: const Color(0xFFB45309),
      rightColor: const Color(0xFF92400E),
    );

    // Seviye 6+ Kağanlık Kitaplığı / Arşiv Dolabı
    if (safeLevel >= 6) {
      drawIsoCube(
        canvas,
        Offset(center.dx + 6 * scale, center.dy - 10 * scale),
        w: 5.0 * scale,
        d: 5.0 * scale,
        h: 9.0 * scale,
        topColor: const Color(0xFFFBBF24),
        leftColor: const Color(0xFFD97706),
        rightColor: const Color(0xFFB45309),
      );
    }
  }

  // ==========================================
  // EFSANEVİ BİYOMLAR & ANITSAL BİNALAR
  // ==========================================

  /// Gök Demircisi (Celestial Anvil - Seviye Kademeli)
  static void drawVoxelCelestialAnvil(
    Canvas canvas,
    Offset center, {
    int level = 1,
    double scale = 1.0,
    double animTime = 0.0,
  }) {
    final int safeLevel = math.max(1, level);

    // Göksel krater monolit tabanı
    drawIsoCube(
      canvas,
      Offset(center.dx, center.dy + 3 * scale),
      w: (20.0 + (safeLevel >= 3 ? 4.0 : 0.0)) * scale,
      d: (20.0 + (safeLevel >= 3 ? 4.0 : 0.0)) * scale,
      h: (8.0 + (safeLevel >= 3 ? 2.0 : 0.0)) * scale,
      topColor: const Color(0xFF1E1B4B),
      leftColor: const Color(0xFF0F172A),
      rightColor: const Color(0xFF020617),
    );
    // Mavi parıltılı Mithril gök örsü
    final double pulse = 0.7 + 0.3 * math.sin(animTime * 3.0);
    drawIsoCube(
      canvas,
      Offset(center.dx, center.dy - 8 * scale),
      w: (10.0 + (safeLevel >= 3 ? 2.0 : 0.0)) * scale,
      d: (10.0 + (safeLevel >= 3 ? 2.0 : 0.0)) * scale,
      h: (10.0 + (safeLevel >= 3 ? 2.0 : 0.0)) * scale,
      topColor: Color.lerp(const Color(0xFF38BDF8), const Color(0xFF818CF8), pulse)!,
      leftColor: const Color(0xFF0284C7),
      rightColor: const Color(0xFF1E40AF),
    );
    // Yıldız tozu ışıltısı
    _sharedFillPaint.color = const Color(0xFFBAE6FD).withValues(alpha: pulse);
    canvas.drawCircle(Offset(center.dx, center.dy - 20 * scale), (safeLevel >= 3 ? 6.0 : 4.0) * scale, _sharedFillPaint);

    // Seviye 6+ Üçlü Göktaşı Kristalleri
    if (safeLevel >= 6) {
      drawIsoCube(
        canvas,
        Offset(center.dx - 8 * scale, center.dy - 4 * scale),
        w: 3.5 * scale,
        d: 3.5 * scale,
        h: 8.0 * scale,
        topColor: const Color(0xFFC084FC),
        leftColor: const Color(0xFF9333EA),
        rightColor: const Color(0xFF7E22CE),
      );
      drawIsoCube(
        canvas,
        Offset(center.dx + 8 * scale, center.dy - 4 * scale),
        w: 3.5 * scale,
        d: 3.5 * scale,
        h: 8.0 * scale,
        topColor: const Color(0xFFC084FC),
        leftColor: const Color(0xFF9333EA),
        rightColor: const Color(0xFF7E22CE),
      );
    }
  }

  /// Kurgan Koruyucusu (Ancestral Totem - Seviye Kademeli)
  static void drawVoxelAncestralTotem(
    Canvas canvas,
    Offset center, {
    int level = 1,
    double scale = 1.0,
    double animTime = 0.0,
  }) {
    final int safeLevel = math.max(1, level);

    // Höyük taş kaidesi
    drawIsoCube(
      canvas,
      Offset(center.dx, center.dy + 4 * scale),
      w: (22.0 + (safeLevel >= 3 ? 4.0 : 0.0)) * scale,
      d: (22.0 + (safeLevel >= 3 ? 4.0 : 0.0)) * scale,
      h: (7.0 + (safeLevel >= 3 ? 2.0 : 0.0)) * scale,
      topColor: const Color(0xFF475569),
      leftColor: const Color(0xFF334155),
      rightColor: const Color(0xFF1E293B),
    );
    // Üçlü Taş Balbal Heykelleri
    drawIsoCube(
      canvas,
      Offset(center.dx - 6 * scale, center.dy - 6 * scale),
      w: 5.0 * scale,
      d: 5.0 * scale,
      h: (14.0 + (safeLevel >= 3 ? 3.0 : 0.0)) * scale,
      topColor: const Color(0xFF94A3B8),
      leftColor: const Color(0xFF64748B),
      rightColor: const Color(0xFF475569),
    );
    drawIsoCube(
      canvas,
      Offset(center.dx + 6 * scale, center.dy - 6 * scale),
      w: 5.0 * scale,
      d: 5.0 * scale,
      h: (14.0 + (safeLevel >= 3 ? 3.0 : 0.0)) * scale,
      topColor: const Color(0xFF94A3B8),
      leftColor: const Color(0xFF64748B),
      rightColor: const Color(0xFF475569),
    );
    // Ortadaki kutsal ata sütunu ve tamga ateşi
    drawIsoCube(
      canvas,
      Offset(center.dx, center.dy - 12 * scale),
      w: (6.0 + (safeLevel >= 3 ? 2.0 : 0.0)) * scale,
      d: (6.0 + (safeLevel >= 3 ? 2.0 : 0.0)) * scale,
      h: (20.0 + (safeLevel >= 3 ? 4.0 : 0.0)) * scale,
      topColor: safeLevel >= 6 ? const Color(0xFFFDE047) : const Color(0xFFFBBF24),
      leftColor: safeLevel >= 6 ? const Color(0xFFEAB308) : const Color(0xFFD97706),
      rightColor: safeLevel >= 6 ? const Color(0xFFCA8A04) : const Color(0xFFB45309),
    );
  }

  /// Rezonans Kulesi (Prismatic Resonator - Seviye Kademeli)
  static void drawVoxelPrismaticResonator(
    Canvas canvas,
    Offset center, {
    int level = 1,
    double scale = 1.0,
    double animTime = 0.0,
  }) {
    final int safeLevel = math.max(1, level);

    // Kristal yarık kaidesi
    drawIsoCube(
      canvas,
      Offset(center.dx, center.dy + 3 * scale),
      w: (18.0 + (safeLevel >= 3 ? 4.0 : 0.0)) * scale,
      d: (18.0 + (safeLevel >= 3 ? 4.0 : 0.0)) * scale,
      h: 6.0 * scale,
      topColor: const Color(0xFF581C87),
      leftColor: const Color(0xFF3B0764),
      rightColor: const Color(0xFF2E1065),
    );
    // Yükselen prizmatik kristal monolit
    final double glow = 0.6 + 0.4 * math.sin(animTime * 2.5);
    drawIsoCube(
      canvas,
      Offset(center.dx, center.dy - 10 * scale),
      w: (8.0 + (safeLevel >= 3 ? 2.0 : 0.0)) * scale,
      d: (8.0 + (safeLevel >= 3 ? 2.0 : 0.0)) * scale,
      h: (18.0 + (safeLevel >= 3 ? 4.0 : 0.0)) * scale,
      topColor: Color.lerp(const Color(0xFFC084FC), const Color(0xFFE879F9), glow)!,
      leftColor: const Color(0xFF9333EA),
      rightColor: const Color(0xFF7E22CE),
    );
    // Tepe rezonans halkası
    drawIsoCube(
      canvas,
      Offset(center.dx, center.dy - (22 + (safeLevel >= 3 ? 4.0 : 0.0)) * scale),
      w: 4.0 * scale,
      d: 4.0 * scale,
      h: 4.0 * scale,
      topColor: const Color(0xFFF0ABFC),
      leftColor: const Color(0xFFD946EF),
      rightColor: const Color(0xFFA21CAF),
    );
  }

  // ==========================================
  // EFSANEVİ BİYOM DOĞAL ZEMİN & BALBALLAR
  // ==========================================

  /// Göksel Krater Doğal Zemin Vokselleri
  static void drawVoxelCelestialCraterGround(Canvas canvas, Offset center, {double scale = 1.0, double animTime = 0.0}) {
    // Krater çukuru kayaları
    drawIsoCube(
      canvas,
      Offset(center.dx, center.dy),
      w: 16.0 * scale,
      d: 16.0 * scale,
      h: 3.0 * scale,
      topColor: const Color(0xFF1E1B4B),
      leftColor: const Color(0xFF0F172A),
      rightColor: const Color(0xFF020617),
    );
    // Mavi göktaşı kristal parçaları
    final double pulse = 0.5 + 0.5 * math.sin(animTime * 2.0);
    drawIsoCube(
      canvas,
      Offset(center.dx - 4 * scale, center.dy - 2 * scale),
      w: 4.0 * scale,
      d: 4.0 * scale,
      h: 5.0 * scale,
      topColor: Color.lerp(const Color(0xFF38BDF8), const Color(0xFF818CF8), pulse)!,
      leftColor: const Color(0xFF0284C7),
      rightColor: const Color(0xFF1E40AF),
    );
  }

  /// Atalar Kurganı Doğal Balbal Taşları
  static void drawVoxelKurganBalbals(Canvas canvas, Offset center, {double scale = 1.0, double animTime = 0.0}) {
    // Höyük tepeciği
    drawIsoCube(
      canvas,
      Offset(center.dx, center.dy + 2 * scale),
      w: 18.0 * scale,
      d: 18.0 * scale,
      h: 5.0 * scale,
      topColor: const Color(0xFF334155),
      leftColor: const Color(0xFF1E293B),
      rightColor: const Color(0xFF0F172A),
    );
    // İkili Kadim Taş Balbal
    drawIsoCube(
      canvas,
      Offset(center.dx - 5 * scale, center.dy - 4 * scale),
      w: 4.0 * scale,
      d: 4.0 * scale,
      h: 10.0 * scale,
      topColor: const Color(0xFF94A3B8),
      leftColor: const Color(0xFF64748B),
      rightColor: const Color(0xFF475569),
    );
    drawIsoCube(
      canvas,
      Offset(center.dx + 5 * scale, center.dy - 2 * scale),
      w: 4.0 * scale,
      d: 4.0 * scale,
      h: 8.0 * scale,
      topColor: const Color(0xFF94A3B8),
      leftColor: const Color(0xFF64748B),
      rightColor: const Color(0xFF475569),
    );
  }

  /// Kristal Yarığı Doğal Zemin Vokselleri
  static void drawVoxelCrystalChasmGround(Canvas canvas, Offset center, {double scale = 1.0, double animTime = 0.0}) {
    // Mor-koyu taban yarığı
    drawIsoCube(
      canvas,
      Offset(center.dx, center.dy),
      w: 16.0 * scale,
      d: 16.0 * scale,
      h: 4.0 * scale,
      topColor: const Color(0xFF3B0764),
      leftColor: const Color(0xFF2E1065),
      rightColor: const Color(0xFF1E1B4B),
    );
    // Yükselen 3 kristal dikiti
    final double g = 0.7 + 0.3 * math.sin(animTime * 3.0);
    drawIsoCube(
      canvas,
      Offset(center.dx - 4 * scale, center.dy - 3 * scale),
      w: 3.0 * scale,
      d: 3.0 * scale,
      h: 7.0 * scale,
      topColor: Color.lerp(const Color(0xFFC084FC), const Color(0xFFF472B6), g)!,
      leftColor: const Color(0xFF9333EA),
      rightColor: const Color(0xFF7E22CE),
    );
    drawIsoCube(
      canvas,
      Offset(center.dx + 3 * scale, center.dy - 5 * scale),
      w: 4.0 * scale,
      d: 4.0 * scale,
      h: 11.0 * scale,
      topColor: Color.lerp(const Color(0xFFE879F9), const Color(0xFFA855F7), g)!,
      leftColor: const Color(0xFFA21CAF),
      rightColor: const Color(0xFF701A75),
    );
  }

  // ==========================================
  // CANLI MİKRO-PARTİKÜL & ATMOSFER EFEKTLERİ
  // ==========================================

  /// Çöl: Rüzgarda Savrulan Kum Tozları
  static void drawVoxelDesertDust(Canvas canvas, Offset center, {double animTime = 0.0, int seed = 0}) {
    _sharedFillPaint.color = const Color(0xFFFDE68A).withValues(alpha: 0.45);
    for (int i = 0; i < 3; i++) {
      final double progress = ((animTime * 0.8 + i * 0.33 + (seed % 7) * 0.1) % 1.0);
      final double x = center.dx - 15.0 + progress * 30.0;
      final double y = center.dy - 8.0 + math.sin(progress * math.pi * 2.0) * 4.0;
      canvas.drawCircle(Offset(x, y), 1.2, _sharedFillPaint);
    }
  }

  /// Tundra: Don & Buz Kristalleri Parıltısı
  static void drawVoxelIceSparkles(Canvas canvas, Offset center, {double animTime = 0.0, int seed = 0}) {
    for (int i = 0; i < 2; i++) {
      final double sparkle = (0.5 + 0.5 * math.sin(animTime * 3.5 + i * 2.0 + seed)).clamp(0.0, 1.0);
      _sharedFillPaint.color = const Color(0xFFBAE6FD).withValues(alpha: sparkle * 0.7);
      final double ox = (i == 0 ? -7.0 : 8.0) + (seed % 5);
      final double oy = (i == 0 ? -4.0 : 5.0) - (seed % 3);
      canvas.drawCircle(Offset(center.dx + ox, center.dy + oy), 1.5, _sharedFillPaint);
    }
  }

  /// Volkan: Lav Korları & Kıvılcımlar
  static void drawVoxelVolcanoEmbers(Canvas canvas, Offset center, {double animTime = 0.0, int seed = 0}) {
    for (int i = 0; i < 3; i++) {
      final double progress = ((animTime * 1.2 + i * 0.33 + (seed % 5) * 0.2) % 1.0);
      final double y = center.dy + 4.0 - progress * 20.0;
      final double x = center.dx + math.sin(progress * 6.0 + i) * 5.0;
      final double alpha = (1.0 - progress).clamp(0.0, 0.8);
      _sharedFillPaint.color = (i % 2 == 0 ? const Color(0xFFEF4444) : const Color(0xFFF59E0B)).withValues(alpha: alpha);
      canvas.drawCircle(Offset(x, y), 1.4, _sharedFillPaint);
    }
  }

  /// Sazlık: Uçuşan Yusufçuklar
  static void drawVoxelDragonflies(Canvas canvas, Offset center, {double animTime = 0.0, int seed = 0}) {
    final double flightAngle = animTime * 2.5 + seed;
    final double x = center.dx + math.cos(flightAngle) * 12.0;
    final double y = center.dy + math.sin(flightAngle * 1.5) * 6.0 - 4.0;
    _sharedFillPaint.color = const Color(0xFF38BDF8).withValues(alpha: 0.85);
    canvas.drawCircle(Offset(x, y), 1.8, _sharedFillPaint);
    _sharedFillPaint.color = const Color(0xFFE0F2FE).withValues(alpha: 0.6);
    canvas.drawCircle(Offset(x - 2, y - 1), 1.0, _sharedFillPaint);
    canvas.drawCircle(Offset(x + 2, y - 1), 1.0, _sharedFillPaint);
  }

  /// Göksel Krater & Kristal: Kozmik Yıldız Tozu
  static void drawVoxelCelestialStardust(Canvas canvas, Offset center, {double animTime = 0.0, int seed = 0}) {
    for (int i = 0; i < 4; i++) {
      final double progress = ((animTime * 0.7 + i * 0.25 + seed * 0.1) % 1.0);
      final double radius = 4.0 + progress * 12.0;
      final double angle = progress * math.pi * 2.0 + i * 1.57;
      final double x = center.dx + math.cos(angle) * radius;
      final double y = center.dy + math.sin(angle) * radius * 0.5 - 6.0;
      final double alpha = (math.sin(progress * math.pi)).clamp(0.0, 0.8);
      _sharedFillPaint.color = (i % 2 == 0 ? const Color(0xFFC084FC) : const Color(0xFF38BDF8)).withValues(alpha: alpha);
      canvas.drawCircle(Offset(x, y), 1.3, _sharedFillPaint);
    }
  }

  // --- CANLI VE ORGANİK BOZKIR DÜNYASI SİSTEMİ (LIVING STEPPE ECOSYSTEM) ---

  /// Global Bozkır Rüzgar Dalgası: Harita boyunca yayılan organik, heterodin sakin rüzgar dalgası (-1.0 .. 1.0)
  static double getSteppeWindWave(double globalTime, int q, int r) {
    final double w1 = math.sin(globalTime * 0.32 + q * 0.28 + r * 0.19);
    final double w2 = math.sin(globalTime * 0.55 - q * 0.15 + r * 0.31) * 0.20;
    return (w1 + w2).clamp(-1.0, 1.0);
  }

  /// 3D Voxel Ocak / Otağ Bacası Dumanı (Huzurla Yükselen, Rüzgara Eğilen, Asenkron Partiküller)
  static void drawVoxelSmokePlume(
    Canvas canvas,
    Offset chimneyPos, {
    required double animTime,
    required int seed,
    double windWave = 0.0,
    double scale = 1.0,
    Color? smokeColor,
  }) {
    final double timeOffset = (seed * 3.71) % 10.0;
    final double t = animTime + timeOffset;

    for (int i = 0; i < 3; i++) {
      final double phase = (t * 0.25 + i * 0.33) % 1.0;
      final double puffHeight = phase * 22.0 * scale;
      final double puffDrift = (windWave * 6.0 + math.sin(t * 0.6 + i) * 1.5) * phase * scale;
      final double puffSize = (3.0 + phase * 4.0) * scale;
      final double alpha = (math.sin(phase * math.pi) * 0.65).clamp(0.0, 1.0);

      final Color sColor = smokeColor ?? const Color(0xFFE2E8F0);

      drawIsoCube(
        canvas,
        Offset(chimneyPos.dx + puffDrift, chimneyPos.dy - puffHeight),
        w: puffSize,
        d: puffSize,
        h: puffSize * 0.8,
        topColor: sColor.withValues(alpha: alpha),
        leftColor: const Color(0xFF94A3B8).withValues(alpha: alpha * 0.8),
        rightColor: const Color(0xFF64748B).withValues(alpha: alpha * 0.6),
      );
    }
  }

  /// Geceleyin Otağ, Fırın ve Dökümhane Tabanında Titreyen Sıcak Ocak Ateşi Parıltısı
  static void drawVoxelHearthFirelight(
    Canvas canvas,
    Offset center, {
    required double animTime,
    required int seed,
    double radius = 10.0,
  }) {
    final double flicker = 0.6 +
        0.25 * math.sin(animTime * 1.8 + seed * 2.7) +
        0.15 * math.sin(animTime * 3.2 + seed * 5.1);

    _sharedFillPaint
      ..color = const Color(0xFFF59E0B).withValues(alpha: (0.35 * flicker).clamp(0.0, 0.7))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * flicker, _sharedFillPaint);

    _sharedFillPaint.color = const Color(0xFFFEF08A).withValues(alpha: (0.55 * flicker).clamp(0.0, 0.9));
    canvas.drawCircle(center, (radius * 0.45) * flicker, _sharedFillPaint);
  }

  /// Dokunsal Su Dalgası Halkaları (Suya Dokunulduğunda 2 Kademeli Yayılma)
  static void drawVoxelWaterRipple(
    Canvas canvas,
    Offset center, {
    required double progress,
  }) {
    if (progress <= 0.0 || progress >= 1.0) return;

    for (int i = 0; i < 2; i++) {
      final double delay = i * 0.22;
      final double subProgress = ((progress - delay) / (1.0 - delay)).clamp(0.0, 1.0);
      if (subProgress <= 0.0 || subProgress >= 1.0) continue;

      final double radiusX = subProgress * 28.0;
      final double radiusY = radiusX * 0.58;
      final double alpha = (1.0 - subProgress) * 0.75;

      _sharedStrokePaint
        ..color = const Color(0xFFBAE6FD).withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = (2.2 * (1.0 - subProgress)).clamp(0.8, 2.2);

      canvas.drawOval(
        Rect.fromCenter(center: center, width: radiusX * 2, height: radiusY * 2),
        _sharedStrokePaint,
      );
    }
  }

  /// Ormana Dokunulduğunda Ağaçtan Savrulan Voksel Yapraklar
  static void drawVoxelLeafScatter(
    Canvas canvas,
    Offset center, {
    required double progress,
    required int seed,
  }) {
    if (progress <= 0.0 || progress >= 1.0) return;

    for (int i = 0; i < 4; i++) {
      final double angle = (seed * 0.5 + i * 1.57);
      final double dist = progress * (18.0 + (seed % 7));
      final double lx = center.dx + math.cos(angle) * dist;
      final double ly = center.dy - 16.0 + math.sin(angle) * dist * 0.58 + (progress * progress * 14.0);
      final double leafAlpha = (1.0 - progress).clamp(0.0, 1.0);

      final Color leafCol = i % 2 == 0 ? const Color(0xFF4ADE80) : const Color(0xFFFBBF24);

      drawIsoCube(
        canvas,
        Offset(lx, ly),
        w: 2.0,
        d: 2.0,
        h: 1.5,
        topColor: leafCol.withValues(alpha: leafAlpha),
        leftColor: const Color(0xFF15803D).withValues(alpha: leafAlpha),
        rightColor: const Color(0xFF166534).withValues(alpha: leafAlpha),
      );
    }
  }

  /// Çölde Sıcaklık Serabı (1-2 Piksel Yükselen Isı Dalgası)
  static void drawVoxelDesertHeatShimmer(
    Canvas canvas,
    Offset center, {
    required double animTime,
    required int seed,
  }) {
    final double shimmer = math.sin(animTime * 3.5 + seed);
    if (shimmer < 0.2) return;

    final double sy = math.sin(animTime * 4.0 + seed * 2.0) * 1.5;
    final double sx = math.cos(animTime * 2.5 + seed) * 3.0;

    _sharedStrokePaint
      ..color = const Color(0xFFFEF3C7).withValues(alpha: 0.22 * shimmer)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawLine(
      Offset(center.dx - 10 + sx, center.dy - 6 + sy),
      Offset(center.dx + 10 + sx, center.dy - 6 - sy),
      _sharedStrokePaint,
    );
  }

  /// Dağ Zirvelerinde Rüzgarla Uçuşan İnce Toz Kar Sisi
  static void drawVoxelSnowDrift(
    Canvas canvas,
    Offset peakPos, {
    required double animTime,
    required double windWave,
    required int seed,
  }) {
    if (windWave.abs() < 0.2) return;

    for (int i = 0; i < 3; i++) {
      final double phase = ((animTime * 0.8 + seed * 0.3 + i * 0.35) % 1.0);
      final double dx = phase * 20.0 * (windWave > 0 ? 1.0 : -1.0);
      final double dy = -phase * 4.0 + math.sin(phase * math.pi) * 2.0;
      final double alpha = math.sin(phase * math.pi) * 0.45 * windWave.abs();

      drawIsoCube(
        canvas,
        Offset(peakPos.dx + dx, peakPos.dy + dy),
        w: 1.5,
        d: 1.5,
        h: 1.2,
        topColor: Colors.white.withValues(alpha: alpha),
        leftColor: const Color(0xFFE0F2FE).withValues(alpha: alpha * 0.8),
        rightColor: const Color(0xFFBAE6FD).withValues(alpha: alpha * 0.7),
      );
    }
  }

  /// Gayzer ve Volkanik Masiflerde 18-24 Saniyede Bir Patlayan Buhar Pufu
  static void drawVoxelGeyserBurst(
    Canvas canvas,
    Offset ventPos, {
    required double animTime,
    required int seed,
  }) {
    final double cyclePeriod = 20.0 + (seed % 6);
    final double phaseTime = (animTime + seed * 4.7) % cyclePeriod;
    if (phaseTime > 3.0) return;

    final double burstProgress = phaseTime / 3.0;
    final double h = burstProgress * 28.0;
    final double w = 4.0 + burstProgress * 8.0;
    final double alpha = (1.0 - burstProgress) * 0.85;

    drawIsoCube(
      canvas,
      Offset(ventPos.dx, ventPos.dy - h),
      w: w,
      d: w,
      h: w * 0.7,
      topColor: Colors.white.withValues(alpha: alpha),
      leftColor: const Color(0xFFF1F5F9).withValues(alpha: alpha * 0.8),
      rightColor: const Color(0xFFCBD5E1).withValues(alpha: alpha * 0.6),
    );
  }

  /// Bozkırda Rüzgar Yönünde Yuvarlanan Voksel Çalı (Tumbleweed)
  static void drawVoxelTumbleweed(
    Canvas canvas,
    Offset center, {
    required double animTime,
    required int seed,
    double windWave = 0.0,
  }) {
    final double cyclePeriod = 35.0 + (seed % 15);
    final double phaseTime = (animTime + seed * 3.1) % cyclePeriod;
    if (phaseTime > 4.5) return;

    final double progress = phaseTime / 4.5;
    final double x = center.dx - 30.0 + progress * 60.0;
    final double bounce = (math.sin(progress * math.pi * 6).abs()) * 6.0;
    final double y = center.dy + 4.0 - bounce;

    drawIsoCube(
      canvas,
      Offset(x, y),
      w: 3.5,
      d: 3.5,
      h: 3.5,
      topColor: const Color(0xFFD97706),
      leftColor: const Color(0xFFB45309),
      rightColor: const Color(0xFF92400E),
      drawShadow: true,
      shadowOpacity: 0.2,
    );
  }

  /// 1. İpek Yolu Kervan Devesi ve Heybe Yükleri (VoxelFaunaRenderer Köprüsü)
  static void drawVoxelCaravanCamel(
    Canvas canvas,
    Offset center, {
    required double animTime,
    double walkCycle = 0.0,
    bool flipX = false,
  }) {
    VoxelFaunaRenderer.drawCaravanCamel(
      canvas,
      center,
      animTime: animTime,
      walkCycle: walkCycle,
      flipX: flipX,
    );
  }

  /// 2. Ata Kurganı Balbal Dikilitaşı (Ancestral Kurgan Balbal Stele)
  static void drawVoxelAncestralBalbal(
    Canvas canvas,
    Offset center, {
    required double animTime,
    required int level,
  }) {
    // Taş Kaide
    drawIsoCube(
      canvas,
      Offset(center.dx, center.dy + 2.0),
      w: 10.0,
      d: 10.0,
      h: 2.5,
      topColor: const Color(0xFF475569),
      leftColor: const Color(0xFF334155),
      rightColor: const Color(0xFF1E293B),
      drawShadow: true,
      shadowOpacity: 0.35,
    );

    // Dikilitaş Gövdesi (Balbal Gövde)
    drawIsoCube(
      canvas,
      Offset(center.dx, center.dy - 12.0),
      w: 5.0,
      d: 4.5,
      h: 14.0,
      topColor: const Color(0xFF64748B),
      leftColor: const Color(0xFF475569),
      rightColor: const Color(0xFF334155),
    );

    // Balbal Başlığı ve Kazınmış Kadeh Motifi
    drawIsoCube(
      canvas,
      Offset(center.dx, center.dy - 20.0),
      w: 4.0,
      d: 4.0,
      h: 4.5,
      topColor: const Color(0xFF94A3B8),
      leftColor: const Color(0xFF64748B),
      rightColor: const Color(0xFF475569),
    );

    // Göksel Rün Işıltısı (Pulsing Golden Inscription)
    final double pulse = 0.5 + 0.5 * math.sin(animTime * 2.5);
    drawIsoCube(
      canvas,
      Offset(center.dx, center.dy - 11.0),
      w: 1.5,
      d: 1.0,
      h: 6.0,
      topColor: Color.lerp(const Color(0xFFD97706), const Color(0xFFFDE047), pulse)!,
      leftColor: const Color(0xFFB45309),
      rightColor: const Color(0xFF92400E),
    );
  }

  /// 3. Ekolojik Simbiyoz Parçacık Aurası (Symbiosis Ecological Aura)
  static void drawVoxelSymbiosisSparks(
    Canvas canvas,
    Offset center, {
    required double animTime,
    required SymbiosisType type,
  }) {
    if (type == SymbiosisType.none) return;

    Color sparkTop;
    Color sparkSide;
    switch (type) {
      case SymbiosisType.wildGlade:
        sparkTop = const Color(0xFF10B981);
        sparkSide = const Color(0xFF047857);
        break;
      case SymbiosisType.canyonOasis:
        sparkTop = const Color(0xFF06B6D4);
        sparkSide = const Color(0xFF0891B2);
        break;
      case SymbiosisType.crystalSpring:
        sparkTop = const Color(0xFF38BDF8);
        sparkSide = const Color(0xFF0284C7);
        break;
      case SymbiosisType.volcanicGeothermal:
        sparkTop = const Color(0xFFF97316);
        sparkSide = const Color(0xFFC2410C);
        break;
      case SymbiosisType.none:
        return;
    }

    for (int i = 0; i < 4; i++) {
      final double angle = animTime * 1.5 + (i * (math.pi / 2.0));
      final double rx = 16.0 * math.cos(angle);
      final double ry = 8.0 * math.sin(angle) - 4.0;
      final double floatY = math.sin(animTime * 3.0 + i) * 3.0;

      drawIsoCube(
        canvas,
        Offset(center.dx + rx, center.dy + ry + floatY),
        w: 2.0,
        d: 2.0,
        h: 2.0,
        topColor: sparkTop,
        leftColor: sparkSide,
        rightColor: sparkSide.withValues(alpha: 0.8),
      );
    }
  }

  /// 4. Dokunsal Ritim Dalga Halkası (Tactile Rhythm Resonance Ring)
  static void drawVoxelTactileRing(
    Canvas canvas,
    Offset center, {
    required double progress,
    required int combo,
  }) {
    if (progress >= 1.0) return;

    final double radius = 6.0 + progress * 24.0;
    final double alpha = (1.0 - progress) * 0.8;

    Color ringColor;
    if (combo >= 5) {
      ringColor = const Color(0xFFEC4899); // Pembe Efsanevi Ritim
    } else if (combo >= 3) {
      ringColor = const Color(0xFFF59E0B); // Altın Şamanik Ritim
    } else {
      ringColor = const Color(0xFF38BDF8); // Mavi Bozkır Ritmi
    }

    _sharedStrokePaint
      ..color = ringColor.withValues(alpha: alpha)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(center, radius, _sharedStrokePaint);
  }

  /// 5. Komşuluk Sinerji Hayalet Göstergesi (Adjacency Ghost Preview)
  static void drawVoxelAdjacencyGhost(
    Canvas canvas,
    Offset center, {
    required BuildingType type,
    required double animTime,
  }) {
    final double pulse = 0.4 + 0.3 * math.sin(animTime * 4.0);

    drawIsoCube(
      canvas,
      Offset(center.dx, center.dy - 6.0),
      w: 12.0,
      d: 12.0,
      h: 8.0,
      topColor: const Color(0xFF38BDF8).withValues(alpha: pulse),
      leftColor: const Color(0xFF0284C7).withValues(alpha: pulse * 0.7),
      rightColor: const Color(0xFF0369A1).withValues(alpha: pulse * 0.5),
    );
  }

  /// 6. Kuş Bakışı Taktiksel Makro Karo (Macro Overview Hex Badge)
  static void drawVoxelMacroTile(
    Canvas canvas,
    Offset center, {
    required TileBiome biome,
    required bool isOwned,
    bool hasBuilding = false,
    bool hasKurgan = false,
    bool isResting = false,
  }) {
    Color fillColor;
    switch (biome) {
      case TileBiome.meadow:
        fillColor = isResting ? const Color(0xFF4ADE80) : const Color(0xFF15803D);
        break;
      case TileBiome.forest:
        fillColor = const Color(0xFF166534);
        break;
      case TileBiome.desert:
        fillColor = const Color(0xFFD97706);
        break;
      case TileBiome.mountain:
        fillColor = const Color(0xFF64748B);
        break;
      case TileBiome.sea:
        fillColor = const Color(0xFF0284C7);
        break;
      case TileBiome.wetland:
        fillColor = const Color(0xFF0D9488);
        break;
      case TileBiome.tundra:
        fillColor = const Color(0xFFE2E8F0);
        break;
      case TileBiome.volcano:
        fillColor = const Color(0xFFDC2626);
        break;
      case TileBiome.celestialCrater:
      case TileBiome.kurganValley:
      case TileBiome.crystalChasm:
        fillColor = const Color(0xFFA855F7);
        break;
    }

    if (!isOwned) {
      fillColor = fillColor.withValues(alpha: 0.35);
    }

    drawIsoCube(
      canvas,
      center,
      w: 14.0,
      d: 14.0,
      h: hasBuilding ? 6.0 : 2.5,
      topColor: fillColor,
      leftColor: fillColor.withValues(alpha: 0.75),
      rightColor: fillColor.withValues(alpha: 0.55),
    );
  }

  /// 1. Orhun Bitig Taşı (Runic Monolith Stele - Seviye Kademeli)
  static void drawVoxelRunicStele(
    Canvas canvas,
    Offset center, {
    int level = 1,
    double animTime = 0.0,
  }) {
    final int safeLevel = math.max(1, level);
    final double baseW = safeLevel >= 6 ? 22.0 : (safeLevel >= 3 ? 18.0 : 16.0);

    // Taş Kaide Tabanı
    drawIsoCube(
      canvas,
      center,
      w: baseW,
      d: baseW - 2.0,
      h: (safeLevel >= 3 ? 5.0 : 4.0),
      topColor: safeLevel >= 6 ? const Color(0xFF1E293B) : const Color(0xFF334155),
      leftColor: safeLevel >= 6 ? const Color(0xFF0F172A) : const Color(0xFF1E293B),
      rightColor: safeLevel >= 6 ? const Color(0xFF020617) : const Color(0xFF0F172A),
      drawShadow: true,
    );

    // Dikilitaş Gövdesi
    final Offset steleBase = Offset(center.dx, center.dy - 3.0);
    final double steleH = safeLevel >= 6 ? 30.0 : (safeLevel >= 3 ? 26.0 : 22.0);
    final double steleW = safeLevel >= 6 ? 10.0 : (safeLevel >= 3 ? 9.0 : 8.0);
    drawIsoCube(
      canvas,
      steleBase,
      w: steleW,
      d: steleW,
      h: steleH,
      topColor: safeLevel >= 6 ? const Color(0xFF64748B) : const Color(0xFF475569),
      leftColor: safeLevel >= 6 ? const Color(0xFF475569) : const Color(0xFF334155),
      rightColor: safeLevel >= 6 ? const Color(0xFF334155) : const Color(0xFF1E293B),
    );

    // Seviye 3+ Yan Flank Dikilitaşları
    if (safeLevel >= 3) {
      drawIsoCube(
        canvas,
        Offset(center.dx - 7.0, center.dy - 1.0),
        w: 4.0,
        d: 4.0,
        h: 12.0,
        topColor: const Color(0xFF475569),
        leftColor: const Color(0xFF334155),
        rightColor: const Color(0xFF1E293B),
      );
      drawIsoCube(
        canvas,
        Offset(center.dx + 7.0, center.dy - 1.0),
        w: 4.0,
        d: 4.0,
        h: 12.0,
        topColor: const Color(0xFF475569),
        leftColor: const Color(0xFF334155),
        rightColor: const Color(0xFF1E293B),
      );
    }

    // Seviye 6+ Altın Başlık & Tamga Tacı
    if (safeLevel >= 6) {
      drawIsoCube(
        canvas,
        Offset(center.dx, center.dy - steleH - 2.0),
        w: 6.0,
        d: 6.0,
        h: 5.0,
        topColor: const Color(0xFFFDE047),
        leftColor: const Color(0xFFEAB308),
        rightColor: const Color(0xFFCA8A04),
      );
    }

    // Parlayan Rünik Yazıt Harfleri
    final double pulse = 0.6 + 0.4 * math.sin(animTime * 3.0);
    final Color runeGlow = (safeLevel >= 6 ? const Color(0xFF38BDF8) : const Color(0xFF06B6D4)).withValues(alpha: pulse);

    _sharedFillPaint.color = runeGlow;
    canvas.drawRect(
      Rect.fromCenter(center: Offset(center.dx - 1, center.dy - 14), width: 3.0, height: 1.5),
      _sharedFillPaint,
    );
    canvas.drawRect(
      Rect.fromCenter(center: Offset(center.dx - 1, center.dy - 10), width: 3.0, height: 1.5),
      _sharedFillPaint,
    );
    canvas.drawRect(
      Rect.fromCenter(center: Offset(center.dx - 1, center.dy - 6), width: 2.5, height: 1.5),
      _sharedFillPaint,
    );
  }

  /// 2. Kurgan Mahzeni (Granary Vault / Bulk Buffer - Seviye Kademeli)
  static void drawVoxelGranaryVault(
    Canvas canvas,
    Offset center, {
    int level = 1,
    double animTime = 0.0,
  }) {
    final int safeLevel = math.max(1, level);
    final double baseW = safeLevel >= 6 ? 26.0 : (safeLevel >= 3 ? 24.0 : 22.0);
    final double baseD = safeLevel >= 6 ? 24.0 : (safeLevel >= 3 ? 22.0 : 20.0);

    // Taş Temel
    drawIsoCube(
      canvas,
      center,
      w: baseW,
      d: baseD,
      h: (safeLevel >= 3 ? 10.0 : 8.0),
      topColor: safeLevel >= 6 ? const Color(0xFF334155) : const Color(0xFF475569),
      leftColor: safeLevel >= 6 ? const Color(0xFF1E293B) : const Color(0xFF334155),
      rightColor: safeLevel >= 6 ? const Color(0xFF0F172A) : const Color(0xFF1E293B),
      drawShadow: true,
    );

    // Ahşap Takviyeli Çatı
    final Offset roofBase = Offset(center.dx, center.dy - (safeLevel >= 3 ? 9.0 : 7.0));
    drawIsoCube(
      canvas,
      roofBase,
      w: (baseW - 4.0),
      d: (baseD - 4.0),
      h: (safeLevel >= 3 ? 8.0 : 6.0),
      topColor: safeLevel >= 6 ? const Color(0xFFD97706) : const Color(0xFFB45309),
      leftColor: safeLevel >= 6 ? const Color(0xFFB45309) : const Color(0xFF92400E),
      rightColor: safeLevel >= 6 ? const Color(0xFF92400E) : const Color(0xFF78350F),
    );

    // Kapı ve Tahıl Çuvalları
    drawIsoCube(
      canvas,
      Offset(center.dx + 4, center.dy + 3),
      w: 6.0,
      d: 6.0,
      h: 5.0,
      topColor: const Color(0xFFF59E0B),
      leftColor: const Color(0xFFD97706),
      rightColor: const Color(0xFFB45309),
    );

    // Seviye 3+ Çoklu Tahıl Fıçıları
    if (safeLevel >= 3) {
      drawIsoCube(
        canvas,
        Offset(center.dx - 8, center.dy + 3),
        w: 5.0,
        d: 5.0,
        h: 6.0,
        topColor: const Color(0xFFD97706),
        leftColor: const Color(0xFFB45309),
        rightColor: const Color(0xFF92400E),
      );
    }

    // Seviye 6+ Kağanlık Mahzen Bayrağı ve Taş Mazgallar
    if (safeLevel >= 6) {
      drawIsoCube(
        canvas,
        Offset(center.dx, center.dy - 17.0),
        w: 2.5,
        d: 2.5,
        h: 8.0,
        topColor: const Color(0xFFFBBF24),
        leftColor: const Color(0xFFF59E0B),
        rightColor: const Color(0xFFD97706),
      );
    }
  }

  /// 3. Kımız Otağı (Kumis Yurt & Fermentation Lodge - Seviye Kademeli)
  static void drawVoxelKumisYurt(
    Canvas canvas,
    Offset center, {
    int level = 1,
    double animTime = 0.0,
  }) {
    final int safeLevel = math.max(1, level);
    final double yurtW = safeLevel >= 6 ? 24.0 : (safeLevel >= 3 ? 22.0 : 20.0);

    // Beyaz Keçe Kubbe Gövde
    drawIsoCube(
      canvas,
      center,
      w: yurtW,
      d: yurtW,
      h: (safeLevel >= 3 ? 12.0 : 10.0),
      topColor: const Color(0xFFF8FAFC),
      leftColor: const Color(0xFFE2E8F0),
      rightColor: const Color(0xFFCBD5E1),
      drawShadow: true,
    );

    // Çadır Kırmızı/Altın Göçebe Kuşağı
    _sharedFillPaint.color = safeLevel >= 6 ? const Color(0xFFF59E0B) : const Color(0xFFDC2626);
    canvas.drawRect(
      Rect.fromCenter(center: Offset(center.dx, center.dy - 4), width: yurtW * 0.7, height: 2.0),
      _sharedFillPaint,
    );

    // Kımız Fıçısı (Yayık)
    drawIsoCube(
      canvas,
      Offset(center.dx + 7, center.dy + 2),
      w: 5.0,
      d: 5.0,
      h: 6.0,
      topColor: const Color(0xFF10B981),
      leftColor: const Color(0xFF059669),
      rightColor: const Color(0xFF047857),
    );

    // Seviye 3+ İkinci Kımız Yayığı & Yan Sundurma
    if (safeLevel >= 3) {
      drawIsoCube(
        canvas,
        Offset(center.dx + 10, center.dy - 2),
        w: 4.5,
        d: 4.5,
        h: 5.0,
        topColor: const Color(0xFF34D399),
        leftColor: const Color(0xFF10B981),
        rightColor: const Color(0xFF059669),
      );
    }

    // Seviye 6+ Çift Otağ Kompleksi & Bronz At Başı Sancağı
    if (safeLevel >= 6) {
      drawIsoCube(
        canvas,
        Offset(center.dx - 8, center.dy - 4),
        w: 12.0,
        d: 12.0,
        h: 7.0,
        topColor: const Color(0xFFF1F5F9),
        leftColor: const Color(0xFFCBD5E1),
        rightColor: const Color(0xFF94A3B8),
      );
      drawIsoCube(
        canvas,
        Offset(center.dx, center.dy - 14.0),
        w: 3.0,
        d: 3.0,
        h: 7.0,
        topColor: const Color(0xFFFDE047),
        leftColor: const Color(0xFFEAB308),
        rightColor: const Color(0xFFCA8A04),
      );
    }
  }

  /// 4. Keçe Çadırhanesi (Felt Tent Workshop - Seviye Kademeli)
  static void drawVoxelFeltTentWorkshop(
    Canvas canvas,
    Offset center, {
    int level = 1,
    double animTime = 0.0,
  }) {
    final int safeLevel = math.max(1, level);
    final double shopW = safeLevel >= 6 ? 26.0 : (safeLevel >= 3 ? 24.0 : 22.0);

    // Büyük Dokuma Çadırı
    drawIsoCube(
      canvas,
      center,
      w: shopW,
      d: 18.0,
      h: (safeLevel >= 3 ? 13.0 : 11.0),
      topColor: safeLevel >= 6 ? const Color(0xFFF59E0B) : const Color(0xFFD97706),
      leftColor: safeLevel >= 6 ? const Color(0xFFD97706) : const Color(0xFFB45309),
      rightColor: safeLevel >= 6 ? const Color(0xFFB45309) : const Color(0xFF92400E),
      drawShadow: true,
    );

    // Yan Kurutma İskeleleri & Kilim
    drawIsoCube(
      canvas,
      Offset(center.dx - 8, center.dy + 1),
      w: 5.0,
      d: 10.0,
      h: 4.0,
      topColor: const Color(0xFFFB923C),
      leftColor: const Color(0xFFEA580C),
      rightColor: const Color(0xFFC2410C),
    );

    // Seviye 3+ Yün Eğirme Çıkrığı ve Boya Kazanları
    if (safeLevel >= 3) {
      drawIsoCube(
        canvas,
        Offset(center.dx + 8, center.dy + 4),
        w: 5.0,
        d: 5.0,
        h: 5.0,
        topColor: const Color(0xFFEF4444),
        leftColor: const Color(0xFFDC2626),
        rightColor: const Color(0xFFB91C1C),
      );
    }

    // Seviye 6+ İpek ve Kağanlık Kilim Panoları
    if (safeLevel >= 6) {
      drawIsoCube(
        canvas,
        Offset(center.dx, center.dy - 15.0),
        w: 8.0,
        d: 3.0,
        h: 5.0,
        topColor: const Color(0xFFFEF3C7),
        leftColor: const Color(0xFFFDE68A),
        rightColor: const Color(0xFFFCD34D),
      );
    }
  }

  /// 5. Şam Çeliği Dökümhanesi (Damascus Steel Forge - Seviye Kademeli)
  static void drawVoxelDamascusForge(
    Canvas canvas,
    Offset center, {
    int level = 1,
    double animTime = 0.0,
  }) {
    final int safeLevel = math.max(1, level);
    final double forgeW = safeLevel >= 6 ? 24.0 : (safeLevel >= 3 ? 22.0 : 20.0);

    // Döküm Fırını Gövdesi
    drawIsoCube(
      canvas,
      center,
      w: forgeW,
      d: 18.0,
      h: (safeLevel >= 3 ? 14.0 : 12.0),
      topColor: const Color(0xFF1E293B),
      leftColor: const Color(0xFF0F172A),
      rightColor: const Color(0xFF020617),
      drawShadow: true,
    );

    // Köz & Ateş Parıltısı
    final double emberPulse = 0.7 + 0.3 * math.sin(animTime * 5.0);
    drawIsoCube(
      canvas,
      Offset(center.dx - 2, center.dy - 3),
      w: 7.0,
      d: 7.0,
      h: 4.0,
      topColor: Color(0xFFEF4444).withValues(alpha: emberPulse),
      leftColor: Color(0xFFDC2626).withValues(alpha: emberPulse),
      rightColor: Color(0xFFB91C1C).withValues(alpha: emberPulse),
    );

    // Örs & Çelik Külçesi
    drawIsoCube(
      canvas,
      Offset(center.dx + 7, center.dy + 3),
      w: 5.0,
      d: 5.0,
      h: 5.0,
      topColor: const Color(0xFF94A3B8),
      leftColor: const Color(0xFF64748B),
      rightColor: const Color(0xFF475569),
    );

    // Seviye 3+ Su Verme Havuzu (Quenching Basin)
    if (safeLevel >= 3) {
      drawIsoCube(
        canvas,
        Offset(center.dx - 8, center.dy + 3),
        w: 5.0,
        d: 5.0,
        h: 4.0,
        topColor: const Color(0xFF38BDF8),
        leftColor: const Color(0xFF0284C7),
        rightColor: const Color(0xFF0369A1),
      );
    }

    // Seviye 6+ Çift Baca & Altın Kakmalı Şam Kılıç Standı
    if (safeLevel >= 6) {
      drawIsoCube(
        canvas,
        Offset(center.dx - 4, center.dy - 16.0),
        w: 4.0,
        d: 4.0,
        h: 8.0,
        topColor: const Color(0xFF64748B),
        leftColor: const Color(0xFF475569),
        rightColor: const Color(0xFF334155),
      );
      drawIsoCube(
        canvas,
        Offset(center.dx + 4, center.dy - 16.0),
        w: 4.0,
        d: 4.0,
        h: 8.0,
        topColor: const Color(0xFF64748B),
        leftColor: const Color(0xFF475569),
        rightColor: const Color(0xFF334155),
      );
    }
  }
}
