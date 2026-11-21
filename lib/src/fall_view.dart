import 'package:flutter/material.dart';
import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/game_api.dart';
import 'package:studio_core/app/play_kit.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';

import 'fall_engine.dart';

const _garbageColor = Color(0xFF7A8494);

/// Renk körü kipinde her parça tipine ayrı bir iç işaret.
const _marks = ['', '●', '▲', '■', '◆', '✚', '★', '✖'];

Color _colorOf(ArcadePalette p, int v) => v == kGarbage ? _garbageColor : p.piece(v - 1);

void _cell(Canvas c, Rect r, Color col, {double alpha = 1, bool cb = false, int v = 0}) {
  final rr = RRect.fromRectAndRadius(r.deflate(2.5), Radius.circular(r.width * 0.22));
  c.drawRRect(rr, Paint()..color = col.withValues(alpha: alpha));
  // Yumuşak üst ışık: düz, kendine has bir görünüm.
  c.drawRRect(
    RRect.fromRectAndRadius(Rect.fromLTWH(r.left + 6, r.top + 5, r.width - 12, r.height * 0.28),
        Radius.circular(r.width * 0.14)),
    Paint()..color = Colors.white.withValues(alpha: 0.18 * alpha),
  );
  if (cb && v > 0 && v < _marks.length) {
    paintText(c, _marks[v], r.center, r.width * 0.36, Colors.black.withValues(alpha: 0.45 * alpha));
  }
}

Rect _boardCell(int x, int y) => Rect.fromLTWH(kBoardLeft + x * kCell, kBoardTop + y * kCell, kCell, kCell);

void _mini(Canvas c, ArcadePalette p, int type, Offset center, double size, {double alpha = 1}) {
  final cells = shapes[type][0];
  var minX = 9, maxX = -9, minY = 9, maxY = -9;
  for (final q in cells) {
    if (q[0] < minX) minX = q[0];
    if (q[0] > maxX) maxX = q[0];
    if (q[1] < minY) minY = q[1];
    if (q[1] > maxY) maxY = q[1];
  }
  final w = (maxX - minX + 1) * size, h = (maxY - minY + 1) * size;
  for (final q in cells) {
    final r = Rect.fromLTWH(center.dx - w / 2 + (q[0] - minX) * size, center.dy - h / 2 + (q[1] - minY) * size, size, size);
    _cell(c, r, p.piece(type), alpha: alpha, cb: p.colorBlind, v: type + 1);
  }
}

void paintFall(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as FallSim;
  final board = Rect.fromLTWH(kBoardLeft, kBoardTop, kCols * kCell, kRows * kCell);
  c.drawRRect(RRect.fromRectAndRadius(board.inflate(8), const Radius.circular(22)),
      Paint()..color = Colors.black.withValues(alpha: 0.32));
  final line = Paint()
    ..color = Colors.white.withValues(alpha: 0.05)
    ..strokeWidth = 2;
  for (var x = 1; x < kCols; x++) {
    c.drawLine(Offset(board.left + x * kCell, board.top), Offset(board.left + x * kCell, board.bottom), line);
  }
  for (var y = 1; y < kRows; y++) {
    c.drawLine(Offset(board.left, board.top + y * kCell), Offset(board.right, board.top + y * kCell), line);
  }
  for (var y = 0; y < kRows; y++) {
    for (var x = 0; x < kCols; x++) {
      final v = s.grid[y * kCols + x];
      if (v != 0) _cell(c, _boardCell(x, y), _colorOf(p, v), cb: p.colorBlind, v: v);
    }
  }
  if (s.flash > 0 && !p.reducedMotion) {
    final a = s.flash / 18 * 0.55;
    for (final y in s.flashRows) {
      c.drawRect(Rect.fromLTWH(board.left, board.top + y * kCell, board.width, kCell),
          Paint()..color = Colors.white.withValues(alpha: a));
    }
  }
  if (s.cur >= 0) {
    final gy = s.ghostY;
    final col = p.piece(s.cur);
    for (final q in shapes[s.cur][s.rot]) {
      final x = s.px + q[0], y = gy + q[1];
      if (y < 0) continue;
      c.drawRRect(
        RRect.fromRectAndRadius(_boardCell(x, y).deflate(5), const Radius.circular(12)),
        Paint()
          ..color = col.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );
    }
    final blink = s.shield > 0 && (s.ticks ~/ 6).isOdd;
    for (final q in shapes[s.cur][s.rot]) {
      final x = s.px + q[0], y = s.py + q[1];
      if (y < 0) continue;
      _cell(c, _boardCell(x, y), col, alpha: blink ? 0.45 : 1, cb: p.colorBlind, v: s.cur + 1);
    }
  }
  // Yan panel: sıradakiler ve tutulan.
  final px = board.right + 22, pw = kWorldW - px - 14;
  final panel = Paint()..color = Colors.black.withValues(alpha: 0.25);
  final nextBox = Rect.fromLTWH(px, kBoardTop, pw, 560);
  c.drawRRect(RRect.fromRectAndRadius(nextBox, const Radius.circular(20)), panel);
  paintText(c, '▼', Offset(nextBox.center.dx, nextBox.top + 34), 30, Colors.white70);
  for (var i = 0; i < 3 && i < s.queue.length; i++) {
    _mini(c, p, s.queue[i], Offset(nextBox.center.dx, nextBox.top + 130 + i * 150), i == 0 ? 50 : 38);
  }
  final holdBox = Rect.fromLTWH(px, kBoardTop + 590, pw, 230);
  c.drawRRect(RRect.fromRectAndRadius(holdBox, const Radius.circular(20)), panel);
  paintText(c, '⟲', Offset(holdBox.center.dx, holdBox.top + 34), 32, Colors.white70);
  if (s.hold >= 0) {
    _mini(c, p, s.hold, Offset(holdBox.center.dx, holdBox.top + 135), 44, alpha: s.holdUsed ? 0.4 : 1);
  }
  if (s.combo > 0) {
    paintText(c, 'x${s.combo + 1}', Offset(px + pw / 2, kBoardTop + 900), 64, const Color(0xFFFFCA3A));
  }
  if (s.level.riseEvery > 0) {
    final k = s.riseTimer / s.level.riseEvery;
    final bar = Rect.fromLTWH(px, board.bottom - 26, pw, 18);
    c.drawRRect(RRect.fromRectAndRadius(bar, const Radius.circular(9)), panel);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(bar.left, bar.top, bar.width * k, bar.height), const Radius.circular(9)),
        Paint()..color = const Color(0xFFFF7043));
    paintText(c, '⇡', Offset(px + pw / 2, board.bottom - 60), 40, Colors.white70);
  }
}

