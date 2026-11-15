# Workout Tracker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Android-приложение на Flutter для учёта тренировок: экран «Сегодня», ввод подходов кнопками «плюс/минус», прогресс по упражнению, синхронизация с Google-таблицей, APK из GitHub Releases.

**Architecture:** Чистое ядро на Dart (`lib/domain`, `lib/sheets/sheet_codec.dart`, `lib/migration`) без зависимостей от Flutter. Хранилища описаны интерфейсами с двумя реализациями: drift/SQLite для телефона и in-memory для тестов и демо-режима в браузере. Синхронизация работает через интерфейс `SheetsGateway`, поэтому вся логика проверяется на подделке.

**Tech Stack:** Flutter stable, Dart 3, `flutter_riverpod`, `drift` + `sqlite3_flutter_libs`, `google_sign_in`, `googleapis` (Sheets v4, Drive v3), `extension_google_sign_in_as_googleapis_auth`, `dynamic_color`, `fl_chart`, `uuid`, `csv`, `intl`.

**Spec:** `docs/superpowers/specs/2026-11-15-workout-tracker-design.md`

## Global Constraints

- `applicationId`: `com.gradysnik.workout_tracker`; `minSdk` 26.
- Все строки интерфейса на русском. Тема: светлая/тёмная по системе; на Android 12+ палитра из `dynamic_color`, иначе `ColorScheme.fromSeed(Color(0xFF5B9DFF))`. Галочка «выполнено» всегда `Color(0xFF4ADE80)`, линия графика всегда `Color(0xFF5B9DFF)`.
- Единственная область доступа Google: `https://www.googleapis.com/auth/drive.file`.
- Название создаваемой таблицы: `Workout Tracker`. Листы: `Программа`, `Расписание`, `Журнал`.
- Заголовки листов (точно):
  - `Программа`: `Тренировка, Порядок, Упражнение, Тип, Подходы, Повторы, Дроп-сет, Шаг веса, Заметка`
  - `Расписание`: `День недели, Тренировка`
  - `Журнал`: `ID, Дата, Тренировка, Упражнение, Подход, Часть, Вес, Повторы, Секунды, Минуты, Ккал, Заметка`
- Типы упражнений в таблице: `силовое`, `время`, `кардио`. Дроп-сет: `да` / `нет`.
- Шаг веса по умолчанию 2,5.
- Запись в таблицу с `valueInputOption=RAW`; дата в журнале — строка `yyyy-MM-dd`.
- Приложение полностью работает без сети; журнал в локальной базе — источник правды.
- Модули в `lib/domain`, `lib/migration`, `lib/sheets/sheet_codec.dart` не импортируют Flutter.
- `drift/native.dart` импортируется только из `lib/data/drift/open_native.dart` (условный импорт), чтобы веб-сборка демо-режима компилировалась.
- Версии пакетов — последние стабильные на момент установки; для `google_sign_in` следовать README установленной версии (API менялся между 6 и 7).
- Коммит после каждой задачи; `flutter analyze` и `flutter test` зелёные перед коммитом.

## Review Focus

1. **Значения после ручной правки или CSV-импорта.** Дата приходит как `10.11.2026`, вес как `"7,5"` или число `60.0`, пустые хвостовые ячейки отсутствуют. Ожидание: разбираются так же, как `2026-11-10` и `7.5`. → Task 3.
2. **Ошибки в листе «Программа».** Неизвестный тип, пустое название, нечисловые «Подходы», полностью пустая строка. Ожидание: строка пропущена, сообщение с номером строки, остальные загружены, приложение не падает. → Task 3.
3. **Одно упражнение, разное написание.** Регистр, двойные пробелы, перенос строки внутри названия. Ожидание: одна история. → Task 2.
4. **Обрыв синхронизации.** Строки добавлены в таблицу, но отметка «отправлено» не сохранилась. Ожидание: повторная отправка не создаёт дубликатов. → Task 6.
5. **Пустые программа или расписание.** Ожидание: `chooseWorkout` возвращает `null`, экран «Сегодня» показывает подсказку, а не ошибку. → Task 2, Task 8.

---

## Структура файлов

