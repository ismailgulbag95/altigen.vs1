import 'dart:ui';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart' show Colors, Color;
import '../../core/hex/hex_coordinates.dart';
import '../../core/hex/hex_math.dart';
import '../../domain/models/building_model.dart';
import '../../domain/models/game_state.dart';
import '../../domain/models/hex_tile_model.dart';
import 'components/floating_resource_number_component.dart';
import 'components/floating_voxel_cloud_component.dart';
import 'components/hex_tile_component.dart';
import 'components/snow_particle_emitter.dart';
import 'components/steppe_messenger_component.dart';
import 'components/caravan_convoy_component.dart';
import 'components/harvest_sparkle_emitter.dart';
import 'components/tile_conquer_poof_emitter.dart';
import 'components/worker_agent_component.dart';
import 'components/worker_flow_arrow_component.dart';
import 'components/voxel_enemy_component.dart';
import 'components/voxel_projectile_component.dart';
import 'components/dynamic_lighting_overlay_component.dart';
import 'components/volumetric_sun_rays_component.dart';
import 'components/shockwave_effect_component.dart';
import 'renderers/viewport_culling_manager.dart';

class HexMapGame extends FlameGame {
  final void Function(HexAxial) onTileSelected;
  final bool Function(HexAxial)? onTileHarvest;
  late final World gameWorld;
  late final CameraComponent gameCamera;

  final Map<HexAxial, HexTileComponent> _tileComponents = {};
  final Map<HexAxial, WorkerAgentComponent> _workerComponents = {};
  final Map<String, CaravanConvoyComponent> _caravanComponents = {};
  final Map<String, VoxelEnemyComponent> _enemyComponents = {};
  final Set<String> _spawnedProjectileIds = {};
  final List<FloatingVoxelCloudComponent> _cloudComponents = [];
  late final SeasonWeatherParticleEmitter _weatherEmitter;
  late final SteppeMessengerComponent _steppeMessenger;
  late final WorkerFlowArrowComponent _workerFlowArrows;
  late final DynamicLightingOverlayComponent _lightingOverlay;
  late final VolumetricSunRaysComponent _sunRays;

  GameState? _lastState;
  double _currentZoom = 1.0;
  double _dayNightClock = 0.0;
  bool _isNight = false;

  // Kamera sürtünmesi / sönümleme (Smooth Pan Inertia)
  Vector2 _panVelocity = Vector2.zero();

  HexMapGame({
    required this.onTileSelected,
    this.onTileHarvest,
  });

  double get currentZoom => _currentZoom;
  Vector2 get cameraPosition => gameCamera.viewfinder.position;
  bool get isNight => _isNight;

  /// Koordinata ait HexTileComponent referansını döner
  HexTileComponent? getTileComponent(HexAxial coord) => _tileComponents[coord];

  /// Keşfedilmiş açık (sis olmayan) karo koordinatlarını döner
  List<HexAxial> getDiscoveredTileCoords() {
    return _tileComponents.entries
        .where((e) => !e.value.tileModel.isFog)
        .map((e) => e.key)
        .toList(growable: false);
  }

  /// Aktif kamera görüş alanının dünya koordinatlarındaki dikdörtgeni (Viewport Culling için)
  Rect get visibleWorldBounds {
    final vp = canvasSize;
    final halfW = (vp.x > 0 ? (vp.x / 2) : 600.0) / _currentZoom;
    final halfH = (vp.y > 0 ? (vp.y / 2) : 500.0) / _currentZoom;
    final camPos = gameCamera.viewfinder.position;
    const margin = 140.0;
    return Rect.fromLTRB(
      camPos.x - halfW - margin,
      camPos.y - halfH - margin,
      camPos.x + halfW + margin,
      camPos.y + halfH + margin,
    );
  }

