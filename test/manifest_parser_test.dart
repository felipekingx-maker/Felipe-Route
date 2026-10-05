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

  test('preserva unidade relevante sem GPS e ignora referencia fraca', () {
    const manifest = '''Parada;Pacote;Endereco;Complemento
21;A1;Rua Luiz Izzo 779;Casa 1
22;A2;Rua Luiz Izzo, 779;Fundos
23;A3;Rua Luiz Izzo 779;Portão azul
''';

    final route = ManifestParser().parseText(manifest);

    expect(route.stops.length, 2);

    final casa = route.stops.firstWhere(
      (stop) => stop.packages.any((p) => p.stopLabel == '21'),
    );
    expect(casa.totalPackages, 1);

    final referencias = route.stops.firstWhere(
      (stop) => stop.packages.any((p) => p.stopLabel == '22'),
    );
    expect(referencias.totalPackages, 2);
    expect(referencias.packagesByStop.keys, containsAll(['22', '23']));
  });

  test('GPS igual em até 5m agrupa mesmo com casas diferentes', () {
    const manifest = '''Parada;Pacote;Endereco;Complemento;Latitude;Longitude
31;A1;Rua Exemplo 500;Casa 1;-23.000000;-46.000000
32;A2;Rua Exemplo 500;Casa 50;-23.000020;-46.000010
''';

    final route = ManifestParser().parseText(manifest);

    expect(route.stops.length, 1);
    expect(route.stops.first.totalPackages, 2);
    expect(route.stops.first.packagesByStop.keys, containsAll(['31', '32']));
  });

  test('GPS acima de 5m mantém parada separada', () {
    const manifest = '''Parada;Pacote;Endereco;Complemento;Latitude;Longitude
41;A1;Rua Exemplo 900;Casa 1;-23.000000;-46.000000
42;A2;Rua Exemplo 900;Casa 2;-23.000100;-46.000000
''';

    final route = ManifestParser().parseText(manifest);

    expect(route.stops.length, 2);
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
