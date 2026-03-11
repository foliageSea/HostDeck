import 'package:flutter/material.dart';
import 'server/server_service.dart';

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

  @override
  void initState() {
    super.initState();
    _serverService.start();
  }

  @override
  void dispose() {
    _serverService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SSH Tool Host',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('SSH Tool Host')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Text('Server is running on port 8080'),
              Text('Access http://localhost:5173 for UI'),
            ],
          ),
        ),
      ),
    );
  }
}
