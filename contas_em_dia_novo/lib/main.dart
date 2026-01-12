import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:flutter/services.dart';

import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_native_timezone/flutter_native_timezone.dart';

final RouteObserver<ModalRoute<void>> routeObserver =
RouteObserver<ModalRoute<void>>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseHelper.instance.database;

  tz.initializeTimeZones();
  final String timeZoneName = await FlutterNativeTimezone.getLocalTimezone();
  tz.setLocalLocation(tz.getLocation(timeZoneName));

  await NotificationHelper.instance.init();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Contas em Dia',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.green,
      ),
      navigatorObservers: [routeObserver],
      home: const MainPage(),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({Key? key}) : super(key: key);

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _index = 0;

  final _pages =  [
    HomePage(),
    FilterPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_index],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.filter_list),
            label: 'Filtrar',
          ),
        ],
      ),
    );
  }
}


class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with RouteAware {

  // ✅ 1. FICA AQUI (logo abaixo da classe)
  Widget _verTodasPagasButton(BuildContext context) {
    return Center(
      child: TextButton.icon(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const FilterPage(
                initialStatus: 'Pagas',
              ),
            ),
          );
        },
        icon: const Icon(
          Icons.history,
          size: 20,
          color: Colors.white,
        ),
        label: const Text(
          'Ver todas as contas pagas',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  List<Billing> _items = [];
  String _filter = 'Todas';

  DateTime _normalize(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void didPopNext() {
    // Chamado quando volta da EditPage
    _reload();
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }


  Future<void> _reload() async {
    final all = await DatabaseHelper.instance.getAll();
    setState(() => _items = all);
  }

  String _formatMoney(double v) =>
      NumberFormat.simpleCurrency(locale: 'pt_BR').format(v);

  Widget _buildCard(
      String title,
      List<Billing> bills,
      Color color, {
        Widget? footer,
      }) {
    if (bills.isEmpty) return const SizedBox.shrink();

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: color.withOpacity(0.85),
      margin: const EdgeInsets.all(10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            const SizedBox(height: 8),
            ...bills.map((b) => ListTile(
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      b.name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      DateFormat('dd/MM').format(b.dueDate),
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              subtitle: Text(
                b.amount > 0
                    ? formatMoney(b.amount)
                    : 'Valor não informado',
                style: const TextStyle(color: Colors.white70),
              ),
              leading: Checkbox(
                value: b.paid == 1,
                onChanged: (v) async {
                  b.paid = v! ? 1 : 0;
                  await DatabaseHelper.instance.update(b);
                  await _reload();
                },
              ),
              trailing: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onSelected: (value) async {
                  if (value == 'editar') {
                    final result = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EditPage(billing: b),
                      ),
                    );
                    if (result == true) await _reload();
                  }

                  if (value == 'excluir') {
                    await DatabaseHelper.instance.delete(b.id!);
                    await _reload();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'editar',
                    child: Text('Editar'),
                  ),
                  PopupMenuItem(
                    value: 'excluir',
                    child: Text('Excluir'),
                  ),
                ],
              ),

            )),
            if (footer != null) ...[
              const SizedBox(height: 8),
              footer,
            ]
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = _normalize(DateTime.now());

    final atrasadas = _items.where((b) =>
    b.paid == 0 && _normalize(b.dueDate).isBefore(today)).toList();

    final proximos5 = _items.where((b) {
      final diff =
          _normalize(b.dueDate).difference(today).inDays;
      return b.paid == 0 && diff >= 0 && diff <= 5;
    }).toList();

    final futuras = _items.where((b) {
      final diff =
          _normalize(b.dueDate).difference(today).inDays;
      return b.paid == 0 && diff > 5;
    }).toList();

    final pagas = _items
        .where((b) => b.paid == 1)
        .toList()
      ..sort((a, b) => b.dueDate.compareTo(a.dueDate));

    const limitePagas = 3;
    final pagasLimitadas = pagas.take(limitePagas).toList();


    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.check_circle_outline,
                color: Colors.green,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Contas em Dia',
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.4,
                  ),
                ),
                Text(
                  'Organize seus pagamentos',
                  style: TextStyle(
                    color: Colors.black54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),

      // appBar: AppBar(
      //   title: const Text('Contas em Dia'),
      //   actions: [
      //     PopupMenuButton<String>(
      //       onSelected: (v) {
      //         setState(() => _filter = v);
      //       },
      //       itemBuilder: (_) => ['Todas', 'Pagas', 'Pendentes']
      //           .map((e) =>
      //           PopupMenuItem(value: e, child: Text(e)))
      //           .toList(),
      //     ),
      //   ],
      // ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            if (_filter != 'Pagas')
              _buildCard('⚠️ Contas atrasadas', atrasadas, Colors.red),
            if (_filter != 'Pagas')
              _buildCard('⏰ Próximos 5 dias', proximos5, Colors.orange),
            if (_filter != 'Pagas')
              _buildCard('📅 Contas futuras', futuras, Colors.blue),
            if (_filter != 'Pendentes' && pagas.length > 1)
              _buildCard(
                '✅ Contas pagas',
                pagasLimitadas,
                Colors.green,
                footer: _verTodasPagasButton(context),
              ),
            //_buildCard('✅ Contas pagas recentes', pagasLimitadas, Colors.green),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Nova conta'),
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => EditPage()),
          );
          if (result == true) await _reload();
        },
      ),
    );
  }
}