```
lib/
  main.dart                      точка входа, выбор реального/демо окружения
  app.dart                       MaterialApp, тема, нижняя навигация
  providers.dart                 провайдеры Riverpod (хранилища, синхронизация)
  domain/
    models.dart                  ExerciseType, ProgramExercise, ScheduleEntry, JournalRow
    exercise_key.dart            exerciseKey()
    today_selector.dart          chooseWorkout()
    prefill.dart                 prefillSet()
    progress.dart                progressSeries()
  data/
    stores.dart                  интерфейсы JournalStore, ProgramStore, MetaStore
    memory_stores.dart           in-memory реализации
    demo_data.dart               образец программы и журнала для демо-режима
    drift/database.dart          таблицы drift
    drift/drift_stores.dart      реализации на drift
    drift/open_native.dart, open_stub.dart
  sheets/
    sheet_codec.dart             строки таблицы <-> модели
    sheets_gateway.dart          интерфейс SheetsGateway
    google_sheets_gateway.dart   реализация на googleapis
    google_auth.dart             вход через Google
    sync_service.dart            SyncService
  migration/legacy_parser.dart   разбор старой таблицы
  ui/
    today_screen.dart, exercise_screen.dart, progress_screen.dart,
    history_screen.dart, program_screen.dart, settings_screen.dart
    widgets/stepper_field.dart
tool/migrate.dart                CLI переноса истории
test/…                           зеркалит lib/
.github/workflows/ci.yml, release.yml
docs/setup.md
```

---

### Task 1: Каркас проекта и CI

**Files:**
- Create: Flutter-проект в корне репозитория, `analysis_options.yaml`, `.github/workflows/ci.yml`
- Modify: `.gitignore`, `android/app/build.gradle*`

**Interfaces:**
- Produces: рабочие команды `flutter analyze`, `flutter test`.

- [ ] **Step 1:** Установить Flutter: `brew install --cask flutter`. Проверка: `flutter --version` печатает версию stable.
- [ ] **Step 2:** В корне репозитория: `flutter create --org com.gradysnik --project-name workout_tracker --platforms android,web .` Проверка: `flutter test` проходит на шаблонном тесте.
- [ ] **Step 3:** Добавить зависимости из Tech Stack (`flutter pub add …`; dev: `drift_dev`, `build_runner`, `flutter_lints`). Выставить `minSdk = 26` и `applicationId` из Global Constraints.
- [ ] **Step 4:** `ci.yml`: на `push` и `pull_request` — `subosito/flutter-action@v2` (channel stable), `flutter pub get`, `dart run build_runner build --delete-conflicting-outputs`, `flutter analyze`, `flutter test`.
- [ ] **Step 5:** Удалить шаблонный счётчик, оставить пустой `MaterialApp` с текстом «Workout Tracker». `flutter analyze` — без замечаний. Commit: `chore: scaffold Flutter project and CI`.

### Task 2: Модели и логика домена

**Files:**
- Create: `lib/domain/models.dart`, `exercise_key.dart`, `today_selector.dart`, `prefill.dart`, `progress.dart`
- Test: `test/domain/*_test.dart`

**Interfaces:**
- Produces:

```dart
enum ExerciseType { strength, timed, cardio }

class ProgramExercise { // все поля final, const-конструктор с именованными параметрами
  String workout; int order; String name; ExerciseType type;
  int sets; String repsTarget; bool dropSet; double weightStep; String note; }

class ScheduleEntry { int weekday; /* DateTime.monday..sunday */ String workout; }

class JournalRow { // + copyWith, ==, hashCode
  String id; DateTime date; /* только дата, UTC-полночь */ String workout; String exercise;
  int setNo; int partNo; double? weight; int? reps; int? seconds; double? minutes; int? kcal; String note; }

String exerciseKey(String name);

class TodayChoice { String workout; String? missedWorkout; bool early; }
TodayChoice? chooseWorkout({required DateTime today,
    required List<ScheduleEntry> schedule,
    required List<({DateTime date, String workout})> sessions});

class SetDraft { double? weight; int? reps; int? seconds; double? minutes; int? kcal; }
SetDraft prefillSet({required ProgramExercise exercise, required int setNo,
    required List<JournalRow> today, required List<JournalRow> lastSession});

enum Metric { maxWeight, volume, reps, seconds, kcal }
List<Metric> metricsFor(ExerciseType type); // strength: maxWeight, volume, reps; timed: seconds; cardio: kcal
List<({DateTime date, double value})> progressSeries(List<JournalRow> rows, Metric metric);
```

- [ ] **Step 1: Тесты `exerciseKey`**

