

/*
// Contas em Dia — Flutter (main.dart) - ORIGINAL FUNCIONAL
// Código-fonte mínimo funcional com:
// - Listagem de contas
// - Adicionar / Editar / Excluir
// - Marcar Paga/Não Paga
// - Recorrência mensal (cria próximo vencimento ao marcar paga)
// - Armazenamento local com sqflite
// - Notificações locais (5 dias antes) com flutter_local_notifications
// - Formatação de moeda

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:flutter/services.dart';

import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_native_timezone/flutter_native_timezone.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializar banco (chamando o getter)
  await DatabaseHelper.instance.database;


  // Inicializar timezone
  tz.initializeTimeZones();
  final String timeZoneName = await FlutterNativeTimezone.getLocalTimezone();
  tz.setLocalLocation(tz.getLocation(timeZoneName));

  // Inicializar notificações
  await NotificationHelper.instance.init();

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Contas em Dia',
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: ThemeMode.system, // automático conforme o celular
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Billing> _items = [];
  String _filter = 'Todas';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final all = await DatabaseHelper.instance.getAll();

    DateTime normalize(DateTime d) => DateTime(d.year, d.month, d.day);
    final today = normalize(DateTime.now());

    setState(() {
      if (_filter == 'Todas') {
        _items = all;
      } else if (_filter == 'Pagas') {
        _items = all.where((e) => e.paid == 1).toList();
      } else if (_filter == 'Pendentes') {
        _items = all.where((e) => e.paid == 0).toList();
      }
      _items.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    });

  }

  Color _statusColor(Billing b) {
    final now = DateTime.now();
    if (b.paid == 1) return Colors.green[200]!;
    if (b.dueDate.isBefore(now)) return Colors.red[200]!;
    if (b.dueDate.difference(now).inDays <= 5) return Colors.yellow[200]!;
    return Colors.white;
  }

  String _formatMoney(double v) => NumberFormat.simpleCurrency(locale: 'pt_BR').format(v);

  @override
  Widget build(BuildContext context) {
    //inicio código teste
    DateTime normalize(DateTime d) => DateTime(d.year, d.month, d.day);
    final today = normalize(DateTime.now());

    final upcoming5Days = _items.where((b) {
      final diff = normalize(b.dueDate).difference(today).inDays;
      return diff >= 0 && diff <= 5 && b.paid == 0;
    }).toList();

    final overdue = _items.where((b) {
      return normalize(b.dueDate).isBefore(today) && b.paid == 0;
    }).toList();

    final upcoming10Days = _items.where((b) {
      final diff = normalize(b.dueDate).difference(today).inDays;
      return diff > 5 && diff <= 10 && b.paid == 0;
    }).toList();

    final futureBills = _items.where((b) {
      final diff = normalize(b.dueDate).difference(today).inDays;
      return diff > 10 && b.paid == 0;
    }).toList();


    //fim código teste

    return Scaffold(
      appBar: AppBar(
        title: Text('Contas em Dia'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (s) async {
              setState(() => _filter = s); // garante rebuild imediato do filtro
              await _reload();
            },
            itemBuilder: (_) => ['Todas', 'Pagas', 'Pendentes']
                .map((s) => PopupMenuItem(value: s, child: Text(s)))
                .toList(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            if (_filter == 'Todas') ...[
              _buildBlock("Contas para hoje ou próximos 5 dias", upcoming5Days, Colors.blueAccent),
              _buildBlock("Contas atrasadas", overdue, Colors.redAccent),
              _buildBlock("Contas para os próximos 10 dias", upcoming10Days, Colors.amberAccent),
            ] else if (_filter == 'Pagas') ...[
              _buildPaidBlock("Contas pagas", _items),
            ] else if (_filter == 'Pendentes') ...[
              _buildPendingBlock("Contas pendentes", _items),
              _buildBlock("Contas futuras (mais de 10 dias)", futureBills, Colors.yellow),
            ],
          ],
        ),
      ),

      floatingActionButton: FloatingActionButton(
        child: Icon(Icons.add),
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => EditPage()),
          );
          if (result == true) {
            await _reload();
            setState(() {});
          }
        },
      ),
    );
  }

  //inicio codigo novo teste
  Widget _buildBlock(String title, List<Billing> bills, Color color) {
    if (bills.isEmpty) return const SizedBox.shrink();
    return Card(
      color: color,
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            ...bills.map((b) => ListTile(
              title: Text(b.name, style: const TextStyle(color: Colors.white)),
              subtitle: Text(
                "Vencimento: ${DateFormat('dd/MM/yyyy').format(b.dueDate)} • ${_formatMoney(b.amount)}",
                style: const TextStyle(color: Colors.white70),
              ),
              leading: Checkbox(
                value: b.paid == 1,
                onChanged: (val) async {
                  setState(() {
                    b.paid = val! ? 1 : 0;
                  });

                  if (val == true) {
                    await DatabaseHelper.instance.update(b);
                    if (b.recurring == 1 && b.paid == 1) {
                      final next = Billing.copyWithNextMonth(b);
                      final all = await DatabaseHelper.instance.getAll();
                      final exists = all.any((bill) =>
                      bill.name == next.name &&
                          bill.dueDate.year == next.dueDate.year &&
                          bill.dueDate.month == next.dueDate.month &&
                          bill.dueDate.day == next.dueDate.day);
                      if (!exists) {
                        final id = await DatabaseHelper.instance.insert(next);
                        next.id = id;
                        await NotificationHelper.instance.scheduleNotificationForBilling(next);
                      }
                    }
                    await NotificationHelper.instance.cancelNotification(b.id!);
                  } else {
                    await DatabaseHelper.instance.update(b);
                    await NotificationHelper.instance.scheduleNotificationForBilling(b);
                  }

                  await _reload();
                },
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.white),
                    onPressed: () async {
                      final result = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(builder: (_) => EditPage(billing: b)),
                      );
                      if (result == true) {
                        await _reload(); // atualiza lista ao voltar somente se salvou
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.white),
                    onPressed: () async {
                      await DatabaseHelper.instance.delete(b.id!);
                      await NotificationHelper.instance.cancelNotification(b.id!);
                      await _reload();
                    },
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildPaidBlock(String title, List<Billing> bills) {
    if (bills.isEmpty) return SizedBox.shrink();
    return Card(
      color: Colors.greenAccent.shade700,
      margin: EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            ...bills.map((b) => ListTile(
              title: Text(b.name, style: const TextStyle(color: Colors.white)),
              subtitle: Text(
                "Vencimento: ${DateFormat('dd/MM/yyyy').format(b.dueDate)} • ${_formatMoney(b.amount)}",
                style: const TextStyle(color: Colors.white70),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.white),
                    onPressed: () async {
                      await DatabaseHelper.instance.delete(b.id!);
                      await NotificationHelper.instance.cancelNotification(b.id!);
                      await _reload();
                    },
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }


  Widget _buildPendingBlock(String title, List<Billing> bills) {
    if (bills.isEmpty) return SizedBox.shrink();
    return Card(
      color: Colors.yellowAccent.shade700,
      margin: EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            ...bills.map((b) => ListTile(
              title: Text(b.name, style: const TextStyle(color: Colors.white)),
              subtitle: Text(
                "Vencimento: ${DateFormat('dd/MM/yyyy').format(b.dueDate)} • ${_formatMoney(b.amount)}",
                style: const TextStyle(color: Colors.white70),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning, color: Colors.white),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.white),
                    onPressed: () async {
                      await DatabaseHelper.instance.delete(b.id!);
                      await NotificationHelper.instance.cancelNotification(b.id!);
                      await _reload();
                    },
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

}

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
      _amountCtrl.text = widget.billing!.amount.toStringAsFixed(2);
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
    final amount = double.tryParse(_amountCtrl.text.replaceAll(',', '.'));
    if (amount == null) return;

    if (widget.billing == null) {
      final b = Billing(
        name: name,
        amount: amount,
        dueDate: _due,
        recurring: _recurring ? 1 : 0,
        paid: 0,
      );
      final id = await DatabaseHelper.instance.insert(b);
      b.id = id;
      await NotificationHelper.instance.scheduleNotificationForBilling(b);
    } else {
      final b = widget.billing!;
      b
        ..name = name
        ..amount = amount
        ..dueDate = _due
        ..recurring = _recurring ? 1 : 0;

      await DatabaseHelper.instance.update(b);
      await NotificationHelper.instance.cancelNotification(b.id!);
      await NotificationHelper.instance.scheduleNotificationForBilling(b);
    }

    if (!mounted) return;
    Navigator.pop(context, true); // retorna para a Home
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.billing == null ? 'Nova conta' : 'Editar conta'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Nome'),
                validator: (v) => v == null || v.isEmpty ? 'Informe o nome' : null,
              ),
              TextFormField(
                controller: _amountCtrl,
                decoration: const InputDecoration(labelText: 'Valor (R\$)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9\.,]'))
                ],
                validator: (v) => v == null || v.isEmpty ? 'Informe o valor' : null,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('Vencimento: ${DateFormat('dd/MM/yyyy').format(_due)}'),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _due,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (d != null) setState(() => _due = d);
                    },
                    child: const Text('Escolher'),
                  ),
                ],
              ),
              CheckboxListTile(
                title: const Text('Recorrente (todo mês)'),
                value: _recurring,
                onChanged: (v) => setState(() => _recurring = v!),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _save,
                child: const Text('Salvar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Models & DB helper ---
class Billing {
  int? id;
  String name;
  double amount;
  DateTime dueDate;
  int recurring; // 0/1
  int paid; // 0/1

  Billing({this.id, required this.name, required this.amount, required this.dueDate, this.recurring = 0, this.paid = 0});

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'amount': amount,
    'dueDate': dueDate.toIso8601String(),
    'recurring': recurring,
    'paid': paid,
  };

  static Billing fromMap(Map<String, dynamic> m) => Billing(
    id: m['id'] as int?,
    name: m['name'],
    amount: (m['amount'] as num).toDouble(),
    dueDate: DateTime.parse(m['dueDate']),
    recurring: m['recurring'],
    paid: m['paid'],
  );

  static Billing copyWithNextMonth(Billing b) {
    final next = DateTime(b.dueDate.year, b.dueDate.month + 1, b.dueDate.day);
    return Billing(name: b.name, amount: b.amount, dueDate: next, recurring: b.recurring, paid: 0);
  }
}
class DatabaseHelper {
  // Singleton
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;

  // Getter que estava faltando
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  // Inicializa o banco
  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'bills.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  // Criação das tabelas
  Future _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE bills (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        amount REAL NOT NULL,
        dueDate TEXT NOT NULL,
        recurring INTEGER NOT NULL,
        paid INTEGER NOT NULL
      )
    ''');
  }

  // Métodos CRUD
  Future<int> insert(Billing b) async {
    final db = await database;
    return await db.insert('bills', b.toMap());
  }

  Future<int> update(Billing b) async {
    final db = await database;
    return await db.update(
      'bills',
      b.toMap(),
      where: 'id = ?',
      whereArgs: [b.id],
    );
  }

  Future<int> delete(int id) async {
    final db = await database;
    return await db.delete(
      'bills',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Billing>> getAll() async {
    final db = await database;
    final result = await db.query('bills', orderBy: 'dueDate ASC');
    return result.map((e) => Billing.fromMap(e)).toList();
  }
}

// --- Notifications ---
class NotificationHelper {
  static final NotificationHelper instance = NotificationHelper._();
  NotificationHelper._();
  final _plugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iOS = DarwinInitializationSettings();
    await _plugin.initialize(const InitializationSettings(android: android, iOS: iOS));
  }

  Future<void> scheduleNotificationForBilling(Billing b) async {
    if (b.paid == 1) return;

    final when = b.dueDate.subtract(const Duration(days: 5));
    if (when.isBefore(DateTime.now())) return;

    final androidDetails = AndroidNotificationDetails(
      'contas_channel',
      'Lembretes',
      importance: Importance.max,
      priority: Priority.high,
    );
    final iosDetails = DarwinNotificationDetails();

    await _plugin.zonedSchedule(
      b.id ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'Vencimento: ${b.name}',
      'Vence em ${DateFormat('dd/MM/yyyy').format(b.dueDate)} — '
          '${NumberFormat.simpleCurrency(locale: 'pt_BR').format(b.amount)}',
      tz.TZDateTime.from(when, tz.local),
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dateAndTime, // opcional
    );

  }

  Future<void> cancelNotification(int id) async => await _plugin.cancel(id);
}

*/









































































