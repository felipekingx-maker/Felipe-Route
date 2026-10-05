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
    'stop': ['parada', 'stop', 'numero parada', 'n parada', 'sequencia'],
    'package': ['pacote', 'codigo', 'codigo pacote', 'tracking', 'awb', 'spx'],
    'address': ['endereco', 'endereço', 'address', 'logradouro'],
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
      final index = headers.indexWhere(
        (header) => entry.value.map(_normalizeHeader).contains(header),
      );
      if (index >= 0) indexes[entry.key] = index;
    }

    for (final required in ['stop', 'package', 'address']) {
      if (!indexes.containsKey(required)) {
        throw ManifestParseException(
          'Não encontrei a coluna obrigatória "$required". '
          'Use colunas como Parada, Pacote/Código e Endereço.',
        );
      }
    }

    final packages = <DeliveryPackage>[];

    for (var lineIndex = 1; lineIndex < lines.length; lineIndex++) {
      final values = _splitLine(lines[lineIndex], delimiter);
      String read(String key) {
        final index = indexes[key];
        if (index == null || index >= values.length) return '';
        return values[index].trim();
      }

      final stop = read('stop');
      final code = read('package');
      final address = read('address');

      if (stop.isEmpty && code.isEmpty && address.isEmpty) continue;
      if (stop.isEmpty || code.isEmpty || address.isEmpty) {
        throw ManifestParseException(
          'Linha ${lineIndex + 1} incompleta. '
          'Parada, pacote e endereço são obrigatórios.',
        );
      }

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
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');

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