```dart
expect(exerciseKey('  Тяга верхнего блока \nк груди  (широкий) '), 'тяга верхнего блока к груди (широкий)');
expect(exerciseKey('FACE pulls'), exerciseKey('Face  Pulls'));
```

- [ ] **Step 2:** Реализовать: `trim`, все пробельные последовательности (включая `\n`) в один пробел, `toLowerCase`. Тесты зелёные.

- [ ] **Step 3: Тесты `chooseWorkout`.** Расписание Вт=`A`, Чт=`B`, Сб=`C`. Недели считаются от 2026-11-10 (вторник).

| today | sessions | ожидание |
|---|---|---|
| Вт 17.11 | A 10.11, B 12.11, C 14.11 | workout A, missed null, early false |
| Ср 18.11 | …, C 14.11 (A 17.11 нет) | workout A, missed null, early false |
| Чт 19.11 | …, C 14.11 (A 17.11 нет) | workout B, missed A, early false |
| Чт 19.11 | …, A 18.11 | workout B, missed null |
| Пн 16.11 | …, C 14.11 | workout A, early true |
| Вт 17.11 | …, A 16.11 (сделана досрочно) | workout B, early true |
| Вт 17.11 | …, A 17.11 (сделана сегодня) | workout A, early false |
| Вт 24.11 | последняя C 14.11 (пропущена неделя) | workout A, missed null |
| Ср 18.11 | …, C 14.11, A 18.11 (пропущенная сделана сегодня) | workout A, missed null, early false |
| любой | schedule пуст | null |

- [ ] **Step 4:** Реализовать `chooseWorkout` по алгоритму:
  1. Если в `sessions` есть сессия с датой `today` → `workout` = её тренировка, `missedWorkout = null`, `early = false`. Конец.
  2. «Слот» — пара (дата, тренировка) по расписанию. «Окно» слота — от дня после предыдущего слота (любой тренировки) до `today` включительно. Слот «закрыт», если в его окне есть сессия этой тренировки.
  3. `prev` — ближайший слот строго до `today`, `prev2` — слот перед ним. `missed = prev.workout`, если `prev` не закрыт, а `prev2` закрыт; иначе `null`.
  4. Если на `today` есть слот и он не закрыт → `workout` = он, `early = false`, `missedWorkout = missed`.
  5. Иначе если `missed != null` → `workout = missed`, `missedWorkout = null`, `early = false`.
  6. Иначе → первый незакрытый слот с датой ≥ `today`; `early = (его дата > today)`.

- [ ] **Step 5: Тесты `prefillSet`**: (а) берёт вес и повторы части 1 того же `setNo` из `lastSession`; (б) если в `lastSession` такого подхода нет — из предыдущего подхода `today`; (в) если нет ничего — `weight 0`, `reps` = нижняя граница `repsTarget` (`'8–10'` → 8, `''` → 0); (г) для `timed` заполняет `seconds`, для `cardio` — `minutes` и `kcal`.
- [ ] **Step 6:** Реализовать `prefillSet`. Тесты зелёные.
- [ ] **Step 7: Тесты `progressSeries`**: одна точка на дату, даты по возрастанию; `maxWeight` — максимум веса за день; `volume` — сумма `weight*reps` по всем частям; `reps` — сумма повторов; `seconds` — максимум; `kcal` — сумма; строки с `null` в нужном поле пропускаются.
- [ ] **Step 8:** Реализовать. `flutter test test/domain` — PASS. Commit: `feat: domain models and workout selection`.

### Task 3: Кодек листов

**Files:**
- Create: `lib/sheets/sheet_codec.dart`
- Test: `test/sheets/sheet_codec_test.dart`

**Interfaces:**
- Consumes: модели из Task 2.
- Produces:

```dart
const programHeader = [...]; const scheduleHeader = [...]; const journalHeader = [...]; // из Global Constraints
class ParseResult<T> { List<T> items; List<String> errors; }
ParseResult<ProgramExercise> parseProgram(List<List<Object?>> rows);   // rows включает строку заголовков
ParseResult<ScheduleEntry>   parseSchedule(List<List<Object?>> rows);
ParseResult<JournalRow>      parseJournal(List<List<Object?>> rows);
List<Object?> journalRowToCells(JournalRow row);                       // 12 ячеек, null -> ''
List<Object?> programToCells(ProgramExercise e); List<Object?> scheduleToCells(ScheduleEntry e);
```

