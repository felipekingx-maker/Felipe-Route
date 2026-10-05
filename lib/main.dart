import 'package:flutter/material.dart';

import 'models/delivery_models.dart';
import 'screens/import_manifest_screen.dart';

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

class _HomeScreenState extends State<HomeScreen> {
  DeliveryRoute? _route;

  Future<void> _importManifest() async {
    final route = await Navigator.of(context).push<DeliveryRoute>(
      MaterialPageRoute(builder: (_) => const ImportManifestScreen()),
    );

    if (route != null && mounted) {
      setState(() => _route = route);
    }
  }

  void _continueRoute() {
    final route = _route;
    if (route == null || route.stops.isEmpty) {
      _importManifest();
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RouteScreen(route: route)),
    ).then((_) {
      if (mounted) setState(() {});
    });
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
          IconButton(
            tooltip: 'Configurações',
            onPressed: () {},
            icon: const Icon(Icons.settings_outlined),
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
              subtitle: 'CSV ou TXT no beta',
              onTap: _importManifest,
            ),
            const SizedBox(height: 12),
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
                child: ListTile(
                  leading: const Icon(Icons.route_rounded),
                  title: Text(
                    route.name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    '${route.stops.length} locais físicos • ${route.totalPackages} pacotes',
                  ),
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
                    value: '${route?.deliveredStops ?? 0}',
                    label: 'Entregues',
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

  const RouteScreen({super.key, required this.route});

  @override
  State<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends State<RouteScreen> {
  int _index = 0;

  PhysicalStop get _stop => widget.route.stops[_index];

  void _next() {
    if (_index < widget.route.stops.length - 1) {
      setState(() => _index++);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fim da rota.')),
      );
    }
  }

  void _markDelivered() {
    for (final package in _stop.packages) {
      package.status = DeliveryStatus.delivered;
    }
    setState(() {});
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
                            onPressed: () {},
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
                              subtitle: package.recipient == null
                                  ? null
                                  : Text(package.recipient!),
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
                          onPressed: _next,
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
