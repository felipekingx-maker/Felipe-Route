import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class PackageCounterScreen extends StatefulWidget {
  const PackageCounterScreen({super.key});

  @override
  State<PackageCounterScreen> createState() => _PackageCounterScreenState();
}

class _PackageCounterScreenState extends State<PackageCounterScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [
      BarcodeFormat.qrCode,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.dataMatrix,
    ],
  );

  final Set<String> _uniqueCodes = <String>{};
  String? _lastCode;
  int _duplicateReads = 0;

  void _onDetect(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue?.trim();
      if (code == null || code.isEmpty) continue;

      if (_uniqueCodes.add(code)) {
        setState(() => _lastCode = code);
      } else if (_lastCode != code) {
        setState(() {
          _lastCode = code;
          _duplicateReads++;
        });
      }
    }
  }

  Future<void> _resetCounter() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Zerar contador?'),
        content: const Text(
          'Todos os códigos lidos nesta contagem serão apagados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ZERAR'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() {
        _uniqueCodes.clear();
        _lastCode = null;
        _duplicateReads = 0;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Contador de pacotes',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'Lanterna',
            onPressed: _controller.toggleTorch,
            icon: const Icon(Icons.flashlight_on_outlined),
          ),
          IconButton(
            tooltip: 'Zerar contagem',
            onPressed: _uniqueCodes.isEmpty ? null : _resetCounter,
            icon: const Icon(Icons.restart_alt_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Card(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      Expanded(
                        child: _Metric(
                          value: '${_uniqueCodes.length}',
                          label: 'Pacotes únicos',
                        ),
                      ),
                      Expanded(
                        child: _Metric(
                          value: '$_duplicateReads',
                          label: 'Duplicados',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MobileScanner(
                        controller: _controller,
                        onDetect: _onDetect,
                      ),
                      IgnorePointer(
                        child: Center(
                          child: Container(
                            width: 260,
                            height: 180,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Colors.white,
                                width: 3,
                              ),
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.qr_code_scanner_rounded, size: 30),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Última leitura',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _lastCode ?? 'Aponte a câmera para um QR ou código de barras',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
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
          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 3),
        Text(label, textAlign: TextAlign.center),
      ],
    );
  }
}