- [ ] **Step 1: Тесты.**
  - Круговой: `parseJournal([journalHeader, journalRowToCells(r)]).items.single == r` для строки дроп-сета и для кардио-строки.
  - Дата `'10.11.2026'` и `'2026-11-10'` дают одну и ту же дату; вес `'7,5'`, `'7.5'`, `7.5`, `60` (int) разбираются; короткая строка (обрезаны пустые хвостовые ячейки) разбирается.
  - `parseProgram`: `Тип` `'Силовое '` → `strength`; `Дроп-сет` `'Да'` → true, пусто → false; пустой `Шаг веса` → 2.5; пустые `Подходы` у кардио → 1.
  - Ошибки программы: неизвестный тип, пустое название, `Подходы = 'много'` → строка пропущена, `errors` содержит `'Программа, строка N: …'`; полностью пустая строка пропускается без ошибки.
  - `parseSchedule`: `'Вт'`, `'вторник'`, `'ВТ'` → `DateTime.tuesday`; неизвестный день → ошибка.
  - Строка журнала с пустым `ID` или неразборной датой → пропущена с ошибкой.
- [ ] **Step 2:** Запустить — FAIL.
- [ ] **Step 3:** Реализовать. Колонки находятся по позиции согласно заголовкам из Global Constraints.
- [ ] **Step 4:** `flutter test test/sheets/sheet_codec_test.dart` — PASS. Commit: `feat: sheet codec`.

### Task 4: Перенос истории из старой таблицы

**Files:**
- Create: `lib/migration/legacy_parser.dart`, `tool/migrate.dart`
- Test: `test/migration/legacy_parser_test.dart`, фикстура `test/migration/legacy_sample.csv`

**Interfaces:**
- Consumes: модели, `*ToCells`, заголовки.
- Produces:

```dart
class LegacyResult { List<ProgramExercise> program; List<ScheduleEntry> schedule;
                     List<JournalRow> journal; List<String> warnings; }
LegacyResult parseLegacy(List<List<String>> cells);
```
CLI: `dart run tool/migrate.dart <input.csv> <outDir>` пишет `program.csv`, `schedule.csv`, `journal.csv` и печатает предупреждения.

Правила разбора (выведены из реальной таблицы):
- Строка 1: `A1` игнорируется; ячейка колонки — три даты `dd.MM.yyyy` через перевод строки. Колонка, где дат не три, пропускается.
- Строка-раздел: `A` соответствует `^(ПН|ВТ|СР|ЧТ|ПТ|СБ|ВС)\.\s*(.+)$`. Даёт день недели и название тренировки; k-й по счёту раздел берёт k-ю дату из заголовка колонки (позиционно, даты не обязаны идти по порядку). Названия: `Сп+Биц`→`Спина + Бицепс`, `Гр+Триц`→`Грудь + Трицепс`, `Ноги+Кор`→`Ноги + Кор`, прочие как есть.
- Строка упражнения: строки ячейки `A` разбиваются по `\n`. Если последняя соответствует `^(\d+)\s*[×xх]\s*(\d+(?:[–-]\d+)?)(.*)$` → `sets`, `repsTarget`, `dropSet = содержит 'дроп'`, а название — остальные строки через пробел. Если содержит `секунд` → `timed`, из `(\d+) по (\d+[–-]\d+)` берутся `sets` и `repsTarget`. Иначе, если в любой ячейке данных строки есть `\d+\s*[кk]` → `cardio`, `sets=1`, название — первая строка, остальное в `note`. Иначе `strength`, `sets=3`, название — вся ячейка через пробел.
- Ячейка `strength`: строка = подход; `-` делит на части; часть — `^(\d+(?:,\d+)?)\.(\d+)$` (вес.повторы). Хвост `(…)` уходит в `note`. Одна строка из трёх чисел через точку (`20.20.20`) — три подхода с повторами без веса.
- Ячейка `timed`: `30.30.30` или строки — секунды по подходам.
- Ячейка `cardio`: `kcal` из `(\d+)\s*[кk]`, `minutes` из `(\d+)\s*m`, остальной текст — в `note`.
- Пропускаются: пустые ячейки и части, где все числа равны 0. Неразборная ячейка → предупреждение `'R<row>C<col>: <текст>'`, ячейка пропущена.
- `id` строки журнала: `m-<row>-<col>-<setNo>-<partNo>`. `order` — порядковый номер упражнения внутри раздела с 1.