Sfx? fallSound(ArcadeSim sim) => switch ((sim as FallSim).lastEvent) {
      1 => Sfx.place,
      2 => Sfx.clear,
      3 => Sfx.combo,
      4 => Sfx.tap,
      5 => Sfx.lose,
      6 => Sfx.tap,
      _ => null,
    };

Widget buildFallStage(PlayContext ctx, FallLevel level) => ArcadeStage(
      ctx: ctx,
      create: () => FallSim(level),
      paint: paintFall,
      sound: fallSound,
      boosterIcon: Icons.vertical_align_bottom,
      boosterLabel: (l) => l == 'tr' ? 'Alt 2 sırayı sil' : 'Clear 2 rows',
      howTo: const [
        'Sürükle: kaydır · Dokun: döndür · Aşağı fırlat: bırak · Yukarı fırlat: tut',
        'Drag: move · Tap: rotate · Flick down: drop · Flick up: hold',
        'Ziehen: bewegen · Tippen: drehen · Nach unten: fallen · Nach oben: halten',
        'Arrastra: mover · Toca: girar · Abajo: soltar · Arriba: guardar',
        'Glisser : déplacer · Toucher : tourner · Vers le bas : lâcher · Vers le haut : garder',
      // ar fa he ur ru uk pl cs ro hu el it pt nl sv da nb fi ja ko zh hi bn id ms th vi fil
      'اسحب: تحريك · المس: تدوير · لأسفل: إسقاط · لأعلى: احتفاظ',
      'کشیدن: جابه‌جایی · لمس: چرخش · پایین: انداختن · بالا: نگه‌داشتن',
      'גרירה: הזזה · הקשה: סיבוב · למטה: הפלה · למעלה: שמירה',
      'گھسیٹیں: سرکائیں · چھوئیں: گھمائیں · نیچے: گرائیں · اوپر: رکھیں',
      'Тяни: сдвиг · Касание: поворот · Вниз: сброс · Вверх: отложить',
      'Тягни: зсув · Дотик: поворот · Вниз: скинути · Вгору: відкласти',
      'Przeciągnij: ruch · Dotknij: obrót · W dół: upuść · W górę: odłóż',
      'Táhni: posun · Klepni: otočit · Dolů: pustit · Nahoru: odložit',
      'Trage: mută · Atinge: rotește · Jos: lasă · Sus: păstrează',
      'Húzás: mozgatás · Koppintás: forgatás · Le: ejtés · Fel: félretesz',
      'Σύρσιμο: μετακίνηση · Πάτημα: περιστροφή · Κάτω: ρίψη · Πάνω: φύλαξη',
      'Trascina: muovi · Tocca: ruota · Giù: lascia · Su: tieni',
      'Arrastar: mover · Tocar: girar · Para baixo: soltar · Para cima: guardar',
      'Slepen: schuiven · Tik: draaien · Omlaag: laten vallen · Omhoog: bewaren',
      'Dra: flytta · Tryck: rotera · Nedåt: släpp · Uppåt: spara',
      'Træk: flyt · Tryk: drej · Ned: slip · Op: gem',
      'Dra: flytt · Trykk: roter · Ned: slipp · Opp: spar',
      'Veto: siirto · Napautus: käännä · Alas: pudota · Ylös: säästä',
      'ドラッグ:移動・タップ:回転・下フリック:落とす・上フリック:キープ',
      '끌기: 이동 · 누르기: 회전 · 아래로: 떨어뜨리기 · 위로: 보관',
      '拖动：移动 · 点击：旋转 · 下滑：落下 · 上滑：暂存',
      'खींचें: सरकाएँ · छुएँ: घुमाएँ · नीचे: गिराएँ · ऊपर: रखें',
      'টানুন: সরান · ছুঁন: ঘোরান · নিচে: ফেলুন · ওপরে: রাখুন',
      'Seret: geser · Ketuk: putar · Ke bawah: jatuhkan · Ke atas: simpan',
      'Seret: geser · Ketik: putar · Ke bawah: jatuhkan · Ke atas: simpan',
      'ลาก: เลื่อน · แตะ: หมุน · ปัดลง: ปล่อย · ปัดขึ้น: เก็บไว้',
      'Kéo: di chuyển · Chạm: xoay · Vuốt xuống: thả · Vuốt lên: giữ',
      'I-drag: galaw · I-tap: ikot · Pababa: ihulog · Pataas: itabi',
    ],
    );
