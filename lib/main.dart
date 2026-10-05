import 'package:flutter/material.dart';

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

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Felipe Route', style: TextStyle(fontWeight: FontWeight.w800)),
            Text('Sua rota de hoje', style: TextStyle(fontSize: 12)),
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
            const _RouteSummaryCard(),
            const SizedBox(height: 14),
            _PrimaryAction(
              icon: Icons.upload_file_rounded,
              title: 'Importar manifesto',
              subtitle: 'PDF, planilha ou arquivo da rota',
              onTap: () {},
            ),
            const SizedBox(height: 12),
            _PrimaryAction(
              icon: Icons.route_rounded,
              title: 'Continuar rota',
              subtitle: 'Ir direto para a próxima entrega',
              highlighted: true,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DeliveryScreen()),
                );
              },
            ),
            const SizedBox(height: 20),
            const Text(
              'Acesso rápido',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _QuickAction(
                    icon: Icons.list_alt_rounded,
                    label: 'Paradas',
                    onTap: () {},
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _QuickAction(
                    icon: Icons.map_outlined,
                    label: 'Mapa',
                    onTap: () {},
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _QuickAction(
                    icon: Icons.inventory_2_outlined,
                    label: 'Pacotes',
                    onTap: () {},
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Início'),
          NavigationDestination(icon: Icon(Icons.route_rounded), label: 'Rota'),
          NavigationDestination(icon: Icon(Icons.list_alt_rounded), label: 'Paradas'),
          NavigationDestination(icon: Icon(Icons.more_horiz_rounded), label: 'Mais'),
        ],
      ),
    );
  }
}

class _RouteSummaryCard extends StatelessWidget {
  const _RouteSummaryCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.local_shipping_rounded),
                SizedBox(width: 8),
                Text('Resumo da rota',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: const [
                Expanded(child: _Metric(value: '84', label: 'Paradas')),
                Expanded(child: _Metric(value: '126', label: 'Pacotes')),
                Expanded(child: _Metric(value: '0', label: 'Entregues')),
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
        Text(value,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool highlighted;
  final VoidCallback onTap;

  const _PrimaryAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      color: highlighted ? scheme.primaryContainer : Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor:
                    highlighted ? scheme.primary : scheme.surfaceContainerHighest,
                child: Icon(icon,
                    color: highlighted ? scheme.onPrimary : scheme.onSurface),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800)),
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

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Column(
            children: [
              Icon(icon, size: 28),
              const SizedBox(height: 7),
              Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class DeliveryScreen extends StatelessWidget {
  const DeliveryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Parada 11',
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text('11 / 84',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: const [
                  _NextStopCard(),
                  SizedBox(height: 12),
                  _PackageAlert(),
                  SizedBox(height: 12),
                  _GroupedStopsCard(),
                  SizedBox(height: 12),
                  _PackageListCard(),
                ],
              ),
            ),
            const _DeliveryBottomBar(),
          ],
        ),
      ),
    );
  }
}

class _NextStopCard extends StatelessWidget {
  const _NextStopCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('PRÓXIMA ENTREGA',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text(
              'Rua Exemplo, 123 - Centro',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.schedule_rounded, size: 20),
                const SizedBox(width: 5),
                const Text('3 min'),
                const SizedBox(width: 18),
                const Icon(Icons.straighten_rounded, size: 20),
                const SizedBox(width: 5),
                const Text('850 m'),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.navigation_rounded),
                  label: const Text('NAVEGAR'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PackageAlert extends StatelessWidget {
  const _PackageAlert();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFFFF4D6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Icon(Icons.warning_amber_rounded),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Atenção: há pacotes de outras numerações para entregar neste mesmo local.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupedStopsCard extends StatelessWidget {
  const _GroupedStopsCard();

  @override
  Widget build(BuildContext context) {
    const groups = [
      ('11', 8),
      ('12', 3),
      ('18', 2),
      ('11+1', 1),
      ('11+2', 1),
    ];

    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Expanded(
                  child: Text('15 pacotes neste local',
                      style:
                          TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                ),
                Icon(Icons.inventory_2_rounded),
              ],
            ),
            const SizedBox(height: 12),
            ...groups.map(
              (entry) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Text('Parada ${entry.$1}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Text('${entry.$2} pacote${entry.$2 == 1 ? '' : 's'}'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PackageListCard extends StatelessWidget {
  const _PackageListCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      child: ExpansionTile(
        title: const Text('Ver códigos dos pacotes',
            style: TextStyle(fontWeight: FontWeight.w800)),
        subtitle: const Text('15 pacotes esperados'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: const [
          ListTile(
            dense: true,
            leading: Icon(Icons.qr_code_2_rounded),
            title: Text('BR123456789'),
            trailing: Text('Parada 11'),
          ),
          ListTile(
            dense: true,
            leading: Icon(Icons.qr_code_2_rounded),
            title: Text('BR123456790'),
            trailing: Text('Parada 11+1'),
          ),
          ListTile(
            dense: true,
            leading: Icon(Icons.qr_code_2_rounded),
            title: Text('BR123456791'),
            trailing: Text('Parada 12'),
          ),
        ],
      ),
    );
  }
}

class _DeliveryBottomBar extends StatelessWidget {
  const _DeliveryBottomBar();

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 12,
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.report_problem_outlined),
                  label: const Text('PROBLEMA'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.check_circle_rounded),
                  label: const Text('ENTREGUE'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    textStyle: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