/* ===================== EDIT PAGE ===================== */

class EditPage extends StatefulWidget {
  final Billing? billing;
  const EditPage({Key? key, this.billing}) : super(key: key);

  @override
  _EditPageState createState() => _EditPageState();
}

class _EditPageState extends State<EditPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();

  DateTime _due = DateTime.now();
  bool _recurring = false;

  @override
  void initState() {
    super.initState();
    if (widget.billing != null) {
      _nameCtrl.text = widget.billing!.name;
      _amountCtrl.text =
      widget.billing!.amount > 0 ? widget.billing!.amount.toStringAsFixed(2) : '';
      _due = widget.billing!.dueDate;
      _recurring = widget.billing!.recurring == 1;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameCtrl.text.trim();
    final amountText = _amountCtrl.text.replaceAll(',', '.');
    final amount = amountText.isEmpty ? 0.0 : double.tryParse(amountText) ?? 0.0;

    if (widget.billing == null) {
      final b = Billing(
        name: name,
        amount: amount,
        dueDate: _due,
        recurring: _recurring ? 1 : 0,
        paid: 0,
      );

      b.id = await DatabaseHelper.instance.insert(b);
      await NotificationHelper.instance.scheduleNotificationForBilling(b);

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } else {
      final updated = Billing(
        id: widget.billing!.id,
        name: name,
        amount: amount,
        dueDate: _due,
        recurring: _recurring ? 1 : 0,
        paid: widget.billing!.paid,
      );

      await DatabaseHelper.instance.update(updated);

      // 👇 fecha a tela IMEDIATAMENTE
      if (mounted) {
        Navigator.of(context).pop(true);
      }

      // 👇 notificação roda em background
      Future.microtask(() async {
        await NotificationHelper.instance
            .cancelNotification(updated.id!);
        await NotificationHelper.instance
            .scheduleNotificationForBilling(updated);
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.billing == null ? 'Nova conta' : 'Editar conta'),
        centerTitle: true,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // NOME
            _buildCard(
              child: TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nome da conta',
                  prefixIcon: Icon(Icons.description),
                  border: InputBorder.none,
                ),
                validator: (v) =>
                v == null || v.isEmpty ? 'Informe o nome da conta' : null,
              ),
            ),

            // VALOR
            _buildCard(
              child: TextFormField(
                controller: _amountCtrl,
                decoration: const InputDecoration(
                  labelText: 'Valor (opcional)',
                  prefixIcon: Icon(Icons.attach_money),
                  border: InputBorder.none,
                ),
                keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9\.,]'))
                ],
              ),
            ),

            // DATA
            _buildCard(
              child: ListTile(
                leading: const Icon(Icons.calendar_month),
                title: const Text('Vencimento'),
                subtitle: Text(
                  DateFormat('dd/MM/yyyy').format(_due),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                trailing: TextButton(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _due,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (d != null) setState(() => _due = d);
                  },
                  child: const Text('Alterar'),
                ),
              ),
            ),

            // RECORRENTE
            _buildCard(
              child: SwitchListTile(
                title: const Text('Conta recorrente'),
                subtitle: const Text('Repete todo mês'),
                value: _recurring,
                onChanged: (v) => setState(() => _recurring = v),
              ),
            ),

            const SizedBox(height: 24),

            // BOTÃO SALVAR
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check),
                label: const Text(
                  'Salvar conta',
                  style: TextStyle(fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _save,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: child,
      ),
    );
  }
}