- [ ] **Step 1:** Составить `legacy_sample.csv`: заголовок с двумя колонками недель и колонкой `Столбец 26`; три раздела; строки, покрывающие каждое правило выше, включая `40.9-30.8-20.10`, `15.12 (у стены)`, `64к`, `7%-5.5s\n7m-57k`, `30.30.30`, `20.20.20`, `0.0\n0.0`, `0k`, и одну неразборную ячейку.
- [ ] **Step 2: Тесты**: количество упражнений и их типы; `Тяга верхнего блока к груди (широкий)` имеет `sets 4`, `repsTarget '8–10'`, `dropSet false`; дроп-сет даёт три строки с `partNo 1..3` и одним `setNo`; дата строки раздела 2 равна второй дате заголовка; заметка `у стены`; кардио: `kcal 57`, `minutes 7`, note содержит `7%`; нулевые ячейки не дают строк; ровно одно предупреждение; `schedule` = Вт, Чт, Сб.
- [ ] **Step 3:** FAIL → реализовать `parseLegacy` → PASS.
- [ ] **Step 4:** `tool/migrate.dart`: чтение через `csv`, запись трёх файлов с заголовками. Проверка: `dart run tool/migrate.dart test/migration/legacy_sample.csv /tmp/out` создаёт три файла, `journal.csv` разбирается `parseJournal` без ошибок (тест).
- [ ] **Step 5:** Commit: `feat: legacy spreadsheet migration tool`.

### Task 5: Хранилища

**Files:**
- Create: `lib/data/stores.dart`, `memory_stores.dart`, `drift/database.dart`, `drift/drift_stores.dart`, `drift/open_native.dart`, `drift/open_stub.dart`
- Test: `test/data/stores_contract_test.dart`

**Interfaces:**
- Produces:

```dart
abstract class JournalStore {
  Future<void> upsert(JournalRow row);                 // помечает строку «к отправке»
  Future<void> delete(String id);                      // мягкое удаление, «к отправке»
  Stream<List<JournalRow>> watchSession(DateTime date, String workout);
  Future<List<JournalRow>> lastSessionOf(String exerciseKey, {required DateTime before});
  Future<List<JournalRow>> historyOf(String exerciseKey);
  Future<List<({DateTime date, String workout})>> sessions();
  Future<List<String>> exerciseNames();                // последнее написание для каждого ключа
  Future<List<({JournalRow row, bool deleted})>> pending();
  Future<void> markSynced(Iterable<String> ids);       // удалённые после этого стираются физически
  Future<void> replaceAll(List<JournalRow> rows);      // все строки «отправлены»
}
abstract class ProgramStore {
  Future<void> replace(List<ProgramExercise> program, List<ScheduleEntry> schedule);
  Future<List<ProgramExercise>> program(); Future<List<ScheduleEntry>> schedule();
  Stream<void> changes();
}
abstract class MetaStore { Future<String?> get(String key); Future<void> set(String key, String? value); }
```

- [ ] **Step 1:** Контрактный тест — одна функция `void storeContract(String name, JournalStore Function() make)`, вызываемая для in-memory и для drift (`NativeDatabase.memory()`). Проверяет: `upsert` дважды с одним `id` оставляет одну строку; `lastSessionOf` возвращает строки только последней даты строго раньше `before` и находит упражнение по ключу при другом регистре; `delete` убирает строку из `watchSession`, но она есть в `pending()` с `deleted: true`; после `markSynced` `pending()` пуст; правка отправленной строки возвращает её в `pending()`; `replaceAll` заменяет всё и оставляет `pending()` пустым; `sessions()` без дубликатов.
- [ ] **Step 2:** FAIL → реализовать `memory_stores.dart` → PASS для in-memory.
- [ ] **Step 3:** Таблицы drift: `journal_rows` (поля `JournalRow` + `exercise_key`, `sync_state` 0/1, `deleted` bool), `program_exercises`, `schedule`, `meta`. `dart run build_runner build`. Реализовать `drift_stores.dart`. Открытие базы — через условный импорт `open_stub.dart` / `open_native.dart` (`dart.library.ffi`).
- [ ] **Step 4:** `flutter test test/data` — PASS для обеих реализаций. Commit: `feat: local stores`.

### Task 6: Синхронизация

**Files:**
- Create: `lib/sheets/sheets_gateway.dart`, `lib/sheets/sync_service.dart`
- Test: `test/sheets/sync_service_test.dart` (с `FakeSheetsGateway` в тестовом файле)