/*
// Contas em Dia — Flutter (main.dart)
// Código-fonte mínimo funcional com:
// - Listagem de contas
// - Adicionar / Editar / Excluir
// - Marcar Paga/Não Paga
// - Recorrência mensal (cria próximo vencimento ao marcar paga)
// - Armazenamento local com sqflite
// - Notificações locais (5 dias antes) com flutter_local_notifications
// - Formatação de moeda

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:flutter/services.dart';

import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_native_timezone/flutter_native_timezone.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializar banco (chamando o getter)
  await DatabaseHelper.instance.database;


  // Inicializar timezone
  tz.initializeTimeZones();
  final String timeZoneName = await FlutterNativeTimezone.getLocalTimezone();
  tz.setLocalLocation(tz.getLocation(timeZoneName));

  // Inicializar notificações
  await NotificationHelper.instance.init();

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Contas em Dia',
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: ThemeMode.system, // automático conforme o celular
      home: HomePage(),
    );
  }
}

// class HomePage extends StatefulWidget {
//   const HomePage({super.key});
//
//   @override
//   State<HomePage> createState() => _HomePageState();
// }

// class _HomePageState extends State<HomePage> {
//   final db = DatabaseHelper.instance;
//   List<Billing> _billings = [];
//
//   @override
//   void initState() {
//     super.initState();
//     _reload();
//   }
//
//   Future<void> _reload() async {
//     final list = await db.getAll();
//     setState(() => _billings = list);
//   }
//
//   // Alternar pago / não pago
//   Future<void> _toggle(Billing b) async {
//     b.paid = b.paid == 1 ? 0 : 1;
//     await db.update(b);
//     _reload();
//   }
//
//   // Ir para editar
//   Future<void> _openEdit(Billing? b) async {
//     final result = await Navigator.push(
//       context,
//       MaterialPageRoute(builder: (_) => EditPage(billing: b)),
//     );
//     if (result == true) _reload();
//   }
//
//   // Status visual
//   Color _statusColor(Billing b) {
//     final now = DateTime.now();
//     if (b.paid == 1) return Colors.green.withOpacity(0.25);
//     if (b.dueDate.isBefore(now)) return Colors.red.withOpacity(0.25);
//     if (b.dueDate.difference(now).inDays <= 5) {
//       return Colors.yellow.withOpacity(0.25);
//     }
//     return Colors.grey.withOpacity(0.15);
//   }
//
//   IconData _statusIcon(Billing b) {
//     final now = DateTime.now();
//     if (b.paid == 1) return Icons.check_circle;
//     if (b.dueDate.isBefore(now)) return Icons.error;
//     if (b.dueDate.difference(now).inDays <= 5) return Icons.schedule;
//     return Icons.circle_outlined;
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text("Contas em Dia"),
//         centerTitle: true,
//         backgroundColor: Colors.green.shade700,
//       ),
//
//       floatingActionButton: FloatingActionButton(
//         child: const Icon(Icons.add),
//         onPressed: () => _openEdit(null),
//       ),
//
//       body: _billings.isEmpty
//           ? const Center(
//         child: Text(
//           "Nenhuma conta cadastrada",
//           style: TextStyle(fontSize: 18),
//         ),
//       )
//           : ListView(
//         children: _billings.map((b) {
//           return Card(
//             margin: const EdgeInsets.symmetric(
//                 vertical: 6, horizontal: 12),
//             color: _statusColor(b),
//             shape: RoundedRectangleBorder(
//               borderRadius: BorderRadius.circular(12),
//             ),
//             child: ListTile(
//               leading: Icon(
//                 _statusIcon(b),
//                 size: 32,
//                 color: b.paid == 1
//                     ? Colors.green.shade900
//                     : Colors.orange.shade700,
//               ),
//               title: Text(
//                 b.name,
//                 style: const TextStyle(
//                   fontSize: 18,
//                   fontWeight: FontWeight.w600,
//                 ),
//               ),
//               subtitle: Text(
//                 "Vence em: ${DateFormat('dd/MM/yyyy').format(b.dueDate)}",
//                 style: const TextStyle(fontSize: 14),
//               ),
//               trailing: Text(
//                 NumberFormat.simpleCurrency(locale: 'pt_BR')
//                     .format(b.amount),
//                 style: const TextStyle(
//                   fontSize: 17,
//                   fontWeight: FontWeight.bold,
//                 ),
//               ),
//
//               onTap: () => _openEdit(b), // editar — toque simples
//               onLongPress: () => _toggle(b), // marcar pago — toque longo
//             ),
//           );
//         }).toList(),
//       ),
//     );
//   }
// }

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Billing> _items = [];
  String _filter = 'Todas';

  void _changeTab(String filter) async {
    setState(() => _filter = filter);
    await _reload();
  }

  Widget _navButton({
    required String label,
    required IconData icon,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: selected ? color : Colors.grey),
          Text(label,
              style: TextStyle(
                fontSize: 12,
                color: selected ? color : Colors.grey,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              )),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final all = await DatabaseHelper.instance.getAll();

    DateTime normalize(DateTime d) => DateTime(d.year, d.month, d.day);
    final today = normalize(DateTime.now());

    setState(() {
      if (_filter == 'Todas') {
        _items = all;
      } else if (_filter == 'Pagas') {
        _items = all.where((e) => e.paid == 1).toList();
      } else if (_filter == 'Pendentes') {
        _items = all.where((e) => e.paid == 0).toList();
      }
      _items.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    });

  }

  Color _statusColor(Billing b) {
    final now = DateTime.now();
    if (b.paid == 1) return Colors.green.shade100;
    if (b.dueDate.isBefore(now)) return Colors.red.shade100;
    if (b.dueDate.difference(now).inDays <= 5) return Colors.yellow.shade100;
    return Colors.grey.shade200;
  }

  String _statusIcon(Billing b) {
    final now = DateTime.now();
    if (b.paid == 1) return "🟢";
    if (b.dueDate.isBefore(now)) return "🔴";
    if (b.dueDate.difference(now).inDays <= 5) return "🟡";
    return "⚪";
  }

  String _formatMoney(double v) => NumberFormat.simpleCurrency(locale: 'pt_BR').format(v);

  @override
  Widget build(BuildContext context) {
    //inicio código teste
    DateTime normalize(DateTime d) => DateTime(d.year, d.month, d.day);
    final today = normalize(DateTime.now());

    final upcoming5Days = _items.where((b) {
      final diff = normalize(b.dueDate).difference(today).inDays;
      return diff >= 0 && diff <= 5 && b.paid == 0;
    }).toList();

    final overdue = _items.where((b) {
      return normalize(b.dueDate).isBefore(today) && b.paid == 0;
    }).toList();

    final upcoming10Days = _items.where((b) {
      final diff = normalize(b.dueDate).difference(today).inDays;
      return diff > 5 && diff <= 10 && b.paid == 0;
    }).toList();

    final futureBills = _items.where((b) {
      final diff = normalize(b.dueDate).difference(today).inDays;
      return diff > 10 && b.paid == 0;
    }).toList();


    //fim código teste

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contas em Dia'),
      ),

      body: SingleChildScrollView(
        child: Column(
          children: [
            if (_filter == 'Todas') ...[
              _buildBlock("Contas para hoje ou próximos 5 dias", upcoming5Days, Colors.blueAccent),
              _buildBlock("Contas atrasadas", overdue, Colors.redAccent),
              _buildBlock("Contas para os próximos 10 dias", upcoming10Days, Colors.amberAccent),
            ] else if (_filter == 'Pagas') ...[
              _buildPaidBlock("Contas pagas", _items),
            ] else if (_filter == 'Vencidas') ...[
              _buildBlock("Contas atrasadas", overdue, Colors.redAccent),
            ] else if (_filter == 'Pendentes') ...[
              _buildPendingBlock("Contas pendentes", _items),
              _buildBlock("Contas futuras (mais de 10 dias)", futureBills, Colors.yellow),
            ],
          ],
        ),
      ),

      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 60),
        child: FloatingActionButton(
          child: const Icon(Icons.add),
          onPressed: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => EditPage()),
            );
            if (result == true) {
              await _reload();
            }
          },
        ),
      ),

      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navButton(
                label: "Home",
                icon: Icons.home,
                color: Colors.blue,
                selected: _filter == "Todas",
                onTap: () => _changeTab("Todas"),
              ),
              _navButton(
                label: "Pagas",
                icon: Icons.check_circle,
                color: Colors.green,
                selected: _filter == "Pagas",
                onTap: () => _changeTab("Pagas"),
              ),
              _navButton(
                label: "Vencidas",
                icon: Icons.warning_amber_rounded,
                color: Colors.red,
                selected: _filter == "Vencidas",
                onTap: () => _changeTab("Vencidas"),
              ),
              _navButton(
                label: "Pendentes",
                icon: Icons.watch_later,
                color: Colors.amber,
                selected: _filter == "Pendentes",
                onTap: () => _changeTab("Pendentes"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  //inicio codigo novo teste
  Widget _buildBlock(String title, List<Billing> bills, Color color) {
    if (bills.isEmpty) return const SizedBox.shrink();
    return Card(
      color: _statusColor(),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Text(
          _statusIcon(b),
          style: TextStyle(fontSize: 28),
        ),
        title: Text(
          b.description,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        subtitle: Text(
          "Vence: ${DateFormat('dd MMM yyyy').format(b.dueDate)}",
          style: TextStyle(fontSize: 14),
        ),
        trailing: IconButton(
          icon: Icon(
            b.paid == 1 ? Icons.check_circle : Icons.radio_button_unchecked,
          ),
          onPressed: () => _togglePaid(b),
        ),
        onTap: () => _edit(b),
      ),
    );
  }

  Widget _buildPaidBlock(String title, List<Billing> bills) {
    if (bills.isEmpty) return SizedBox.shrink();
    return Card(
      color: Colors.greenAccent.shade700,
      margin: EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            ...bills.map((b) => ListTile(
              title: Text(b.name, style: const TextStyle(color: Colors.white)),
              subtitle: Text(
                "Vencimento: ${DateFormat('dd/MM/yyyy').format(b.dueDate)} • ${_formatMoney(b.amount)}",
                style: const TextStyle(color: Colors.white70),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.white),
                    onPressed: () async {
                      await DatabaseHelper.instance.delete(b.id!);
                      await NotificationHelper.instance.cancelNotification(b.id!);
                      await _reload();
                    },
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }


  Widget _buildPendingBlock(String title, List<Billing> bills) {
    if (bills.isEmpty) return SizedBox.shrink();
    return Card(
      color: Colors.yellowAccent.shade700,
      margin: EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            ...bills.map((b) => ListTile(
              title: Text(b.name, style: const TextStyle(color: Colors.white)),
              subtitle: Text(
                "Vencimento: ${DateFormat('dd/MM/yyyy').format(b.dueDate)} • ${_formatMoney(b.amount)}",
                style: const TextStyle(color: Colors.white70),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning, color: Colors.white),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.white),
                    onPressed: () async {
                      await DatabaseHelper.instance.delete(b.id!);
                      await NotificationHelper.instance.cancelNotification(b.id!);
                      await _reload();
                    },
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

}

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
      _amountCtrl.text = widget.billing!.amount.toStringAsFixed(2);
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
    final amount = double.tryParse(_amountCtrl.text.replaceAll(',', '.'));
    if (amount == null) return;

    if (widget.billing == null) {
      final b = Billing(
        name: name,
        amount: amount,
        dueDate: _due,
        recurring: _recurring ? 1 : 0,
        paid: 0,
      );
      final id = await DatabaseHelper.instance.insert(b);
      b.id = id;
      await NotificationHelper.instance.scheduleNotificationForBilling(b);
    } else {
      final b = widget.billing!;
      b
        ..name = name
        ..amount = amount
        ..dueDate = _due
        ..recurring = _recurring ? 1 : 0;

      await DatabaseHelper.instance.update(b);
      await NotificationHelper.instance.cancelNotification(b.id!);
      await NotificationHelper.instance.scheduleNotificationForBilling(b);
    }

    if (!mounted) return;
    Navigator.pop(context, true); // retorna para a Home
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.billing == null ? 'Nova conta' : 'Editar conta'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Nome'),
                validator: (v) => v == null || v.isEmpty ? 'Informe o nome' : null,
              ),
              TextFormField(
                controller: _amountCtrl,
                decoration: const InputDecoration(labelText: 'Valor (R\$)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9\.,]'))
                ],
                validator: (v) => v == null || v.isEmpty ? 'Informe o valor' : null,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('Vencimento: ${DateFormat('dd/MM/yyyy').format(_due)}'),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _due,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (d != null) setState(() => _due = d);
                    },
                    child: const Text('Escolher'),
                  ),
                ],
              ),
              CheckboxListTile(
                title: const Text('Recorrente (todo mês)'),
                value: _recurring,
                onChanged: (v) => setState(() => _recurring = v!),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _save,
                child: const Text('Salvar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Models & DB helper ---
class Billing {
  int? id;
  String name;
  double amount;
  DateTime dueDate;
  int recurring; // 0/1
  int paid; // 0/1

  Billing({this.id, required this.name, required this.amount, required this.dueDate, this.recurring = 0, this.paid = 0});

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'amount': amount,
    'dueDate': dueDate.toIso8601String(),
    'recurring': recurring,
    'paid': paid,
  };

  static Billing fromMap(Map<String, dynamic> m) => Billing(
    id: m['id'] as int?,
    name: m['name'],
    amount: (m['amount'] as num).toDouble(),
    dueDate: DateTime.parse(m['dueDate']),
    recurring: m['recurring'],
    paid: m['paid'],
  );

  static Billing copyWithNextMonth(Billing b) {
    final next = DateTime(b.dueDate.year, b.dueDate.month + 1, b.dueDate.day);
    return Billing(name: b.name, amount: b.amount, dueDate: next, recurring: b.recurring, paid: 0);
  }
}
class DatabaseHelper {
  // Singleton
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;

  // Getter que estava faltando
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  // Inicializa o banco
  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'bills.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  // Criação das tabelas
  Future _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE bills (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        amount REAL NOT NULL,
        dueDate TEXT NOT NULL,
        recurring INTEGER NOT NULL,
        paid INTEGER NOT NULL
      )
    ''');
  }

  // Métodos CRUD
  Future<int> insert(Billing b) async {
    final db = await database;
    return await db.insert('bills', b.toMap());
  }

  Future<int> update(Billing b) async {
    final db = await database;
    return await db.update(
      'bills',
      b.toMap(),
      where: 'id = ?',
      whereArgs: [b.id],
    );
  }

  Future<int> delete(int id) async {
    final db = await database;
    return await db.delete(
      'bills',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Billing>> getAll() async {
    final db = await database;
    final result = await db.query('bills', orderBy: 'dueDate ASC');
    return result.map((e) => Billing.fromMap(e)).toList();
  }
}

// --- Notifications ---
class NotificationHelper {
  static final NotificationHelper instance = NotificationHelper._();
  NotificationHelper._();
  final _plugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iOS = DarwinInitializationSettings();
    await _plugin.initialize(const InitializationSettings(android: android, iOS: iOS));
  }

  Future<void> scheduleNotificationForBilling(Billing b) async {
    if (b.paid == 1) return;

    final when = b.dueDate.subtract(const Duration(days: 5));
    if (when.isBefore(DateTime.now())) return;

    final androidDetails = AndroidNotificationDetails(
      'contas_channel',
      'Lembretes',
      importance: Importance.max,
      priority: Priority.high,
    );
    final iosDetails = DarwinNotificationDetails();

    await _plugin.zonedSchedule(
      b.id ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'Vencimento: ${b.name}',
      'Vence em ${DateFormat('dd/MM/yyyy').format(b.dueDate)} — '
          '${NumberFormat.simpleCurrency(locale: 'pt_BR').format(b.amount)}',
      tz.TZDateTime.from(when, tz.local),
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dateAndTime, // opcional
    );

  }

  Future<void> cancelNotification(int id) async => await _plugin.cancel(id);
}
 */




