/* ===================== MODEL ===================== */

class Billing {
  int? id;
  String name;
  double amount;
  DateTime dueDate;
  int recurring;
  int paid;

  Billing(
      {this.id,
        required this.name,
        required this.amount,
        required this.dueDate,
        this.recurring = 0,
        this.paid = 0});

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'amount': amount,
    'dueDate': dueDate.toIso8601String(),
    'recurring': recurring,
    'paid': paid,
  };

  static Billing fromMap(Map<String, dynamic> m) => Billing(
    id: m['id'],
    name: m['name'],
    amount: (m['amount'] as num).toDouble(),
    dueDate: DateTime.parse(m['dueDate']),
    recurring: m['recurring'],
    paid: m['paid'],
  );
}

/* ===================== DATABASE ===================== */

class DatabaseHelper {
  DatabaseHelper._();
  static final instance = DatabaseHelper._();
  static Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final path = p.join(await getDatabasesPath(), 'bills.db');
    return openDatabase(path, version: 1,
        onCreate: (db, _) async {
          await db.execute('''
        CREATE TABLE bills(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT,
          amount REAL,
          dueDate TEXT,
          recurring INTEGER,
          paid INTEGER
        )
      ''');
        });
  }

  Future<List<Billing>> getAll() async {
    final db = await database;
    final res = await db.query('bills');
    return res.map((e) => Billing.fromMap(e)).toList();
  }

  Future<int> insert(Billing b) async =>
      (await database).insert('bills', b.toMap());

  Future<int> update(Billing b) async =>
      (await database).update('bills', b.toMap(),
          where: 'id=?', whereArgs: [b.id]);

  Future<int> delete(int id) async =>
      (await database)
          .delete('bills', where: 'id=?', whereArgs: [id]);
}

/* ===================== NOTIFICATIONS ===================== */

class NotificationHelper {
  static final NotificationHelper instance = NotificationHelper._();
  NotificationHelper._();

  final FlutterLocalNotificationsPlugin _plugin =
  FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iOS = DarwinInitializationSettings();

    await _plugin.initialize(
      const InitializationSettings(
        android: android,
        iOS: iOS,
      ),
    );
  }

  /// Agenda notificação 5 dias antes do vencimento
  Future<void> scheduleNotificationForBilling(Billing b) async {
    if (b.paid == 1) return;

    final notifyDate = b.dueDate.subtract(const Duration(days: 5));
    if (notifyDate.isBefore(DateTime.now())) return;

    final androidDetails = AndroidNotificationDetails(
      'contas_channel',
      'Lembretes de contas',
      importance: Importance.max,
      priority: Priority.high,
    );

    const iosDetails = DarwinNotificationDetails();

    await _plugin.zonedSchedule(
      b.id ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'Conta a vencer',
      '${b.name} vence em ${DateFormat('dd/MM/yyyy').format(b.dueDate)}',
      tz.TZDateTime.from(notifyDate, tz.local),
      NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dateAndTime,
    );
  }


  /// Cancela notificação pelo ID da conta
  Future<void> cancelNotification(int id) async {
    await _plugin.cancel(id);
  }
}



class FilterPage extends StatefulWidget {
  final String initialStatus;

  const FilterPage({
    Key? key,
    this.initialStatus = 'Todas',
  }) : super(key: key);


  @override
  State<FilterPage> createState() => _FilterPageState();
}

