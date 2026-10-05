import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/delivery_models.dart';
import '../services/manifest_parser.dart';
import '../services/xlsx_manifest_parser.dart';

class ImportManifestScreen extends StatefulWidget {
  const ImportManifestScreen({super.key});

  @override
  State<ImportManifestScreen> createState() => _ImportManifestScreenState();
}

class _ImportManifestScreenState extends State<ImportManifestScreen> {
  final _parser = ManifestParser();
  final _xlsxParser = XlsxManifestParser();
  DeliveryRoute? _preview;
  String? _error;
  String? _fileName;
  bool _loading = false;

  Future<void> _pickManifest() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['csv', 'txt', 'xlsx', 'xls'],
      );

      if (file == null) return;

      final bytes = await file.readAsBytes();

      final lowerName = file.name.toLowerCase();
      final cleanName = file.name.replaceAll(
        RegExp(r'\.(csv|txt|xlsx|xls)

      setState(() {
        _preview = route;
        _fileName = file.name;
      });
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _loadExample() {
    const example = '''Parada;Pacote;Endereco;Destinatario;Complemento
11;BR000001;Rua Exemplo 100;Cliente A;Casa
11;BR000002;Rua Exemplo 100;Cliente A;Casa
11+1;BR000003;Rua Exemplo 100;Cliente A;Casa
12;BR000004;Rua Exemplo 100;Cliente A;Casa
18;BR000005;Rua Exemplo 100;Cliente A;Casa
19;BR000006;Rua Outra 250;Cliente B;Apto 12
''';

    setState(() {
      _preview = _parser.parseText(example, routeName: 'Rota de demonstração');
      _fileName = 'exemplo.csv';
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final route = _preview;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Importar manifesto',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.upload_file_rounded, size: 38),
                    const SizedBox(height: 10),
                    const Text(
                      'Selecione o manifesto',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Agora aceitamos XLSX/XLS (romaneio), CSV e TXT. O app tenta reconhecer Parada, Pacote/Código e Endereço automaticamente.',
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _loading ? null : _pickManifest,
                      icon: const Icon(Icons.folder_open_rounded),
                      label: Text(_loading ? 'LENDO...' : 'ESCOLHER ARQUIVO'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _loadExample,
                      child: const Text('Carregar exemplo para testar'),
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
            if (route != null) ...[
              const SizedBox(height: 16),
              Text(
                _fileName ?? route.name,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Card(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      Expanded(
                        child: _Metric(
                          value: '${route.stops.length}',
                          label: 'Locais físicos',
                        ),
                      ),
                      Expanded(
                        child: _Metric(
                          value: '${route.totalPackages}',
                          label: 'Pacotes',
                        ),
                      ),
                      Expanded(
                        child: _Metric(
                          value: '${route.stops.where((s) => s.hasGroupedStops).length}',
                          label: 'Agrupados',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ...route.stops.take(8).map(
                    (stop) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        color: Colors.white,
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text('${stop.totalPackages}'),
                          ),
                          title: Text(
                            stop.address,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            stop.packagesByStop.entries
                                .map((e) => '${e.key}: ${e.value}')
                                .join(' • '),
                          ),
                          trailing: stop.hasGroupedStops
                              ? const Icon(Icons.merge_type_rounded)
                              : null,
                        ),
                      ),
                    ),
                  ),
              if (route.stops.length > 8)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '+ ${route.stops.length - 8} locais não exibidos na prévia',
                    textAlign: TextAlign.center,
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(route),
                icon: const Icon(Icons.check_circle_rounded),
                label: const Text('USAR ESTA ROTA'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String value;
  final String label;

  const _Metric({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 3),
        Text(label, textAlign: TextAlign.center),
      ],
    );
  }
}
, caseSensitive: false),
        '',
      );

      final DeliveryRoute route;
      if (lowerName.endsWith('.xlsx') || lowerName.endsWith('.xls')) {
        route = _xlsxParser.parseBytes(bytes, routeName: cleanName);
      } else {
        final content = utf8.decode(bytes, allowMalformed: true);
        route = _parser.parseText(content, routeName: cleanName);
      }

      setState(() {
        _preview = route;
        _fileName = file.name;
      });
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _loadExample() {
    const example = '''Parada;Pacote;Endereco;Destinatario;Complemento
11;BR000001;Rua Exemplo 100;Cliente A;Casa
11;BR000002;Rua Exemplo 100;Cliente A;Casa
11+1;BR000003;Rua Exemplo 100;Cliente A;Casa
12;BR000004;Rua Exemplo 100;Cliente A;Casa
18;BR000005;Rua Exemplo 100;Cliente A;Casa
19;BR000006;Rua Outra 250;Cliente B;Apto 12
''';

    setState(() {
      _preview = _parser.parseText(example, routeName: 'Rota de demonstração');
      _fileName = 'exemplo.csv';
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final route = _preview;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Importar manifesto',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.upload_file_rounded, size: 38),
                    const SizedBox(height: 10),
                    const Text(
                      'Selecione o manifesto',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'No beta aceitamos CSV ou TXT. As colunas mínimas são Parada, Pacote/Código e Endereço.',
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _loading ? null : _pickManifest,
                      icon: const Icon(Icons.folder_open_rounded),
                      label: Text(_loading ? 'LENDO...' : 'ESCOLHER ARQUIVO'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _loadExample,
                      child: const Text('Carregar exemplo para testar'),
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
            if (route != null) ...[
              const SizedBox(height: 16),
              Text(
                _fileName ?? route.name,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Card(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      Expanded(
                        child: _Metric(
                          value: '${route.stops.length}',
                          label: 'Locais físicos',
                        ),
                      ),
                      Expanded(
                        child: _Metric(
                          value: '${route.totalPackages}',
                          label: 'Pacotes',
                        ),
                      ),
                      Expanded(
                        child: _Metric(
                          value: '${route.stops.where((s) => s.hasGroupedStops).length}',
                          label: 'Agrupados',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ...route.stops.take(8).map(
                    (stop) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        color: Colors.white,
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text('${stop.totalPackages}'),
                          ),
                          title: Text(
                            stop.address,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            stop.packagesByStop.entries
                                .map((e) => '${e.key}: ${e.value}')
                                .join(' • '),
                          ),
                          trailing: stop.hasGroupedStops
                              ? const Icon(Icons.merge_type_rounded)
                              : null,
                        ),
                      ),
                    ),
                  ),
              if (route.stops.length > 8)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '+ ${route.stops.length - 8} locais não exibidos na prévia',
                    textAlign: TextAlign.center,
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(route),
                icon: const Icon(Icons.check_circle_rounded),
                label: const Text('USAR ESTA ROTA'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String value;
  final String label;

  const _Metric({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 3),
        Text(label, textAlign: TextAlign.center),
      ],
    );
  }
}