/*// Contas em Dia — Flutter (main.dart) — Light clean verde + Barra lateral colorida
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:flutter/services.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_native_timezone/flutter_native_timezone.dart';

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
      theme: ThemeData.light().copyWith(
        primaryColor: Colors.green,
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: Colors.green,
        ),
      ),
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Billing> _items = [];
  String _filter = 'Todas';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final all = await DatabaseHelper.instance.getAll();
    DateTime normalize(DateTime d) => DateTime(d.year, d.month, d.day);
    final today = normalize(DateTime.now());
    setState(() {
      if (_filter == 'Todas') {
        _items = all;
      } else if (_filter == 'Pagas') {
        _items = all.where((e) => e.paid == 1).toList();
      } else if (_filter == 'Pendentes') {
        _items = all.where((e) => e.paid == 0).toList();
      }
      _items.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    });
  }

  Color _statusColor(Billing b) {
    final now = DateTime.now();
    if (b.paid == 1) return Colors.green;
    if (b.dueDate.isBefore(now)) return Colors.red;
    if (b.dueDate.difference(now).inDays <= 5) return Colors.yellow[700]!;
    return Colors.grey.shade300;
  }

  String _formatMoney(double v) => NumberFormat.simpleCurrency(locale: 'pt_BR').format(v);

  @override
  Widget build(BuildContext context) {
    DateTime normalize(DateTime d) => DateTime(d.year, d.month, d.day);
    final today = normalize(DateTime.now());
    final upcoming5Days = _items.where((b) {
      final diff = normalize(b.dueDate).difference(today).inDays;
      return diff >= 0 && diff <= 5 && b.paid == 0;
    }).toList();
    final overdue = _items.where((b) {
      return normalize(b.dueDate).isBefore(today) && b.paid == 0;
    }).toList();
    final upcoming10Days = _items.where((b) {
      final diff = normalize(b.dueDate).difference(today).inDays;
      return diff > 5 && diff <= 10 && b.paid == 0;
    }).toList();
    final futureBills = _items.where((b) {
      final diff = normalize(b.dueDate).difference(today).inDays;
      return diff > 10 && b.paid == 0;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contas em Dia'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (s) async {
              setState(() => _filter = s);
              await _reload();
            },
            itemBuilder: (_) => ['Todas', 'Pagas', 'Pendentes']
                .map((s) => PopupMenuItem(value: s, child: Text(s)))
                .toList(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            if (_filter == 'Todas') ...[
              _buildBlock("Contas para hoje ou próximos 5 dias", upcoming5Days),
              _buildBlock("Contas atrasadas", overdue),
              _buildBlock("Contas para os próximos 10 dias", upcoming10Days),
            ] else if (_filter == 'Pagas') ...[
              _buildBlock("Contas pagas", _items),
            ] else if (_filter == 'Pendentes') ...[
              _buildBlock("Contas pendentes", _items),
              _buildBlock("Contas futuras (mais de 10 dias)", futureBills),
            ],
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

  Widget _buildBlock(String title, List<Billing> bills) {
    if (bills.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
          const SizedBox(height: 4),
          ...bills.map((b) => _buildCard(b)).toList(),
        ],
      ),
    );
  }

  Widget _buildCard(Billing b) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        onTap: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => EditPage(billing: b)),
          );
          if (result == true) await _reload();
        },
        child: Row(
          children: [
            Container(
              width: 6,
              height: 60,
              decoration: BoxDecoration(
                color: _statusColor(b),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  bottomLeft: Radius.circular(8),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(b.name,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: b.paid == 1 ? Colors.green : Colors.black87)),
                    const SizedBox(height: 2),
                    Text(
                      "Vencimento: ${DateFormat('dd/MM/yyyy').format(b.dueDate)} • ${_formatMoney(b.amount)}",
                      style: const TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ),
            Column(
              children: [
                Checkbox(
                  value: b.paid == 1,
                  activeColor: Colors.green,
                  onChanged: (val) async {
                    setState(() {
                      b.paid = val! ? 1 : 0;
                    });
                    if (val == true) {
                      await DatabaseHelper.instance.update(b);
                      if (b.recurring == 1) {
                        final next = Billing.copyWithNextMonth(b);
                        final all = await DatabaseHelper.instance.getAll();
                        final exists = all.any((bill) =>
                        bill.name == next.name &&
                            bill.dueDate.year == next.dueDate.year &&
                            bill.dueDate.month == next.dueDate.month &&
                            bill.dueDate.day == next.dueDate.day);
                        if (!exists) {
                          final id = await DatabaseHelper.instance.insert(next);
                          next.id = id;
                          await NotificationHelper.instance
                              .scheduleNotificationForBilling(next);
                        }
                      }
                      await NotificationHelper.instance.cancelNotification(b.id!);
                    } else {
                      await DatabaseHelper.instance.update(b);
                      await NotificationHelper.instance.scheduleNotificationForBilling(b);
                    }
                    await _reload();
                  },
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.green),
                      onPressed: () async {
                        final result = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(builder: (_) => EditPage(billing: b)),
                        );
                        if (result == true) await _reload();
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () async {
                        await DatabaseHelper.instance.delete(b.id!);
                        await NotificationHelper.instance.cancelNotification(b.id!);
                        await _reload();
                      },
                    ),
                  ],
                )
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// --- EditPage (sem alteração visual) ---
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
      _amountCtrl.text = widget.billing!.amount.toStringAsFixed(2);
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
    final amount = double.tryParse(_amountCtrl.text.replaceAll(',', '.'));
    if (amount == null) return;

    if (widget.billing == null) {
      final b = Billing(
        name: name,
        amount: amount,
        dueDate: _due,
        recurring: _recurring ? 1 : 0,
        paid: 0,
      );
      final id = await DatabaseHelper.instance.insert(b);
      b.id = id;
      await NotificationHelper.instance.scheduleNotificationForBilling(b);
    } else {
      final b = widget.billing!;
      b
        ..name = name
        ..amount = amount
        ..dueDate = _due
        ..recurring = _recurring ? 1 : 0;
      await DatabaseHelper.instance.update(b);
      await NotificationHelper.instance.cancelNotification(b.id!);
      await NotificationHelper.instance.scheduleNotificationForBilling(b);
    }
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.billing == null ? 'Nova conta' : 'Editar conta'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Nome'),
                validator: (v) => v == null || v.isEmpty ? 'Informe o nome' : null,
              ),
              TextFormField(
                controller: _amountCtrl,
                decoration: const InputDecoration(labelText: 'Valor (R\$)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9\.,]'))
                ],
                validator: (v) => v == null || v.isEmpty ? 'Informe o valor' : null,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('Vencimento: ${DateFormat('dd/MM/yyyy').format(_due)}'),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _due,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (d != null) setState(() => _due = d);
                    },
                    child: const Text('Escolher'),
                  ),
                ],
              ),
              CheckboxListTile(
                title: const Text('Recorrente (todo mês)'),
                value: _recurring,
                onChanged: (v) => setState(() => _recurring = v!),
              ),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _save, child: const Text('Salvar')),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Models & DB helper ---
class Billing {
  int? id;
  String name;
  double amount;
  DateTime dueDate;
  int recurring;
  int paid;

  Billing({this.id, required this.name, required this.amount, required this.dueDate, this.recurring = 0, this.paid = 0});

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'amount': amount,
    'dueDate': dueDate.toIso8601String(),
    'recurring': recurring,
    'paid': paid,
  };

  static Billing fromMap(Map<String, dynamic> m) => Billing(
    id: m['id'] as int?,
    name: m['name'],
    amount: (m['amount'] as num).toDouble(),
    dueDate: DateTime.parse(m['dueDate']),
    recurring: m['recurring'],
    paid: m['paid'],
  );

  static Billing copyWithNextMonth(Billing b) {
    final next = DateTime(b.dueDate.year, b.dueDate.month + 1, b.dueDate.day);
    return Billing(name: b.name, amount: b.amount, dueDate: next, recurring: b.recurring, paid: 0);
  }
}

class DatabaseHelper {
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'bills.db');
    return await openDatabase(path, version: 1, onCreate: _onCreate);
  }

  Future _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE bills (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        amount REAL NOT NULL,
        dueDate TEXT NOT NULL,
        recurring INTEGER NOT NULL,
        paid INTEGER NOT NULL
      )
    ''');
  }

  Future<int> insert(Billing b) async {
    final db = await database;
    return await db.insert('bills', b.toMap());
  }

  Future<int> update(Billing b) async {
    final db = await database;
    return await db.update('bills', b.toMap(), where: 'id = ?', whereArgs: [b.id]);
  }

  Future<int> delete(int id) async {
    final db = await database;
    return await db.delete('bills', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Billing>> getAll() async {
    final db = await database;
    final result = await db.query('bills', orderBy: 'dueDate ASC');
    return result.map((e) => Billing.fromMap(e)).toList();
  }
}

class NotificationHelper {
  static final NotificationHelper instance = NotificationHelper._();
  NotificationHelper._();
  final _plugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iOS = DarwinInitializationSettings();
    await _plugin.initialize(const InitializationSettings(android: android, iOS: iOS));
  }

  Future<void> scheduleNotificationForBilling(Billing b) async {
    if (b.paid == 1) return;
    final when = b.dueDate.subtract(const Duration(days: 5));
    if (when.isBefore(DateTime.now())) return;
    final androidDetails = AndroidNotificationDetails(
      'contas_channel',
      'Lembretes',
      importance: Importance.max,
      priority: Priority.high,
    );
    final iosDetails = DarwinNotificationDetails();

    await _plugin.zonedSchedule(
      b.id ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'Vencimento: ${b.name}',
      'Vence em ${DateFormat('dd/MM/yyyy').format(b.dueDate)} — '
          '${NumberFormat.simpleCurrency(locale: 'pt_BR').format(b.amount)}',
      tz.TZDateTime.from(when, tz.local),
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dateAndTime,
    );
  }

  Future<void> cancelNotification(int id) async => await _plugin.cancel(id);
}*/








































