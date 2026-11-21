import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/rng.dart';

/// Düşen Bloklar: dörtlü parçalar yukarıdan düşer, dolan sıralar silinir.
///
/// Saf Dart, sabit adımlı ve tohuma göre belirlenimli bir benzetim; bu
/// sayede seviyeler bir botla doğrulanır ve yarıda kalan tur, kaydedilen
/// girdiler yeniden oynatılarak geri yüklenir.

const int kCols = 10;
const int kRows = 20;

/// Bir tahta karesinin dünya birimi cinsinden boyu.
const double kCell = 66;
const double kBoardLeft = 24;
const double kBoardTop = 220;

/// Sürüklemede bir sütun kaydırmak için gereken mesafe.
const double kDragStep = 58;

/// Çöp (başlangıç / yükselen) kareleri bu değerle tutulur.
const int kGarbage = 8;

/// Parçalar: [x, y] kareleri ve döndürme kutusu boyu.
const List<List<List<int>>> _baseShapes = [
  [[0, 1], [1, 1], [2, 1], [3, 1]], // I
  [[0, 0], [1, 0], [0, 1], [1, 1]], // O
  [[1, 0], [0, 1], [1, 1], [2, 1]], // T
  [[1, 0], [2, 0], [0, 1], [1, 1]], // S
  [[0, 0], [1, 0], [1, 1], [2, 1]], // Z
  [[0, 0], [0, 1], [1, 1], [2, 1]], // J
  [[2, 0], [0, 1], [1, 1], [2, 1]], // L
];
const List<int> _box = [4, 2, 3, 3, 3, 3, 3];

/// shapes[tip][döndürme] = kareler.
final List<List<List<List<int>>>> shapes = [
  for (var t = 0; t < 7; t++)
    () {
      final out = <List<List<int>>>[];
      var cur = _baseShapes[t];
      for (var r = 0; r < 4; r++) {
        out.add(cur);
        final n = _box[t];
        cur = [for (final c in cur) [n - 1 - c[1], c[0]]];
      }
      return out;
    }(),
];

int boxOf(int type) => _box[type];

class FallLevel {
  final ArcadeMeta meta;

  /// Bir sıra düşme süresi (tik).
  final int gravity;

  /// Hedef sıra sayısı; 0 = hedefsiz (sonsuz, zamana karşı, zen).
  final int target;

  /// Başlangıç tahtası (kRows * kCols), 0 boş.
  final List<int> start;

  /// Alttan çöp sırası ekleme aralığı (tik), 0 = kapalı.
  final int riseEvery;

  const FallLevel({
    required this.meta,
    required this.gravity,
    required this.target,
    required this.start,
    required this.riseEvery,
  });
}

FallLevel generateFallLevel(LevelSpec spec) {
  final m = ArcadeMeta.of(spec);
  final r = SeededRandom(mixSeed([spec.seed, 4242]));
  final d = spec.difficulty.clamp(1, 10);
  var gravity = (42 - d * 3).clamp(8, 42);
  if (spec.has('fast')) gravity = (gravity - 8).clamp(5, 42);
  final target = m.goal ? 8 + d * 2 : 0;
  final grid = List<int>.filled(kRows * kCols, 0);
  if (spec.has('garbage') || d >= 6) {
    final n = (1 + d ~/ 2).clamp(2, 6);
    for (var i = 0; i < n; i++) {
      final y = kRows - 1 - i;
      final hole = r.nextInt(kCols);
      final hole2 = d >= 8 && r.chance(0.3) ? r.nextInt(kCols) : hole;
      for (var x = 0; x < kCols; x++) {
        if (x != hole && x != hole2) grid[y * kCols + x] = kGarbage;
      }
    }
  }
  final rise = spec.has('rise') ? ((16 - d) * kTicksPerSecond).clamp(7 * kTicksPerSecond, 15 * kTicksPerSecond) : 0;
  return FallLevel(meta: m, gravity: gravity, target: target, start: grid, riseEvery: rise);
}

class FallSim extends ArcadeSim {
  final FallLevel level;
  late List<int> grid;
  final List<int> queue = [];
  int cur = -1, rot = 0, px = 0, py = 0;
  int hold = -1;
  bool holdUsed = false;
  int fallTimer = 0, lockTimer = 0, lockResets = 0;
  int riseTimer = 0;
  int lines = 0, quads = 0, combo = -1, maxCombo = 0, pieces = 0;

