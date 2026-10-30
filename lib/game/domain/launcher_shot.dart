// 🌎 Project imports:
import 'package:bubble_shooter/game/domain/bubble_color.dart';

enum ShotKind { normal, bomb, rainbow }

typedef LauncherShot = ({BubbleColor color, ShotKind kind});
