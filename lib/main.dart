import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'models/delivery_models.dart';
import 'screens/import_manifest_screen.dart';
import 'screens/package_counter_screen.dart';
import 'screens/route_planner_screen.dart';
import 'screens/route_map_screen.dart';
import 'services/update_service.dart';
import 'services/route_persistence_service.dart';
import 'services/route_tools.dart';

void main() {
  runApp(const FelipeRouteApp());
}

class FelipeRouteApp extends StatelessWidget {
  const FelipeRouteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Felipe Route',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1F6FEB),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF6F7F9),
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(18)),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  DeliveryRoute? _route;
  int _savedCurrentIndex = 0;
  bool _checkingUpdate = false;
  DateTime? _lastAutomaticUpdateCheck;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restoreSavedRoute();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUpdates();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;

    final lastCheck = _lastAutomaticUpdateCheck;
    final shouldCheck = lastCheck == null ||
        DateTime.now().difference(lastCheck) >= const Duration(minutes: 30);

    if (shouldCheck) {
      _checkUpdates();
    }
  }

  Future<void> _restoreSavedRoute() async {
    final saved = await RoutePersistenceService.loadRoute();
    if (!mounted || saved == null) return;

    setState(() {
      _route = saved.route;
      _savedCurrentIndex = saved.currentIndex;
    });
  }

  Future<void> _saveRoute({int? currentIndex}) async {
    final route = _route;
    if (route == null) return;

    final index = currentIndex ?? _savedCurrentIndex;
    _savedCurrentIndex = index;
    await RoutePersistenceService.saveRoute(
      route,
      currentIndex: index,
    );
  }

  Future<void> _checkUpdates({bool manual = false}) async {
    if (_checkingUpdate) return;
    _checkingUpdate = true;

    if (!manual) {
      _lastAutomaticUpdateCheck = DateTime.now();
    }

    final update = await UpdateService.checkForUpdate();
    _checkingUpdate = false;

    if (!mounted) return;

    if (update == null) {
      if (manual) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Você já está usando a versão mais recente.'),
          ),
        );
      }
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: !update.force,
      builder: (dialogContext) => PopScope(
        canPop: !update.force,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.system_update_rounded),
              SizedBox(width: 10),
              Expanded(
                child: Text('Nova versão disponível'),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Felipe Route ${update.version}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              if (update.notes != null && update.notes!.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(update.notes!),
              ],
              const SizedBox(height: 12),
              const Text(
                'Ao tocar em atualizar, o APK mais recente será aberto para download e instalação.',
              ),
            ],
          ),
          actions: [
            if (!update.force)
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('DEPOIS'),
              ),
            FilledButton.icon(
              onPressed: () async {
                await UpdateService.openUpdate(update);
                if (dialogContext.mounted && !update.force) {
                  Navigator.pop(dialogContext);
                }
              },
              icon: const Icon(Icons.download_rounded),
              label: const Text('ATUALIZAR AGORA'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _importManifest() async {
    final route = await Navigator.of(context).push<DeliveryRoute>(
      MaterialPageRoute(builder: (_) => const ImportManifestScreen()),
    );

    if (route == null || !mounted) return;

    final optimized = await _optimizeImportedRouteFromGps(route);

    if (!mounted) return;

    setState(() {
      _route = optimized ?? route;
      _savedCurrentIndex = 0;
    });

    await _saveRoute(currentIndex: 0);

    if (optimized == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Romaneio importado, mas não consegui definir a primeira parada pelo GPS. Ative a localização e toque em REOTIMIZAR.',
          ),
        ),
      );
    }
  }

  Future<DeliveryRoute?> _optimizeImportedRouteFromGps(
    DeliveryRoute route,
  ) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
        ),
      ).timeout(const Duration(seconds: 12));

      final optimizedStops = await RouteTools.optimizeByRoads(
        stops: route.stops,
        startLatitude: position.latitude,
        startLongitude: position.longitude,
        finalLatitude: route.finalDestinationLatitude,
        finalLongitude: route.finalDestinationLongitude,
      );

      if (optimizedStops == null) return null;

      route.stops
        ..clear()
        ..addAll(optimizedStops);

      route.totalRouteDistanceMeters = await RouteTools.calculateRoadDistance(
        stops: route.stops,
        startLatitude: position.latitude,
        startLongitude: position.longitude,
        finalLatitude: route.finalDestinationLatitude,
        finalLongitude: route.finalDestinationLongitude,
      );

      return route;
    } catch (_) {
      return null;
    }
  }

  void _continueRoute() {
    final route = _route;
    if (route == null || route.stops.isEmpty) {
      _importManifest();
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RouteScreen(
          route: route,
          initialIndex: _savedCurrentIndex,
          onProgressChanged: (index) => _saveRoute(currentIndex: index),
        ),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  void _createManualRoute() {
    final route = DeliveryRoute(name: 'Rota manual', stops: []);
    setState(() {
      _route = route;
      _savedCurrentIndex = 0;
    });
    _saveRoute(currentIndex: 0);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RoutePlannerScreen(route: route)),
    ).then((_) async {
      await _saveRoute();
      if (mounted) setState(() {});
    });
  }

  void _planRoute() {
    final route = _route;
    if (route == null) {
      _createManualRoute();
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RoutePlannerScreen(route: route)),
    ).then((_) async {
      await _saveRoute();
      if (mounted) setState(() {});
    });
  }

  Future<void> _reuseCurrentRoute() async {
    final route = _route;
    if (route == null || route.stops.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reutilizar esta rota?'),
        content: const Text(
          'O progresso anterior será zerado e a rota será reorganizada a partir da sua localização atual.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCELAR'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('REUTILIZAR'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Obtendo sua localização e reorganizando a rota...'),
      ),
    );

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ative o GPS para reutilizar e reorganizar a rota.'),
          ),
        );
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permissão de localização necessária para reutilizar a rota.'),
          ),
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
        ),
      ).timeout(const Duration(seconds: 12));

      final oldStatuses = <DeliveryPackage, DeliveryStatus>{};
      for (final stop in route.stops) {
        for (final package in stop.packages) {
          oldStatuses[package] = package.status;
          package.status = DeliveryStatus.pending;
        }
      }

      final optimizedStops = await RouteTools.optimizeByRoads(
        stops: route.stops,
        startLatitude: position.latitude,
        startLongitude: position.longitude,
        finalLatitude: route.finalDestinationLatitude,
        finalLongitude: route.finalDestinationLongitude,
      );

      if (optimizedStops == null) {
        for (final entry in oldStatuses.entries) {
          entry.key.status = entry.value;
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível reorganizar pelas ruas agora. A rota anterior foi mantida.',
            ),
          ),
        );
        return;
      }

      final meters = await RouteTools.calculateRoadDistance(
        stops: optimizedStops,
        startLatitude: position.latitude,
        startLongitude: position.longitude,
        finalLatitude: route.finalDestinationLatitude,
        finalLongitude: route.finalDestinationLongitude,
      );

      setState(() {
        route.stops
          ..clear()
          ..addAll(optimizedStops);
        route.totalRouteDistanceMeters = meters;
        _savedCurrentIndex = 0;
      });

      await RoutePersistenceService.saveRoute(
        route,
        currentIndex: 0,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Rota reutilizada e reorganizada a partir da sua localização atual.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível obter o GPS ou recalcular a rota agora.',
          ),
        ),
      );
    }
  }

  Future<void> _deleteCurrentRoute() async {
    final route = _route;
    if (route == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir rota atual?'),
        content: Text(
          'O romaneio "${route.name}" e todo o progresso salvo serão apagados deste aparelho.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCELAR'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('EXCLUIR'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await RoutePersistenceService.clear();
    if (!mounted) return;

    setState(() {
      _route = null;
      _savedCurrentIndex = 0;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Romaneio e progresso excluídos.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final route = _route;

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Felipe Route', style: TextStyle(fontWeight: FontWeight.w900)),
            Text('Entregas sem complicação', style: TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Menu',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) {
              if (value == 'counter') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const PackageCounterScreen(),
                  ),
                );
              }
              if (value == 'update') {
                _checkUpdates(manual: true);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'counter',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.qr_code_scanner_rounded),
                  title: Text('Contador de pacotes'),
                  subtitle: Text('QR e código de barras'),
                ),
              ),
              PopupMenuItem(
                value: 'update',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.system_update_rounded),
                  title: Text('Verificar atualizações'),
                  subtitle: Text('Buscar nova versão do Felipe Route'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _RouteSummaryCard(route: route),
            const SizedBox(height: 14),
            _BigAction(
              icon: Icons.upload_file_rounded,
              title: route == null ? 'Importar manifesto' : 'Trocar manifesto',
              subtitle: 'XLSX, XLS, CSV ou TXT',
              onTap: _importManifest,
            ),
            const SizedBox(height: 12),
            _BigAction(
              icon: Icons.add_location_alt_rounded,
              title: route == null ? 'Criar rota manual' : 'Editar e planejar rota',
              subtitle: route == null
                  ? 'Adicionar paradas sem manifesto'
                  : 'Adicionar, editar, reordenar e reotimizar',
              onTap: route == null ? _createManualRoute : _planRoute,
            ),
            const SizedBox(height: 12),
            if (route != null) ...[
              _BigAction(
                icon: Icons.map_rounded,
                title: 'Mapa da rota',
                subtitle: 'Ver paradas e sequência no mapa',
                onTap: () async {
                  final selectedIndex = await Navigator.of(context).push<int>(
                    MaterialPageRoute(
                      builder: (_) => RouteMapScreen(route: route),
                    ),
                  );

                  if (selectedIndex != null && context.mounted) {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => RouteScreen(
                          route: route,
                          initialIndex: selectedIndex,
                          onProgressChanged: (index) =>
                              _saveRoute(currentIndex: index),
                        ),
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 12),
            ],
            _BigAction(
              icon: Icons.navigation_rounded,
              title: route == null ? 'Começar rota' : 'Continuar rota',
              subtitle: route == null
                  ? 'Importe o manifesto para iniciar'
                  : 'Abrir a próxima entrega',
              highlighted: true,
              onTap: _continueRoute,
            ),
            if (route != null) ...[
              const SizedBox(height: 20),
              const Text(
                'Rota carregada',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Card(
                color: Colors.white,
                child: Column(
                  children: [
                    ListTile(
                      onTap: _planRoute,
                      leading: const Icon(Icons.route_rounded),
                      title: Text(
                        route.name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '${route.stops.length} locais físicos • '
                        '${route.totalPackages} pacotes • '
                        '${route.totalRouteDistanceMeters == null ? '-- km' : '${(route.totalRouteDistanceMeters! / 1000).toStringAsFixed((route.totalRouteDistanceMeters! / 1000) < 10 ? 1 : 0)} km'} • '
                        '${route.stopDurationMinutes} min/parada',
                      ),
                      trailing: const Icon(Icons.edit_road_rounded),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      onTap: _reuseCurrentRoute,
                      leading: const Icon(Icons.restart_alt_rounded),
                      title: const Text(
                        'Reutilizar rota',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: const Text(
                        'Zerar progresso e reorganizar pelo GPS atual',
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      onTap: _deleteCurrentRoute,
                      leading: const Icon(Icons.delete_outline_rounded),
                      title: const Text(
                        'Excluir romaneio/rota',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: const Text(
                        'Apagar esta rota e o progresso salvo',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RouteSummaryCard extends StatelessWidget {
  final DeliveryRoute? route;

  const _RouteSummaryCard({required this.route});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.local_shipping_rounded),
                SizedBox(width: 8),
                Text(
                  'Resumo da rota',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    value: '${route?.stops.length ?? 0}',
                    label: 'Locais',
                  ),
                ),
                Expanded(
                  child: _Metric(
                    value: '${route?.totalPackages ?? 0}',
                    label: 'Pacotes',
                  ),
                ),
                Expanded(
                  child: _Metric(
                    value: '${route?.deliveredPackages ?? 0}',
                    label: 'Pacotes entregues',
                  ),
                ),
              ],
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
          style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
        ),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class _BigAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool highlighted;
  final VoidCallback onTap;

  const _BigAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      color: highlighted ? colors.primaryContainer : Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor:
                    highlighted ? colors.primary : colors.surfaceContainerHighest,
                child: Icon(
                  icon,
                  color: highlighted ? colors.onPrimary : colors.onSurface,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(subtitle),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class RouteScreen extends StatefulWidget {
  final DeliveryRoute route;
  final int initialIndex;
  final ValueChanged<int>? onProgressChanged;

  const RouteScreen({
    super.key,
    required this.route,
    this.initialIndex = 0,
    this.onProgressChanged,
  });

  @override
  State<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends State<RouteScreen> {
  late int _index;

  @override
  void initState() {
    super.initState();
    final maxIndex = widget.route.stops.isEmpty ? 0 : widget.route.stops.length - 1;
    _index = widget.initialIndex.clamp(0, maxIndex);
    RoutePersistenceService.saveRoute(
      widget.route,
      currentIndex: _index,
    );
  }

  PhysicalStop get _stop => widget.route.stops[_index];

  void _next() {
    if (_index < widget.route.stops.length - 1) {
      setState(() => _index++);
      _persistProgress();
    } else {
      _persistProgress();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fim da rota.')),
      );
    }
  }

  void _persistProgress() {
    RoutePersistenceService.saveRoute(
      widget.route,
      currentIndex: _index,
    );
    widget.onProgressChanged?.call(_index);
  }

  void _markDelivered() {
    for (final package in _stop.packages) {
      package.status = DeliveryStatus.delivered;
    }
    setState(() {});
    _persistProgress();
    _next();
  }

  void _markProblem() {
    for (final package in _stop.packages) {
      package.status = DeliveryStatus.problem;
    }
    setState(() {});
    _persistProgress();
    _next();
  }

  @override
  Widget build(BuildContext context) {
    final stop = _stop;
    final groups = stop.packagesByStop;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Entrega ${_index + 1}',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'Mapa',
            onPressed: () async {
              final selectedIndex = await Navigator.of(context).push<int>(
                MaterialPageRoute(
                  builder: (_) => RouteMapScreen(
                    route: widget.route,
                    currentIndex: _index,
                  ),
                ),
              );

              if (selectedIndex != null && mounted) {
                setState(() => _index = selectedIndex);
                _persistProgress();
              }
            },
            icon: const Icon(Icons.map_rounded),
          ),
          IconButton(
            tooltip: 'Editar rota',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => RoutePlannerScreen(route: widget.route),
                ),
              ).then((_) {
                if (mounted) {
                  setState(() {
                    if (widget.route.stops.isNotEmpty && _index >= widget.route.stops.length) {
                      _index = widget.route.stops.length - 1;
                    }
                  });
                }
              });
            },
            icon: const Icon(Icons.edit_road_rounded),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              child: Text(
                '${_index + 1} / ${widget.route.stops.length}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                children: [
                  Card(
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ENDEREÇO',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            stop.address,
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (stop.complement != null) ...[
                            const SizedBox(height: 4),
                            Text(stop.complement!),
                          ],
                          const SizedBox(height: 14),
                          FilledButton.icon(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => RouteMapScreen(
                                    route: widget.route,
                                    currentIndex: _index,
                                    navigationTargetIndex: _index,
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.navigation_rounded),
                            label: const Text('NAVEGAR'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (stop.hasGroupedStops) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: const Color(0xFFFFF4D6),
                      child: const Padding(
                        padding: EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Há pacotes de várias paradas para entregar neste mesmo local.',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Card(
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${stop.totalPackages} pacotes neste local',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ...groups.entries.map(
                            (entry) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  Text(
                                    'Parada ${entry.key}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '${entry.value} pacote${entry.value == 1 ? '' : 's'}',
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    color: Colors.white,
                    child: ExpansionTile(
                      title: const Text(
                        'Códigos dos pacotes',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      subtitle: Text('${stop.totalPackages} códigos'),
                      children: stop.packages
                          .map(
                            (package) => ListTile(
                              leading: const Icon(Icons.qr_code_2_rounded),
                              title: Text(package.code),
                              subtitle: (package.recipient == null &&
                                      package.notes == null)
                                  ? null
                                  : Text(
                                      [
                                        if (package.recipient != null)
                                          'Destinatário: ${package.recipient}',
                                        if (package.notes != null)
                                          'Obs.: ${package.notes}',
                                      ].join('\n'),
                                    ),
                              trailing: Text('P. ${package.stopLabel}'),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
            Material(
              elevation: 10,
              color: Colors.white,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _markProblem,
                          icon: const Icon(Icons.report_problem_outlined),
                          label: const Text('PROBLEMA'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: _markDelivered,
                          icon: const Icon(Icons.check_circle_rounded),
                          label: const Text('ENTREGUE'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
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