/*import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:flutter/services.dart';

import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_native_timezone/flutter_native_timezone.dart';

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
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Billing> _items = [];
  String _filter = 'Todas';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final all = await DatabaseHelper.instance.getAll();
    setState(() {
      if (_filter == 'Todas') {
        _items = all;
      } else if (_filter == 'Pagas') {
        _items = all.where((e) => e.paid == 1).toList();
      } else {
        _items = all.where((e) => e.paid == 0).toList();
      }
    });
  }

  String _formatMoney(double v) =>
      NumberFormat.simpleCurrency(locale: 'pt_BR').format(v);

  Widget _buildCard(String title, List<Billing> bills, Color color) {
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
                    ? _formatMoney(b.amount)
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
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.white),
                onPressed: () async {
                  await DatabaseHelper.instance.delete(b.id!);
                  await _reload();
                },
              ),
            ))
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendentes = _items.where((b) => b.paid == 0).toList();
    final pagas = _items.where((b) => b.paid == 1).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contas em Dia'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              setState(() => _filter = v);
              _reload();
            },
            itemBuilder: (_) =>
                ['Todas', 'Pagas', 'Pendentes']
                    .map((e) => PopupMenuItem(value: e, child: Text(e)))
                    .toList(),
          )
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            if (_filter != 'Pagas')
              _buildCard('Pendentes', pendentes, Colors.orange),
            if (_filter != 'Pendentes')
              _buildCard('Pagas', pagas, Colors.green),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Nova conta'),
        onPressed: () async {
          final r = await Navigator.push(
              context, MaterialPageRoute(builder: (_) => EditPage()));
          if (r == true) _reload();
        },
      ),
    );
  }
}

class EditPage extends StatefulWidget {
  final Billing? billing;
  const EditPage({this.billing});

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
      if (widget.billing!.amount > 0) {
        _amountCtrl.text = widget.billing!.amount.toStringAsFixed(2);
      }
      _due = widget.billing!.dueDate;
      _recurring = widget.billing!.recurring == 1;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final amountText = _amountCtrl.text.trim();
    final amount = amountText.isEmpty
        ? 0.0
        : double.tryParse(amountText.replaceAll(',', '.')) ?? 0.0;

    final b = widget.billing ??
        Billing(
            name: '',
            amount: 0,
            dueDate: _due,
            recurring: 0,
            paid: 0);

    b
      ..name = _nameCtrl.text.trim()
      ..amount = amount
      ..dueDate = _due
      ..recurring = _recurring ? 1 : 0;

    if (b.id == null) {
      b.id = await DatabaseHelper.instance.insert(b);
    } else {
      await DatabaseHelper.instance.update(b);
    }

    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.billing == null
              ? 'Nova conta'
              : 'Editar conta')),
      body: Padding(
        padding: const EdgeInsets.all(14),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Nome'),
                validator: (v) =>
                v == null || v.isEmpty ? 'Informe o nome' : null,
              ),
              TextFormField(
                controller: _amountCtrl,
                decoration:
                const InputDecoration(labelText: 'Valor (opcional)'),
                keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9\.,]'))
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                      'Vencimento: ${DateFormat('dd/MM/yyyy').format(_due)}'),
                  const Spacer(),
                  TextButton(
                    child: const Text('Escolher'),
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _due,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (d != null) setState(() => _due = d);
                    },
                  )
                ],
              ),
              CheckboxListTile(
                title: const Text('Recorrente'),
                value: _recurring,
                onChanged: (v) => setState(() => _recurring = v!),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _save,
                child: const Text('Salvar'),
              )
            ],
          ),
        ),
      ),
    );
  }
}

*//* MODELS, DB E NOTIFICATION HELPERS
   👉 Mantidos iguais aos seus (sem alteração de lógica)
*//*

// --- Models & DB helper ---
class Billing {
  int? id;
  String name;
  double amount;
  DateTime dueDate;
  int recurring; // 0/1
  int paid; // 0/1

  Billing({this.id, required this.name, required this.amount, required this.dueDate, this.recurring = 0, this.paid = 0});

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'amount': amount,
    'dueDate': dueDate.toIso8601String(),
    'recurring': recurring,
    'paid': paid,
  };

  static Billing fromMap(Map<String, dynamic> m) => Billing(
    id: m['id'] as int?,
    name: m['name'],
    amount: (m['amount'] as num).toDouble(),
    dueDate: DateTime.parse(m['dueDate']),
    recurring: m['recurring'],
    paid: m['paid'],
  );

  static Billing copyWithNextMonth(Billing b) {
    final next = DateTime(b.dueDate.year, b.dueDate.month + 1, b.dueDate.day);
    return Billing(name: b.name, amount: b.amount, dueDate: next, recurring: b.recurring, paid: 0);
  }
}
class DatabaseHelper {
  // Singleton
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;

  // Getter que estava faltando
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  // Inicializa o banco
  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'bills.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  // Criação das tabelas
  Future _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE bills (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        amount REAL NOT NULL,
        dueDate TEXT NOT NULL,
        recurring INTEGER NOT NULL,
        paid INTEGER NOT NULL
      )
    ''');
  }

  // Métodos CRUD
  Future<int> insert(Billing b) async {
    final db = await database;
    return await db.insert('bills', b.toMap());
  }

  Future<int> update(Billing b) async {
    final db = await database;
    return await db.update(
      'bills',
      b.toMap(),
      where: 'id = ?',
      whereArgs: [b.id],
    );
  }

  Future<int> delete(int id) async {
    final db = await database;
    return await db.delete(
      'bills',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Billing>> getAll() async {
    final db = await database;
    final result = await db.query('bills', orderBy: 'dueDate ASC');
    return result.map((e) => Billing.fromMap(e)).toList();
  }
}

// --- Notifications ---
class NotificationHelper {
  static final NotificationHelper instance = NotificationHelper._();
  NotificationHelper._();
  final _plugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iOS = DarwinInitializationSettings();
    await _plugin.initialize(const InitializationSettings(android: android, iOS: iOS));
  }

  Future<void> scheduleNotificationForBilling(Billing b) async {
    if (b.paid == 1) return;

    final when = b.dueDate.subtract(const Duration(days: 5));
    if (when.isBefore(DateTime.now())) return;

    final androidDetails = AndroidNotificationDetails(
      'contas_channel',
      'Lembretes',
      importance: Importance.max,
      priority: Priority.high,
    );
    final iosDetails = DarwinNotificationDetails();

    await _plugin.zonedSchedule(
      b.id ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'Vencimento: ${b.name}',
      'Vence em ${DateFormat('dd/MM/yyyy').format(b.dueDate)} — '
          '${NumberFormat.simpleCurrency(locale: 'pt_BR').format(b.amount)}',
      tz.TZDateTime.from(when, tz.local),
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dateAndTime, // opcional
    );

  }

  Future<void> cancelNotification(int id) async => await _plugin.cancel(id);
}*/




