  /// Ses ve boyama için: 1 yerleşti, 2 sıra, 3 dörtlü, 4 tutma, 5 çarptı.
  int lastEvent = 0;

  /// Son silinen sıralar ve parlama süresi (boyama).
  List<int> flashRows = const [];
  int flash = 0;

  // Dokunma durumu
  bool _prevDown = false, _dragging = false, _moved = false;
  double _sx = 0, _sy = 0;
  int _sCol = 0, _sTick = 0, _softTick = 0;
  int _dasDir = 0, _dasTimer = 0;

  // Bot planı
  int botPiece = -1, botRot = 0, botCol = 0, botSteps = 0;

  FallSim(this.level) : super(level.meta) {
    grid = List<int>.of(level.start);
    _refill();
  }

  int get target => level.target;

  void _refill() {
    while (queue.length < 7) {
      final bag = [0, 1, 2, 3, 4, 5, 6];
      rng.shuffle(bag);
      queue.addAll(bag);
    }
  }

  int spawnX(int type) => (kCols - boxOf(type)) ~/ 2;
  int spawnY(int type) => type == 0 ? -1 : 0;

  bool fits(int type, int r, int x, int y, [List<int>? g]) {
    final b = g ?? grid;
    for (final c in shapes[type][r]) {
      final cx = x + c[0], cy = y + c[1];
      if (cx < 0 || cx >= kCols || cy >= kRows) return false;
      if (cy >= 0 && b[cy * kCols + cx] != 0) return false;
    }
    return true;
  }

  void _spawn([int? type]) {
    cur = type ?? queue.removeAt(0);
    _refill();
    rot = 0;
    px = spawnX(cur);
    py = spawnY(cur);
    fallTimer = 0;
    lockTimer = 0;
    lockResets = 0;
    if (!fits(cur, rot, px, py)) _topOut();
  }

  /// Hayalet parçanın satırı.
  int get ghostY {
    var y = py;
    while (fits(cur, rot, px, y + 1)) {
      y++;
    }
    return y;
  }

  bool get landed => cur >= 0 && !fits(cur, rot, px, py + 1);

  void _touchLock() {
    if (landed && lockResets < 15) {
      lockTimer = 0;
      lockResets++;
    }
  }

  bool move(int dx) {
    if (cur < 0 || !fits(cur, rot, px + dx, py)) return false;
    px += dx;
    _touchLock();
    return true;
  }

  bool rotate() {
    if (cur < 0 || cur == 1) return false;
    final nr = (rot + 1) % 4;
    const kicks = [[0, 0], [-1, 0], [1, 0], [-2, 0], [2, 0], [0, -1]];
    for (final k in kicks) {
      if (fits(cur, nr, px + k[0], py + k[1])) {
        rot = nr;
        px += k[0];
        py += k[1];
        _touchLock();
        return true;
      }
    }
    return false;
  }

  void softDrop() {
    if (cur >= 0 && fits(cur, rot, px, py + 1)) {
      py++;
      score += 1;
      fallTimer = 0;
    }
  }

  void hardDrop() {
    if (cur < 0) return;
    final y = ghostY;
    score += 2 * (y - py);
    py = y;
    _lock();
  }

  void doHold() {
    if (cur < 0 || holdUsed) return;
    holdUsed = true;
    lastEvent = 4;
    final h = hold;
    hold = cur;
    _spawn(h >= 0 ? h : null);
  }

  void _lock() {
    var above = false;
    for (final c in shapes[cur][rot]) {
      final cx = px + c[0], cy = py + c[1];
      if (cy < 0) {
        above = true;
        continue;
      }
      grid[cy * kCols + cx] = cur + 1;
    }
    pieces++;
    holdUsed = false;
    lastEvent = 1;
    final full = <int>[];
    for (var y = 0; y < kRows; y++) {
      var ok = true;
      for (var x = 0; x < kCols; x++) {
        if (grid[y * kCols + x] == 0) {
          ok = false;
          break;
        }
      }
      if (ok) full.add(y);
    }
    if (full.isNotEmpty) {
      _removeRows(full);
      final n = full.length;
      lines += n;
      if (n == 4) quads++;
      combo++;
      if (combo > maxCombo) maxCombo = combo;
      score += const [0, 100, 300, 500, 800][n] + combo * 50;
      lastEvent = n == 4 ? 3 : 2;
      flashRows = full;
      flash = 18;
    } else {
      combo = -1;
    }
    cur = -1;
    if (above && full.isEmpty) {
      _topOut();
      return;
    }
    if (target > 0 && lines >= target) {
      win();
      return;
    }
    _spawn();
  }

