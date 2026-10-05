import 'package:excel_plus/excel_plus.dart';

import '../models/delivery_models.dart';
import 'manifest_parser.dart';

class XlsxManifestParser {
  final ManifestParser _textParser = ManifestParser();

  DeliveryRoute parseBytes(
    List<int> bytes, {
    String routeName = 'Rota importada',
  }) {
    final workbook = Excel.decodeBytes(bytes);
    if (workbook.tables.isEmpty) {
      throw ManifestParseException('A planilha não possui nenhuma aba legível.');
    }

    Sheet? selected;
    for (final sheet in workbook.tables.values) {
      if (sheet.rows.length >= 2) {
        selected = sheet;
        break;
      }
    }
    selected ??= workbook.tables.values.first;

    if (selected.rows.length < 2) {
      throw ManifestParseException(
        'A planilha precisa ter cabeçalho e pelo menos uma linha de dados.',
      );
    }

    final buffer = StringBuffer();

    for (final row in selected.rows) {
      final values = row.map((cell) {
        final value = cell?.value?.toString() ?? '';
        final escaped = value.replaceAll('"', '""');
        return '"$escaped"';
      }).join(';');
      buffer.writeln(values);
    }

    return _textParser.parseText(
      buffer.toString(),
      routeName: routeName,
    );
  }
}