import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:flutter/services.dart';

import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_native_timezone/flutter_native_timezone.dart';

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

class _HomePageState extends State<HomePage> {
  List<Billing> _items = [];
  String _filter = 'Todas';

  DateTime _normalize(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final all = await DatabaseHelper.instance.getAll();
    setState(() => _items = all);
  }

  String _formatMoney(double v) =>
      NumberFormat.simpleCurrency(locale: 'pt_BR').format(v);

  Widget _buildCard(String title, List<Billing> bills, Color color) {
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
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon:
                    const Icon(Icons.edit, color: Colors.white),
                    onPressed: () async {
                      final result =
                      await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              EditPage(billing: b),
                        ),
                      );
                      if (result == true) await _reload();
                    },
                  ),
                  IconButton(
                    icon:
                    const Icon(Icons.delete, color: Colors.white),
                    onPressed: () async {
                      await DatabaseHelper.instance.delete(b.id!);
                      await _reload();
                    },
                  ),
                ],
              ),
            ))
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

    final pagas = _items.where((b) => b.paid == 1).toList();

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
            if (_filter != 'Pendentes')
              _buildCard('✅ Contas pagas', pagas, Colors.green),
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
  const EditPage({this.billing});

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
      if (widget.billing!.amount > 0) {
        _amountCtrl.text =
            widget.billing!.amount.toStringAsFixed(2);
      }
      _due = widget.billing!.dueDate;
      _recurring = widget.billing!.recurring == 1;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final amountText = _amountCtrl.text.trim();
    final amount = amountText.isEmpty
        ? 0.0
        : double.tryParse(
        amountText.replaceAll(',', '.')) ??
        0.0;

    final b = widget.billing ??
        Billing(
            name: '',
            amount: 0,
            dueDate: _due,
            recurring: 0,
            paid: 0);

    b
      ..name = _nameCtrl.text.trim()
      ..amount = amount
      ..dueDate = _due
      ..recurring = _recurring ? 1 : 0;

    if (b.id == null) {
      b.id = await DatabaseHelper.instance.insert(b);
    } else {
      await DatabaseHelper.instance.update(b);
    }

    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.billing == null
              ? 'Nova conta'
              : 'Editar conta')),
      body: Padding(
        padding: const EdgeInsets.all(14),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration:
                const InputDecoration(labelText: 'Nome'),
                validator: (v) =>
                v == null || v.isEmpty
                    ? 'Informe o nome'
                    : null,
              ),
              TextFormField(
                controller: _amountCtrl,
                decoration: const InputDecoration(
                    labelText: 'Valor (opcional)'),
                keyboardType:
                const TextInputType.numberWithOptions(
                    decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(r'[0-9\.,]'))
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                      'Vencimento: ${DateFormat('dd/MM/yyyy').format(_due)}'),
                  const Spacer(),
                  TextButton(
                    child: const Text('Escolher'),
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _due,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (d != null)
                        setState(() => _due = d);
                    },
                  )
                ],
              ),
              CheckboxListTile(
                title: const Text('Recorrente'),
                value: _recurring,
                onChanged: (v) =>
                    setState(() => _recurring = v!),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _save,
                child: const Text('Salvar'),
              )
            ],
          ),
        ),
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
  static final instance = NotificationHelper._();
  NotificationHelper._();

  final _plugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _plugin.initialize(
        const InitializationSettings(android: android, iOS: ios));
  }
}



class FilterPage extends StatefulWidget {
  const FilterPage({Key? key}) : super(key: key);

  @override
  State<FilterPage> createState() => _FilterPageState();
}

class _FilterPageState extends State<FilterPage> {
  List<Billing> _items = [];
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await DatabaseHelper.instance.getAll();
    setState(() => _items = all);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _items
        .where((b) =>
        b.name.toLowerCase().contains(_filter.toLowerCase()))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Filtrar contas'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Buscar por nome',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final b = _items[index];

                return Card(
                  color: statusColor(b).withOpacity(0.12),
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    title: Text(
                      b.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'Vence em ${DateFormat('dd/MM').format(b.dueDate)}',
                    ),
                    trailing: Text(
                      formatMoney(b.amount),
                      style: TextStyle(
                        color: statusColor(b),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
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
