// lib/screens/dashboard_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:intl/intl.dart';

import '../models/sms_log.dart';
import '../services/storage_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  bool _serverRunning = false;
  int _serverPort = 8080;
  String _localIp = '…';
  List<SmsLog> _logs = [];
  StreamSubscription? _statusSub;
  StreamSubscription? _logSub;
  StreamSubscription? _heartbeatSub;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  final _service = FlutterBackgroundService();
  final _networkInfo = NetworkInfo();

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _init();
  }

  Future<void> _init() async {
    _serverPort = await StorageService.getServerPort();
    _localIp = await _networkInfo.getWifiIP() ?? '(no WiFi)';
    _serverRunning = await _service.isRunning();
    await _loadLogs();

    // Listen to events from background isolate
    _statusSub = _service.on('serverStatus').listen((data) {
      if (data == null) return;
      setState(() {
        _serverRunning = data['running'] ?? false;
      });
    });

    _logSub = _service.on('newLog').listen((data) {
      if (data == null) return;
      final log = SmsLog.fromMap(Map<String, dynamic>.from(data));
      setState(() {
        _logs.insert(0, log);
        if (_logs.length > 50) _logs.removeLast();
      });
    });

    _heartbeatSub = _service.on('heartbeat').listen((_) async {
      final running = await _service.isRunning();
      if (mounted) setState(() => _serverRunning = running);
    });

    setState(() {});
  }

  Future<void> _loadLogs() async {
    final logs = await StorageService.getLogs();
    setState(() => _logs = logs);
  }

  Future<void> _toggleService() async {
    if (_serverRunning) {
      _service.invoke('stopService');
      await Future.delayed(const Duration(milliseconds: 500));
    } else {
      await _service.startService();
    }
    final running = await _service.isRunning();
    setState(() => _serverRunning = running);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _statusSub?.cancel();
    _logSub?.cancel();
    _heartbeatSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F1A),
      body: CustomScrollView(
        slivers: [
          _buildAppBar(),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildStatusCard(),
                const SizedBox(height: 16),
                _buildNetworkCard(),
                const SizedBox(height: 16),
                _buildStatsRow(),
                const SizedBox(height: 16),
                _buildLogsHeader(),
                const SizedBox(height: 8),
                ..._buildLogItems(),
                const SizedBox(height: 80),
              ]),
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFAB(),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 120,
      pinned: true,
      backgroundColor: const Color(0xFF0D0F1A),
      flexibleSpace: FlexibleSpaceBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6C63FF), Color(0xFF3ECFCF)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.sms_rounded, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 8),
            const Text(
              'SMS Gateway Pro',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        centerTitle: false,
      ),
    );
  }

  Widget _buildStatusCard() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: _serverRunning
                  ? [const Color(0xFF1A2B1A), const Color(0xFF0D3D1A)]
                  : [const Color(0xFF2B1A1A), const Color(0xFF3D0D0D)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: _serverRunning
                  ? const Color(0xFF00FF88).withOpacity(0.4)
                  : const Color(0xFFFF4444).withOpacity(0.4),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: _serverRunning
                    ? const Color(0xFF00FF88).withOpacity(0.15 * _pulseAnimation.value)
                    : const Color(0xFFFF4444).withOpacity(0.1),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              // Pulse dot
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _serverRunning
                      ? const Color(0xFF00FF88).withOpacity(0.15)
                      : const Color(0xFFFF4444).withOpacity(0.15),
                ),
                child: Center(
                  child: Transform.scale(
                    scale: _serverRunning ? _pulseAnimation.value : 1.0,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _serverRunning
                            ? const Color(0xFF00FF88)
                            : const Color(0xFFFF4444),
                      ),
                      child: Icon(
                        _serverRunning ? Icons.wifi_tethering : Icons.wifi_off,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _serverRunning ? 'SERVIDOR ACTIVO' : 'SERVIDOR DETENIDO',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _serverRunning
                            ? const Color(0xFF00FF88)
                            : const Color(0xFFFF4444),
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _serverRunning
                          ? 'Escuchando peticiones en el puerto $_serverPort'
                          : 'Toca el botón para iniciar el gateway',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              // Toggle switch
              GestureDetector(
                onTap: _toggleService,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 52,
                  height: 28,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: _serverRunning
                        ? const Color(0xFF00FF88)
                        : const Color(0xFF333355),
                  ),
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 300),
                    alignment: _serverRunning
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.all(3),
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNetworkCard() {
    final url = 'http://$_localIp:$_serverPort';
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: const Color(0xFF6C63FF).withOpacity(0.3),
          width: 1.5,
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lan_rounded, color: Color(0xFF6C63FF), size: 20),
              const SizedBox(width: 8),
              const Text(
                'DIRECCIÓN DEL SERVIDOR',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6C63FF),
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0D0F1A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF3ECFCF).withOpacity(0.3),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    url,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF3ECFCF),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded,
                      color: Color(0xFF3ECFCF), size: 20),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: url));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('URL copiada al portapapeles'),
                        backgroundColor: const Color(0xFF3ECFCF),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildEndpointChip('POST', '/send-sms', 'Enviar SMS'),
          const SizedBox(height: 6),
          _buildEndpointChip('GET', '/ping', 'Health check'),
        ],
      ),
    );
  }

  Widget _buildEndpointChip(String method, String path, String desc) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: method == 'POST'
                ? const Color(0xFF6C63FF).withOpacity(0.25)
                : const Color(0xFF00FF88).withOpacity(0.15),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: method == 'POST'
                  ? const Color(0xFF6C63FF)
                  : const Color(0xFF00FF88),
              width: 1,
            ),
          ),
          child: Text(
            method,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: method == 'POST'
                  ? const Color(0xFF6C63FF)
                  : const Color(0xFF00FF88),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          path,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            color: Colors.white70,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '– $desc',
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withOpacity(0.4),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsRow() {
    final successCount = _logs.where((l) => l.status == SmsStatus.success).length;
    final failCount = _logs.where((l) => l.status == SmsStatus.failed).length;
    return Row(
      children: [
        Expanded(child: _buildStatCard('Total', '${_logs.length}', Icons.message_rounded, const Color(0xFF6C63FF))),
        const SizedBox(width: 12),
        Expanded(child: _buildStatCard('Exitosos', '$successCount', Icons.check_circle_rounded, const Color(0xFF00FF88))),
        const SizedBox(width: 12),
        Expanded(child: _buildStatCard('Fallidos', '$failCount', Icons.error_rounded, const Color(0xFFFF4444))),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF1A1A2E),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'REGISTRO DE ACTIVIDAD',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.white70,
            letterSpacing: 1.5,
          ),
        ),
        TextButton.icon(
          icon: const Icon(Icons.delete_sweep_rounded, size: 16),
          label: const Text('Limpiar', style: TextStyle(fontSize: 12)),
          style: TextButton.styleFrom(
            foregroundColor: Colors.white38,
          ),
          onPressed: () async {
            await StorageService.clearLogs();
            setState(() => _logs = []);
          },
        ),
      ],
    );
  }

  List<Widget> _buildLogItems() {
    if (_logs.isEmpty) {
      return [
        Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              Icon(Icons.inbox_rounded,
                  size: 48, color: Colors.white.withOpacity(0.2)),
              const SizedBox(height: 12),
              Text(
                'Sin actividad aún',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.3),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ];
    }

    return _logs
        .map((log) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildLogItem(log),
            ))
        .toList();
  }

  Widget _buildLogItem(SmsLog log) {
    final isSuccess = log.status == SmsStatus.success;
    final statusColor = isSuccess ? const Color(0xFF00FF88) : const Color(0xFFFF4444);
    final timeStr =
        DateFormat('dd/MM HH:mm:ss').format(log.timestamp.toLocal());

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: const Color(0xFF1A1A2E),
        border: Border.all(color: statusColor.withOpacity(0.2)),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor.withOpacity(0.15),
            ),
            child: Icon(
              isSuccess ? Icons.check_rounded : Icons.close_rounded,
              color: statusColor,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      log.phone,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  log.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
                if (log.errorMessage != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '⚠ ${log.errorMessage}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFFF6B6B),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFAB() {
    return FloatingActionButton.extended(
      backgroundColor: _serverRunning
          ? const Color(0xFFFF4444)
          : const Color(0xFF6C63FF),
      onPressed: _toggleService,
      icon: Icon(_serverRunning ? Icons.stop_rounded : Icons.play_arrow_rounded),
      label: Text(_serverRunning ? 'Detener' : 'Iniciar'),
    );
  }
}
