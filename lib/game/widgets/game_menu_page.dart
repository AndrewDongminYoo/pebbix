// 🐦 Flutter imports:
import 'package:flutter/material.dart';

// 🌎 Project imports:
import 'package:bubble_shooter/gen/assets.gen.dart';

/// A readable menu surface over the same sky used by the title screen.
class GameMenuPage extends StatelessWidget {
  const new({required this.title, required this.children, super.key});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const surface = Color(0xFF191A38);
    const accent = Color(0xFFC4BAFF);
    const scheme = ColorScheme.dark(
      primary: accent,
      onPrimary: Color(0xFF272044),
      secondary: accent,
      surface: surface,
      onSurface: Color(0xFFF5F2FF),
    );
    return Theme(
      data: theme.copyWith(
        colorScheme: scheme,
        disabledColor: const Color(0xFFA6A1BA),
        textTheme: theme.textTheme.apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: scheme.onSurface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: theme.textTheme.headlineSmall?.copyWith(
            color: scheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        listTileTheme: const ListTileThemeData(
          textColor: Color(0xFFF5F2FF),
          iconColor: accent,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
        dividerTheme: const DividerThemeData(color: Color(0xFF3B3A5C), space: 24, indent: 16, endIndent: 16),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? surface : const Color(0xFFD5D0E5),
          ),
          trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? accent : const Color(0xFF44435F),
          ),
          trackOutlineColor: const WidgetStatePropertyAll(Color(0xFF8E88AB)),
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ExcludeSemantics(child: Assets.images.background.image(fit: BoxFit.cover)),
          Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(title: Text(title)),
            body: SafeArea(
              top: false,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    child: Material(
                      color: surface,
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                        side: const BorderSide(color: Color(0xFF4D466F)),
                      ),
                      child: ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        children: children,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
