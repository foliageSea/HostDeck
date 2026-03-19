import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:window_manager/window_manager.dart';
import 'package:logging/logging.dart';
import 'server/server_service.dart';
import 'utils/app_settings.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化 window_manager 插件
  await windowManager.ensureInitialized();

  // 配置窗口属性 (调整为标准的 16:9 分辨率)
  WindowOptions windowOptions = const WindowOptions(
    size: Size(1280, 720),
    minimumSize: Size(1280, 720),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden, // 隐藏原生标题栏
  );

  // 等待窗口准备就绪后显示，避免白屏闪烁
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setAspectRatio(16 / 9); // 锁定窗口比例为 16:9
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WindowListener {
  final ServerService _serverService = ServerService();
  final _log = Logger('MyApp');
  StreamSubscription<LogRecord>? _logSubscription;

  bool _isRunning = false;
  bool _showLogs = false;
  bool _isMaximized = false; // 记录窗口最大化状态
  final List<String> _logs = [];
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _portController = TextEditingController();
  InAppWebViewController? webViewController;

  String get _targetUrl => kDebugMode
      ? 'http://localhost:5173'
      : 'http://localhost:${_serverService.port}';

  @override
  void initState() {
    super.initState();
    _initLogging();
    windowManager.addListener(this);
    _initWindowManager();
    _initServer();
  }

  void _initLogging() {
    Logger.root.level = Level.ALL;
    _logSubscription = Logger.root.onRecord.listen((record) {
      final msg =
          '[${record.level.name}] [${record.loggerName}]: ${record.message}';
      final errorMsg = record.error != null ? '\nError: ${record.error}' : '';
      final stackTraceMsg = record.stackTrace != null
          ? '\n${record.stackTrace}'
          : '';

      final fullMsg = '$msg$errorMsg$stackTraceMsg';

      // 输出到控制台
      debugPrint(fullMsg);
      // 输出到 UI
      _addLog(fullMsg);
    });
  }

  Future<void> _initServer() async {
    final port = await AppSettings.getPort();
    _serverService.port = port;
    _portController.text = port.toString();
    await _startServer();
  }

  /// 初始化 window_manager 并获取初始最大化状态
  void _initWindowManager() async {
    _isMaximized = await windowManager.isMaximized();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _logSubscription?.cancel();
    windowManager.removeListener(this);
    _serverService.stop();
    _scrollController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    setState(() {
      _isMaximized = true;
    });
  }

  @override
  void onWindowUnmaximize() {
    setState(() {
      _isMaximized = false;
    });
  }

  /// 格式化时间，用于日志输出
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
      await _serverService.start();
      setState(() {
        _isRunning = true;
      });
      _log.info('Server started successfully on port ${_serverService.port}.');
      if (webViewController != null && !kDebugMode) {
        webViewController?.loadUrl(
          urlRequest: URLRequest(url: WebUri(_targetUrl)),
        );
      }
    } catch (e) {
      _log.severe('Error starting server: $e');
    }
  }

  Future<void> _stopServer() async {
    if (!_isRunning) return;
    try {
      await _serverService.stop();
      setState(() {
        _isRunning = false;
      });
      _log.info('Server stopped.');
    } catch (e) {
      _log.severe('Error stopping server: $e');
    }
  }

  void _clearLogs() {
    setState(() {
      _logs.clear();
    });
  }

  /// 构建自定义窗口控制按钮
  Widget _buildWindowButton({
    required IconData icon,
    required VoidCallback onTap,
    required bool isDark,
    bool isClose = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: isClose
            ? Colors.red
            : (isDark ? Colors.white12 : Colors.black12),
        child: Container(
          width: 46,
          height: 40,
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 16,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
      ),
    );
  }

  /// 构建自绘窗口标题栏
  Widget _buildTitleBar(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return DragToMoveArea(
      child: Container(
        height: 40,
        color: theme.scaffoldBackgroundColor, // 跟随系统主题背景色
        child: Row(
          children: [
            const SizedBox(width: 16),
            Icon(Icons.terminal, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              'SSH Tool',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: theme.textTheme.bodyLarge?.color,
              ),
            ),
            const Spacer(),
            // 最小化按钮
            _buildWindowButton(
              icon: Icons.remove,
              onTap: () => windowManager.minimize(),
              isDark: isDark,
            ),
            // 最大化/还原按钮
            _buildWindowButton(
              icon: _isMaximized ? Icons.filter_none : Icons.crop_square,
              onTap: () async {
                if (await windowManager.isMaximized()) {
                  windowManager.unmaximize();
                } else {
                  windowManager.maximize();
                }
              },
              isDark: isDark,
            ),
            // 关闭按钮
            _buildWindowButton(
              icon: Icons.close,
              onTap: () => windowManager.close(),
              isDark: isDark,
              isClose: true,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SSH Tool',
      debugShowCheckedModeBanner: false,
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
        body: SafeArea(
          child: Column(
            children: [
              _buildTitleBar(context),
              Expanded(
                child: Stack(
                  children: [
                    if (!_isRunning)
                      const Center(child: CircularProgressIndicator())
                    else
                      InAppWebView(
                        initialUrlRequest: URLRequest(url: WebUri(_targetUrl)),
                        initialSettings: InAppWebViewSettings(
                          javaScriptEnabled: true,
                          transparentBackground: true,
                          disableContextMenu: true,
                          isInspectable: kDebugMode,
                        ),
                        onWebViewCreated: (controller) {
                          webViewController = controller;
                        },
                        onReceivedError: (controller, request, error) {
                          _log.severe('WebView Error: ${error.description}');
                        },
                        onConsoleMessage: (controller, consoleMessage) {
                          _log.info('WebView: ${consoleMessage.message}');
                        },
                      ),
                    // Logs Overlay
                    if (_showLogs)
                      Positioned(
                        top: 0,
                        right: 0,
                        bottom: 0,
                        width: MediaQuery.of(context).size.width > 400
                            ? 400
                            : MediaQuery.of(context).size.width,
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.9),
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Host Logs',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.close,
                                        color: Colors.white,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _showLogs = false;
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(color: Colors.grey),
                              Expanded(
                                child: _logs.isEmpty
                                    ? const Center(
                                        child: Text(
                                          '暂无日志...',
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                      )
                                    : ListView.builder(
                                        controller: _scrollController,
                                        itemCount: _logs.length,
                                        itemBuilder: (context, index) {
                                          return Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8.0,
                                              vertical: 2.0,
                                            ),
                                            child: SelectableText(
                                              _logs[index],
                                              style: const TextStyle(
                                                color: Colors.greenAccent,
                                                fontFamily: 'consolas',
                                                fontSize: 12,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        const Text(
                                          '端口: ',
                                          style: TextStyle(color: Colors.white),
                                        ),
                                        SizedBox(
                                          width: 80,
                                          child: TextField(
                                            controller: _portController,
                                            enabled: !_isRunning,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                            ),
                                            decoration: const InputDecoration(
                                              isDense: true,
                                              contentPadding:
                                                  EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 8,
                                                  ),
                                              border: OutlineInputBorder(),
                                              enabledBorder: OutlineInputBorder(
                                                borderSide: BorderSide(
                                                  color: Colors.grey,
                                                ),
                                              ),
                                            ),
                                            keyboardType: TextInputType.number,
                                            onChanged: (value) {
                                              final port = int.tryParse(value);
                                              if (port != null &&
                                                  port > 0 &&
                                                  port < 65536) {
                                                _serverService.port = port;
                                                AppSettings.savePort(port);
                                              }
                                            },
                                          ),
                                        ),
                                        const Spacer(),
                                        OutlinedButton(
                                          onPressed: _clearLogs,
                                          child: const Text('清空'),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: ElevatedButton(
                                            onPressed: _isRunning
                                                ? _stopServer
                                                : _startServer,
                                            child: Text(
                                              _isRunning ? '停止服务' : '启动服务',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: _showLogs
            ? null
            : FloatingActionButton(
                mini: true,
                backgroundColor: Colors.black54,
                child: const Icon(Icons.terminal, color: Colors.white),
                onPressed: () {
                  setState(() {
                    _showLogs = true;
                  });
                },
              ),
      ),
    );
  }
}
