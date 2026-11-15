import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers.dart';

final _pendingCountProvider = FutureProvider.autoDispose<int>((ref) async {
  ref.watch(revisionProvider);
  return (await ref.watch(journalStoreProvider).pending()).length;
});

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  var _busy = false;

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      _say('Не получилось: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sync() => _guard(_syncNow);

  Future<void> _syncNow() async {
    final report = await ref.read(syncRunnerProvider).run();
    if (report == null) {
      _say('Сначала войдите в Google');
    } else if (report.failure != null) {
      _say('Не удалось синхронизировать: ${report.failure}');
    } else {
      _say('Синхронизация выполнена');
    }
  }

  Future<bool> _confirm(String title, String text, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Text(text)),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Отмена')),
            FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(action)),
          ],
        ),
      ) ??
      false;

  Future<void> _restore() async {
    if (!await _confirm(
        'Восстановить из таблицы?',
        'Журнал на телефоне будет заменён содержимым листа «Журнал». '
            'Неотправленные подходы сначала уйдут в таблицу.',
        'Восстановить')) {
      return;
    }
    final sync = ref.read(syncServiceProvider)!;
    var errors = const <String>[];
    var done = false;
    await _guard(() async {
      errors = await sync.restoreJournal();
      done = errors.isEmpty;
    });
    if (errors.isNotEmpty && mounted) {
      // Строки, которые не удалось прочитать, пропали бы с телефона.
      final shown = errors.take(8).join('\n');
      final more = errors.length > 8 ? '\n…и ещё ${errors.length - 8}' : '';
      if (!await _confirm(
          'Часть строк не прочитана',
          'Эти строки листа «Журнал» не удалось разобрать:\n\n'
              '$shown$more\n\nИсправьте их в таблице или восстановите '
              'журнал без них.',
          'Восстановить без них')) {
        return;
      }
      await _guard(() async {
        await sync.restoreJournal(ignoreErrors: true);
        done = true;
      });
    }
    if (done) _say('Журнал восстановлен из таблицы');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sync = ref.watch(syncServiceProvider);
    final auth = ref.watch(googleAuthProvider);
    final pending = ref.watch(_pendingCountProvider).value ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: SafeArea(
        child: ListView(
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (sync == null)
              const ListTile(
                leading: Icon(Icons.science_outlined),
                title: Text('Демо-режим'),
                subtitle: Text(
                    'Данные — образец, синхронизация с Google отключена.'),
              )
            else ...[
              if (auth != null && !auth.isConfigured)
                ListTile(
                  leading: Icon(Icons.error_outline,
                      color: theme.colorScheme.error),
                  title: const Text('Вход через Google не настроен'),
                  subtitle: const Text(
                      'Сборка сделана без GOOGLE_SERVER_CLIENT_ID. '
                      'См. docs/setup.md.'),
                )
              else if (auth != null && auth.email == null)
                ListTile(
                  leading: const Icon(Icons.login),
                  title: const Text('Войти через Google'),
                  subtitle: const Text(
                      'Нужно для синхронизации с таблицей. Приложение получит '
                      'доступ только к таблице, которую создаст само.'),
                  onTap: () => _guard(() async {
                    final signedIn = await auth.signIn();
                    if (!mounted) return;
                    setState(() {});
                    if (signedIn) await _syncNow();
                  }),
                )
              else if (auth != null)
                ListTile(
                  leading: const Icon(Icons.account_circle_outlined),
                  title: Text(auth.email!),
                  subtitle: const Text('Выйти из аккаунта'),
                  onTap: () => _guard(() async {
                    await auth.signOut();
                    // Другой аккаунт получит свою таблицу.
                    await sync.forgetSpreadsheet();
                    if (mounted) setState(() {});
                  }),
                ),
              ListTile(
                leading: const Icon(Icons.cloud_upload_outlined),
                title: Text(
                    pending == 0 ? 'Всё отправлено' : 'Не отправлено: $pending'),
                subtitle: const Text('Подходы, которые ждут отправки в таблицу'),
              ),
              ListTile(
                leading: const Icon(Icons.sync),
                title: const Text('Синхронизировать'),
                subtitle: const Text(
                    'Загрузить программу и отправить новые подходы'),
                onTap: _sync,
              ),
              ListTile(
                leading: const Icon(Icons.table_chart_outlined),
                title: const Text('Открыть таблицу'),
                onTap: () => _guard(() async {
                  final url = await sync.spreadsheetUrl();
                  if (url == null) {
                    _say('Таблица появится после первой синхронизации');
                  } else {
                    await launchUrl(Uri.parse(url),
                        mode: LaunchMode.externalApplication);
                  }
                }),
              ),
              ListTile(
                leading: const Icon(Icons.restore),
                title: const Text('Восстановить из таблицы'),
                subtitle: const Text(
                    'Заменить журнал на телефоне содержимым листа «Журнал»'),
                onTap: _restore,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