  @override
  Future<void> onLoad() async {
    gameWorld = World();
    add(gameWorld);

    gameCamera = CameraComponent(world: gameWorld);
    gameCamera.viewfinder.position = Vector2(0, 0);
    gameCamera.viewfinder.anchor = Anchor.center;
    add(gameCamera);

    // 3D Voxel Yüzen Bulutlar
    _initFloatingClouds();

    // Seyrek Bozkır Kervanı / Ulak
    _steppeMessenger = SteppeMessengerComponent();
    gameWorld.add(_steppeMessenger);

    _weatherEmitter = SeasonWeatherParticleEmitter();
    gameWorld.add(_weatherEmitter);

    _workerFlowArrows = WorkerFlowArrowComponent();
    gameWorld.add(_workerFlowArrows);

    // Impeller Volumetrik Güneş Hüzmeleri (Gündüz & Yaz hüzmeleri)
    _sunRays = VolumetricSunRaysComponent();
    gameWorld.add(_sunRays);

    // Impeller 2.5D Dinamik Gece Işıklandırması & Fener Maskesi
    _lightingOverlay = DynamicLightingOverlayComponent();
    gameWorld.add(_lightingOverlay);

    if (_lastState != null) {
      _buildWorldFromState(_lastState!);
    }
  }

  @override
  void update(double dt) {
    super.update(dt);

    // Dinamik Gün/Gece Döngüsü (120 saniyede bir tam gün/gece turu)
    _dayNightClock += dt;
    final double cycle = (_dayNightClock % 120.0) / 120.0;
    final bool newIsNight = cycle > 0.65; // %65'ten sonrası gece

    if (newIsNight != _isNight) {
      _isNight = newIsNight;
      // Tüm karolara gece durumunu ilet
      for (final comp in _tileComponents.values) {
        comp.isNight = _isNight;
      }
    }

    // Impeller Işık Kaynaklarını Topla ve Gece Fenerlerini Güncelle
    if (_isNight) {
      final List<LightEmitter> emitters = [];
      for (final comp in _tileComponents.values) {
        if (!comp.tileModel.isOwned || comp.tileModel.isFog) continue;
        final bType = comp.tileModel.building?.type;
        if (bType == BuildingType.castle) {
          emitters.add(LightEmitter(
            position: comp.position,
            radius: 80.0,
            color: const Color(0xFFF59E0B),
            intensity: 1.2,
          ));
        } else if (bType == BuildingType.damascusForge || bType == BuildingType.bakery) {
          emitters.add(LightEmitter(
            position: comp.position,
            radius: 54.0,
            color: const Color(0xFFF97316),
            intensity: 1.0,
          ));
        } else if (comp.tileModel.hasShrine || comp.tileModel.hasKurgan) {
          emitters.add(LightEmitter(
            position: comp.position,
            radius: 64.0,
            color: const Color(0xFF38BDF8),
            intensity: 1.1,
          ));
        }
      }
      _lightingOverlay.updateLightingState(
        night: true,
        darkness: 0.65,
        emitters: emitters,
      );
      _sunRays.isEnabled = false;
    } else {
      _lightingOverlay.updateLightingState(
        night: false,
        darkness: 0.0,
        emitters: const [],
      );
      _sunRays.isEnabled = !(_lastState?.season.isZud ?? false);
    }

    // Frustum Culling: Kamera görüş alanını güncelle
    ViewportCullingManager.instance.updateVisibleBounds(visibleWorldBounds);

    // Pürüzsüz kamera sürükleme sönümlemesi (Pan Inertia)
    if (_panVelocity.length2 > 1.0) {
      gameCamera.viewfinder.position += _panVelocity * dt;
      _clampCameraPosition();
      _panVelocity *= 0.88; // Sönümleme katsayısı
    } else {
      _panVelocity = Vector2.zero();
    }
  }

  /// Bozkır Borusu, Sunak Uyandırma veya Kadim Keşif anında şok dalgası tetikler
  void triggerShockwave(Vector2 worldPosition) {
    final wave = ShockwaveEffectComponent(center: worldPosition);
    gameWorld.add(wave);
  }

