import 'package:flame/components.dart';
import 'package:flutter/material.dart';

/// Kuş yapısı kullanıcı talebi doğrultusunda tamamen kaldırılmıştır.
class FlyingVoxelBirdComponent extends PositionComponent {
  FlyingVoxelBirdComponent({
    required Vector2 startPos,
    double flightSpeed = 35.0,
    double flightRadius = 240.0,
  }) : super(position: startPos, priority: 90);

  @override
  void render(Canvas canvas) {}
}