class _FilterPageState extends State<FilterPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  DateTime? _selectedDate;

  late String _statusFilter;

  List<Billing> _all = [];
  List<Billing> _items = [];

  @override
  void initState() {
    super.initState();
    _statusFilter = widget.initialStatus;
    _load();
  }

  Future<void> _load() async {
    _all = await DatabaseHelper.instance.getAll();
    _applyFilters();
  }

  void _applyFilters() {
    final now = DateTime.now();

    List<Billing> filtered = _all;

    // 1️⃣ PRÉ-FILTRO POR STATUS
    if (_statusFilter == 'Pendentes') {
      filtered = filtered.where((b) => b.paid == 0 && !b.dueDate.isBefore(now)).toList();
    } else if (_statusFilter == 'Vencidas') {
      filtered = filtered.where((b) => b.paid == 0 && b.dueDate.isBefore(now)).toList();
    } else if (_statusFilter == 'Pagas') {
      filtered = filtered.where((b) => b.paid == 1).toList();
    }

    // 2️⃣ FILTRO POR NOME
    final text = _searchCtrl.text.trim().toLowerCase();
    if (text.isNotEmpty) {
      filtered = filtered.where((b) => b.name.toLowerCase().contains(text)).toList();
    }

    // 3️⃣ FILTRO POR DATA
    if (_selectedDate != null) {
      filtered = filtered.where((b) =>
      b.dueDate.year == _selectedDate!.year &&
          b.dueDate.month == _selectedDate!.month &&
          b.dueDate.day == _selectedDate!.day).toList();
    }

    setState(() => _items = filtered);
  }

  Color _statusColor(Billing b) {
    final now = DateTime.now();
    if (b.paid == 1) return Colors.green;
    if (b.dueDate.isBefore(now)) return Colors.red;
    if (b.dueDate.difference(now).inDays <= 5) return Colors.orange;
    return Colors.blueGrey;
  }

  String _formatMoney(double v) =>
      NumberFormat.simpleCurrency(locale: 'pt_BR').format(v);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Filtrar contas'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // 🔹 STATUS FILTER
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              children: ['Todas', 'Pendentes', 'Vencidas', 'Pagas']
                  .map(
                    (s) => ChoiceChip(
                  label: Text(s),
                  selected: _statusFilter == s,
                  onSelected: (_) {
                    setState(() => _statusFilter = s);
                    _applyFilters();
                  },
                ),
              )
                  .toList(),
            ),
          ),

          // 🔹 SEARCH
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                labelText: 'Pesquisar por nome',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => _applyFilters(),
            ),
          ),

          // 🔹 DATE FILTER
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedDate == null
                        ? 'Filtrar por data'
                        : DateFormat('dd/MM/yyyy').format(_selectedDate!),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (d != null) {
                      setState(() => _selectedDate = d);
                      _applyFilters();
                    }
                  },
                  child: const Text('Escolher'),
                ),
                if (_selectedDate != null)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      setState(() => _selectedDate = null);
                      _applyFilters();
                    },
                  )
              ],
            ),
          ),

          const Divider(),

          // 🔹 LIST
          Expanded(
            child: _items.isEmpty
                ? const Center(child: Text('Nenhuma conta encontrada'))
                : ListView.builder(
              itemCount: _items.length,
              itemBuilder: (context, i) {
                final b = _items[i];
                final color = _statusColor(b);

                return ContaCard(
                  billing: b,
                  onEdit: () async {
                    final result = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EditPage(billing: b),
                      ),
                    );
                    if (result == true) _load();
                  },
                  onDelete: () async {
                    await DatabaseHelper.instance.delete(b.id!);
                    _load();
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}


String formatMoney(double value) {
  return 'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';
}

Color statusColor(Billing b) {
  final now = DateTime.now();

  if (b.paid == 1) {
    return Colors.green;
  }

  if (b.dueDate.isBefore(DateTime(now.year, now.month, now.day))) {
    return Colors.red;
  }

  return Colors.orange;
}

class ContaCard extends StatelessWidget {
  final Billing billing;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const ContaCard({
    Key? key,
    required this.billing,
    required this.onEdit,
    required this.onDelete,
  }) : super(key: key);

  Color _statusColor() {
    final now = DateTime.now();

    if (billing.paid == 1) return Colors.green;
    if (billing.dueDate.isBefore(DateTime(now.year, now.month, now.day))) {
      return Colors.red;
    }
    if (billing.dueDate.difference(now).inDays <= 5) {
      return Colors.orange;
    }
    return Colors.blue;
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: color.withOpacity(0.85),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        title: Text(
          billing.name,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          'Vence em ${DateFormat('dd/MM/yyyy').format(billing.dueDate)}',
          style: const TextStyle(color: Colors.white70),
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white),
          onSelected: (v) {
            if (v == 'editar') onEdit();
            if (v == 'excluir') onDelete();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'editar', child: Text('Editar')),
            PopupMenuItem(value: 'excluir', child: Text('Excluir')),
          ],
        ),
      ),
    );
  }
}