  /// Haritanın ekrandan tamamen çıkıp kaybolmasını ve kilitlenme hissi yaratmasını engeller
  void _clampCameraPosition() {
    final pos = gameCamera.viewfinder.position;
    pos.x = pos.x.clamp(-1200.0, 1200.0);
    pos.y = pos.y.clamp(-1000.0, 1000.0);
  }

  void _initFloatingClouds() {
    final clouds = [
      FloatingVoxelCloudComponent(initialPosition: Vector2(-180, -140), speed: 3.2, cloudScale: 1.1),
      FloatingVoxelCloudComponent(initialPosition: Vector2(40, -180), speed: 4.2, cloudScale: 0.85),
      FloatingVoxelCloudComponent(initialPosition: Vector2(-60, 120), speed: 2.8, cloudScale: 1.0),
    ];
    for (final c in clouds) {
      _cloudComponents.add(c);
      gameWorld.add(c);
    }
  }

  void handleTapAtScreenPosition(Offset localPos, Size screenSize) {
    final double screenCenterX = screenSize.width / 2;
    final double screenCenterY = screenSize.height / 2;

    final double worldX =
        (localPos.dx - screenCenterX) / _currentZoom + gameCamera.viewfinder.position.x;
    final double worldY =
        (localPos.dy - screenCenterY) / _currentZoom + gameCamera.viewfinder.position.y;
    final tapWorld = Offset(worldX, worldY);

    if (_lastState == null || _lastState!.tiles.isEmpty) return;

    final approxCoord = HexMath.pixelToHex(
      tapWorld,
      hexSize: HexTileComponent.hexRadius,
    );

    // En doğru karoyu bulmak için yaklaşık koordinatı ve komşularını incele
    // Öncelik sırasına göre (öndeki/alttaki karolar önce) kontrol et
    final candidates = {
      approxCoord,
      ...approxCoord.neighbors,
      ...approxCoord.neighbors.expand((n) => n.neighbors),
    }.toList()
      ..sort((a, b) {
        final posA = HexMath.hexToPixel(a, hexSize: HexTileComponent.hexRadius);
        final posB = HexMath.hexToPixel(b, hexSize: HexTileComponent.hexRadius);
        return posB.dy.compareTo(posA.dy); // Öndeki (aşağıdaki) karolar önce kontrol edilir
      });

    HexAxial? matchedCoord;

    // 1. Aşama: Voksel/İzometrik üst yüzey poligon kontrolü
    for (final coord in candidates) {
      if (!_lastState!.tiles.containsKey(coord)) continue;
      final tile = _lastState!.tiles[coord]!;
      final tilePixel = HexMath.hexToPixel(coord, hexSize: HexTileComponent.hexRadius);
      final double elevation = HexTileComponent.getBiomeElevation(tile.biome, isFog: tile.isFog);
      final visualCenter = Offset(tilePixel.dx, tilePixel.dy - elevation);

      if (HexMath.isPointInsideHex(tapWorld, visualCenter, hexSize: HexTileComponent.hexRadius)) {
        matchedCoord = coord;
        break;
      }
    }

    // 2. Aşama: Eğer tam üst yüzeye denk gelmediyse (kenar/duvar tıklaması), en yakın görsel merkeze sahip karoyu seç
    if (matchedCoord == null) {
      double minDistance = double.infinity;
      for (final coord in candidates) {
        if (!_lastState!.tiles.containsKey(coord)) continue;
        final tile = _lastState!.tiles[coord]!;
        final tilePixel = HexMath.hexToPixel(coord, hexSize: HexTileComponent.hexRadius);
        final double elevation = HexTileComponent.getBiomeElevation(tile.biome, isFog: tile.isFog);
        final visualCenter = Offset(tilePixel.dx, tilePixel.dy - elevation);

        final double d = (tapWorld - visualCenter).distanceSquared;
        if (d < minDistance) {
          minDistance = d;
          matchedCoord = coord;
        }
      }
    }

    final tappedCoord = matchedCoord ?? approxCoord;

    if (_lastState!.tiles.containsKey(tappedCoord)) {
      final tile = _lastState!.tiles[tappedCoord]!;

      // Dokunulan karoyu zıplat (Bounce)
      if (_tileComponents.containsKey(tappedCoord)) {
        _tileComponents[tappedCoord]!.triggerTapBounce();
      }

      // Juicy Floating Number Efekti
      final tilePixel = HexMath.hexToPixel(tappedCoord, hexSize: HexTileComponent.hexRadius);
      final tileVec = Vector2(tilePixel.dx, tilePixel.dy - 20);

      if (tile.hasBuilding) {
        final b = tile.building!;
        if (b.type == BuildingType.castle) {
          onTileHarvest?.call(tappedCoord);
          gameWorld.add(
            FloatingResourceNumberComponent(
              position: tileVec,
              text: '+1 GIDA',
              bgColor: const Color(0xFF10B981),
              textColor: Colors.black,
            ),
          );
          gameWorld.add(
            HarvestSparkleEmitter(
              centerPosition: tileVec,
              isGolden: true,
              particleCount: 8,
            ),
          );
        } else if (b.accumulatedResource > 0) {
          final int amount = b.accumulatedResource.toInt();
          onTileHarvest?.call(tappedCoord);
          gameWorld.add(
            FloatingResourceNumberComponent(
              position: tileVec,
              text: _getHarvestResourceLabel(b.type, amount),
              bgColor: const Color(0xFF10B981),
              textColor: Colors.black,
            ),
          );
          gameWorld.add(
            HarvestSparkleEmitter(
              centerPosition: tileVec,
              isGolden: b.type == BuildingType.bakery || b.type == BuildingType.furniture,
              particleCount: (8 + (amount ~/ 4)).clamp(8, 18),
            ),
          );
        }
      } else if (!tile.isOwned && !tile.isFog) {
        // Fetih / İnşaat Puf Partikülü & Impeller Şok Dalgası
        gameWorld.add(TileConquerPoofEmitter(centerPosition: tileVec));
        triggerShockwave(tileVec);
      }

      onTileSelected(tappedCoord);
    }
  }

