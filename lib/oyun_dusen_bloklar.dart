/// Düşen Bloklar: düşen parçaları yerleştir, dolan sıraları temizle.
/// Blok Oyunları merkez uygulamasının oyunu.
library;

import 'package:flutter/material.dart';
import 'package:studio_core/app/game_api.dart';
import 'package:studio_core/core/game_rules.dart';

import 'src/fall_engine.dart';
import 'src/fall_rules.dart';
import 'src/fall_view.dart';

export 'src/fall_engine.dart';
export 'src/fall_rules.dart';

final dusenBloklarConfig = GameConfig(
  gameId: dusenBloklarId,
  title: const ['Düşen Bloklar', 'Falling Blocks', 'Fallende Blöcke', 'Bloques que Caen', 'Blocs qui Tombent'],
  tagline: const [
    'Parçaları yerleştir, sıraları temizle!',
    'Place the pieces, clear the lines!',
    'Teile setzen, Reihen leeren!',
    '¡Coloca las piezas y limpia filas!',
    'Placez les pièces, videz les lignes !',
  ],
  seedColor: const Color(0xFF00897B),
  icon: Icons.view_agenda_rounded,
  rules: FallRules(),
  buildPlay: (ctx) => buildFallStage(ctx, (ctx.generated as GeneratedLevel<FallLevel>).puzzle),
  tutorial: const [
    TutorialStep(Icons.swipe, [
      'Parçayı sürükleyerek sağa sola kaydır. Dokununca döner.',
      'Drag the piece left or right. Tap to rotate.',
      'Ziehe das Teil nach links oder rechts. Tippen dreht.',
      'Arrastra la pieza a los lados. Toca para girar.',
      'Glissez la pièce à gauche ou à droite. Touchez pour tourner.',
    ]),
    TutorialStep(Icons.vertical_align_bottom, [
      'Aşağı fırlatırsan parça hemen düşer. Yukarı fırlatırsan kenara tutulur.',
      'Flick down to drop at once. Flick up to hold the piece.',
      'Nach unten wischen lässt es fallen, nach oben hält es.',
      'Desliza abajo para soltar, arriba para guardar.',
      'Vers le bas pour lâcher, vers le haut pour garder.',
    ]),
    TutorialStep(Icons.horizontal_rule, [
      'Dolan sıra silinir. Aynı anda 4 sıra en çok puanı verir.',
      'Full rows clear. Four at once scores the most.',
      'Volle Reihen verschwinden. Vier auf einmal zählen am meisten.',
      'Las filas llenas desaparecen. Cuatro a la vez puntúan más.',
      'Les lignes pleines disparaissent. Quatre d\'un coup rapportent le plus.',
    ]),
  ],
);
