import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Photo Locker',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
            colorSchemeSeed: Colors.indigo, useMaterial3: true),
        home: const LockScreen(),
      );
}

String hashPass(String p) =>
    sha256.convert(utf8.encode('pl_salt_$p')).toString();

Future<Directory> vaultDir() async {
  final d = await getApplicationDocumentsDirectory();
  final v = Directory('${d.path}/vault');
  if (!await v.exists()) await v.create(recursive: true);
  return v;
}

// ---------------- PASSWORD SCREEN ----------------
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final ctrl = TextEditingController();
  String? saved;
  bool loading = true;
  String error = '';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      setState(() {
        saved = p.getString('pass');
        loading = false;
      });
    });
  }

  Future<void> submit() async {
    final text = ctrl.text;
    if (text.length < 4) {
      setState(() => error = 'Kam az kam 4 characters rakho');
      return;
    }
    if (saved == null) {
      final p = await SharedPreferences.getInstance();
      await p.setString('pass', hashPass(text));
      saved = hashPass(text);
      open();
    } else if (saved == hashPass(text)) {
      open();
    } else {
      setState(() => error = 'Galat password');
    }
  }

  void open() {
    ctrl.clear();
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const HomeScreen()));
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final first = saved == null;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock, size: 70),
              const SizedBox(height: 16),
              Text(first ? 'Naya password set karo' : 'Password dalo',
                  style: const TextStyle(fontSize: 20)),
              const SizedBox(height: 20),
              TextField(
                controller: ctrl,
                obscureText: true,
                onSubmitted: (_) => submit(),
                decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: 'Password',
                    errorText: error.isEmpty ? null : error),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                    onPressed: submit,
                    child: Text(first ? 'Set karo' : 'Kholo')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- HOME (VAULT) ----------------
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<File> files = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final v = await vaultDir();
    final list = v.listSync().whereType<File>().toList();
    list.sort((a, b) => b.path.compareTo(a.path));
    setState(() => files = list);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Locked Photos')),
      body: files.isEmpty
          ? const Center(child: Text('Abhi koi photo lock nahi hai.\n+ dabao'))
          : GridView.builder(
              padding: const EdgeInsets.all(4),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, mainAxisSpacing: 4, crossAxisSpacing: 4),
              itemCount: files.length,
              itemBuilder: (_, i) => GestureDetector(
                onTap: () async {
                  final changed = await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => ViewScreen(file: files[i])));
                  if (changed == true) load();
                },
                child: Image.file(files[i],
                    fit: BoxFit.cover, cacheWidth: 300),
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final changed = await Navigator.push(context,
              MaterialPageRoute(builder: (_) => const PickScreen()));
          if (changed == true) load();
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ---------------- PHOTO VIEW / UNLOCK ----------------
class ViewScreen extends StatelessWidget {
  final File file;
  const ViewScreen({super.key, required this.file});

  Future<void> unlock(BuildContext context) async {
    final name = file.path.split('/').last;
    final bytes = await file.readAsBytes();
    final saved =
        await PhotoManager.editor.saveImage(bytes, filename: name);
    if (saved != null) {
      await file.delete();
      if (context.mounted) Navigator.pop(context, true);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Unlock nahi hua')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Photo'),
        actions: [
          IconButton(
            tooltip: 'Gallery mein wapas',
            icon: const Icon(Icons.lock_open),
            onPressed: () => unlock(context),
          ),
          IconButton(
            tooltip: 'Hamesha ke liye delete',
            icon: const Icon(Icons.delete),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Delete?'),
                  content: const Text('Ye photo hamesha ke liye delete ho jayegi.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('Nahi')),
                    TextButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('Haan')),
                  ],
                ),
              );
              if (ok == true) {
                await file.delete();
                if (context.mounted) Navigator.pop(context, true);
              }
            },
          ),
        ],
      ),
      body: Center(child: InteractiveViewer(child: Image.file(file))),
    );
  }
}

// ---------------- GALLERY SE PHOTO CHUNNA ----------------
class PickScreen extends StatefulWidget {
  const PickScreen({super.key});
  @override
  State<PickScreen> createState() => _PickScreenState();
}

class _PickScreenState extends State<PickScreen> {
  List<AssetEntity> assets = [];
  final Set<String> selected = {};
  bool loading = true;
  bool working = false;
  String msg = '';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final perm = await PhotoManager.requestPermissionExtend();
    if (!perm.hasAccess) {
      setState(() {
        loading = false;
        msg = 'Gallery ki permission do (Settings mein)';
      });
      return;
    }
    final albums = await PhotoManager.getAssetPathList(
        type: RequestType.image, onlyAll: true);
    if (albums.isNotEmpty) {
      final list = await albums.first.getAssetListPaged(page: 0, size: 500);
      assets = list;
    }
    setState(() => loading = false);
  }

  Future<void> lockSelected() async {
    setState(() => working = true);
    final v = await vaultDir();
    final doneIds = <String>[];

    for (final a in assets.where((x) => selected.contains(x.id))) {
      try {
        final f = await a.originFile;
        if (f == null) continue;
        final ext = f.path.contains('.') ? f.path.split('.').last : 'jpg';
        final safeId = a.id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
        final dest =
            '${v.path}/${DateTime.now().millisecondsSinceEpoch}_$safeId.$ext';
        final copy = await f.copy(dest);
        // delete sirf tab jab copy sahi ho
        if (await copy.length() == await f.length()) {
          doneIds.add(a.id);
        } else {
          await copy.delete();
        }
      } catch (_) {}
    }

    if (doneIds.isNotEmpty) {
      await PhotoManager.editor.deleteWithIds(doneIds);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(selected.isEmpty
            ? 'Photos chuno'
            : '${selected.length} selected'),
        actions: [
          if (selected.isNotEmpty && !working)
            IconButton(
                icon: const Icon(Icons.lock), onPressed: lockSelected),
        ],
      ),
      body: loading || working
          ? const Center(child: CircularProgressIndicator())
          : assets.isEmpty
              ? Center(child: Text(msg.isEmpty ? 'Koi photo nahi mili' : msg))
              : GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 2,
                      crossAxisSpacing: 2),
                  itemCount: assets.length,
                  itemBuilder: (_, i) {
                    final a = assets[i];
                    final sel = selected.contains(a.id);
                    return GestureDetector(
                      onTap: () => setState(() {
                        sel ? selected.remove(a.id) : selected.add(a.id);
                      }),
                      child: Stack(fit: StackFit.expand, children: [
                        FutureBuilder(
                          future: a.thumbnailDataWithSize(
                              const ThumbnailSize(250, 250)),
                          builder: (_, snap) => snap.data == null
                              ? Container(color: Colors.grey.shade300)
                              : Image.memory(snap.data!, fit: BoxFit.cover),
                        ),
                        if (sel)
                          Container(
                            color: Colors.black45,
                            child: const Icon(Icons.check_circle,
                                color: Colors.white, size: 36),
                          ),
                      ]),
                    );
                  },
                ),
    );
  }
}