  String _getHarvestResourceLabel(BuildingType type, int amount) {
    switch (type) {
      case BuildingType.corn:
      case BuildingType.barley:
      case BuildingType.pasture:
      case BuildingType.orchard:
      case BuildingType.reindeerSanctuary:
      case BuildingType.herbalistYurt:
      case BuildingType.oasisCistern:
        return '+$amount GIDA';
      case BuildingType.lumberjack:
      case BuildingType.resinCamp:
        return '+$amount ODUN';
      case BuildingType.quarry:
        return '+$amount TAŞ';
      case BuildingType.fisherman:
        return '+$amount BALIK';
      case BuildingType.windmill:
        return '+$amount UN';
      case BuildingType.sawmill:
      case BuildingType.scribeWorkshop:
        return '+$amount KERESTE';
      case BuildingType.bakery:
      case BuildingType.caravanserai:
        return '+$amount EKMEK';
      case BuildingType.furniture:
        return '+$amount MOBİLYA';
      case BuildingType.mine:
      case BuildingType.permafrostDig:
      case BuildingType.obsidianForge:
      case BuildingType.celestialAnvil:
        return '+$amount MADEN';
      case BuildingType.runicStele:
        return '+$amount BİTİG';
      case BuildingType.kumisYurt:
        return '+$amount KIMIZ';
      case BuildingType.feltTentWorkshop:
        return '+$amount KEÇE';
      case BuildingType.damascusForge:
        return '+$amount ŞAM ÇELİĞİ';
      case BuildingType.granaryVault:
        return '+$amount AMBAR';
      default:
        return '+$amount HASAT';
    }
  }

