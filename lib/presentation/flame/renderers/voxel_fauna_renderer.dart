import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 3D Voxel İzometrik Derinlik Sıralı Canlı Render Motoru (Depth-Sorted Voxel Fauna Engine)
/// Her voksel prizması 3D lokal koordinatlarından izometrik kamera derinliğine (Z-order) göre
/// sıralanarak çizilir; böylece gövdenin arkasında kalan bacaklar ASLA önde görünmez.
class VoxelFaunaRenderer {
  static const double isoAngle = 30.0 * (math.pi / 180.0);
  static final double cosIso = math.cos(isoAngle);
  static final double sinIso = math.sin(isoAngle);

  // Zero-GC Reusable static Paint & Path pools
  static final Paint _sharedFillPaint = Paint()..style = PaintingStyle.fill;
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

  // ===========================================================================
  // ZERO-GC DERİNLİK SIRALAMA MOTORU (PAINTER'S ALGORITHM BUFFER)
  // ===========================================================================
  static final List<_VoxelPrimitive> _pool = List.generate(64, (_) => _VoxelPrimitive());
  static int _count = 0;

  static void _clear() {
    _count = 0;
  }

  /// 3D Lokal Koordinatlardan (lx, ly, lz) Derinlik Sıralı Voksel Ekler
  /// lx: Boyuna eksen (Kuyruk: -lx, Baş: +lx)
  /// ly: Enine eksen (Uzak taraf: -ly, Yakın taraf: +ly)
  /// lz: Dikey yükseklik (Zemin: 0, Yukarı: +lz)
  static void _addVoxel({
    required double lx,
    required double ly,
    required double lz,
    required double w,
    required double d,
    required double h,
    required Color topColor,
    required Color leftColor,
    required Color rightColor,
    required Offset origin,
    required double scale,
    bool drawShadow = false,
    double shadowOpacity = 0.28,
    bool flipX = false,
  }) {
    if (_count >= _pool.length) return;
    final prim = _pool[_count++];

    // Flip X durumunda lateral eksen ters çevrilir
    final double effLx = flipX ? -lx : lx;
    final double effLy = flipX ? -ly : ly;

    // İzometrik ekran projeksiyonu
    final double sx = origin.dx + (effLx - effLy) * cosIso * scale;
    final double sy = origin.dy + (effLx + effLy) * sinIso * scale - lz * scale;

    // İzometrik Kamera Derinliği: Derinlik ne kadar büyükse kameraya o kadar yakındır (son çizilir)
    final double depth = (effLx + effLy) * 100.0 + lz;

    prim
      ..screenX = sx
      ..screenY = sy
      ..w = w * scale
      ..d = d * scale
      ..h = h * scale
      ..depth = depth
      ..topColor = topColor
      ..leftColor = flipX ? rightColor : leftColor
      ..rightColor = flipX ? leftColor : rightColor
      ..drawShadow = drawShadow
      ..shadowOpacity = shadowOpacity;
  }

  /// Bufferdaki tüm vokselleri derinliklerine göre sıralar ve Canvas'a basar (Zero-GC Insertion Sort)
  static void _flush(Canvas canvas) {
    // Küçük diziler için sıfır bellek tahsisli In-place Insertion Sort
    for (int i = 1; i < _count; i++) {
      int j = i;
      while (j > 0 && _pool[j - 1].depth > _pool[j].depth) {
        _swapPrimitive(j - 1, j);
        j--;
      }
    }

    // Sıralanmış derinlikte (Arkadan Öne) çiz
    for (int i = 0; i < _count; i++) {
      final p = _pool[i];
      drawIsoCube(
        canvas,
        Offset(p.screenX, p.screenY),
        w: p.w,
        d: p.d,
        h: p.h,
        topColor: p.topColor,
        leftColor: p.leftColor,
        rightColor: p.rightColor,
        drawShadow: p.drawShadow,
        shadowOpacity: p.shadowOpacity,
      );
    }
  }

  static void _swapPrimitive(int i, int j) {
    final a = _pool[i];
    final b = _pool[j];

    final tx = a.screenX; a.screenX = b.screenX; b.screenX = tx;
    final ty = a.screenY; a.screenY = b.screenY; b.screenY = ty;
    final tw = a.w; a.w = b.w; b.w = tw;
    final td = a.d; a.d = b.d; b.d = td;
    final th = a.h; a.h = b.h; b.h = th;
    final tdepth = a.depth; a.depth = b.depth; b.depth = tdepth;
    final ttop = a.topColor; a.topColor = b.topColor; b.topColor = ttop;
    final tleft = a.leftColor; a.leftColor = b.leftColor; b.leftColor = tleft;
    final tright = a.rightColor; a.rightColor = b.rightColor; b.rightColor = tright;
    final tshad = a.drawShadow; a.drawShadow = b.drawShadow; b.drawShadow = tshad;
    final topac = a.shadowOpacity; a.shadowOpacity = b.shadowOpacity; b.shadowOpacity = topac;
  }

  /// 3D İzometrik Voksel Prizması Çizer
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
    double shadowOpacity = 0.28,
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

    final double tFrontY = bFrontY - h;
    final double tRightY = bRightY - h;
    final double tLeftY = bLeftY - h;
    final double tBackY = bBackY - h;

