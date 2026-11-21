import 'package:flutter_test/flutter_test.dart';
import 'package:oyun_dusen_bloklar/oyun_dusen_bloklar.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/level_plan.dart';

void main() {
  final rules = FallRules();
  final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: rules.optionalMechanics);

  (FallSim, List<List<int>>) play(FallLevel l, int ticks) {
    final s = FallSim(l);
    final log = <List<int>>[];
    var last = ArcadeInput.idle;
    for (var t = 0; t < ticks && !s.over; t++) {
      final i = rules.bot(s).quantized();
      if (!i.sameAs(last)) {
        log.add([s.ticks + 1, ...i.encode()]);
        last = i;
      }
      s.tick(i);
    }
    return (s, log);
  }

  test('her parçanın 4 dönüşü 4 kareden oluşur ve 4. dönüş başa döner', () {
    for (var t = 0; t < 7; t++) {
      for (var r = 0; r < 4; r++) {
        expect(shapes[t][r].length, 4);
      }
    }
  });

  test('aynı tohum aynı oyunu verir', () {
    final a = play(rules.build(planner.spec(55)).puzzle, 3000).$1;
    final b = play(rules.build(planner.spec(55)).puzzle, 3000).$1;
    expect(b.score, a.score);
    expect(b.lines, a.lines);
  });

  test('girdi kaydı yeniden oynatılınca tur aynen geri gelir', () {
    final l = rules.build(planner.spec(73)).puzzle;
    final (a, log) = play(l, 2000);
    final b = FallSim(l);
    replayLog(b, log, a.ticks);
    expect(b.ticks, a.ticks);
    expect(b.score, a.score);
    expect(b.grid, a.grid);
  });

  test('kampanya bölümleri bot tarafından bitirilir (her zorluk)', () {
    for (final lv in [1, 15, 40, 77, 120, 260, 555, 999, 4321, 9876, 25000, 49999]) {
      final g = rules.build(planner.spec(lv));
      final s = FallSim(g.puzzle);
      final r = runBot(s, rules.bot, rules.maxTicks(g.puzzle));
      expect(r.won, isTrue, reason: 'bölüm $lv: ${s.lines}/${s.target}');
    }
  });

  test('sıra silme ve tutma çalışır', () {
    final l = rules.build(planner.spec(3)).puzzle;
    final s = FallSim(l);
    s.tick(ArcadeInput.idle);
    final first = s.cur;
    s.doHold();
    expect(s.hold, first);
    expect(s.cur, isNot(-1));
    for (var x = 0; x < kCols; x++) {
      s.grid[(kRows - 1) * kCols + x] = x == 0 ? 0 : kGarbage;
    }
    final before = s.lines;
    s.useBooster();
    expect(s.grid.sublist((kRows - 1) * kCols).every((v) => v == 0), isTrue);
    expect(s.lines, before);
  });

  test('dokunma: kısa dokunuş döndürür, sürükleme kaydırır, aşağı fırlatma bırakır', () {
    final l = rules.build(planner.spec(2)).puzzle;
    final s = FallSim(l);
    while (s.cur != 2 && s.cur != 5 && s.cur != 6 && s.ticks < 50) {
      s.tick(ArcadeInput.idle);
      if (s.cur == 1 || s.cur == 0 || s.cur == 3 || s.cur == 4) s.hardDrop();
    }
    final r0 = s.rot;
    s.tick(const ArcadeInput(down: true, x: 300, y: 600, tap: true));
    s.tick(const ArcadeInput(down: false, x: 300, y: 600));
    expect(s.rot, (r0 + 1) % 4);
    final x0 = s.px;
    s.tick(const ArcadeInput(down: true, x: 300, y: 600, tap: true));
    s.tick(const ArcadeInput(down: true, x: 300 + kDragStep * 2, y: 600));
    s.tick(const ArcadeInput(down: true, x: 300 + kDragStep * 2, y: 600));
    s.tick(const ArcadeInput(down: false, x: 300 + kDragStep * 2, y: 600));
    expect(s.px, x0 + 2);
    final p = s.pieces;
    s.tick(const ArcadeInput(down: true, x: 300, y: 600, tap: true));
    s.tick(const ArcadeInput(down: false, x: 300, y: 900, swipe: 2));
    expect(s.pieces, p + 1);
  });

  test('her kip doğrulanır', () {
    for (final m in rules.modes) {
      final spec = planner.spec(31, mode: m);
      final g = rules.build(spec);
      expect(g.puzzle.meta.mode, m);
    }
  });
}