**Interfaces:**
- Consumes: хранилища (Task 5), кодек (Task 3).
- Produces:

```dart
abstract class SheetsGateway {
  Future<String?> findSpreadsheet(String title);
  Future<String> createSpreadsheet(String title, Map<String, List<String>> headersBySheet);
  Future<List<List<Object?>>> readSheet(String spreadsheetId, String sheet);
  Future<void> appendRows(String spreadsheetId, String sheet, List<List<Object?>> rows);
  Future<void> updateRow(String spreadsheetId, String sheet, int rowNumber, List<Object?> cells); // с 1
}
class SyncReport { List<String> programErrors; int pushed; Object? failure; }
class SyncService {
  SyncService(SheetsGateway gateway, JournalStore journal, ProgramStore program, MetaStore meta);
  Future<String> ensureSpreadsheet();   // meta['spreadsheetId'] -> findSpreadsheet -> createSpreadsheet
  Future<List<String>> pullProgram();   // возвращает ошибки разбора
  Future<int> pushJournal();
  Future<void> restoreJournal();
  Future<SyncReport> syncAll();         // ensure + pull + push; исключения ловит в failure
  String? get spreadsheetUrl;
}
```

`pushJournal`: прочитать колонку `ID` листа `Журнал` (через `readSheet`), построить карту `id → номер строки`. Для каждой ожидающей строки: есть в карте и не удалена → `updateRow`; есть и удалена → `updateRow` двенадцатью пустыми ячейками; нет в карте и не удалена → в пакет `appendRows`; нет и удалена → ничего. После успешных вызовов — `markSynced`.

- [ ] **Step 1: Тесты**
  - `ensureSpreadsheet`: при пустом `meta` и отсутствии таблицы создаёт её с тремя листами и заголовками из Global Constraints и сохраняет id; при найденной по названию — не создаёт; при сохранённом id — не обращается к шлюзу.
  - `pullProgram` кладёт разобранные программу и расписание в `ProgramStore`, возвращает ошибки кодека; при пустом листе `Программа` хранилище становится пустым.
  - `pushJournal`: две новые строки → один `appendRows` с двумя строками, `pending()` пуст.
  - **Обрыв:** шлюз-подделка выполняет `appendRows`, затем бросает исключение; повторный `pushJournal` не добавляет дубликатов (в листе по-прежнему две строки данных).
  - Правка отправленной строки → `updateRow` в ту же строку листа, количество строк не меняется.
  - Удаление отправленной строки → её строка листа очищена; `parseJournal` по листу её не возвращает.
  - `restoreJournal` заменяет локальный журнал содержимым листа.
  - `syncAll` при исключении шлюза возвращает `failure != null` и не бросает.
- [ ] **Step 2:** FAIL → реализовать → PASS. Commit: `feat: sync service`.

### Task 7: Google: вход и шлюз

**Files:**
- Create: `lib/sheets/google_auth.dart`, `lib/sheets/google_sheets_gateway.dart`, `docs/setup.md`
- Modify: `android/app/src/main/AndroidManifest.xml` (разрешение `INTERNET`)

**Interfaces:**
- Consumes: `SheetsGateway`.
- Produces:

```dart
class GoogleAuth { Future<bool> signInSilently(); Future<bool> signIn(); Future<void> signOut();
                   String? get email; Future<http.Client?> client(); }
class GoogleSheetsGateway implements SheetsGateway { GoogleSheetsGateway(GoogleAuth auth); }
```

- [ ] **Step 1:** `GoogleAuth` по README установленной версии `google_sign_in`, область только `drive.file`; `client()` через `extension_google_sign_in_as_googleapis_auth`.
- [ ] **Step 2:** `GoogleSheetsGateway`: `findSpreadsheet` — Drive v3 `files.list` с `q: "name = '<title>' and mimeType = 'application/vnd.google-apps.spreadsheet' and trashed = false"`; `createSpreadsheet` — Sheets `spreadsheets.create` с тремя листами, затем запись заголовков; `readSheet` — `values.get` диапазона `'<лист>'!A:L` с `valueRenderOption=UNFORMATTED_VALUE`, `dateTimeRenderOption=FORMATTED_STRING`; запись — `RAW`.
- [ ] **Step 3:** `docs/setup.md` на русском, по шагам: создать проект Google Cloud; включить Google Sheets API и Google Drive API; экран согласия (External, область `drive.file`, статус «In production»); OAuth-клиент типа Android с пакетом `com.gradysnik.workout_tracker` и SHA-1 ключа релиза (плюс веб-клиент, если этого требует установленная версия `google_sign_in`, и куда вписать его id); как получить SHA-1; секреты репозитория из Task 10; как перенести историю (`tool/migrate.dart`, Файл → Импорт → Заменить текущий лист, затем «Восстановить из таблицы»).
- [ ] **Step 4:** `flutter analyze` чист; `flutter build web` компилируется. Проверка на устройстве — в Task 10. Commit: `feat: Google sign-in and Sheets gateway`.

