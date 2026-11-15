/// Ключ, по которому упражнение (и тренировка) опознаётся в журнале:
/// без учёта регистра, крайних и повторяющихся пробелов и переносов строк.
String exerciseKey(String name) =>
    name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
