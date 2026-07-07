import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';

import 'server/app/server_service.dart';
import 'utils/asset_extractor.dart';
import 'utils/app_settings.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化 window_manager 插件
  await windowManager.ensureInitialized();

  // 配置窗口属性 (标准 16:9 分辨率)
  WindowOptions windowOptions = const WindowOptions(
    size: Size(1280, 720),
    minimumSize: Size(960, 540),
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
    // await windowManager.maximize();
  });

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static const double _logsPanelWidth = 800.0;

  final ServerService _serverService = ServerService();
  final _log = Logger('MyApp');
  StreamSubscription<LogRecord>? _logSubscription;

  bool _isRunning = false;
  bool _showLogs = false;
  final List<String> _logs = [];
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _portController = TextEditingController();

  String get _targetUrl => kDebugMode
      ? 'http://localhost:5173'
      : 'http://localhost:${_serverService.port}';

  @override
  void initState() {
    super.initState();
    _initLogging();
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

    if (!kDebugMode) {
      final staticPath = await extractWebAssets();
      _serverService.webDir = staticPath;
    }

    await _startServer();
  }

  @override
  void dispose() {
    _logSubscription?.cancel();
    _serverService.stop();
    _scrollController.dispose();
    _portController.dispose();
    super.dispose();
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
      await _openTargetUrl();
    } catch (e) {
      _log.severe('Error starting server: $e');
    }
  }

  Future<void> _openTargetUrl() async {
    final uri = Uri.parse(_targetUrl);
    if (!await canLaunchUrl(uri)) {
      _log.warning('Cannot launch $_targetUrl.');
      return;
    }

    await launchUrl(uri, mode: LaunchMode.externalApplication);
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

  /// 构建自绘窗口标题栏 (MacOS 风格)
  Widget _buildTitleBar(BuildContext context) {
    // 强制暗黑模式背景色和主题颜色
    final backgroundColor = const Color(0xFF1E1E1E); // 暗黑模式背景色
    final textColor = Colors.white;
    final primaryColor = Colors.deepPurple.shade200;

    return DragToMoveArea(
      child: Container(
        height: 40,
        color: backgroundColor,
        child: Stack(
          children: [
            // 左侧：MacOS 风格交通灯窗口控制按钮
            Positioned(
              left: 16,
              top: 0,
              bottom: 0,
              child: Center(
                child: _MacWindowButtonRow(
                  onClose: () => windowManager.close(),
                  onMinimize: () => windowManager.minimize(),
                  onMaximize: () async {
                    if (await windowManager.isMaximized()) {
                      windowManager.unmaximize();
                    } else {
                      windowManager.maximize();
                    }
                  },
                ),
              ),
            ),
            // 中间：应用图标和居中标题
            Align(
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.terminal, size: 18, color: primaryColor),
                  const SizedBox(width: 8),
                  Text(
                    'HostDeck',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: textColor,
                    ),
                  ),
                ],
              ),
            ),
            // 右侧：Host Logs 操作按钮
            Positioned(
              right: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: IconButton(
                  icon: const Icon(Icons.receipt_long, size: 18),
                  color: Colors.white70,
                  hoverColor: Colors.white12,
                  splashRadius: 20,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  tooltip: 'Host Logs',
                  onPressed: () {
                    setState(() {
                      _showLogs = !_showLogs;
                    });
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLauncherBody() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: const Color(0xFF121212),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.dns_outlined,
                  size: 56,
                  color: _isRunning ? Colors.greenAccent : Colors.white54,
                ),
                const SizedBox(height: 20),
                Text(
                  _isRunning ? 'HostDeck 服务已启动' : 'HostDeck 正在启动',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _isRunning ? _targetUrl : '请稍候，正在准备本地服务...',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white60, fontSize: 14),
                ),
                const SizedBox(height: 28),
                ElevatedButton.icon(
                  onPressed: _isRunning ? _openTargetUrl : null,
                  icon: const Icon(Icons.open_in_browser),
                  label: const Text('打开 HostDeck'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.deepPurple.shade400,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.white10,
                    disabledForegroundColor: Colors.white38,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _showLogs = true;
                    });
                  },
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('查看日志'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HostDeck',
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
      themeMode: ThemeMode.dark, // 默认使用暗黑模式
      home: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _buildTitleBar(context),
              Expanded(
                child: Stack(
                  children: [
                    _buildLauncherBody(),
                    // Logs Overlay
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      top: 0,
                      bottom: 0,
                      right: _showLogs
                          ? 0
                          : -(MediaQuery.of(context).size.width >
                                    _logsPanelWidth
                                ? _logsPanelWidth
                                : MediaQuery.of(context).size.width),
                      width: MediaQuery.of(context).size.width > _logsPanelWidth
                          ? _logsPanelWidth
                          : MediaQuery.of(context).size.width,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF1E1E1E,
                          ).withValues(alpha: 0.98),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 16,
                              offset: const Offset(-4, 0),
                            ),
                          ],
                          border: Border(
                            left: BorderSide(
                              color: Colors.white.withValues(alpha: 0.1),
                              width: 1,
                            ),
                          ),
                        ),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16.0,
                                vertical: 12.0,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(
                                        Icons.terminal,
                                        color: Colors.white70,
                                        size: 20,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Host Logs',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.close,
                                      color: Colors.white70,
                                      size: 20,
                                    ),
                                    splashRadius: 20,
                                    onPressed: () {
                                      setState(() {
                                        _showLogs = false;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1, color: Colors.white12),
                            Expanded(
                              child: _logs.isEmpty
                                  ? const Center(
                                      child: Text(
                                        '暂无日志...',
                                        style: TextStyle(color: Colors.white38),
                                      ),
                                    )
                                  : ListView.builder(
                                      controller: _scrollController,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8.0,
                                      ),
                                      itemCount: _logs.length,
                                      itemBuilder: (context, index) {
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16.0,
                                            vertical: 2.0,
                                          ),
                                          child: SelectableText(
                                            _logs[index],
                                            style: const TextStyle(
                                              color: Color(0xFF4AF626),
                                              fontFamily: 'Consolas',
                                              fontFamilyFallback: [
                                                'Courier New',
                                                'monospace',
                                              ],
                                              fontSize: 13,
                                              height: 1.4,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                            const Divider(height: 1, color: Colors.white12),
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      const Text(
                                        '端口: ',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 80,
                                        child: TextField(
                                          controller: _portController,
                                          enabled: !_isRunning,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                          ),
                                          decoration: InputDecoration(
                                            isDense: true,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 10,
                                                ),
                                            filled: true,
                                            fillColor: Colors.white.withValues(
                                              alpha: 0.05,
                                            ),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              borderSide: BorderSide.none,
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              borderSide: const BorderSide(
                                                color: Colors.white24,
                                              ),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              borderSide: const BorderSide(
                                                color: Colors.blueAccent,
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
                                      OutlinedButton.icon(
                                        onPressed: _clearLogs,
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          size: 16,
                                        ),
                                        label: const Text('清空'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.white70,
                                          side: const BorderSide(
                                            color: Colors.white24,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      onPressed: _isRunning
                                          ? _stopServer
                                          : _startServer,
                                      icon: Icon(
                                        _isRunning
                                            ? Icons.stop
                                            : Icons.play_arrow,
                                      ),
                                      label: Text(
                                        _isRunning ? '停止服务' : '启动服务',
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _isRunning
                                            ? Colors.redAccent.shade400
                                            : Colors.green.shade600,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 16,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        elevation: 0,
                                      ),
                                    ),
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
      ),
    );
  }
}

/// MacOS 风格的交通灯控制按钮组组件
class _MacWindowButtonRow extends StatefulWidget {
  final VoidCallback onClose;
  final VoidCallback onMinimize;
  final VoidCallback onMaximize;

  const _MacWindowButtonRow({
    required this.onClose,
    required this.onMinimize,
    required this.onMaximize,
  });

  @override
  State<_MacWindowButtonRow> createState() => _MacWindowButtonRowState();
}

class _MacWindowButtonRowState extends State<_MacWindowButtonRow> {
  bool _isHovering = false;

  /// 构建单个交通灯按钮
  Widget _buildButton(Color color, IconData icon, VoidCallback onTap) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.black.withValues(alpha: 0.2),
              width: 0.5,
            ),
          ),
          child: _isHovering
              ? Icon(icon, size: 8, color: Colors.black.withValues(alpha: 0.6))
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 红色关闭按钮
          _buildButton(const Color(0xFFFF5F56), Icons.close, widget.onClose),
          const SizedBox(width: 8),
          // 黄色最小化按钮
          _buildButton(
            const Color(0xFFFFBD2E),
            Icons.remove,
            widget.onMinimize,
          ),
          const SizedBox(width: 8),
          // 绿色最大化/还原按钮
          _buildButton(
            const Color(0xFF27C93F),
            Icons.open_in_full,
            widget.onMaximize,
          ),
        ],
      ),
    );
  }
}
