import 'dart:convert';
import 'dart:math' as math;

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
    'notes': [
      'observacao', 'observação', 'obs', 'nota', 'notas', 'note', 'notes',
      'informacao adicional', 'informação adicional', 'informacoes adicionais',
      'informações adicionais', 'detalhes', 'comentario', 'comentário',
      'instrucoes', 'instruções', 'delivery instructions', 'remarks'
    ],
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

        // Evita ambiguidades críticas como "parada" ser confundida
        // com "parada física". Para esses campos, só aceitamos nome exato.
        if (entry.key == 'stop' || entry.key == 'physical') {
          return false;
        }

        if (header.length < 5) return false;
        return normalizedAliases.any(
          (alias) =>
              alias.length >= 5 &&
              (header.contains(alias) || alias.contains(header)),
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
          notes: _nullIfEmpty(read('notes')),
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
    final coordinateGroups = <String, ({double lat, double lng})>{};

    for (final package in packages) {
      String groupKey;

      if (package.physicalStopId?.trim().toLowerCase().isNotEmpty == true) {
        groupKey = 'id:${package.physicalStopId!.trim().toLowerCase()}';
      } else if (package.latitude != null && package.longitude != null) {
        final lat = package.latitude!;
        final lng = package.longitude!;

        String? matchingKey;

        for (final entry in coordinateGroups.entries) {
          if (_distanceMeters(
                lat,
                lng,
                entry.value.lat,
                entry.value.lng,
              ) <=
              5) {
            matchingKey = entry.key;
            break;
          }
        }

        if (matchingKey != null) {
          groupKey = matchingKey;
        } else {
          groupKey = 'gps:${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';
          coordinateGroups[groupKey] = (lat: lat, lng: lng);
        }
      } else {
        groupKey =
            'addr:${_physicalAddressFallback(package.address, package.complement)}';
      }

      grouped.putIfAbsent(groupKey, () => []).add(package);
    }

    // Segunda consolidação: se o endereço físico for exatamente o mesmo
    // e não houver unidade/complemento forte diferente, junta os pacotes
    // mesmo que o romaneio tenha trazido IDs de parada distintos.
    final consolidated = <String, List<DeliveryPackage>>{};
    for (final entry in grouped.entries) {
      final groupPackages = entry.value;
      final first = groupPackages.first;
      final addressKey =
          _physicalAddressFallback(first.address, first.complement);
      consolidated
          .putIfAbsent('addrmerge:$addressKey', () => <DeliveryPackage>[])
          .addAll(groupPackages);
    }

    final stops = <PhysicalStop>[];
    var index = 1;

    for (final entry in consolidated.entries) {
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

  String _physicalAddressFallback(String address, String? complement) {
    final base = _normalizeAddressPart(address);
    final comp = _normalizeComplementPart(complement ?? '');

    if (comp.isEmpty) return base;

    final unitPattern = RegExp(
      r'\b(ap|bloco|torre|unidade|sala|cj|casa|lote|quadra|andar|pavimento|predio)\b',
      caseSensitive: false,
    );

    return unitPattern.hasMatch(comp) ? '$base|unit:$comp' : base;
  }

  String _normalizeComplementPart(String value) {
    var result = _normalizeAddressPart(value);

    result = result
        .replaceAll(RegExp(r'\b(apartamento|apto)\b'), 'ap')
        .replaceAll(RegExp(r'\bblk\b'), 'bloco')
        .replaceAll(RegExp(r'\btower\b'), 'torre')
        .replaceAll(RegExp(r'\bunit\b'), 'unidade')
        .replaceAll(RegExp(r'\bconjunto\b'), 'cj')
        .replaceAll(RegExp(r'\bqd\b'), 'quadra')
        .replaceAll(RegExp(r'\bedificio\b'), 'predio');

    final weakReferencePatterns = <RegExp>[
      RegExp(r'\b(fundos|frente|lateral)\b'),
      RegExp(r'\bportao\b.*'),
      RegExp(r'\b(proximo|perto)\b.*'),
      RegExp(r'\b(referencia|ref)\b.*'),
    ];

    for (final pattern in weakReferencePatterns) {
      result = result.replaceAll(pattern, ' ');
    }

    return result
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
  String _normalizeAddressPart(String value) {
    var result = value
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
        .replaceAll('ç', 'c');

    result = result.replaceAll(RegExp(r'\b\d{5}[- ]?\d{3}\b'), ' ');

    return result
        .replaceAll(RegExp(r'\b(r|r\.)\b'), 'rua')
        .replaceAll(RegExp(r'\b(av|av\.)\b'), 'avenida')
        .replaceAll(RegExp(r'\b(rod|rod\.)\b'), 'rodovia')
        .replaceAll(RegExp(r'\b(estr|estr\.)\b'), 'estrada')
        .replaceAll(RegExp(r'\b(al|al\.)\b'), 'alameda')
        .replaceAll(RegExp(r'\b(trav|trav\.)\b'), 'travessa')
        .replaceAll(RegExp(r'\bn[º°o]?\b'), ' ')
        .replaceAll(RegExp(r'\bnumero\b'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  double _distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371000.0;

    double radians(double degrees) => degrees * 3.141592653589793 / 180.0;

    final dLat = radians(lat2 - lat1);
    final dLon = radians(lon2 - lon1);

    final a =
        (math.sin(dLat / 2) * math.sin(dLat / 2)) +
        math.cos(radians(lat1)) *
            math.cos(radians(lat2)) *
            (math.sin(dLon / 2) * math.sin(dLon / 2));

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  String? _nullIfEmpty(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
),
      RegExp(r'\b(proximo|próximo|perto)\b.*

  String _normalizeAddressPart(String value) {
    var result = value
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
        .replaceAll('ç', 'c');

    result = result.replaceAll(RegExp(r'\b\d{5}[- ]?\d{3}\b'), ' ');

    return result
        .replaceAll(RegExp(r'\b(r|r\.)\b'), 'rua')
        .replaceAll(RegExp(r'\b(av|av\.)\b'), 'avenida')
        .replaceAll(RegExp(r'\b(rod|rod\.)\b'), 'rodovia')
        .replaceAll(RegExp(r'\b(estr|estr\.)\b'), 'estrada')
        .replaceAll(RegExp(r'\bn[º°o]?\b'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  double _distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371000.0;

    double radians(double degrees) => degrees * 3.141592653589793 / 180.0;

    final dLat = radians(lat2 - lat1);
    final dLon = radians(lon2 - lon1);

    final a =
        (math.sin(dLat / 2) * math.sin(dLat / 2)) +
        math.cos(radians(lat1)) *
            math.cos(radians(lat2)) *
            (math.sin(dLon / 2) * math.sin(dLon / 2));

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  String? _nullIfEmpty(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
),
      RegExp(r'\b(referencia|referência|ref)\b.*

  String _normalizeAddressPart(String value) {
    var result = value
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
        .replaceAll('ç', 'c');

    result = result.replaceAll(RegExp(r'\b\d{5}[- ]?\d{3}\b'), ' ');

    return result
        .replaceAll(RegExp(r'\b(r|r\.)\b'), 'rua')
        .replaceAll(RegExp(r'\b(av|av\.)\b'), 'avenida')
        .replaceAll(RegExp(r'\b(rod|rod\.)\b'), 'rodovia')
        .replaceAll(RegExp(r'\b(estr|estr\.)\b'), 'estrada')
        .replaceAll(RegExp(r'\bn[º°o]?\b'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  double _distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371000.0;

    double radians(double degrees) => degrees * 3.141592653589793 / 180.0;

    final dLat = radians(lat2 - lat1);
    final dLon = radians(lon2 - lon1);

    final a =
        (math.sin(dLat / 2) * math.sin(dLat / 2)) +
        math.cos(radians(lat1)) *
            math.cos(radians(lat2)) *
            (math.sin(dLon / 2) * math.sin(dLon / 2));

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  String? _nullIfEmpty(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
),
    ];

    for (final pattern in weakReferencePatterns) {
      result = result.replaceAll(pattern, ' ');
    }

    return result
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _normalizeAddressPart(String value) {
    var result = value
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
        .replaceAll('ç', 'c');

    result = result.replaceAll(RegExp(r'\b\d{5}[- ]?\d{3}\b'), ' ');

    return result
        .replaceAll(RegExp(r'\b(r|r\.)\b'), 'rua')
        .replaceAll(RegExp(r'\b(av|av\.)\b'), 'avenida')
        .replaceAll(RegExp(r'\b(rod|rod\.)\b'), 'rodovia')
        .replaceAll(RegExp(r'\b(estr|estr\.)\b'), 'estrada')
        .replaceAll(RegExp(r'\bn[º°o]?\b'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  double _distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371000.0;

    double radians(double degrees) => degrees * 3.141592653589793 / 180.0;

    final dLat = radians(lat2 - lat1);
    final dLon = radians(lon2 - lon1);

    final a =
        (math.sin(dLat / 2) * math.sin(dLat / 2)) +
        math.cos(radians(lat1)) *
            math.cos(radians(lat2)) *
            (math.sin(dLon / 2) * math.sin(dLon / 2));

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  String? _nullIfEmpty(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