  void panCamera(Offset delta) {
    if (delta.dx.isNaN || delta.dy.isNaN) return;
    final panDelta = Vector2(-delta.dx, -delta.dy) / _currentZoom;
    gameCamera.viewfinder.position += panDelta;
    _clampCameraPosition();
    _panVelocity = panDelta * 4.0; // Harekete atalet momentumu ekle
  }

  void zoomCamera(double delta) {
    if (delta.isNaN) return;
    _currentZoom = (_currentZoom + delta).clamp(0.45, 2.2);
    gameCamera.viewfinder.zoom = _currentZoom;
    _clampCameraPosition();
  }

  void syncGameState(GameState state) {
    final prev = _lastState;
    _lastState = state;
    if (!isLoaded) return;

    final bool tilesRefChanged = prev == null || !identical(prev.tiles, state.tiles);
    final bool selectionChanged = prev?.selectedCoord != state.selectedCoord;
    final bool seasonChanged = prev?.season.current != state.season.current || prev?.season.isZud != state.season.isZud;
    final bool themeChanged = prev?.settings.activeThemePalette != state.settings.activeThemePalette;
    final bool caravanChanged = prev == null || prev.caravanRoutes.length != state.caravanRoutes.length;
    final bool macroChanged = prev?.isMacroOverview != state.isMacroOverview;

    final bool combatChanged = prev == null ||
        prev.combatState.isActiveWave != state.combatState.isActiveWave ||
        prev.combatState.activeEnemies.length != state.combatState.activeEnemies.length ||
        prev.combatState.activeProjectiles.length != state.combatState.activeProjectiles.length;

    if (tilesRefChanged || selectionChanged || seasonChanged || themeChanged) {
      _updateTiles(state, prev: prev);
    }
    if (tilesRefChanged) {
      _updateWorkers(state);
    }
    if (caravanChanged) {
      _updateCaravans(state);
    }
    if (combatChanged) {
      _updateCombat(state);
    }
    if (seasonChanged) {
      _updateWeather(state);
    }
    if (macroChanged) {
      _currentZoom = state.isMacroOverview ? 0.45 : 1.0;
      gameCamera.viewfinder.zoom = _currentZoom;
    }
  }

  void _buildWorldFromState(GameState state) {
    for (final comp in _tileComponents.values) {
      comp.removeFromParent();
    }
    _tileComponents.clear();

    for (final w in _workerComponents.values) {
      w.removeFromParent();
    }
    _workerComponents.clear();

    for (final c in _caravanComponents.values) {
      c.removeFromParent();
    }
    _caravanComponents.clear();

    for (final e in _enemyComponents.values) {
      e.removeFromParent();
    }
    _enemyComponents.clear();
    _spawnedProjectileIds.clear();

    _updateTiles(state);
    _updateWorkers(state);
    _updateCaravans(state);
    _updateCombat(state);
    _updateWeather(state);
  }

