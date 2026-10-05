
import 'package:flutter/material.dart';

import '../models/delivery_models.dart';
import '../services/route_tools.dart';

class RoutePlannerScreen extends StatefulWidget {
  final DeliveryRoute route;
  const RoutePlannerScreen({super.key, required this.route});

  @override
  State<RoutePlannerScreen> createState() => _RoutePlannerScreenState();
}

class _RoutePlannerScreenState extends State<RoutePlannerScreen> {
  DeliveryRoute get route => widget.route;

  Future<void> _settings() async {
    final minutes = TextEditingController(text: route.stopDurationMinutes.toString());
    final destination = TextEditingController(text: route.finalDestinationAddress ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Configurações da rota'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: minutes,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Tempo médio em cada parada (min)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: destination,
                decoration: const InputDecoration(
                  labelText: 'Destino depois da última entrega',
                  hintText: 'Casa, hub ou outro endereço',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCELAR')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('SALVAR')),
        ],
      ),
    );

    if (ok == true) {
      setState(() {
        route.stopDurationMinutes =
            (int.tryParse(minutes.text.trim()) ?? 3).clamp(0, 120);
        final value = destination.text.trim();
        route.finalDestinationAddress = value.isEmpty ? null : value;
      });
    }
  }

  Future<PhysicalStop?> _editDialog([PhysicalStop? original]) async {
    final label = TextEditingController(
      text: original != null && original.packages.isNotEmpty
          ? original.packages.first.stopLabel
          : (route.stops.length + 1).toString(),
    );
    final address = TextEditingController(text: original?.address ?? '');
    final complement = TextEditingController(text: original?.complement ?? '');
    final quantity = TextEditingController(text: (original?.totalPackages ?? 1).toString());
    final latitude = TextEditingController(text: original?.latitude?.toString() ?? '');
    final longitude = TextEditingController(text: original?.longitude?.toString() ?? '');

    return showDialog<PhysicalStop>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(original == null ? 'Adicionar parada' : 'Editar parada'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: label, decoration: const InputDecoration(labelText: 'Parada (ex.: 11 ou 11+1)')),
              const SizedBox(height: 8),
              TextField(controller: address, decoration: const InputDecoration(labelText: 'Endereço')),
              const SizedBox(height: 8),
              TextField(controller: complement, decoration: const InputDecoration(labelText: 'Complemento')),
              const SizedBox(height: 8),
              TextField(
                controller: quantity,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantidade de pacotes'),
              ),
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Coordenadas (opcional)'),
                children: [
                  TextField(
                    controller: latitude,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Latitude'),
                  ),
                  TextField(
                    controller: longitude,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Longitude'),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
          FilledButton(
            onPressed: () {
              final stopLabel = label.text.trim();
              final addr = address.text.trim();
              final count = int.tryParse(quantity.text.trim()) ?? 1;
              if (stopLabel.isEmpty || addr.isEmpty || count < 1) return;

              final lat = double.tryParse(latitude.text.replaceAll(',', '.'));
              final lng = double.tryParse(longitude.text.replaceAll(',', '.'));
              final old = original?.packages ?? <DeliveryPackage>[];
              final list = <DeliveryPackage>[];

              for (var i = 0; i < count; i++) {
                final previous = i < old.length ? old[i] : null;
                list.add(
                  DeliveryPackage(
                    code: previous?.code ??
                        'MANUAL-' + DateTime.now().millisecondsSinceEpoch.toString() + '-' + i.toString(),
                    stopLabel: stopLabel,
                    address: addr,
                    recipient: previous?.recipient,
                    complement: complement.text.trim().isEmpty ? null : complement.text.trim(),
                    physicalStopId: original?.id,
                    latitude: lat,
                    longitude: lng,
                    status: previous?.status ?? DeliveryStatus.pending,
                  ),
                );
              }

              Navigator.pop(
                context,
                PhysicalStop(
                  id: original?.id ?? 'MANUAL-' + DateTime.now().millisecondsSinceEpoch.toString(),
                  address: addr,
                  complement: complement.text.trim().isEmpty ? null : complement.text.trim(),
                  latitude: lat,
                  longitude: lng,
                  packages: list,
                ),
              );
            },
            child: const Text('SALVAR'),
          ),
        ],
      ),
    );
  }

  Future<void> _add() async {
    final stop = await _editDialog();
    if (stop != null) setState(() => route.stops.add(stop));
  }

  Future<void> _edit(int index) async {
    final stop = await _editDialog(route.stops[index]);
    if (stop != null) setState(() => route.stops[index] = stop);
  }

  void _remove(int index) {
    final removed = route.stops.removeAt(index);
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Parada removida: ' + removed.address),
        action: SnackBarAction(
          label: 'DESFAZER',
          onPressed: () => setState(() => route.stops.insert(index, removed)),
        ),
      ),
    );
  }

  void _returnLater(int index) {
    setState(() {
      final item = route.stops.removeAt(index);
      route.stops.add(item);
    });
  }

  void _optimize() {
    if (!RouteTools.canOptimize(route.stops)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A reotimização automática precisa de coordenadas em pelo menos duas paradas. Por enquanto você pode reordenar arrastando.',
          ),
        ),
      );
      return;
    }

    final optimized = RouteTools.optimize(
      stops: route.stops,
      finalLatitude: route.finalDestinationLatitude,
      finalLongitude: route.finalDestinationLongitude,
    );

    setState(() {
      route.stops
        ..clear()
        ..addAll(optimized);
    });
  }

  String _timeText() {
    final d = route.estimatedServiceTime;
    if (d.inHours == 0) return d.inMinutes.toString() + ' min';
    return d.inHours.toString() + 'h ' + d.inMinutes.remainder(60).toString().padLeft(2, '0');
  }

  @override
  Widget build(BuildContext context) {
    final duplicates = RouteTools.potentialDuplicateCount(route.stops);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Planejar rota', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(onPressed: _settings, icon: const Icon(Icons.tune_rounded), tooltip: 'Configurações'),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add_location_alt_rounded),
        label: const Text('PARADA'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(
                children: [
                  Card(
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(child: _Metric(value: route.stops.length.toString(), label: 'Paradas')),
                          Expanded(child: _Metric(value: route.totalPackages.toString(), label: 'Pacotes')),
                          Expanded(child: _Metric(value: _timeText(), label: 'Tempo parado')),
                        ],
                      ),
                    ),
                  ),
                  if (duplicates > 0) ...[
                    const SizedBox(height: 8),
                    Card(
                      color: const Color(0xFFFFF4D6),
                      child: ListTile(
                        leading: const Icon(Icons.merge_type_rounded),
                        title: Text(duplicates.toString() + ' possível(is) parada(s) duplicada(s)'),
                        subtitle: const Text('Revise endereços iguais antes de sair.'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _optimize,
                          icon: const Icon(Icons.auto_awesome_rounded),
                          label: const Text('REOTIMIZAR'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _settings,
                          icon: const Icon(Icons.schedule_rounded),
                          label: Text(route.stopDurationMinutes.toString() + ' min/parada'),
                        ),
                      ),
                    ],
                  ),
                  if (route.finalDestinationAddress != null) ...[
                    const SizedBox(height: 8),
                    Card(
                      color: Colors.white,
                      child: ListTile(
                        leading: const Icon(Icons.flag_rounded),
                        title: const Text('Depois da rota'),
                        subtitle: Text(route.finalDestinationAddress!),
                        trailing: IconButton(onPressed: _settings, icon: const Icon(Icons.edit_outlined)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: route.stops.isEmpty
                  ? const Center(
                      child: Text(
                        'Nenhuma parada.\nUse + PARADA para criar uma rota manual.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                      itemCount: route.stops.length,
                      onReorder: (oldIndex, newIndex) {
                        setState(() {
                          if (newIndex > oldIndex) newIndex--;
                          final item = route.stops.removeAt(oldIndex);
                          route.stops.insert(newIndex, item);
                        });
                      },
                      itemBuilder: (context, index) {
                        final stop = route.stops[index];
                        return Card(
                          key: ValueKey(stop.id),
                          color: Colors.white,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: CircleAvatar(child: Text((index + 1).toString())),
                            title: Text(stop.address, style: const TextStyle(fontWeight: FontWeight.w800)),
                            subtitle: Text(
                              stop.totalPackages.toString() +
                                  (stop.totalPackages == 1 ? ' pacote • ' : ' pacotes • ') +
                                  stop.packagesByStop.keys.map((e) => 'P. ' + e).join(', '),
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'edit') _edit(index);
                                if (value == 'return') _returnLater(index);
                                if (value == 'remove') _remove(index);
                              },
                              itemBuilder: (context) => const [
                                PopupMenuItem(value: 'edit', child: Text('Editar')),
                                PopupMenuItem(value: 'return', child: Text('Deixar para retorno')),
                                PopupMenuItem(value: 'remove', child: Text('Remover')),
                              ],
                            ),
                          ),
                        );
                      },
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
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
        Text(label, textAlign: TextAlign.center),
      ],
    );
  }
}
