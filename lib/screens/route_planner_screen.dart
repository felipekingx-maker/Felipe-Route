
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../models/delivery_models.dart';
import '../services/route_tools.dart';
import '../services/route_persistence_service.dart';
import 'route_map_screen.dart';

class RoutePlannerScreen extends StatefulWidget {
  final DeliveryRoute route;
  const RoutePlannerScreen({super.key, required this.route});

  @override
  State<RoutePlannerScreen> createState() => _RoutePlannerScreenState();
}

class _RoutePlannerScreenState extends State<RoutePlannerScreen> {
  DeliveryRoute get route => widget.route;
  bool _optimizing = false;

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
      RoutePersistenceService.saveRoute(route);
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
    if (stop != null) {
      setState(() => route.stops.add(stop));
      RoutePersistenceService.saveRoute(route);
    }
  }

  Future<void> _edit(int index) async {
    final stop = await _editDialog(route.stops[index]);
    if (stop != null) {
      setState(() => route.stops[index] = stop);
      RoutePersistenceService.saveRoute(route);
    }
  }

  void _remove(int index) {
    final removed = route.stops.removeAt(index);
    setState(() {});
    RoutePersistenceService.saveRoute(route);
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
    RoutePersistenceService.saveRoute(route);
  }

  void _toggleDelivered(int index) {
    final stop = route.stops[index];
    final markDelivered = !stop.completed;

    for (final package in stop.packages) {
      package.status =
          markDelivered ? DeliveryStatus.delivered : DeliveryStatus.pending;
    }

    setState(() {});
    RoutePersistenceService.saveRoute(route);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          markDelivered ? 'Parada marcada como entregue.' : 'Entrega desfeita.',
        ),
      ),
    );
  }

  Future<void> _manualOptimize() async {
    final completed = route.stops.where((stop) => stop.completed).toList();
    final pending = route.stops.where((stop) => !stop.completed).toList();

    if (pending.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não há paradas pendentes suficientes para reordenar.'),
        ),
      );
      return;
    }

    final working = List<PhysicalStop>.from(pending);

    final reordered = await showModalBottomSheet<List<PhysicalStop>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              top: false,
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.82,
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Column(
                        children: [
                          Text(
                            'Otimização manual',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Arraste as paradas para definir a ordem. A primeira da lista será a próxima entrega.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ReorderableListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: working.length,
                        onReorder: (oldIndex, newIndex) {
                          setSheetState(() {
                            if (newIndex > oldIndex) newIndex--;
                            final item = working.removeAt(oldIndex);
                            working.insert(newIndex, item);
                          });
                        },
                        itemBuilder: (context, index) {
                          final stop = working[index];
                          return Card(
                            key: ValueKey(stop.id),
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              leading: CircleAvatar(
                                child: Text('${index + 1}'),
                              ),
                              title: Text(
                                stop.address,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Text(
                                '${stop.totalPackages} pacote${stop.totalPackages == 1 ? '' : 's'} • ${stop.packagesByStop.keys.map((e) => 'P. $e').join(', ')}',
                              ),
                              trailing: SizedBox(
                                width: 116,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    IconButton(
                                      tooltip: 'Subir',
                                      onPressed: index == 0
                                          ? null
                                          : () {
                                              setSheetState(() {
                                                final item =
                                                    working.removeAt(index);
                                                working.insert(index - 1, item);
                                              });
                                            },
                                      icon: const Icon(
                                        Icons.keyboard_arrow_up_rounded,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Descer',
                                      onPressed: index == working.length - 1
                                          ? null
                                          : () {
                                              setSheetState(() {
                                                final item =
                                                    working.removeAt(index);
                                                working.insert(index + 1, item);
                                              });
                                            },
                                      icon: const Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                      ),
                                    ),
                                    ReorderableDragStartListener(
                                      index: index,
                                      child: const Icon(
                                        Icons.drag_handle_rounded,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(sheetContext),
                              child: const Text('CANCELAR'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed: () => Navigator.pop(
                                sheetContext,
                                List<PhysicalStop>.from(working),
                              ),
                              child: const Text('SALVAR ORDEM'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (reordered == null || !mounted) return;

    setState(() {
      route.stops
        ..clear()
        ..addAll(completed)
        ..addAll(reordered);
    });

    await RoutePersistenceService.saveRoute(route);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ordem manual salva. O mapa seguirá essa sequência.'),
      ),
    );
  }
  Future<void> _optimize() async {
    if (_optimizing) return;

    if (!RouteTools.canOptimize(route.stops)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A reotimização precisa de coordenadas em pelo menos duas paradas.',
          ),
        ),
      );
      return;
    }

    setState(() => _optimizing = true);

    double? startLat;
    double? startLng;

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }

        if (permission == LocationPermission.always ||
            permission == LocationPermission.whileInUse) {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.bestForNavigation,
            ),
          ).timeout(const Duration(seconds: 10));

          startLat = position.latitude;
          startLng = position.longitude;
        }
      }
    } catch (_) {
      // A rota automática precisa partir da posição real do entregador.
    }

    if (startLat == null || startLng == null) {
      if (!mounted) return;
      setState(() => _optimizing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não consegui obter seu GPS. Ative a localização para definir a primeira parada mais próxima.',
          ),
        ),
      );
      return;
    }

    final optimized = await RouteTools.optimizeByRoads(
      stops: route.stops,
      startLatitude: startLat,
      startLongitude: startLng,
      finalLatitude: route.finalDestinationLatitude,
      finalLongitude: route.finalDestinationLongitude,
    );

    if (!mounted) return;

    setState(() => _optimizing = false);

    if (optimized == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível calcular a rota pelas ruas agora. A ordem atual foi mantida.',
          ),
        ),
      );
      return;
    }

    setState(() {
      route.stops
        ..clear()
        ..addAll(optimized);
    });

    await RoutePersistenceService.saveRoute(route);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Rota otimizada pelo tempo de carro e sentido das ruas.',
        ),
      ),
    );
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
          IconButton(
            tooltip: 'Mapa',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => RouteMapScreen(route: route),
                ),
              );
            },
            icon: const Icon(Icons.map_rounded),
          ),
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
                          onPressed: _optimizing ? null : _optimize,
                          icon: _optimizing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.auto_awesome_rounded),
                          label: Text(
                            _optimizing ? 'CALCULANDO...' : 'REOTIMIZAR',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _manualOptimize,
                          icon: const Icon(Icons.reorder_rounded),
                          label: const Text('ORDEM MANUAL'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _settings,
                    icon: const Icon(Icons.schedule_rounded),
                    label: Text(
                      '${route.stopDurationMinutes} min/parada • Configurações',
                    ),
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
                        RoutePersistenceService.saveRoute(route);
                      },
                      itemBuilder: (context, index) {
                        final stop = route.stops[index];
                        return Card(
                          key: ValueKey(stop.id),
                          color: Colors.white,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: CircleAvatar(child: Text((index + 1).toString())),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    stop.address,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      decoration: stop.completed
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                  ),
                                ),
                                if (stop.completed)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 6),
                                    child: Icon(
                                      Icons.check_circle_rounded,
                                      size: 20,
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Text(
                              (stop.completed ? 'ENTREGUE • ' : '') +
                                  stop.totalPackages.toString() +
                                  (stop.totalPackages == 1 ? ' pacote • ' : ' pacotes • ') +
                                  stop.packagesByStop.keys.map((e) => 'P. ' + e).join(', '),
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'edit') _edit(index);
                                if (value == 'delivered') _toggleDelivered(index);
                                if (value == 'return') _returnLater(index);
                                if (value == 'remove') _remove(index);
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Editar'),
                                ),
                                PopupMenuItem(
                                  value: 'delivered',
                                  child: Text(
                                    stop.completed
                                        ? 'Desfazer entrega'
                                        : 'Marcar como entregue',
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'return',
                                  child: Text('Deixar para retorno'),
                                ),
                                const PopupMenuItem(
                                  value: 'remove',
                                  child: Text('Remover'),
                                ),
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
