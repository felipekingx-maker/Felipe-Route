import 'dart:convert';

import '../models/delivery_models.dart';

class ManifestParseException implements Exception {
  final String message;
  ManifestParseException(this.message);

  @override
  String toString() => message;
}

class ManifestParser {
  static const _aliases = <String, List<String>>{
    'stop': [
      'parada', 'stop', 'numero parada', 'n parada', 'sequencia',
      'sequência', 'ordem', 'ordem da parada', 'stop no', 'stop number',
      'route stop', 'número da parada', 'numero da parada'
    ],
    'package': [
      'pacote', 'codigo', 'código', 'codigo pacote', 'código pacote',
      'codigo do pacote', 'código do pacote', 'id pacote', 'id do pacote',
      'numero do pacote', 'número do pacote', 'tracking', 'tracking number',
      'tracking no', 'numero de rastreio', 'número de rastreio',
      'numero de rastreamento', 'número de rastreamento', 'awb', 'spx',
      'spx tracking', 'spx tracking no', 'shipment id', 'shipment',
      'order id', 'pedido', 'numero do pedido', 'número do pedido', 'waybill'
    ],
    'address': [
      'endereco', 'endereço', 'address', 'logradouro', 'endereco completo',
      'endereço completo', 'endereco de entrega', 'endereço de entrega',
      'shipping address', 'delivery address', 'recipient address',
      'buyer address', 'endereco destinatario', 'endereço destinatário'
    ],
    'recipient': ['destinatario', 'destinatário', 'recipient', 'cliente', 'nome'],
    'complement': ['complemento', 'complement', 'referencia', 'referência'],
    'physical': ['parada fisica', 'parada física', 'physical stop', 'grupo'],
    'lat': ['lat', 'latitude'],
    'lng': ['lng', 'lon', 'long', 'longitude'],
  };

  DeliveryRoute parseText(
    String content, {
    String routeName = 'Rota importada',
  }) {
    final normalizedContent =
        content.replaceFirst('\u{feff}', '').replaceAll('\r\n', '\n').trim();

    if (normalizedContent.isEmpty) {
      throw ManifestParseException('O arquivo está vazio.');
    }

    final lines = const LineSplitter()
        .convert(normalizedContent)
        .where((line) => line.trim().isNotEmpty)
        .toList();

    if (lines.length < 2) {
      throw ManifestParseException(
        'O manifesto precisa ter cabeçalho e pelo menos uma linha de pacote.',
      );
    }

    final delimiter = _detectDelimiter(lines.first);
    final headers = _splitLine(lines.first, delimiter)
        .map(_normalizeHeader)
        .toList(growable: false);

    final indexes = <String, int>{};
    for (final entry in _aliases.entries) {
      final normalizedAliases = entry.value.map(_normalizeHeader).toList();
      final index = headers.indexWhere((header) {
        if (normalizedAliases.contains(header)) return true;
        if (header.length < 4) return false;
        return normalizedAliases.any(
          (alias) => header.contains(alias) || alias.contains(header),
        );
      });
      if (index >= 0) indexes[entry.key] = index;
    }

    if (!indexes.containsKey('address')) {
      throw ManifestParseException(
        'Não encontrei a coluna de endereço no romaneio.',
      );
    }

    final packages = <DeliveryPackage>[];

    for (var lineIndex = 1; lineIndex < lines.length; lineIndex++) {
      final values = _splitLine(lines[lineIndex], delimiter);
      String read(String key) {
        final index = indexes[key];
        if (index == null || index >= values.length) return '';
        return values[index].trim();
      }

      final address = read('address');
      if (address.isEmpty) continue;

      final stopRaw = read('stop');
      final packageRaw = read('package');

      final stop = stopRaw.isEmpty ? '$lineIndex' : stopRaw;
      final code = packageRaw.isEmpty
          ? 'LINHA-${lineIndex.toString().padLeft(4, '0')}'
          : packageRaw;

      packages.add(
        DeliveryPackage(
          code: code,
          stopLabel: stop,
          address: address,
          recipient: _nullIfEmpty(read('recipient')),
          complement: _nullIfEmpty(read('complement')),
          physicalStopId: _nullIfEmpty(read('physical')),
          latitude: double.tryParse(read('lat').replaceAll(',', '.')),
          longitude: double.tryParse(read('lng').replaceAll(',', '.')),
        ),
      );
    }

    if (packages.isEmpty) {
      throw ManifestParseException('Nenhum pacote válido foi encontrado.');
    }

    final grouped = <String, List<DeliveryPackage>>{};
    for (final package in packages) {
      final groupKey = package.physicalStopId?.trim().toLowerCase().isNotEmpty == true
          ? 'id:${package.physicalStopId!.trim().toLowerCase()}'
          : 'addr:${_normalizeAddress(package.address, package.complement)}';

      grouped.putIfAbsent(groupKey, () => []).add(package);
    }

    final stops = <PhysicalStop>[];
    var index = 1;

    for (final entry in grouped.entries) {
      final groupPackages = entry.value;
      final first = groupPackages.first;
      stops.add(
        PhysicalStop(
          id: first.physicalStopId ?? 'LOCAL-${index.toString().padLeft(3, '0')}',
          address: first.address,
          complement: first.complement,
          latitude: first.latitude,
          longitude: first.longitude,
          packages: groupPackages,
        ),
      );
      index++;
    }

    return DeliveryRoute(name: routeName, stops: stops);
  }

  String _detectDelimiter(String header) {
    final counts = <String, int>{
      ';': ';'.allMatches(header).length,
      ',': ','.allMatches(header).length,
      '\t': '\t'.allMatches(header).length,
    };

    final selected =
        counts.entries.reduce((a, b) => a.value >= b.value ? a : b);

    if (selected.value == 0) {
      throw ManifestParseException(
        'Não consegui identificar as colunas. Use CSV, TXT separado por ;, , ou tabulação.',
      );
    }

    return selected.key;
  }

  List<String> _splitLine(String line, String delimiter) {
    final values = <String>[];
    final buffer = StringBuffer();
    var quoted = false;

    for (var i = 0; i < line.length; i++) {
      final char = line[i];

      if (char == '"') {
        if (quoted && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (char == delimiter && !quoted) {
        values.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }

    values.add(buffer.toString());
    return values;
  }

  String _normalizeHeader(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('à', 'a')
      .replaceAll('â', 'a')
      .replaceAll('ã', 'a')
      .replaceAll('é', 'e')
      .replaceAll('è', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ì', 'i')
      .replaceAll('î', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ò', 'o')
      .replaceAll('ô', 'o')
      .replaceAll('õ', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ù', 'u')
      .replaceAll('û', 'u')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp(r'[_\-./()]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  String _normalizeAddress(String address, String? complement) {
    final value = '$address ${complement ?? ''}'
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9áàâãéèêíìîóòôõúùûç ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return value;
  }

  String? _nullIfEmpty(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