  void _updateCombat(GameState state) {
    final combat = state.combatState;

    if (!combat.isActiveWave) {
      for (final enemy in _enemyComponents.values) {
        enemy.removeFromParent();
      }
      _enemyComponents.clear();
      _spawnedProjectileIds.clear();
      return;
    }

    // 1. Düşmanları Güncelle & Sil
    final Set<String> activeIds = combat.activeEnemies.map((e) => e.id).toSet();
    _enemyComponents.removeWhere((id, comp) {
      if (!activeIds.contains(id)) {
        comp.removeFromParent();
        return true;
      }
      return false;
    });

    for (final enemy in combat.activeEnemies) {
      if (_enemyComponents.containsKey(enemy.id)) {
        _enemyComponents[enemy.id]!.updateEnemyData(enemy);
      } else {
        final comp = VoxelEnemyComponent(
          enemy: enemy,
          getElevation: (c) {
            final t = state.tiles[c];
            if (t == null) return 0.0;
            return HexTileComponent.getBiomeElevation(t.biome, isFog: t.isFog);
          },
        );
        _enemyComponents[enemy.id] = comp;
        gameWorld.add(comp);
      }
    }

    // 2. Kule Mermilerini / Oklarını Fırlat
    for (final proj in combat.activeProjectiles) {
      if (!_spawnedProjectileIds.contains(proj.id)) {
        _spawnedProjectileIds.add(proj.id);
        final targetEnemyComp = _enemyComponents[proj.targetEnemyId];
        Vector2 targetPos;
        if (targetEnemyComp != null) {
          targetPos = targetEnemyComp.position.clone();
        } else {
          final enemyInst = combat.activeEnemies.where((e) => e.id == proj.targetEnemyId).firstOrNull;
          final targetCoord = enemyInst?.currentCoord ?? const HexAxial(0, 0);
          final targetPixel = HexMath.hexToPixel(targetCoord, hexSize: HexTileComponent.hexRadius);
          final double elev = HexTileComponent.getBiomeElevation(
            state.tiles[targetCoord]?.biome ?? TileBiome.meadow,
            isFog: state.tiles[targetCoord]?.isFog ?? false,
          );
          targetPos = Vector2(targetPixel.dx, targetPixel.dy - elev);
        }

        final pComp = VoxelProjectileComponent(
          projectile: proj,
          targetPixelPos: targetPos,
          getElevation: (c) {
            final t = state.tiles[c];
            if (t == null) return 0.0;
            return HexTileComponent.getBiomeElevation(t.biome, isFog: t.isFog);
          },
        );
        gameWorld.add(pComp);
      }
    }
  }

  void _updateCaravans(GameState state) {
    final Set<String> activeIds = state.caravanRoutes.map((r) => r.id).toSet();
    _caravanComponents.removeWhere((id, comp) {
      if (!activeIds.contains(id)) {
        comp.removeFromParent();
        return true;
      }
      return false;
    });

    for (final route in state.caravanRoutes) {
      if (!_caravanComponents.containsKey(route.id)) {
        final comp = CaravanConvoyComponent(route: route);
        comp.priority = 2500;
        _caravanComponents[route.id] = comp;
        gameWorld.add(comp);
      }
    }
  }

  static bool _isProducerBuilding(BuildingType type) {
    switch (type) {
      case BuildingType.castle:
      case BuildingType.worker:
      case BuildingType.watchtower:
      case BuildingType.bridge:
      case BuildingType.fishermanHut:
      case BuildingType.granaryVault:
        return false;
      default:
        return true;
    }
  }

