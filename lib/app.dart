import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'domain/models.dart';
import 'providers.dart';

import 'ui/history_screen.dart';
import 'ui/program_screen.dart';
import 'ui/settings_screen.dart';
import 'ui/today_screen.dart';

/// Запасной акцент для устройств без системной палитры (до Android 12).
const seedColor = Color(0xFF5B9DFF);

class WorkoutTrackerApp extends StatelessWidget {
  const WorkoutTrackerApp({super.key});

  @override
  Widget build(BuildContext context) => DynamicColorBuilder(
        builder: (light, dark) => MaterialApp(
          title: 'Workout Tracker',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
              colorScheme: light?.harmonized() ??
                  ColorScheme.fromSeed(seedColor: seedColor)),
          darkTheme: ThemeData(
              colorScheme: dark?.harmonized() ??
                  ColorScheme.fromSeed(
                      seedColor: seedColor, brightness: Brightness.dark)),
          home: const HomeShell(),
        ),
      );
}

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  var _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Приложение могло пролежать в фоне до другого дня: без этого подходы
      // записывались бы вчерашней датой.
      if (dateOnly(ref.read(clockProvider)()) != ref.read(todayDateProvider)) {
        ref.invalidate(todayDateProvider);
      }
      ref.read(syncRunnerProvider).run();
    } else if (state == AppLifecycleState.paused) {
      // Последние подходы тренировки уходят в таблицу при сворачивании.
      ref.read(syncRunnerProvider).run();
    }
  }

  static const _titles = ['Сегодня', 'История', 'Программа'];

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(_titles[_tab]),
          actions: [
            IconButton(
              tooltip: 'Настройки',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const SettingsScreen())),
            ),
          ],
        ),
        body: IndexedStack(
          index: _tab,
          children: const [TodayScreen(), HistoryScreen(), ProgramScreen()],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.fitness_center), label: 'Сегодня'),
            NavigationDestination(
                icon: Icon(Icons.calendar_month_outlined), label: 'История'),
            NavigationDestination(
                icon: Icon(Icons.list_alt_outlined), label: 'Программа'),
          ],
        ),
      );
}
