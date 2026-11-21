import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';

import 'fall_engine.dart';

const dusenBloklarId = 'oyun-dusen-bloklar';

class FallRules extends ArcadeRules<FallLevel> {
  @override
  String get gameId => dusenBloklarId;

  @override
  List<String> get optionalMechanics => const ['garbage', 'rise', 'fast'];

  @override
  List<GameStat> get gameStats => const [
        GameStat('lines_cleared', 'Silinen sıra', 'Lines cleared', scale: 40),
        GameStat('quads', 'Dörtlü silme', 'Four-line clears', scale: 3),
        GameStat('max_combo', 'En uzun seri', 'Best combo', scale: 3),
      ];

  @override
  List<MissionTemplate> get missionTemplates => const [
        MissionTemplate('lines_cleared', 'lines_cleared', [20, 60, 150]),
        MissionTemplate('quads', 'quads', [1, 3, 6]),
      ];

  @override
  FallLevel generate(LevelSpec spec) => generateFallLevel(spec);

  @override
  ArcadeMeta metaOf(FallLevel l) => l.meta;

  @override
  ArcadeSim createSim(FallLevel l) => FallSim(l);

  @override
  ArcadeInput bot(ArcadeSim sim) => fallBot(sim);

  @override
  String? check(FallLevel l) {
    for (var i = 0; i < 4 * kCols; i++) {
      if (l.start[i] != 0) return 'start area blocked';
    }
    return null;
  }
}
