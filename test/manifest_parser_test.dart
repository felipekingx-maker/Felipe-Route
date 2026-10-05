import 'package:flutter_test/flutter_test.dart';
import 'package:felipe_route/services/manifest_parser.dart';

void main() {
  test('agrupa paradas diferentes no mesmo local físico', () {
    const manifest = '''Parada;Pacote;Endereco;Complemento
11;A1;Rua Exemplo 100;Casa
11;A2;Rua Exemplo 100;Casa
11+1;A3;Rua Exemplo 100;Casa
12;A4;Rua Exemplo 100;Casa
18;A5;Rua Exemplo 100;Casa
19;B1;Rua Outra 250;Apto 12
''';

    final route = ManifestParser().parseText(manifest);

    expect(route.stops.length, 2);
    expect(route.totalPackages, 6);

    final first = route.stops.first;
    expect(first.totalPackages, 5);
    expect(first.packagesByStop['11'], 2);
    expect(first.packagesByStop['11+1'], 1);
    expect(first.packagesByStop['12'], 1);
    expect(first.packagesByStop['18'], 1);
    expect(first.hasGroupedStops, isTrue);
  });

  test('mantém parada única quando endereço é diferente', () {
    const manifest = '''Parada,Pacote,Endereco
1,A1,Rua Um 10
2,A2,Rua Dois 20
''';

    final route = ManifestParser().parseText(manifest);

    expect(route.stops.length, 2);
    expect(route.stops.first.hasGroupedStops, isFalse);
  });
}
