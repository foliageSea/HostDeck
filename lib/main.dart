import 'package:flutter/material.dart';
import 'server/server_service.dart';
import 'dart:io';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final ServerService _serverService = ServerService();
  bool _isRunning = false;
  final List<String> _logs = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _startServer();
  }

  @override
  void dispose() {
    _serverService.stop();
    _scrollController.dispose();
    super.dispose();
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }

  void _addLog(String message) {
    if (!mounted) return;
    setState(() {
      final timeStr = _formatTime(DateTime.now());
      _logs.add('[$timeStr] $message');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _startServer() async {
    if (_isRunning) return;
    try {
      await _serverService.start(onLog: _addLog);
      setState(() {
        _isRunning = true;
      });
      _addLog('System: Server started successfully.');
    } catch (e) {
      _addLog('Error starting server: $e');
    }
  }

  Future<void> _stopServer() async {
    if (!_isRunning) return;
    try {
      await _serverService.stop();
      setState(() {
        _isRunning = false;
      });
      _addLog('System: Server stopped.');
    } catch (e) {
      _addLog('Error stopping server: $e');
    }
  }

  void _clearLogs() {
    setState(() {
      _logs.clear();
    });
  }

  /// Launch the GitHub repository URL in the default browser
  Future<void> _launchUrl() async {
    const url = 'https://github.com/foliageSea/ssh_tool';
    try {
      if (Platform.isWindows) {
        await Process.run('start', [url], runInShell: true);
      } else if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [url]);
      }
    } catch (e) {
      _addLog('Error launching URL: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SSH Tool Host',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('SSH Tool Host'),
          actions: [
            IconButton(
              icon: const Icon(Icons.code),
              tooltip: 'GitHub Repository',
              onPressed: _launchUrl,
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isRunning ? Colors.green : Colors.red,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isRunning ? '运行中' : '已停止',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _isRunning ? null : _startServer,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('启动服务'),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: !_isRunning ? null : _stopServer,
                    icon: const Icon(Icons.stop),
                    label: const Text('停止服务'),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: _clearLogs,
                    icon: const Icon(Icons.clear_all),
                    label: const Text('清空日志'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Container(
                width: double.infinity,
                color: Colors.black87,
                padding: const EdgeInsets.all(16.0),
                child: _logs.isEmpty
                    ? const Center(
                        child: Text(
                          '暂无日志输出...',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        itemCount: _logs.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2.0),
                            child: SelectableText(
                              _logs[index],
                              style: const TextStyle(
                                color: Colors.greenAccent,
                                fontFamily: 'consolas',
                                fontSize: 13,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