    // 0. Yönlü İzometrik Zemin Gölgesi
    if (drawShadow) {
      final double shadowLength = h * 0.45;
      final double sOffsetBx = shadowLength * cosIso;
      final double sOffsetBy = shadowLength * sinIso;

      _cubeShadowPath
        ..reset()
        ..moveTo(bLeftX, bLeftY)
        ..lineTo(bFrontX, bFrontY)
        ..lineTo(bRightX, bRightY)
        ..lineTo(bRightX + sOffsetBx, bRightY + sOffsetBy)
        ..lineTo(bBackX + sOffsetBx, bBackY + sOffsetBy)
        ..lineTo(bLeftX + sOffsetBx * 0.5, bLeftY + sOffsetBy * 0.5)
        ..close();

      _cubeShadowPaint.color = Colors.black.withValues(alpha: shadowOpacity * 0.85);
      canvas.drawPath(_cubeShadowPath, _cubeShadowPaint);

      _cubePenumbraPath
        ..reset()
        ..moveTo(bLeftX - 1.0, bLeftY)
        ..lineTo(bFrontX, bFrontY + 1.0)
        ..lineTo(bRightX + 1.0, bRightY)
        ..lineTo(bRightX + sOffsetBx + 2.0, bRightY + sOffsetBy + 1.0)
        ..lineTo(bBackX + sOffsetBx + 1.0, bBackY + sOffsetBy - 1.0)
        ..close();

      _cubePenumbraPaint.color = Colors.black.withValues(alpha: shadowOpacity * 0.35);
      canvas.drawPath(_cubePenumbraPath, _cubePenumbraPaint);
    }

    // 1. Sol Yüzey
    _cubeLeftPath
      ..reset()
      ..moveTo(bLeftX, bLeftY)
      ..lineTo(bFrontX, bFrontY)
      ..lineTo(bFrontX, tFrontY)
      ..lineTo(bLeftX, tLeftY)
      ..close();
    _sharedFillPaint.color = leftColor;
    canvas.drawPath(_cubeLeftPath, _sharedFillPaint);

    // 2. Sağ Yüzey
    _cubeRightPath
      ..reset()
      ..moveTo(bFrontX, bFrontY)
      ..lineTo(bRightX, bRightY)
      ..lineTo(bRightX, tRightY)
      ..lineTo(bFrontX, tFrontY)
      ..close();
    _sharedFillPaint.color = rightColor;
    canvas.drawPath(_cubeRightPath, _sharedFillPaint);

    // 3. Üst Yüzey
    _cubeTopPath
      ..reset()
      ..moveTo(bFrontX, tFrontY)
      ..lineTo(bRightX, tRightY)
      ..lineTo(bBackX, tBackY)
      ..lineTo(bLeftX, tLeftY)
      ..close();
    _sharedFillPaint.color = topColor;
    canvas.drawPath(_cubeTopPath, _sharedFillPaint);

