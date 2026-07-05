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

  try {
    await DatabaseHelper.instance.database;
  } catch (e) {
    debugPrint('Erro banco: $e');
  }

  try {
    tz.initializeTimeZones();

    final timeZoneName =
    await FlutterNativeTimezone.getLocalTimezone();

    tz.setLocalLocation(
      tz.getLocation(timeZoneName),
    );
  } catch (e) {
    debugPrint('Erro timezone: $e');

    tz.setLocalLocation(
      tz.getLocation('America/Sao_Paulo'),
    );
  }

  try {
    await NotificationHelper.instance.init();
  } catch (e) {
    debugPrint('Erro notificações: $e');
  }

  runApp(const MyApp());

  Future.microtask(() async {
    try {
      final bills =
      await DatabaseHelper.instance.getAll();

      for (final bill in bills) {
        if (bill.id != null &&
            bill.paid == 0) {
          await NotificationHelper.instance
              .scheduleNotificationForBilling(
            bill,
          );
        }
      }
    } catch (e) {
      debugPrint(
        'Erro reagendando notificações: $e',
      );
    }
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isDark = false;

  void _toggleTheme(bool value) {
    setState(() {
      _isDark = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Contas em Dia',
      debugShowCheckedModeBanner: false,
      navigatorObservers: [routeObserver],

      themeMode:
      _isDark ? ThemeMode.dark : ThemeMode.light,

      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),

      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),

      home: MainPage(
        isDark: _isDark,
        onThemeChanged: _toggleTheme,
      ),
    );
  }
}


class MainPage extends StatefulWidget {
  final bool isDark;
  final ValueChanged<bool> onThemeChanged;