### Task 8: Оболочка приложения и экран «Сегодня»

**Files:**
- Create: `lib/app.dart`, `lib/providers.dart`, `lib/data/demo_data.dart`, `lib/ui/today_screen.dart`
- Modify: `lib/main.dart`
- Test: `test/ui/today_screen_test.dart`

**Interfaces:**
- Consumes: хранилища, `chooseWorkout`, `SyncService`.
- Produces: провайдеры `journalStoreProvider`, `programStoreProvider`, `metaStoreProvider`, `syncServiceProvider`, `clockProvider` (`DateTime Function()`), `selectedWorkoutProvider` (ручной выбор, `String?`); маршрут `ExerciseScreen(exercise: ProgramExercise, date: DateTime)` (экран — в Task 9, здесь заглушка).

- [ ] **Step 1:** `main.dart`: при `const bool.fromEnvironment('DEMO')` — in-memory хранилища с `demo_data.dart` (программа из трёх тренировок спецификации и две недели журнала) и без синхронизации; иначе drift и `SyncService`, при старте `signInSilently` и `syncAll` в фоне.
- [ ] **Step 2:** `app.dart`: тема по Global Constraints (`DynamicColorBuilder`), `NavigationBar` с пунктами «Сегодня», «История», «Программа»; шестерёнка в `AppBar` ведёт в настройки.
- [ ] **Step 3: Widget-тесты** (in-memory хранилища, часы зафиксированы на вторнике):
  - заголовок — название тренировки вторника; в списке только её упражнения в порядке `order`;
  - под упражнением цель `4×8–10, дроп-сет` и текст `прошлый раз 60×10` (макс. вес последней сессии);
  - упражнение, у которого сегодня записано подходов ≥ `sets`, показано с галочкой; счётчик `N из M выполнено`;
  - при `missedWorkout != null` виден баннер `<название> не выполнена — сделать сегодня?`, нажатие переключает экран на неё;
  - при `early` — подпись `Следующая по расписанию`;
  - выбор другой тренировки из меню заголовка показывает её упражнения;
  - при пустой программе — текст `Заполните лист «Программа» в таблице` и кнопка открытия таблицы; исключений нет;
  - жест «потянуть вниз» вызывает `syncAll`.
- [ ] **Step 4:** FAIL → реализовать → PASS.
- [ ] **Step 5:** Визуальная проверка: `flutter run -d web-server --dart-define=DEMO=true --web-port 8080`, открыть в браузере в мобильном размере, сравнить с макетом «1. Сегодня». Commit: `feat: app shell and Today screen`.

### Task 9: Экран ввода подхода

**Files:**
- Create: `lib/ui/exercise_screen.dart`, `lib/ui/widgets/stepper_field.dart`
- Test: `test/ui/exercise_screen_test.dart`, `test/ui/stepper_field_test.dart`

**Interfaces:**
- Consumes: `prefillSet`, `JournalStore`, `uuid`.
- Produces: `StepperField({required double value, required double step, required String label, required ValueChanged<double> onChanged, bool integer = false})`; переход на `ProgressScreen(exerciseName: String)` (Task 10).

- [ ] **Step 1: Тесты `StepperField`**: «+» прибавляет `step`, «−» вычитает и не уходит ниже 0; касание по числу открывает поле ввода, ввод `7,5` даёт 7.5; область нажатия кнопок не меньше 48×48.
- [ ] **Step 2: Тесты экрана**
  - силовое: два `StepperField` (вес с шагом `weightStep`, повторы с шагом 1), значения из `prefillSet`; строка `Прошлый раз: 40×10 · 60×10 · 60×10–40×10`;
  - «Готово» сохраняет `JournalRow` с `date` = переданной дате, `setNo` = следующий, `partNo` 1, новым `id`; подход появляется в списке выше, поля заполняются для следующего;
  - «+ часть дроп-сета» (видна только при `dropSet`) после «Готово» сохраняет строку с тем же `setNo` и `partNo + 1`;
  - касание по записанному подходу позволяет изменить его (тот же `id`) или удалить;
  - `timed`: одно поле «секунды»; `cardio`: поля «минуты» и «ккал»;
  - поле «Заметка» сохраняется в `note`;
  - после подхода номер `sets` заголовок показывает `подход N из M`, ввод сверх `sets` не запрещён.