    // 4. Kenar Işığı
    if (specularHighlight && w >= 2.0 && h >= 1.5) {
      _cubeSpecularPaint
        ..color = Colors.white.withValues(alpha: 0.28)
        ..strokeWidth = 1.0;
      _cubeSpecularPath
        ..reset()
        ..moveTo(bLeftX, tLeftY)
        ..lineTo(bBackX, tBackY)
        ..lineTo(bRightX, tRightY);
      canvas.drawPath(_cubeSpecularPath, _cubeSpecularPaint);

      _cubeSpecularPaint.color = Colors.black.withValues(alpha: 0.22);
      canvas.drawLine(Offset(bLeftX, bLeftY), Offset(bFrontX, bFrontY), _cubeSpecularPaint);
      canvas.drawLine(Offset(bFrontX, bFrontY), Offset(bRightX, bRightY), _cubeSpecularPaint);
    }
  }

  // ===========================================================================
  // 1. BOZKIR YILKI ATI (KUSURSUZ DERİNLİK SIRALAMALI ASİL MONOLİTİK ANATOMİ)
  // ===========================================================================
  static void drawHorse(
    Canvas canvas,
    Offset pos, {
    double animTime = 0.0,
    double scale = 1.0,
    int seed = 0,
    bool flipX = false,
    double startleProgress = 0.0,
  }) {
    final double timeOffset = (seed * 2.83) % 20.0;
    final double t = animTime + timeOffset;
    final int coatVariant = seed % 4;

    // Asil, sakin ve stabil nefes alma salınımı
    double bobZ = math.sin(t * 1.2) * 0.35;
    double headTilt = math.sin(t * 1.4) * 0.3;
    double headYaw = math.sin(t * 1.0) * 0.4;
    final double tailWave = math.sin(t * 2.5) * 0.8;
    final double maneWave = math.sin(t * 2.0) * 0.5;

    if (startleProgress > 0.0) {
      final double jump = math.sin(startleProgress * math.pi) * 3.0;
      bobZ += jump;
      headTilt = -1.5;
    }

    Color coatTop, coatMid, coatDark;
    Color maneTop, maneDark;
    const Color muzzleColor = Color(0xFF1E293B);

    switch (coatVariant) {
      case 0: // Doru
        coatTop = const Color(0xFFD97706);
        coatMid = const Color(0xFF92400E);
        coatDark = const Color(0xFF451A03);
        maneTop = const Color(0xFF1E293B);
        maneDark = const Color(0xFF020617);
        break;
      case 1: // Yağız
        coatTop = const Color(0xFF334155);
        coatMid = const Color(0xFF1E293B);
        coatDark = const Color(0xFF020617);
        maneTop = const Color(0xFF0F172A);
        maneDark = const Color(0xFF000000);
        break;
      case 2: // Kır
        coatTop = const Color(0xFFFFFFFF);
        coatMid = const Color(0xFFCBD5E1);
        coatDark = const Color(0xFF64748B);
        maneTop = const Color(0xFFF1F5F9);
        maneDark = const Color(0xFF94A3B8);
        break;
      case 3: // Alaca
      default:
        coatTop = const Color(0xFFF59E0B);
        coatMid = const Color(0xFFB45309);
        coatDark = const Color(0xFF78350F);
        maneTop = const Color(0xFFFEF08A);
        maneDark = const Color(0xFFD97706);
        break;
    }

    _clear();

    // 1. ARKA-UZAK BACAK (Far Rear Leg: lx = -4.5, ly = -2.6) -> Derinlikte en arkadadır
    _addVoxel(
      lx: -4.5, ly: -2.6, lz: 0.0,
      w: 2.6, d: 2.6, h: 7.5,
      topColor: coatMid, leftColor: coatDark, rightColor: coatDark,
      origin: pos, scale: scale, flipX: flipX,
    );

    // 2. ÖN-UZAK BACAK (Far Front Leg: lx = 4.5, ly = -2.6)
    _addVoxel(
      lx: 4.5, ly: -2.6, lz: 0.0,
      w: 2.6, d: 2.6, h: 7.5,
      topColor: coatMid, leftColor: coatDark, rightColor: coatDark,
      origin: pos, scale: scale, flipX: flipX,
    );

    // 3. KUYRUK (Tail: lx = -8.5, ly = 0.0, lz = 4.0)
    _addVoxel(
      lx: -8.5, ly: tailWave, lz: 4.0 + bobZ,
      w: 2.8, d: 2.8, h: 9.0,
      topColor: maneTop, leftColor: maneDark, rightColor: maneDark,
      origin: pos, scale: scale, flipX: flipX,
    );

    // 4. TEK PARÇA MONOLİTİK GÖVDE (Torso Core: lx = 0.0, ly = 0.0, lz = 7.0) -> Uzak bacakların üstünü örter
    _addVoxel(
      lx: 0.0, ly: 0.0, lz: 7.0 + bobZ,
      w: 15.5, d: 8.5, h: 8.5,
      topColor: coatTop, leftColor: coatMid, rightColor: coatDark,
      origin: pos, scale: scale, drawShadow: true, shadowOpacity: 0.35, flipX: flipX,
    );

    // Alaca Benek
    if (coatVariant == 3) {
      _addVoxel(
        lx: 1.0, ly: 0.0, lz: 15.2 + bobZ,
        w: 5.0, d: 5.0, h: 0.6,
        topColor: const Color(0xFFFFFFFF), leftColor: const Color(0xFFE2E8F0), rightColor: const Color(0xFFCBD5E1),
        origin: pos, scale: scale, flipX: flipX,
      );
    }

    // 5. GÜÇLÜ OMUZ & SAĞRI KAS KABARTMALARI
    _addVoxel(
      lx: -4.0, ly: 0.0, lz: 7.0 + bobZ,
      w: 6.8, d: 8.8, h: 8.8,
      topColor: coatTop, leftColor: coatMid, rightColor: coatDark,
      origin: pos, scale: scale, flipX: flipX,
    );
    _addVoxel(
      lx: 3.8, ly: 0.0, lz: 7.0 + bobZ,
      w: 6.8, d: 8.8, h: 8.8,
      topColor: coatTop, leftColor: coatMid, rightColor: coatDark,
      origin: pos, scale: scale, flipX: flipX,
    );

    // 6. ARKA-YAKIN BACAK (Near Rear Leg: lx = -4.5, ly = 2.6) -> Gövdenin önünde durur
    _addVoxel(
      lx: -4.5, ly: 2.6, lz: 0.0,
      w: 2.6, d: 2.6, h: 7.5,
      topColor: coatTop, leftColor: coatMid, rightColor: coatDark,
      origin: pos, scale: scale, flipX: flipX,
    );

    // 7. ÖN-YAKIN BACAK (Near Front Leg: lx = 4.5, ly = 2.6) -> Gövdenin önünde durur
    _addVoxel(
      lx: 4.5, ly: 2.6, lz: 0.0,
      w: 2.6, d: 2.6, h: 7.5,
      topColor: coatTop, leftColor: coatMid, rightColor: coatDark,
      origin: pos, scale: scale, flipX: flipX,
    );

    // 8. ASİL BOYUN (Neck: lx = 6.0, ly = headYaw, lz = 10.5)
    _addVoxel(
      lx: 6.0, ly: headYaw, lz: 10.5 + bobZ + headTilt,
      w: 5.5, d: 5.5, h: 9.0,
      topColor: coatTop, leftColor: coatMid, rightColor: coatDark,
      origin: pos, scale: scale, flipX: flipX,
    );

    // 9. YELE (Mane: lx = 5.5, ly = -0.5 + maneWave, lz = 12.0)
    _addVoxel(
      lx: 5.5, ly: -0.5 + maneWave, lz: 12.0 + bobZ + headTilt,
      w: 2.5, d: 4.2, h: 8.0,
      topColor: maneTop, leftColor: maneDark, rightColor: maneDark,
      origin: pos, scale: scale, flipX: flipX,
    );

    // 10. BAŞ (Head: lx = 8.8, ly = headYaw, lz = 14.5)
    _addVoxel(
      lx: 8.8, ly: headYaw, lz: 14.5 + bobZ + headTilt,
      w: 5.5, d: 5.0, h: 5.0,
      topColor: coatTop, leftColor: coatMid, rightColor: coatDark,
      origin: pos, scale: scale, flipX: flipX,
    );

    // Beyaz Alın Sakıtı
    if (coatVariant == 0 || coatVariant == 3) {
      _addVoxel(
        lx: 9.2, ly: headYaw, lz: 16.5 + bobZ + headTilt,
        w: 1.5, d: 3.0, h: 1.8,
        topColor: const Color(0xFFFFFFFF), leftColor: const Color(0xFFE2E8F0), rightColor: const Color(0xFFCBD5E1),
        origin: pos, scale: scale, flipX: flipX,
      );
    }

    // 11. BURUN / AĞIZ (Muzzle: lx = 12.0, ly = headYaw, lz = 13.5)
    _addVoxel(
      lx: 12.0, ly: headYaw, lz: 13.5 + bobZ + headTilt,
      w: 3.6, d: 3.6, h: 3.5,
      topColor: muzzleColor, leftColor: const Color(0xFF0F172A), rightColor: const Color(0xFF020617),
      origin: pos, scale: scale, flipX: flipX,
    );

    // 12. SİVRİ KULAKLAR
    _addVoxel(
      lx: 7.8, ly: headYaw - 1.2, lz: 18.8 + bobZ + headTilt,
      w: 1.4, d: 1.4, h: 2.6,
      topColor: coatTop, leftColor: coatMid, rightColor: coatDark,
      origin: pos, scale: scale, flipX: flipX,
    );
    _addVoxel(
      lx: 7.8, ly: headYaw + 1.2, lz: 18.8 + bobZ + headTilt,
      w: 1.4, d: 1.4, h: 2.6,
      topColor: coatTop, leftColor: coatMid, rightColor: coatDark,
      origin: pos, scale: scale, flipX: flipX,
    );

    // Tüm vokselleri derinliğe göre sıralayıp çiz
    _flush(canvas);
  }

  // ===========================================================================
  // 2. KOÇ, KOYUN VE KUZU (DERİNLİK SIRALAMALI 3D BULUT YÜN)
  // ===========================================================================
  static void drawSheep(
    Canvas canvas,
    Offset pos, {
    double animTime = 0.0,
    double scale = 1.0,
    int seed = 0,
    bool flipX = false,
  }) {
    final int behavior = seed % 4;
    final int coat = ((seed * 7) ~/ 3) % 4;
    final double timeOffset = (seed * 2.37) % 20.0;
    final double t = animTime + timeOffset;

    double bobZ = 0.0;
    double headTilt = 0.0;
    double headYaw = 0.0;
    double chew = 0.0;
    double tailWag = math.sin(t * 6.0) * 0.8;

    Color woolTop, woolMid, woolDark;

    switch (coat) {
      case 1: // Kara Koyun
        woolTop = const Color(0xFF475569);
        woolMid = const Color(0xFF1E293B);
        woolDark = const Color(0xFF020617);
        break;
      case 2: // Karamel
        woolTop = const Color(0xFFF59E0B);
        woolMid = const Color(0xFFB45309);
        woolDark = const Color(0xFF78350F);
        break;
      case 3:
      case 0:
      default:
        woolTop = const Color(0xFFFFFFFF);
        woolMid = const Color(0xFFE2E8F0);
        woolDark = const Color(0xFF94A3B8);
        break;
    }

    if (behavior == 0) {
      if (t % 7.0 < 4.8) {
        headTilt = -2.5;
        chew = math.sin(t * 7.5) * 0.4;
      } else {
        headYaw = math.sin(t * 2.0) * 0.8;
      }
    } else if (behavior == 1) {
      headTilt = 1.0;
      headYaw = (t % 6.0 < 3.0) ? 1.0 : -1.0;
    }

    _clear();

    // 1. Uzak Bacaklar
    _addVoxel(lx: -3.5, ly: -2.8, lz: 0.0, w: 2.0, d: 2.0, h: 4.0, topColor: const Color(0xFF1E293B), leftColor: const Color(0xFF0F172A), rightColor: const Color(0xFF020617), origin: pos, scale: scale, flipX: flipX);
    _addVoxel(lx: 3.5, ly: -2.8, lz: 0.0, w: 2.0, d: 2.0, h: 4.0, topColor: const Color(0xFF1E293B), leftColor: const Color(0xFF0F172A), rightColor: const Color(0xFF020617), origin: pos, scale: scale, flipX: flipX);

    // 2. Kuyruk
    _addVoxel(lx: -6.5, ly: tailWag, lz: 4.0 + bobZ, w: 2.8, d: 2.8, h: 2.8, topColor: woolTop, leftColor: woolMid, rightColor: woolDark, origin: pos, scale: scale, flipX: flipX);

    // 3. Gövde Yünü
    _addVoxel(lx: 0.0, ly: 0.0, lz: 3.5 + bobZ, w: 12.5, d: 10.5, h: 8.5, topColor: woolTop, leftColor: woolMid, rightColor: woolDark, origin: pos, scale: scale, drawShadow: true, shadowOpacity: 0.28, flipX: flipX);
    _addVoxel(lx: 0.0, ly: 0.0, lz: 9.5 + bobZ, w: 9.0, d: 8.0, h: 3.0, topColor: woolTop, leftColor: woolMid, rightColor: woolDark, origin: pos, scale: scale, flipX: flipX);

    // 4. Yakın Bacaklar
    _addVoxel(lx: -3.5, ly: 2.8, lz: 0.0, w: 2.0, d: 2.0, h: 4.0, topColor: const Color(0xFF334155), leftColor: const Color(0xFF1E293B), rightColor: const Color(0xFF0F172A), origin: pos, scale: scale, flipX: flipX);
    _addVoxel(lx: 3.5, ly: 2.8, lz: 0.0, w: 2.0, d: 2.0, h: 4.0, topColor: const Color(0xFF334155), leftColor: const Color(0xFF1E293B), rightColor: const Color(0xFF0F172A), origin: pos, scale: scale, flipX: flipX);

    // 5. Baş & Yüz
    _addVoxel(lx: 6.5, ly: headYaw + chew, lz: 5.5 + bobZ + headTilt, w: 5.2, d: 5.2, h: 5.2, topColor: const Color(0xFF334155), leftColor: const Color(0xFF1E293B), rightColor: const Color(0xFF0F172A), origin: pos, scale: scale, flipX: flipX);
    _addVoxel(lx: 9.2, ly: headYaw + chew, lz: 4.8 + bobZ + headTilt, w: 2.6, d: 2.6, h: 2.2, topColor: const Color(0xFFFDA4AF), leftColor: const Color(0xFFFB7185), rightColor: const Color(0xFFE11D48), origin: pos, scale: scale, flipX: flipX);

    // 6. Kulaklar
    _addVoxel(lx: 6.0, ly: headYaw - 2.5, lz: 8.5 + bobZ + headTilt, w: 1.6, d: 2.4, h: 1.6, topColor: const Color(0xFF475569), leftColor: const Color(0xFF334155), rightColor: const Color(0xFF1E293B), origin: pos, scale: scale, flipX: flipX);
    _addVoxel(lx: 6.0, ly: headYaw + 2.5, lz: 8.5 + bobZ + headTilt, w: 1.6, d: 2.4, h: 1.6, topColor: const Color(0xFF475569), leftColor: const Color(0xFF334155), rightColor: const Color(0xFF1E293B), origin: pos, scale: scale, flipX: flipX);

    _flush(canvas);
  }

  /// 5 Parçalı 3D Spiral Kıvrık Kehribar Boynuzlu Koç
  static void drawRam(
    Canvas canvas,
    Offset pos, {
    double animTime = 0.0,
    double scale = 1.0,
    int seed = 0,
    bool flipX = false,
  }) {
    drawSheep(canvas, pos, animTime: animTime, scale: scale, seed: seed, flipX: flipX);

    final double timeOffset = (seed * 2.37) % 20.0;
    final double t = animTime + timeOffset;
    final double headTilt = (t % 7.0 < 4.8) ? -2.5 : 0.0;

    const Color hornTop = Color(0xFFFBBF24);
    const Color hornMid = Color(0xFFD97706);
    const Color hornDark = Color(0xFF92400E);

    _clear();

    // Uzak Boynuz Kemeri
    _addVoxel(lx: 5.5, ly: -3.0, lz: 9.5 + headTilt, w: 2.4, d: 3.4, h: 2.6, topColor: hornTop, leftColor: hornMid, rightColor: hornDark, origin: pos, scale: scale, flipX: flipX);
    _addVoxel(lx: 3.8, ly: -3.5, lz: 7.5 + headTilt, w: 2.0, d: 2.4, h: 3.0, topColor: hornMid, leftColor: hornDark, rightColor: hornDark, origin: pos, scale: scale, flipX: flipX);

    // Yakın Boynuz Kemeri
    _addVoxel(lx: 5.5, ly: 3.0, lz: 9.5 + headTilt, w: 2.4, d: 3.4, h: 2.6, topColor: hornTop, leftColor: hornMid, rightColor: hornDark, origin: pos, scale: scale, flipX: flipX);
    _addVoxel(lx: 3.8, ly: 3.0, lz: 7.5 + headTilt, w: 2.0, d: 2.4, h: 3.0, topColor: hornMid, leftColor: hornDark, rightColor: hornDark, origin: pos, scale: scale, flipX: flipX);

    _flush(canvas);
  }

  /// Oynak Bozkır Kuzusu
  static void drawLamb(
    Canvas canvas,
    Offset pos, {
    double animTime = 0.0,
    double scale = 0.72,
    int seed = 0,
    bool flipX = false,
  }) {
    final double hop = (math.sin((animTime + seed) * 8.0).abs()) * 2.8 * scale;
    drawSheep(canvas, Offset(pos.dx, pos.dy - hop), animTime: animTime, scale: scale, seed: seed, flipX: flipX);
  }

  // ===========================================================================
  // 3. YIRTICILAR & YABAN HAYATI (KURT, DAĞ KEÇİSİ, TİLKİ)
  // ===========================================================================
  static void drawSteppeWolf(
    Canvas canvas,
    Offset pos, {
    double animTime = 0.0,
    double scale = 1.0,
    int seed = 0,
    bool flipX = false,
  }) {
    final double t = animTime + ((seed * 3.11) % 20.0);
    final double stalkBob = math.sin(t * 3.2) * 0.4;
    final double tailWave = math.sin(t * 4.2) * 1.5;

    const Color wolfTop = Color(0xFF64748B);
    const Color wolfMid = Color(0xFF475569);
    const Color wolfDark = Color(0xFF1E293B);

    _clear();

    // 1. Uzak Bacaklar
    _addVoxel(lx: -4.0, ly: -2.2, lz: 0.0, w: 2.0, d: 2.0, h: 5.0, topColor: wolfMid, leftColor: wolfDark, rightColor: wolfDark, origin: pos, scale: scale, flipX: flipX);
    _addVoxel(lx: 4.0, ly: -2.2, lz: 0.0, w: 2.0, d: 2.0, h: 5.0, topColor: wolfMid, leftColor: wolfDark, rightColor: wolfDark, origin: pos, scale: scale, flipX: flipX);

    // 2. Kuyruk
    _addVoxel(lx: -8.0, ly: tailWave, lz: 3.5 + stalkBob, w: 3.0, d: 3.0, h: 7.5, topColor: wolfMid, leftColor: wolfDark, rightColor: wolfDark, origin: pos, scale: scale, flipX: flipX);

    // 3. Gövde
    _addVoxel(lx: 0.0, ly: 0.0, lz: 4.5 + stalkBob, w: 14.5, d: 7.5, h: 7.0, topColor: wolfTop, leftColor: wolfMid, rightColor: wolfDark, origin: pos, scale: scale, drawShadow: true, shadowOpacity: 0.35, flipX: flipX);

    // 4. Yakın Bacaklar
    _addVoxel(lx: -4.0, ly: 2.2, lz: 0.0, w: 2.0, d: 2.0, h: 5.0, topColor: wolfTop, leftColor: wolfMid, rightColor: wolfDark, origin: pos, scale: scale, flipX: flipX);
    _addVoxel(lx: 4.0, ly: 2.2, lz: 0.0, w: 2.0, d: 2.0, h: 5.0, topColor: wolfTop, leftColor: wolfMid, rightColor: wolfDark, origin: pos, scale: scale, flipX: flipX);

    // 5. Alçak Baş & Keskin Çene
    _addVoxel(lx: 7.5, ly: 0.0, lz: 6.5 + stalkBob, w: 5.2, d: 4.8, h: 4.5, topColor: const Color(0xFF94A3B8), leftColor: wolfMid, rightColor: wolfDark, origin: pos, scale: scale, flipX: flipX);
    _addVoxel(lx: 10.5, ly: 0.0, lz: 5.5 + stalkBob, w: 3.2, d: 3.2, h: 2.8, topColor: const Color(0xFF0F172A), leftColor: const Color(0xFF020617), rightColor: const Color(0xFF000000), origin: pos, scale: scale, flipX: flipX);

    // 6. Kulaklar
    _addVoxel(lx: 6.8, ly: -1.4, lz: 10.2 + stalkBob, w: 1.4, d: 1.4, h: 3.0, topColor: const Color(0xFF334155), leftColor: const Color(0xFF1E293B), rightColor: const Color(0xFF0F172A), origin: pos, scale: scale, flipX: flipX);
    _addVoxel(lx: 6.8, ly: 1.4, lz: 10.2 + stalkBob, w: 1.4, d: 1.4, h: 3.0, topColor: const Color(0xFF334155), leftColor: const Color(0xFF1E293B), rightColor: const Color(0xFF0F172A), origin: pos, scale: scale, flipX: flipX);

    _flush(canvas);
  }

  static void drawMountainIbex(
    Canvas canvas,
    Offset pos, {
    double animTime = 0.0,
    double scale = 1.0,
    int seed = 0,
    bool flipX = false,
  }) {
    final double t = animTime + ((seed * 2.19) % 20.0);
    final double bobZ = math.sin(t * 1.4) * 0.3;

    const Color coatTop = Color(0xFF94A3B8);
    const Color coatMid = Color(0xFF64748B);
    const Color coatDark = Color(0xFF475569);

    _clear();

    // Uzak Bacaklar
    _addVoxel(lx: -3.5, ly: -2.2, lz: 0.0, w: 2.0, d: 2.0, h: 6.0, topColor: coatMid, leftColor: coatDark, rightColor: coatDark, origin: pos, scale: scale, flipX: flipX);
    _addVoxel(lx: 3.5, ly: -2.2, lz: 0.0, w: 2.0, d: 2.0, h: 6.0, topColor: coatMid, leftColor: coatDark, rightColor: coatDark, origin: pos, scale: scale, flipX: flipX);

    // Gövde
    _addVoxel(lx: 0.0, ly: 0.0, lz: 5.5 + bobZ, w: 11.0, d: 7.0, h: 6.5, topColor: coatTop, leftColor: coatMid, rightColor: coatDark, origin: pos, scale: scale, drawShadow: true, shadowOpacity: 0.30, flipX: flipX);

    // Yakın Bacaklar
    _addVoxel(lx: -3.5, ly: 2.2, lz: 0.0, w: 2.0, d: 2.0, h: 6.0, topColor: coatTop, leftColor: coatMid, rightColor: coatDark, origin: pos, scale: scale, flipX: flipX);
    _addVoxel(lx: 3.5, ly: 2.2, lz: 0.0, w: 2.0, d: 2.0, h: 6.0, topColor: coatTop, leftColor: coatMid, rightColor: coatDark, origin: pos, scale: scale, flipX: flipX);

    // Baş & Sakal
    _addVoxel(lx: 5.5, ly: 0.0, lz: 10.0 + bobZ, w: 4.8, d: 4.8, h: 4.8, topColor: const Color(0xFFCBD5E1), leftColor: coatMid, rightColor: coatDark, origin: pos, scale: scale, flipX: flipX);
    _addVoxel(lx: 6.5, ly: 0.0, lz: 6.5 + bobZ, w: 1.6, d: 1.6, h: 3.2, topColor: const Color(0xFF334155), leftColor: const Color(0xFF1E293B), rightColor: const Color(0xFF0F172A), origin: pos, scale: scale, flipX: flipX);

    // Geriye Kıvrık Boynuzlar
    _addVoxel(lx: 3.5, ly: -1.5, lz: 14.5 + bobZ, w: 2.2, d: 2.2, h: 7.5, topColor: const Color(0xFF334155), leftColor: const Color(0xFF1E293B), rightColor: const Color(0xFF0F172A), origin: pos, scale: scale, flipX: flipX);
    _addVoxel(lx: 3.5, ly: 1.5, lz: 14.5 + bobZ, w: 2.2, d: 2.2, h: 7.5, topColor: const Color(0xFF334155), leftColor: const Color(0xFF1E293B), rightColor: const Color(0xFF0F172A), origin: pos, scale: scale, flipX: flipX);

    _flush(canvas);
  }

  static void drawArcticFox(
    Canvas canvas,
    Offset pos, {
    double animTime = 0.0,
    double scale = 1.0,
    int seed = 0,
    bool flipX = false,
  }) {
    final double t = animTime + ((seed * 2.71) % 20.0);
    final double bobZ = math.sin(t * 2.0) * 0.3;
    final double tailSway = math.sin(t * 3.5) * 1.5;

    const Color furTop = Color(0xFFFFFFFF);
    const Color furMid = Color(0xFFF1F5F9);
    const Color furDark = Color(0xFFE2E8F0);

    _clear();

    // Uzak Bacaklar
    _addVoxel(lx: -3.0, ly: -2.0, lz: 0.0, w: 1.6, d: 1.6, h: 3.5, topColor: furMid, leftColor: furDark, rightColor: furDark, origin: pos, scale: scale, flipX: flipX);
    _addVoxel(lx: 3.0, ly: -2.0, lz: 0.0, w: 1.6, d: 1.6, h: 3.5, topColor: furMid, leftColor: furDark, rightColor: furDark, origin: pos, scale: scale, flipX: flipX);

    // Kabarık Kuyruk
    _addVoxel(lx: -6.5, ly: tailSway, lz: 3.0 + bobZ, w: 4.8, d: 4.8, h: 4.8, topColor: furTop, leftColor: furMid, rightColor: furDark, origin: pos, scale: scale, flipX: flipX);

    // Gövde
    _addVoxel(lx: 0.0, ly: 0.0, lz: 3.5 + bobZ, w: 9.5, d: 6.2, h: 5.5, topColor: furTop, leftColor: furMid, rightColor: furDark, origin: pos, scale: scale, drawShadow: true, shadowOpacity: 0.22, flipX: flipX);

    // Yakın Bacaklar
    _addVoxel(lx: -3.0, ly: 2.0, lz: 0.0, w: 1.6, d: 1.6, h: 3.5, topColor: furTop, leftColor: furMid, rightColor: furDark, origin: pos, scale: scale, flipX: flipX);
    _addVoxel(lx: 3.0, ly: 2.0, lz: 0.0, w: 1.6, d: 1.6, h: 3.5, topColor: furTop, leftColor: furMid, rightColor: furDark, origin: pos, scale: scale, flipX: flipX);

    // Baş & Siyah Uçlu Kulaklar
    _addVoxel(lx: 5.5, ly: 0.0, lz: 6.5 + bobZ, w: 4.5, d: 4.5, h: 4.0, topColor: furTop, leftColor: furMid, rightColor: furDark, origin: pos, scale: scale, flipX: flipX);
    _addVoxel(lx: 4.8, ly: -1.5, lz: 9.8 + bobZ, w: 1.5, d: 1.5, h: 2.6, topColor: const Color(0xFF334155), leftColor: const Color(0xFF1E293B), rightColor: const Color(0xFF0F172A), origin: pos, scale: scale, flipX: flipX);
    _addVoxel(lx: 4.8, ly: 1.5, lz: 9.8 + bobZ, w: 1.5, d: 1.5, h: 2.6, topColor: const Color(0xFF334155), leftColor: const Color(0xFF1E293B), rightColor: const Color(0xFF0F172A), origin: pos, scale: scale, flipX: flipX);

    _flush(canvas);
  }

  // ===========================================================================
  // 4. İPEK YOLU VE ÇÖL DEVESİ (BACTRIAN CAMEL)
  // ===========================================================================
  static void drawCamel(
    Canvas canvas,
    Offset pos, {
    double animTime = 0.0,
    double scale = 1.0,
    int seed = 0,
    bool flipX = false,
  }) {
    final double t = animTime + ((seed * 3.41) % 20.0);
    final double bobZ = math.sin(t * 1.6) * 0.4;
    final double headSway = math.sin(t * 1.8) * 0.8;

    const Color bodyTop = Color(0xFFF59E0B);
    const Color bodyMid = Color(0xFFB45309);
    const Color bodyDark = Color(0xFF78350F);

    _clear();

    // Uzak Bacaklar
    _addVoxel(lx: -5.0, ly: -3.5, lz: 0.0, w: 2.6, d: 2.6, h: 8.0, topColor: bodyMid, leftColor: bodyDark, rightColor: bodyDark, origin: pos, scale: scale, flipX: flipX);
    _addVoxel(lx: 5.0, ly: -3.5, lz: 0.0, w: 2.6, d: 2.6, h: 8.0, topColor: bodyMid, leftColor: bodyDark, rightColor: bodyDark, origin: pos, scale: scale, flipX: flipX);

    // Gövde Tabanı
    _addVoxel(lx: 0.0, ly: 0.0, lz: 7.5 + bobZ, w: 16.5, d: 10.0, h: 8.5, topColor: bodyTop, leftColor: bodyMid, rightColor: bodyDark, origin: pos, scale: scale, drawShadow: true, shadowOpacity: 0.35, flipX: flipX);

    // Çift Hörgüç
    _addVoxel(lx: -3.5, ly: 0.0, lz: 15.5 + bobZ, w: 5.0, d: 6.0, h: 6.0, topColor: const Color(0xFFFDE047), leftColor: const Color(0xFFD97706), rightColor: const Color(0xFF92400E), origin: pos, scale: scale, flipX: flipX);
    _addVoxel(lx: 4.0, ly: 0.0, lz: 15.5 + bobZ, w: 5.0, d: 6.0, h: 6.0, topColor: const Color(0xFFFDE047), leftColor: const Color(0xFFD97706), rightColor: const Color(0xFF92400E), origin: pos, scale: scale, flipX: flipX);

    // Göçebe Eyer Örtüsü
    _addVoxel(lx: 0.2, ly: 0.0, lz: 12.0 + bobZ, w: 6.0, d: 11.5, h: 3.0, topColor: const Color(0xFFDC2626), leftColor: const Color(0xFFB91C1C), rightColor: const Color(0xFF991B1B), origin: pos, scale: scale, flipX: flipX);

    // Yakın Bacaklar
    _addVoxel(lx: -5.0, ly: 3.5, lz: 0.0, w: 2.6, d: 2.6, h: 8.0, topColor: bodyTop, leftColor: bodyMid, rightColor: bodyDark, origin: pos, scale: scale, flipX: flipX);
    _addVoxel(lx: 5.0, ly: 3.5, lz: 0.0, w: 2.6, d: 2.6, h: 8.0, topColor: bodyTop, leftColor: bodyMid, rightColor: bodyDark, origin: pos, scale: scale, flipX: flipX);

    // Uzun S-Boyun & Baş
    _addVoxel(lx: 8.5, ly: headSway, lz: 14.0 + bobZ, w: 5.0, d: 5.0, h: 7.0, topColor: const Color(0xFFF59E0B), leftColor: bodyMid, rightColor: bodyDark, origin: pos, scale: scale, flipX: flipX);
    _addVoxel(lx: 11.5, ly: headSway, lz: 18.0 + bobZ, w: 5.5, d: 4.5, h: 4.5, topColor: const Color(0xFFFBBF24), leftColor: bodyMid, rightColor: bodyDark, origin: pos, scale: scale, flipX: flipX);
    _addVoxel(lx: 14.5, ly: headSway, lz: 17.5 + bobZ, w: 3.5, d: 3.5, h: 3.0, topColor: const Color(0xFF451A03), leftColor: const Color(0xFF331402), rightColor: const Color(0xFF220D01), origin: pos, scale: scale, flipX: flipX);

    _flush(canvas);
  }

  /// Kervan Yük Devesi
  static void drawCaravanCamel(
    Canvas canvas,
    Offset center, {
    required double animTime,
    double walkCycle = 0.0,
    bool flipX = false,
  }) {
    final double bob = (math.sin(walkCycle * math.pi * 4).abs()) * 1.5;
    final double legSwing = math.sin(walkCycle * math.pi * 4) * 2.0;

    _clear();

    _addVoxel(lx: -3.0 - legSwing, ly: -2.5, lz: 0.0, w: 1.8, d: 1.8, h: 5.5, topColor: const Color(0xFF92400E), leftColor: const Color(0xFF78350F), rightColor: const Color(0xFF78350F), origin: center, scale: 1.0, flipX: flipX);
    _addVoxel(lx: 3.0 + legSwing, ly: -2.5, lz: 0.0, w: 1.8, d: 1.8, h: 5.5, topColor: const Color(0xFF92400E), leftColor: const Color(0xFF78350F), rightColor: const Color(0xFF78350F), origin: center, scale: 1.0, flipX: flipX);

    _addVoxel(lx: 0.0, ly: 0.0, lz: 5.5 + bob, w: 8.5, d: 5.5, h: 5.5, topColor: const Color(0xFFD97706), leftColor: const Color(0xFFB45309), rightColor: const Color(0xFF92400E), origin: center, scale: 1.0, drawShadow: true, shadowOpacity: 0.32, flipX: flipX);
    _addVoxel(lx: 0.0, ly: 0.0, lz: 9.0 + bob, w: 5.0, d: 7.0, h: 3.2, topColor: const Color(0xFF991B1B), leftColor: const Color(0xFF7F1D1D), rightColor: const Color(0xFF450A0A), origin: center, scale: 1.0, flipX: flipX);

    _addVoxel(lx: -3.0 + legSwing, ly: 2.5, lz: 0.0, w: 1.8, d: 1.8, h: 5.5, topColor: const Color(0xFFB45309), leftColor: const Color(0xFF92400E), rightColor: const Color(0xFF78350F), origin: center, scale: 1.0, flipX: flipX);
    _addVoxel(lx: 3.0 - legSwing, ly: 2.5, lz: 0.0, w: 1.8, d: 1.8, h: 5.5, topColor: const Color(0xFFB45309), leftColor: const Color(0xFF92400E), rightColor: const Color(0xFF78350F), origin: center, scale: 1.0, flipX: flipX);

    _addVoxel(lx: 4.8, ly: 0.0, lz: 9.5 + bob, w: 2.6, d: 2.6, h: 5.0, topColor: const Color(0xFFD97706), leftColor: const Color(0xFFB45309), rightColor: const Color(0xFF92400E), origin: center, scale: 1.0, flipX: flipX);
    _addVoxel(lx: 6.5, ly: 0.0, lz: 13.5 + bob, w: 3.2, d: 2.4, h: 2.2, topColor: const Color(0xFFF59E0B), leftColor: const Color(0xFFD97706), rightColor: const Color(0xFF92400E), origin: center, scale: 1.0, flipX: flipX);

    _flush(canvas);
  }

  /// Kuş çizimi devre dışı bırakılmıştır (no-op).
  static void drawSkyBird(
    Canvas canvas,
    Offset pos, {
    required double wingAnim,
    double scale = 1.0,
    Color bodyColor = const Color(0xFFFFFFFF),
    Color wingColor = const Color(0xFFF8FAFC),
    Color wingTipColor = const Color(0xFF94A3B8),
    bool drawShadow = true,
  }) {}
}

class _VoxelPrimitive {
  double screenX = 0;
  double screenY = 0;
  double w = 0;
  double d = 0;
  double h = 0;
  double depth = 0;
  Color topColor = Colors.white;
  Color leftColor = Colors.white;
  Color rightColor = Colors.white;
  bool drawShadow = false;
  double shadowOpacity = 0.28;
}
