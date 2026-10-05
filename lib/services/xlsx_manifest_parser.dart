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
    var headerRow = 0;
    var bestScore = -1;

    String normalize(String value) => value
        .trim()
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('â', 'a')
        .replaceAll('ã', 'a')
        .replaceAll('é', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('õ', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ç', 'c')
        .replaceAll(RegExp(r'[_\-./()]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');

    bool looksLike(String header, List<String> candidates) {
      return candidates.any((candidate) {
        final alias = normalize(candidate);
        return header == alias ||
            (header.length >= 4 &&
                (header.contains(alias) || alias.contains(header)));
      });
    }

    for (final sheet in workbook.tables.values) {
      final limit = sheet.rows.length < 20 ? sheet.rows.length : 20;

      for (var i = 0; i < limit; i++) {
        final headers = sheet.rows[i]
            .map((cell) => normalize(cell?.value?.toString() ?? ''))
            .toList();

        var score = 0;

        for (final header in headers) {
          if (looksLike(header, [
            'endereco',
            'endereço',
            'address',
            'endereco de entrega',
            'endereço de entrega',
            'delivery address',
            'shipping address',
          ])) {
            score += 5;
          }

          if (looksLike(header, [
            'parada',
            'stop',
            'ordem',
            'sequencia',
            'sequência',
            'numero da parada',
            'número da parada',
          ])) {
            score += 3;
          }

          if (looksLike(header, [
            'pacote',
            'codigo',
            'código',
            'tracking',
            'awb',
            'spx',
            'shipment',
            'pedido',
            'order id',
          ])) {
            score += 3;
          }
        }

        if (score > bestScore) {
          bestScore = score;
          selected = sheet;
          headerRow = i;
        }
      }
    }

    selected ??= workbook.tables.values.first;

    if (selected.rows.length <= headerRow + 1) {
      throw ManifestParseException(
        'Não encontrei linhas de dados abaixo do cabeçalho.',
      );
    }

    final buffer = StringBuffer();

    for (var i = headerRow; i < selected.rows.length; i++) {
      final row = selected.rows[i];
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