- [ ] **Step 3:** FAIL → реализовать → PASS.
- [ ] **Step 4:** Визуальная проверка в демо-режиме против макета «А. Кнопки плюс/минус». Commit: `feat: set entry screen`.

### Task 10: Прогресс, история, программа, настройки

**Files:**
- Create: `lib/ui/progress_screen.dart`, `history_screen.dart`, `program_screen.dart`, `settings_screen.dart`
- Test: `test/ui/progress_screen_test.dart`, `history_screen_test.dart`, `settings_screen_test.dart`

**Interfaces:**
- Consumes: `progressSeries`, `metricsFor`, хранилища, `SyncService`, `GoogleAuth`.

- [ ] **Step 1: Тесты**
  - Прогресс: чипы соответствуют `metricsFor(type)`; под графиком список сессий от новых к старым в виде `40×10 · 55×10 · 60×10–40×10`; у упражнения без истории — текст `Пока нет записей`.
  - История: календарь месяца с отметками дат из `sessions()`; касание по дате открывает тренировку этого дня (список упражнений с подходами, с возможностью правки через `ExerciseScreen` на эту дату); раздел «Архив упражнений» содержит названия из `exerciseNames()`, которых нет в программе (сравнение по `exerciseKey`), и ведёт на их прогресс.
  - Программа: тренировки по дням расписания с упражнениями и целями, только чтение; ошибки последнего `pullProgram` показаны сверху списком.
  - Настройки: вход/выход Google и email; «Синхронизировать»; «Открыть таблицу»; «Восстановить из таблицы» требует подтверждения и вызывает `restoreJournal`; строка состояния `Не отправлено: N` по `pending()`.
- [ ] **Step 2:** FAIL → реализовать (график — `fl_chart` `LineChart`, цвет линии из Global Constraints) → PASS.
- [ ] **Step 3:** Визуальная проверка в демо-режиме против макета «3. Прогресс». Commit: `feat: progress, history, program and settings screens`.

### Task 11: Релизная сборка APK

**Files:**
- Create: `.github/workflows/release.yml`
- Modify: `android/app/build.gradle*` (подпись из `android/key.properties`), `.gitignore` (`key.properties`, `*.jks`), `docs/setup.md`, `README.md`

- [ ] **Step 1:** Подпись релиза читается из `android/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`); при отсутствии файла — отладочная подпись, чтобы локальная сборка не падала.
- [ ] **Step 2:** `release.yml` на `push` тега `v*`: Java 17, Flutter stable, восстановление keystore из секрета `KEYSTORE_BASE64` и `key.properties` из `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`; `flutter test`; `flutter build apk --release --build-name=${GITHUB_REF_NAME#v}`; публикация `workout-tracker-<версия>.apk` через `softprops/action-gh-release@v2`. `permissions: contents: write`.
- [ ] **Step 3:** Создать ключ: `keytool -genkeypair -v -keystore ~/.workout-tracker/release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias release` (нужен JDK: `brew install openjdk@17`). Ключ в репозиторий не попадает. Дописать в `docs/setup.md` команды `gh secret set …` и получения SHA-1.
- [ ] **Step 4 (делает владелец):** настроить Google Cloud по `docs/setup.md`, задать секреты.
- [ ] **Step 5:** Тег `v0.1.0`, push. Проверка: workflow зелёный, в релизе есть APK.
- [ ] **Step 6 (на телефоне, владелец):** установить APK; войти; убедиться, что таблица создана; загрузить три CSV; «Восстановить из таблицы»; записать подход в режиме полёта, включить сеть, увидеть строку в листе «Журнал»; заменить название упражнения в «Программе» и убедиться, что у нового пустая история, а старое в «Архиве».
- [ ] **Step 7:** `README.md`: что это, как собрать, ссылка на `docs/setup.md`. Commit: `ci: signed release APK`.