  void _updateTiles(GameState state, {GameState? prev}) {
    final bool globalChange = prev == null ||
        prev.season.current != state.season.current ||
        prev.season.isZud != state.season.isZud ||
        prev.settings.activeThemePalette != state.settings.activeThemePalette;

    // İşçi Kulübesi seçildiğinde 4-hex menzili ve malzeme tedarik eden üretim binalarının tespiti
    final selectedTile = state.selectedCoord != null ? state.tiles[state.selectedCoord!] : null;
    final bool isWorkerSelected = selectedTile != null &&
        selectedTile.isOwned &&
        selectedTile.hasBuilding &&
        selectedTile.building!.type == BuildingType.worker;

    final Set<HexAxial> workerRangeCoords = {};
    final List<MapEntry<HexAxial, BuildingType>> workerContributors = [];

    if (isWorkerSelected) {
      final selectedCoord = state.selectedCoord!;
      for (final entry in state.tiles.entries) {
        final coord = entry.key;
        final tile = entry.value;
        if (!tile.isOwned || tile.isFog) continue;

        if (coord.distanceTo(selectedCoord) <= 4) {
          workerRangeCoords.add(coord);

          if (coord != selectedCoord && tile.hasBuilding) {
            final b = tile.building!;
            if (_isProducerBuilding(b.type)) {
              workerContributors.add(MapEntry(coord, b.type));
            }
          }
        }
      }
    }

    // İnce yeşil lojistik akış oklarını güncelle
    _workerFlowArrows.updateFlows(
      workerCoord: isWorkerSelected ? state.selectedCoord : null,
      contributors: workerContributors,
      getTileElevation: (c) {
        final t = state.tiles[c];
        if (t == null) return 0.0;
        return HexTileComponent.getBiomeElevation(t.biome, isFog: t.isFog);
      },
    );

    final Set<HexAxial> contributorCoords = workerContributors.map((e) => e.key).toSet();

    for (final entry in state.tiles.entries) {
      final coord = entry.key;
      final tile = entry.value;
      final bool isSel = state.selectedCoord == coord;
      final bool wasSel = prev?.selectedCoord == coord;
      final prevTile = prev?.tiles[coord];
      final bool inRange = workerRangeCoords.contains(coord);
      final bool isContributor = contributorCoords.contains(coord);

      // Değişmeyen, seçimi ve menzil durumu değişmeyen karoları atla (Saniyelik tam harita tarama yükünü sıfırlar)
      if (!globalChange &&
          prevTile == tile &&
          isSel == wasSel &&
          _tileComponents.containsKey(coord)) {
        final comp = _tileComponents[coord]!;
        if (comp.isInWorkerRange == inRange && comp.isHarvestHighlight == isContributor) {
          continue;
        }
      }

      // Aynı biyomdaki açık komşuların göreli konum vektörleri (Hayvan Göç ve Gezinme Yolu)
      final List<Offset> compatibleNeighbors = [];
      final currentPixel = HexMath.hexToPixel(coord, hexSize: HexTileComponent.hexRadius);
      for (final nCoord in coord.neighbors) {
        final nTile = state.tiles[nCoord];
        if (nTile != null && !nTile.isFog && nTile.biome == tile.biome) {
          final nPixel = HexMath.hexToPixel(nCoord, hexSize: HexTileComponent.hexRadius);
          compatibleNeighbors.add(nPixel - currentPixel);
        }
      }

      final bool isFrenzy = state.frenzyTimer > 0 && state.frenzyMultiplier > 1;

      // Komşu Kuzeybatı / Üst Karoların Kot Farkı (Cliff Cast Shadow Matrix)
      double maxNwElevation = 0.0;
      final currentElev = HexTileComponent.getBiomeElevation(tile.biome, isFog: tile.isFog);
      final nwNeighborCoords = [
        HexAxial(coord.q, coord.r - 1),
        HexAxial(coord.q - 1, coord.r),
        HexAxial(coord.q - 1, coord.r + 1),
      ];
      for (final nCoord in nwNeighborCoords) {
        final nTile = state.tiles[nCoord];
        if (nTile != null && !nTile.isFog) {
          final nElev = HexTileComponent.getBiomeElevation(nTile.biome, isFog: false);
          if (nElev > currentElev && nElev > maxNwElevation) {
            maxNwElevation = nElev;
          }
        }
      }
      final double nwDelta = maxNwElevation > currentElev ? (maxNwElevation - currentElev) : 0.0;

      // Komşulardan hangileri sisli veya harita dışı? (Island Perimeter Mask)
      int fogMask = 0;
      for (int i = 0; i < 6; i++) {
        final nCoord = coord.neighbors[i];
        final nTile = state.tiles[nCoord];
        if (nTile == null || nTile.isFog) {
          fogMask |= (1 << i);
        }
      }

      if (_tileComponents.containsKey(coord)) {
        _tileComponents[coord]!.updateData(
          newTileModel: tile,
          newIsSelected: isSel,
          newIsInWorkerRange: inRange,
          newIsHarvestHighlight: isContributor,
          newSeason: state.season.current,
          newIsZud: state.season.isZud,
          newIsNight: _isNight,
          newThemePalette: state.settings.activeThemePalette,
          newIsFrenzyActive: isFrenzy,
          newCompatibleNeighborOffsets: compatibleNeighbors,
          newNorthWestDeltaElevation: nwDelta,
          newFogNeighborMask: fogMask,
        );
      } else {
        final comp = HexTileComponent(
          coord: coord,
          tileModel: tile,
          isSelected: isSel,
          isInWorkerRange: inRange,
          isHarvestHighlight: isContributor,
          season: state.season.current,
          isZud: state.season.isZud,
          isNight: _isNight,
          themePalette: state.settings.activeThemePalette,
          isFrenzyActive: isFrenzy,
          compatibleNeighborOffsets: compatibleNeighbors,
          northWestDeltaElevation: nwDelta,
          fogNeighborMask: fogMask,
        );
        final pixelPos = HexMath.hexToPixel(coord, hexSize: HexTileComponent.hexRadius);
        comp.priority = (pixelPos.dy + 1000).toInt();

        _tileComponents[coord] = comp;
        gameWorld.add(comp);
      }
    }
  }