  void _removeRows(List<int> rows) {
    final keep = <List<int>>[];
    for (var y = 0; y < kRows; y++) {
      if (rows.contains(y)) continue;
      keep.add(grid.sublist(y * kCols, (y + 1) * kCols));
    }
    final g = List<int>.filled(kRows * kCols, 0);
    final off = kRows - keep.length;
    for (var i = 0; i < keep.length; i++) {
      g.setRange((off + i) * kCols, (off + i + 1) * kCols, keep[i]);
    }
    grid = g;
  }

  void _clearTop() {
    for (var i = 0; i < 12 * kCols; i++) {
      grid[i] = 0;
    }
  }

  void _topOut() {
    lastEvent = 5;
    final l = lives;
    hit();
    if (over) return;
    if (lives == l) _clearTop();
    cur = -1;
  }

  @override
  void onLifeLost() {
    _clearTop();
    cur = -1;
  }

  void _rise() {
    var spill = false;
    for (var x = 0; x < kCols; x++) {
      if (grid[x] != 0) spill = true;
    }
    final g = List<int>.filled(kRows * kCols, 0);
    g.setRange(0, (kRows - 1) * kCols, grid.sublist(kCols));
    final hole = rng.nextInt(kCols);
    for (var x = 0; x < kCols; x++) {
      if (x != hole) g[(kRows - 1) * kCols + x] = kGarbage;
    }
    grid = g;
    if (spill) {
      _topOut();
      return;
    }
    if (cur >= 0 && !fits(cur, rot, px, py)) {
      if (fits(cur, rot, px, py - 1)) {
        py--;
      } else {
        _topOut();
      }
    }
  }

  int get gravityNow {
    if (level.meta.goal) return level.gravity;
    return (level.gravity - (lines ~/ 10) * 2).clamp(3, 60);
  }

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    if (flash > 0) flash--;
    if (cur < 0) {
      _spawn();
      if (over || cur < 0) return;
    }
    _input(input);
    if (over || cur < 0) return;

    if (level.riseEvery > 0) {
      riseTimer++;
      if (riseTimer >= level.riseEvery) {
        riseTimer = 0;
        _rise();
        if (over || cur < 0) return;
      }
    }

    fallTimer++;
    if (fallTimer >= gravityNow) {
      fallTimer = 0;
      if (fits(cur, rot, px, py + 1)) py++;
    }
    if (landed) {
      lockTimer++;
      if (lockTimer >= 30) _lock();
    } else {
      lockTimer = 0;
    }
  }

  void _input(ArcadeInput i) {
    final release = _prevDown && !i.down;
    if (i.down && !_prevDown) {
      _dragging = true;
      _moved = false;
      _sx = i.x;
      _sy = i.y;
      _sCol = px;
      _sTick = ticks;
      _softTick = 0;
    }
    if (i.down && _dragging && cur >= 0) {
      if (i.hasPointer && _sx >= 0) {
        final want = _sCol + ((i.x - _sx) / kDragStep).round();
        if (want != px) {
          _moved = true;
          move(want > px ? 1 : -1);
        }
        if (i.y - _sy > kCell * 2.2) {
          _moved = true;
          if (++_softTick % 3 == 0) softDrop();
        }
      }
    }
    if (release && _dragging) {
      _dragging = false;
      final dur = ticks - _sTick;
      if (i.swipe == 2 && dur <= 24) {
        hardDrop();
      } else if (i.swipe == 0 && dur <= 24) {
        doHold();
      } else if (!_moved && dur <= 20) {
        if (rotate()) lastEvent = lastEvent == 0 ? 6 : lastEvent;
      }
    } else if (!i.down) {
      // Klavye / bot
      switch (i.swipe) {
        case 0:
          rotate();
        case 1:
          move(1);
        case 3:
          move(-1);
        case 2:
          hardDrop();
      }
    }
    if (cur >= 0 && i.dirX != 0) {
      if (i.dirX != _dasDir) {
        _dasDir = i.dirX;
        _dasTimer = 0;
      } else {
        _dasTimer++;
        if (_dasTimer >= 10 && (_dasTimer - 10) % 3 == 0) move(i.dirX);
      }
    } else {
      _dasDir = 0;
    }
    _prevDown = i.down;
  }

  /// Güçlendirici: en alttaki iki sırayı siler.
  @override
  bool useBooster() {
    if (over) return false;
    _removeRows([kRows - 1, kRows - 2]);
    flashRows = const [kRows - 1, kRows - 2];
    flash = 18;
    lastEvent = 2;
    return true;
  }

  @override
  double get progress => target == 0 ? 0 : (lines / target).clamp(0, 1).toDouble();

  @override
  String get goalText => target == 0 ? '$lines' : '$lines/$target';

  @override
  Map<String, int> get stats => {
        'lines_cleared': lines,
        'quads': quads,
        'max_combo': maxCombo < 0 ? 0 : maxCombo,
        'pieces': pieces,
      };

  @override
  int get stars => lifeStars(this, 3);
}

