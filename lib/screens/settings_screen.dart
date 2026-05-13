// lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/storage_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _apiKeyController = TextEditingController();
  final _portController = TextEditingController();
  bool _apiKeyVisible = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _apiKeyController.text = await StorageService.getApiKey();
    _portController.text = (await StorageService.getServerPort()).toString();
    setState(() {});
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final apiKey = _apiKeyController.text.trim();
    final portStr = _portController.text.trim();
    final port = int.tryParse(portStr);

    if (apiKey.isEmpty) {
      _showSnack('El API Key no puede estar vacío', isError: true);
      setState(() => _saving = false);
      return;
    }
    if (port == null || port < 1024 || port > 65535) {
      _showSnack('Puerto inválido (1024–65535)', isError: true);
      setState(() => _saving = false);
      return;
    }

    await StorageService.setApiKey(apiKey);
    await StorageService.setServerPort(port);
    setState(() => _saving = false);
    _showSnack('✅ Configuración guardada. Reinicia el servidor para aplicar cambios.');
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? const Color(0xFFFF4444) : const Color(0xFF00CC66),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0F1A),
        title: const Text('Configuración',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('SEGURIDAD', Icons.security_rounded),
            const SizedBox(height: 12),
            _buildApiKeyCard(),
            const SizedBox(height: 24),
            _buildSectionHeader('SERVIDOR', Icons.dns_rounded),
            const SizedBox(height: 12),
            _buildPortCard(),
            const SizedBox(height: 24),
            _buildSectionHeader('USO - cURL EJEMPLO', Icons.code_rounded),
            const SizedBox(height: 12),
            _buildCurlExample(),
            const SizedBox(height: 24),
            _buildSectionHeader('USO - PHP EJEMPLO', Icons.code_rounded),
            const SizedBox(height: 12),
            _buildPhpExample(),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.save_rounded),
                label: Text(_saving ? 'Guardando…' : 'Guardar cambios'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF6C63FF), size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF6C63FF),
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildApiKeyCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('API Key',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 8),
          TextField(
            controller: _apiKeyController,
            obscureText: !_apiKeyVisible,
            style: const TextStyle(
                color: Colors.white, fontFamily: 'monospace', fontSize: 14),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF0D0F1A),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                    color: const Color(0xFF6C63FF).withOpacity(0.3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: Color(0xFF6C63FF), width: 1.5),
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      _apiKeyVisible
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      color: Colors.white38,
                    ),
                    onPressed: () =>
                        setState(() => _apiKeyVisible = !_apiKeyVisible),
                  ),
                  IconButton(
                    icon:
                        const Icon(Icons.copy_rounded, color: Colors.white38),
                    onPressed: () {
                      Clipboard.setData(
                          ClipboardData(text: _apiKeyController.text));
                      _showSnack('API Key copiado');
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Envía este key en el header X-API-Key de cada petición.',
            style: TextStyle(
                color: Colors.white.withOpacity(0.4), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildPortCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Puerto del servidor',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 8),
          TextField(
            controller: _portController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(color: Colors.white, fontSize: 16),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF0D0F1A),
              prefixIcon:
                  const Icon(Icons.settings_ethernet, color: Colors.white38),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                    color: const Color(0xFF6C63FF).withOpacity(0.3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: Color(0xFF6C63FF), width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Por defecto: 8080. Rango válido: 1024–65535.',
            style: TextStyle(
                color: Colors.white.withOpacity(0.4), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildCurlExample() {
    final key = _apiKeyController.text.isEmpty
        ? 'TU_API_KEY'
        : _apiKeyController.text;
    final curl = '''curl -X POST http://TU_IP:8080/send-sms \\
  -H "Content-Type: application/json" \\
  -H "X-API-Key: $key" \\
  -d '{"phone": "+52987654321", "message": "Hola desde el gateway!"}'
''';
    return _codeCard(curl);
  }

  Widget _buildPhpExample() {
    final key = _apiKeyController.text.isEmpty
        ? 'TU_API_KEY'
        : _apiKeyController.text;
    final php = '''<?php
\$url     = 'http://TU_IP:8080/send-sms';
\$apiKey  = '$key';
\$payload = json_encode([
    'phone'   => '+52987654321',
    'message' => 'Tu código es: 4821',
]);

\$ch = curl_init(\$url);
curl_setopt_array(\$ch, [
    CURLOPT_POST           => true,
    CURLOPT_POSTFIELDS     => \$payload,
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_HTTPHEADER     => [
        'Content-Type: application/json',
        'X-API-Key: ' . \$apiKey,
    ],
]);
\$response = curl_exec(\$ch);
curl_close(\$ch);
echo \$response;
''';
    return _codeCard(php);
  }

  Widget _codeCard(String code) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D0F1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.25)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: code));
                  _showSnack('Código copiado');
                },
                child: Row(
                  children: [
                    const Icon(Icons.copy_rounded,
                        size: 14, color: Colors.white38),
                    const SizedBox(width: 4),
                    Text('Copiar',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withOpacity(0.3))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            code,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: Color(0xFF3ECFCF),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }
}
