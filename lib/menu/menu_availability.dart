/// Regras de disponibilidade do cardápio.
///
/// Espelho fiel de `backend/domain/menu/availability.ts` no webapp — a mesma
/// lógica que o agente usa para decidir se vende um item. Qualquer divergência
/// aqui faz o app mostrar "disponível" um produto que o agente recusa vender.
library;

/// Chave de data no formato do backend: `YYYY-MM-DD`.
///
/// O servidor calcula no fuso de São Paulo; aqui usamos a data local do
/// aparelho, que é o mesmo fuso na prática (loja e operador no Brasil).
String menuDateKey(DateTime date) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)}';
}

/// Dia da semana da chave, no padrão do backend: 0 = domingo … 6 = sábado.
///
/// O backend faz `new Date('YYYY-MM-DDT00:00:00Z').getUTCDay()`. Em Dart,
/// `DateTime.weekday` é 1 (segunda) … 7 (domingo), então `% 7` converte.
int weekdayFromDateKey(String dateKey) {
  final parts = dateKey.split('-');
  if (parts.length != 3) return 0;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) return 0;
  return DateTime.utc(year, month, day).weekday % 7;
}

/// O produto está disponível na data?
///
/// Ordem de precedência, igual à do backend:
/// 1. `isAvailable == false` → indisponível, ponto final;
/// 2. override para a data → manda, seja para liberar ou bloquear;
/// 3. `availableWeekdays` vazio → disponível todo dia;
/// 4. caso contrário, precisa conter o dia da semana da data.
bool isProductAvailableOnDate({
  required bool isAvailable,
  required List<int> availableWeekdays,
  required Map<String, bool> overridesByDate,
  required String dateKey,
}) {
  if (!isAvailable) return false;

  final override = overridesByDate[dateKey];
  if (override != null) return override;

  if (availableWeekdays.isEmpty) return true;

  return availableWeekdays.contains(weekdayFromDateKey(dateKey));
}

const List<String> kWeekdayShortLabels = [
  'Dom',
  'Seg',
  'Ter',
  'Qua',
  'Qui',
  'Sex',
  'Sáb',
];

const List<String> _weekdayLabels = [
  'domingo',
  'segunda',
  'terça',
  'quarta',
  'quinta',
  'sexta',
  'sábado',
];

/// `[5, 6, 0]` → "domingo, sexta e sábado". Vazio → `''` (todo dia).
String formatWeekdaysPtBr(List<int> weekdays) {
  final labels = (weekdays.where((d) => d >= 0 && d <= 6).toList()..sort())
      .map((d) => _weekdayLabels[d])
      .toList();
  if (labels.isEmpty) return '';
  if (labels.length == 1) return labels.first;
  return '${labels.sublist(0, labels.length - 1).join(', ')} e ${labels.last}';
}