  void _updateWorkers(GameState state) {
    final Set<HexAxial> activeBuildingCoords = {};
    final castlePos = HexMath.hexToPixel(const HexAxial(0, 0), hexSize: HexTileComponent.hexRadius);
    final castleVec = Vector2(castlePos.dx, castlePos.dy);

    for (final entry in state.tiles.entries) {
      final tile = entry.value;
      if (tile.isOwned && tile.hasBuilding && tile.building!.type != BuildingType.castle) {
        activeBuildingCoords.add(entry.key);

        if (!_workerComponents.containsKey(entry.key)) {
          final tilePos = HexMath.hexToPixel(entry.key, hexSize: HexTileComponent.hexRadius);
          final tileVec = Vector2(tilePos.dx, tilePos.dy);

          Color cargoColor = const Color(0xFFFBBF24);
          if (tile.building!.type == BuildingType.corn) cargoColor = const Color(0xFFFBBF24);
          if (tile.building!.type == BuildingType.barley) cargoColor = const Color(0xFFFDE047);
          if (tile.building!.type == BuildingType.pasture) cargoColor = const Color(0xFF10B981);
          if (tile.building!.type == BuildingType.orchard) cargoColor = const Color(0xFFF43F5E);
          if (tile.building!.type == BuildingType.quarry) cargoColor = const Color(0xFF94A3B8);
          if (tile.building!.type == BuildingType.resinCamp) cargoColor = const Color(0xFFB45309);
          if (tile.building!.type == BuildingType.lumberjack) cargoColor = const Color(0xFFB45309);
          if (tile.building!.type == BuildingType.sawmill) cargoColor = const Color(0xFFD97706);
          if (tile.building!.type == BuildingType.windmill) cargoColor = const Color(0xFFFEF08A);
          if (tile.building!.type == BuildingType.bakery) cargoColor = const Color(0xFFF59E0B);
          if (tile.building!.type == BuildingType.furniture) cargoColor = const Color(0xFF78350F);
          if (tile.building!.type == BuildingType.mine) cargoColor = const Color(0xFF94A3B8);
          if (tile.building!.type == BuildingType.fisherman || tile.building!.type == BuildingType.fishermanHut) {
            cargoColor = const Color(0xFF38BDF8);
          }

          final int workerSeed = (entry.key.q * 31 + entry.key.r * 17).abs();
          final worker = WorkerAgentComponent(
            startPos: tileVec,
            endPos: castleVec,
            cargoColor: cargoColor,
            seed: workerSeed,
          );
          _workerComponents[entry.key] = worker;
          gameWorld.add(worker);
        }
      }
    }

    // Kaldırılan binaların işçilerini temizle
    final removed = _workerComponents.keys.where((k) => !activeBuildingCoords.contains(k)).toList();
    for (final k in removed) {
      _workerComponents[k]?.removeFromParent();
      _workerComponents.remove(k);
    }
  }

  void _updateWeather(GameState state) {
    _weatherEmitter.setSeason(state.season.current, newIsZud: state.season.isZud);
  }
}