  const MainPage({
    Key? key,
    required this.isDark,
    required this.onThemeChanged,
  }) : super(key: key);

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {

    final pages = [
      HomePage(
        isDark: widget.isDark,
        onThemeChanged: widget.onThemeChanged,
      ),
      const FilterPage(),
    ];

    return Scaffold(
      body: pages[_index],
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
  final bool isDark;
  final ValueChanged<bool> onThemeChanged;

  const HomePage({
    super.key,
    required this.isDark,
    required this.onThemeChanged,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with RouteAware {

  DateTime _nextRecurringDate(DateTime current) {
    final nextMonth = DateTime(
      current.year,
      current.month + 1,
      1,
    );

    final lastDayOfMonth = DateTime(
      nextMonth.year,
      nextMonth.month + 1,
      0,
    ).day;

    final day = current.day > lastDayOfMonth
        ? lastDayOfMonth
        : current.day;

    return DateTime(
      nextMonth.year,
      nextMonth.month,
      day,
    );
  }


  Future<bool> _recurringAlreadyExists(
      Billing bill,
      DateTime nextDate,
      ) async {

    final all =
    await DatabaseHelper.instance.getAll();

    return all.any((b) =>
    b.id != bill.id &&
        b.name == bill.name &&
        b.recurring == 1 &&
        b.dueDate.year == nextDate.year &&
        b.dueDate.month == nextDate.month &&
        b.dueDate.day == nextDate.day);
  }

  Widget _emptyHomeState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ÍCONE
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.account_balance_wallet_outlined,
                size: 56,
                color: Colors.green,
              ),
            ),

            const SizedBox(height: 24),

            // TEXTO PRINCIPAL
            const Text(
              'Tudo em dia por aqui 💚',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            // TEXTO SECUNDÁRIO
            const Text(
              'Você ainda não cadastrou nenhuma conta.\n'
                  'Adicione sua primeira conta para começar.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.black54,
                fontSize: 14,
              ),
            ),

            const SizedBox(height: 28),

            // CTA
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Adicionar primeira conta'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 26,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const EditPage()),
                );
                if (result == true) _reload();
              },
            ),
          ],
        ),
      ),
    );
  }


  // ✅ COLOQUE AQUI
  DateTime _onlyDate(DateTime d) =>
      DateTime(d.year, d.month, d.day);

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

    WidgetsBinding.instance
        .addPostFrameCallback((_) {
      NotificationHelper.instance.requestPermission();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
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


                  // cria próxima conta recorrente
                  // somente quando marcar como paga
                  if (b.paid == 1 && b.recurring == 1) {

                    final nextDate =
                    _nextRecurringDate(b.dueDate);


                    final exists =
                    await _recurringAlreadyExists(
                      b,
                      nextDate,
                    );


                    if (!exists) {

                      final nextBill = Billing(
                        name: b.name,
                        amount: b.amount,
                        dueDate: nextDate,
                        recurring: 1,
                        paid: 0,
                      );


                      final id =
                      await DatabaseHelper.instance
                          .insert(nextBill);

                      nextBill.id = id;


                      await NotificationHelper.instance
                          .scheduleNotificationForBilling(
                          nextBill);
                    }
                  }


                  if (b.id != null) {

                    if (b.paid == 1) {

                      await NotificationHelper.instance
                          .cancelNotification(b.id!);

                    } else {

                      await NotificationHelper.instance
                          .scheduleNotificationForBilling(b);
                    }
                  }


                  await _reload();


                  showSnack(
                    context,
                    b.paid == 1
                        ? 'Conta marcada como paga'
                        : 'Conta marcada como pendente',
                  );
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
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Excluir conta'),
                        content: Text(
                          'Deseja realmente excluir a conta "${b.name}"?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancelar'),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Excluir'),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true) {

                      await NotificationHelper.instance
                          .cancelNotification(b.id!);

                      await DatabaseHelper.instance.delete(b.id!);

                      await _reload();

                      showSnack(
                        context,
                        'Conta excluída',
                        color: Colors.red,
                      );
                    }
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
    //final today = _normalize(DateTime.now());
    final today = _onlyDate(DateTime.now());

    final atrasadas = _items.where((b) {
      final due = _onlyDate(b.dueDate);
      return b.paid == 0 && due.isBefore(today);
    }).toList();

    final proximos5 = _items.where((b) {
      final due = _onlyDate(b.dueDate);
      final diff = due.difference(today).inDays;
      return b.paid == 0 && diff >= 0 && diff <= 5;
    }).toList();

    final futuras = _items.where((b) {
      final due = _onlyDate(b.dueDate);
      final diff = due.difference(today).inDays;
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
              width: 40,
              height: 40,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Image.asset(
                'assets/icon/app_logo1.png',
                fit: BoxFit.contain,
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
                  'Suas contas, no dia certo',
                  style: TextStyle(
                    color: Colors.black54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),

        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.black87),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SettingsPage(
                    isDark: widget.isDark,
                    onThemeChanged: widget.onThemeChanged,
                  ),
                ),
              );
            },
          ),
        ],
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
      body: _items.isEmpty
          ? _emptyHomeState(context)
          : SingleChildScrollView(
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
          ],
        ),
      ),

      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
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

  double _parseCurrency(String text) {
    if (text.trim().isEmpty) {
      return 0.0;
    }

    String value = text
        .replaceAll('R\$', '')
        .replaceAll(' ', '')
        .trim();

    if (value.contains(',')) {
      value = value
          .replaceAll('.', '')
          .replaceAll(',', '.');
    }

    return double.tryParse(value) ?? 0.0;
  }

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
    final amount = _parseCurrency(_amountCtrl.text);

    Billing b;

    if (widget.billing == null) {
      // CRIAR
      b = Billing(
        name: name,
        amount: amount,
        dueDate: _due,
        recurring: _recurring ? 1 : 0,
        paid: 0,
      );
      b.id = await DatabaseHelper.instance.insert(b);
    } else {
      // EDITAR
      b = Billing(
        id: widget.billing!.id,
        name: name,
        amount: amount,
        dueDate: _due,
        recurring: _recurring ? 1 : 0,
        paid: widget.billing!.paid,
      );
      await DatabaseHelper.instance.update(b);
    }

    // 🔔 notificações SEM travar UI
    Future.microtask(() async {

      if (b.id != null) {

        await NotificationHelper.instance
            .cancelNotification(b.id!);

        if (b.paid == 0) {

          await NotificationHelper.instance
              .scheduleNotificationForBilling(b);

        }
      }
    });

    // ✅ feedback visual
    showSnack(
      context,
      widget.billing == null
          ? 'Conta criada com sucesso'
          : 'Conta atualizada com sucesso',
    );

    // ✅ FECHA A TELA SEMPRE
    if (!mounted) return;
    Navigator.of(context).pop(true);
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
    const android =
    AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const iOS =
    DarwinInitializationSettings();

    await _plugin.initialize(
      const InitializationSettings(
        android: android,
        iOS: iOS,
      ),
    );
  }

  Future<void> requestPermission() async {
    final androidPlugin =
    _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    try {
      await androidPlugin
          ?.requestNotificationsPermission();

      final enabled =
      await androidPlugin
          ?.areNotificationsEnabled();

      debugPrint(
        'Notificações permitidas: $enabled',
      );
    } catch (e) {
      debugPrint(
        'Erro permissão: $e',
      );
    }
  }

  Future<void> showTestNotification() async {
    const androidDetails =
    AndroidNotificationDetails(
      'teste_channel',
      'Teste',
      channelDescription:
      'Canal de testes',
      importance: Importance.max,
      priority: Priority.high,
    );

    const iosDetails =
    DarwinNotificationDetails();

    await _plugin.show(
      999999,
      '🔔 Teste de notificação',
      'Se você está vendo isso, as notificações estão funcionando.',
      const NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
    );
  }

  /// Agenda notificação 5 dias antes do vencimento
  Future<void> scheduleNotificationForBilling(Billing b) async {
    debugPrint('===================');
    debugPrint('Entrou no agendamento');
    debugPrint('Conta: ${b.name}');
    debugPrint('ID: ${b.id}');
    debugPrint('Pago: ${b.paid}');
    if (b.paid == 1) return;

    //final notifyDate = b.dueDate.subtract(const Duration(days: 5));

    //TESTE NOTIFICAÇÃO - REMOVER APOS TESTE
    final notifyDate =
    DateTime.now().add(
      const Duration(seconds: 15),
    );

    debugPrint(
      'Data agendada: $notifyDate',
    );

    if (notifyDate.isBefore(DateTime.now())) return;

    final androidDetails = AndroidNotificationDetails(
      'contas_channel',
      'Lembretes de contas',
      importance: Importance.max,
      priority: Priority.high,
    );

    const iosDetails = DarwinNotificationDetails();

    debugPrint(
      'Chamando zonedSchedule...',
    );

    final tzDate =
    tz.TZDateTime.from(
      notifyDate,
      tz.local,
    );

    debugPrint('Agora: ${DateTime.now()}');
    debugPrint('TZ Local: ${tz.local}');
    debugPrint('NotifyDate: $notifyDate');
    debugPrint('TZ Date: $tzDate');

    // await Future.delayed(
    //   const Duration(seconds: 15),
    // );
    //
    // await _plugin.show(
    //   b.id ?? 999,
    //   'Conta a vencer',
    //   '${b.name} vence em ${DateFormat('dd/MM/yyyy').format(b.dueDate)}',
    //   NotificationDetails(
    //     android: androidDetails,
    //     iOS: iosDetails,
    //   ),
    // );
    //
    // debugPrint('Notificação enviada pelo show()');

    //COMENTADO PARA TESTE
    await _plugin.zonedSchedule(
      b.id ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'Conta a vencer',
      '${b.name} vence em ${DateFormat('dd/MM/yyyy').format(b.dueDate)}',
      tzDate,
      NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
      androidScheduleMode:
      AndroidScheduleMode.inexactAllowWhileIdle,
      // linha comentada para teste
      // matchDateTimeComponents: DateTimeComponents.dateAndTime,
    );

    debugPrint(
      'zonedSchedule executado',
    );

    final pending =
    await _plugin
        .pendingNotificationRequests();

    debugPrint(
      'Pendentes: ${pending.length}',
    );

    for (final p in pending) {
      debugPrint(
        'ID=${p.id}'
            ' | ${p.title}',
      );
    }


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

  DateTime _onlyDate(DateTime d) =>
      DateTime(d.year, d.month, d.day);

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
    final now = _onlyDate(DateTime.now());

    List<Billing> filtered = _all;

    // 1️⃣ PRÉ-FILTRO POR STATUS
    if (_statusFilter == 'Pendentes') {
      filtered = filtered.where(
            (b) =>
        b.paid == 0 &&
            !_onlyDate(b.dueDate).isBefore(now),
      ).toList();
    } else if (_statusFilter == 'Vencidas') {
      filtered = filtered.where(
            (b) =>
        b.paid == 0 &&
            _onlyDate(b.dueDate).isBefore(now),
      ).toList();
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

    final now = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );

    if (b.paid == 1) return Colors.green;
    if (_onlyDate(b.dueDate).isBefore(now)) return Colors.red;
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
                ? _emptyState(context)
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
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Excluir conta'),
                        content: Text(
                          'Deseja realmente excluir a conta "${b.name}"?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancelar'),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Excluir'),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true) {

                      await NotificationHelper.instance
                          .cancelNotification(b.id!);

                      await DatabaseHelper.instance.delete(b.id!);

                      _load();

                      showSnack(
                        context,
                        'Conta excluída',
                        color: Colors.red,
                      );
                    }
                  },
                );
              },
            ),
          ),

        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ÍCONE
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.receipt_long,
                size: 48,
                color: Colors.green,
              ),
            ),

            const SizedBox(height: 20),

            // TEXTO PRINCIPAL
            const Text(
              'Nada por aqui ainda 😊',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            // TEXTO SECUNDÁRIO
            const Text(
              'Adicione uma conta para começar a organizar seus pagamentos.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.black54,
              ),
            ),

            const SizedBox(height: 20),

            // CTA
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Adicionar nova conta'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const EditPage()),
                );
                if (result == true) _load();
              },
            ),
          ],
        ),
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

    final now = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );

    if (billing.paid == 1) return Colors.green;
    if (billing.dueDate.isBefore(DateTime(now.year, now.month, now.day))) {
      return Colors.red;
    }
    if (
    DateTime(
      billing.dueDate.year,
      billing.dueDate.month,
      billing.dueDate.day,
    ).difference(now).inDays <= 5
    ) {
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


void showSnack(
    BuildContext context,
    String message, {
      Color color = const Color(0xFF2E7D32),
      IconData icon = Icons.check_circle,
    }) {
  final snackBar = SnackBar(
    behavior: SnackBarBehavior.floating,
    backgroundColor: Colors.transparent,
    elevation: 0,
    margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
    duration: const Duration(seconds: 3),
    content: _AnimatedSnackContent(
      message: message,
      icon: icon,
      backgroundColor: color,
    ),
  );

  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(snackBar);
}

class _AnimatedSnackContent extends StatefulWidget {
  final String message;
  final IconData icon;
  final Color backgroundColor;

  const _AnimatedSnackContent({
    required this.message,
    required this.icon,
    required this.backgroundColor,
  });

  @override
  State<_AnimatedSnackContent> createState() =>
      _AnimatedSnackContentState();
}

class _AnimatedSnackContentState extends State<_AnimatedSnackContent>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fade;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _fade = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );

    _scale = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutBack,
      ),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: widget.backgroundColor,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10,
                offset: Offset(0, 4),
              )
            ],
          ),
          child: Row(
            children: [
              Icon(widget.icon, color: Colors.white, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
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


/* ===================== SETTINGS PAGE ===================== */

class SettingsPage extends StatefulWidget {
  final bool isDark;
  final ValueChanged<bool> onThemeChanged;

  const SettingsPage({
    Key? key,
    required this.isDark,
    required this.onThemeChanged,
  }) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _notificationsEnabled = true;
  int _notifyDaysBefore = 5;
  bool _darkTheme = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurações'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('Notificações'),

          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: SwitchListTile(
              title: const Text('Ativar notificações'),
              subtitle: const Text('Receber lembretes de contas'),
              value: _notificationsEnabled,
              onChanged: (v) {
                setState(() => _notificationsEnabled = v);

                showSnack(
                  context,
                  v
                      ? 'Notificações ativadas'
                      : 'Notificações desativadas',
                );
              },
            ),
          ),

          // 👇 COLE AQUI
          const SizedBox(height: 12),

          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.notifications),
              label: const Text(
                'Testar notificação',
              ),
              onPressed: () async {
                await NotificationHelper.instance
                    .showTestNotification();

                showSnack(
                  context,
                  'Notificação enviada',
                );
              },
            ),
          ),

          const SizedBox(height: 12),

          Opacity(
            opacity: _notificationsEnabled ? 1 : 0.4,
            child: IgnorePointer(
              ignoring: !_notificationsEnabled,
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Avisar quantos dias antes?',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        children: [5, 3, 1].map((d) {
                          return ChoiceChip(
                            label: Text('$d dias'),
                            selected: _notifyDaysBefore == d,
                            onSelected: (_) {
                              setState(() => _notifyDaysBefore = d);

                              showSnack(
                                context,
                                'Notificação $d dias antes',
                              );
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          _sectionTitle('Aparência'),

          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: SwitchListTile(
              title: const Text('Tema escuro'),
              subtitle: const Text('Ativar modo noturno'),
              value: widget.isDark,
              onChanged: (v) {
                widget.onThemeChanged(v);

                showSnack(
                  context,
                  v
                      ? 'Tema escuro ativado'
                      : 'Tema claro ativado',
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.green,
        ),
      ),
    );
  }
}