/// Tahtayı puanlar (yükseklik, delik, pürüz, silinen sıra).
double evaluateBoard(List<int> g, int cleared) {
  var agg = 0, holes = 0, bump = 0, prev = -1, maxH = 0;
  for (var x = 0; x < kCols; x++) {
    var h = 0;
    var seen = false;
    for (var y = 0; y < kRows; y++) {
      final f = g[y * kCols + x] != 0;
      if (f && !seen) {
        seen = true;
        h = kRows - y;
      } else if (!f && seen) {
        holes++;
      }
    }
    agg += h;
    if (h > maxH) maxH = h;
    if (prev >= 0) bump += (h - prev).abs();
    prev = h;
  }
  return -0.51 * agg + 0.76 * cleared - 0.36 * holes * 2 - 0.18 * bump - (maxH > 14 ? (maxH - 14) * 2.0 : 0);
}

/// Bot: her parça için en iyi döndürme ve sütunu seçer, sonra oraya sürer.
ArcadeInput fallBot(ArcadeSim s) {
  final g = s as FallSim;
  if (g.cur < 0) return ArcadeInput.idle;
  if (g.botPiece != g.pieces) {
    g.botPiece = g.pieces;
    g.botSteps = 0;
    var best = double.negativeInfinity;
    g.botRot = 0;
    g.botCol = g.px;
    for (var r = 0; r < 4; r++) {
      if (g.cur == 1 && r > 0) break;
      for (var x = -2; x < kCols; x++) {
        if (!g.fits(g.cur, r, x, g.py)) continue;
        var y = g.py;
        while (g.fits(g.cur, r, x, y + 1)) {
          y++;
        }
        final b = List<int>.of(g.grid);
        var bad = false;
        for (final c in shapes[g.cur][r]) {
          final cy = y + c[1];
          if (cy < 0) {
            bad = true;
            break;
          }
          b[cy * kCols + x + c[0]] = 9;
        }
        if (bad) continue;
        var cleared = 0;
        for (var yy = 0; yy < kRows; yy++) {
          var full = true;
          for (var xx = 0; xx < kCols; xx++) {
            if (b[yy * kCols + xx] == 0) {
              full = false;
              break;
            }
          }
          if (full) {
            cleared++;
            b.removeRange(yy * kCols, (yy + 1) * kCols);
            b.insertAll(0, List<int>.filled(kCols, 0));
          }
        }
        final v = evaluateBoard(b, cleared);
        if (v > best) {
          best = v;
          g.botRot = r;
          g.botCol = x;
        }
      }
    }
  }
  g.botSteps++;
  if (g.botSteps > 14) return const ArcadeInput(swipe: 2);
  if (g.rot != g.botRot) return const ArcadeInput(swipe: 0);
  if (g.px < g.botCol) return const ArcadeInput(swipe: 1);
  if (g.px > g.botCol) return const ArcadeInput(swipe: 3);
  return const ArcadeInput(swipe: 2);
}
