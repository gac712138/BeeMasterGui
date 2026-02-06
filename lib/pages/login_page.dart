// lib/pages/login_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../app_state.dart';
import '../config.dart';

class LoginPage extends StatefulWidget {
  final VoidCallback onLoginSuccess;
  const LoginPage({super.key, required this.onLoginSuccess});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // 預填帳密 (方便測試)
  final _opsEmailCtrl = TextEditingController(text: "tw.ro@beeinventor.com");
  final _opsPwdCtrl = TextEditingController(text: "12345678");

  final _dsmEmailCtrl = TextEditingController(text: "tw.ro@beeinventor.com");
  final _dsmPwdCtrl = TextEditingController(text: "12345678");

  bool _isOpsLoading = false;
  bool _isDsmLoading = false;

  // --- Keycloak 登入核心 ---
  Future<String?> _performKeycloakLogin(
    String clientId,
    String username,
    String password,
  ) async {
    try {
      debugPrint("🚀 連線到: ${ApiConfig.tokenUrl}");
      debugPrint("🔑 Client ID: $clientId");

      final Map<String, String> formData = {
        'username': username,
        'password': password,
        'client_id': clientId,
        'grant_type': 'password',
      };

      final response = await http.post(
        Uri.parse(ApiConfig.tokenUrl),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: formData,
      );

      debugPrint("📡 狀態碼: ${response.statusCode}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint("✅ 登入成功！");
        return data['access_token'];
      } else {
        debugPrint("❌ 登入失敗: ${response.body}");
        return null;
      }
    } catch (e) {
      debugPrint("❌ 網路錯誤: $e");
      return null;
    }
  }

  Future<void> _loginOps() async {
    setState(() => _isOpsLoading = true);
    final token = await _performKeycloakLogin(
      ApiConfig.opsClientId,
      _opsEmailCtrl.text,
      _opsPwdCtrl.text,
    );
    _finishOpsLogin(token);
  }

  void _finishOpsLogin(String? token) {
    setState(() => _isOpsLoading = false);
    if (token != null) {
      AppState.opsToken = token;
      AppState.opsEmail = _opsEmailCtrl.text;
      widget.onLoginSuccess();
      _showMsg("✅ OPS 平台登入成功", Colors.green);
    } else {
      _showMsg("❌ OPS 登入失敗", Colors.red);
    }
  }

  Future<void> _loginDsm() async {
    setState(() => _isDsmLoading = true);
    final token = await _performKeycloakLogin(
      ApiConfig.dsmClientId,
      _dsmEmailCtrl.text,
      _dsmPwdCtrl.text,
    );
    _finishDsmLogin(token);
  }

  void _finishDsmLogin(String? token) {
    setState(() => _isDsmLoading = false);
    if (token != null) {
      AppState.dsmToken = token;
      AppState.dsmEmail = _dsmEmailCtrl.text;
      widget.onLoginSuccess();
      _showMsg("✅ DSM 登入成功", Colors.green);
    } else {
      _showMsg("❌ DSM 登入失敗", Colors.red);
    }
  }

  void _showMsg(String msg, Color color) {
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  void _logoutOpsAction() {
    AppState.logoutOps();
    widget.onLoginSuccess();
    setState(() {});
  }

  void _logoutDsmAction() {
    AppState.logoutDsm();
    widget.onLoginSuccess();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _buildDarkLoginForm(
            title: "BeeInventor",
            subTitle: "Partner", // OPS
            emailCtrl: _opsEmailCtrl,
            pwdCtrl: _opsPwdCtrl,
            onLogin: _loginOps,
            onLogout: _logoutOpsAction,
            isLoggedIn: AppState.isOpsLoggedIn,
            isLoading: _isOpsLoading,
            token: AppState.opsToken,
          ),
        ),
        const SizedBox(width: 40),
        Expanded(
          child: _buildDarkLoginForm(
            title: "Digital Site Manager",
            subTitle: "", // DSM
            emailCtrl: _dsmEmailCtrl,
            pwdCtrl: _dsmPwdCtrl,
            onLogin: _loginDsm,
            onLogout: _logoutDsmAction,
            isLoggedIn: AppState.isDsmLoggedIn,
            isLoading: _isDsmLoading,
            token: AppState.dsmToken,
          ),
        ),
      ],
    );
  }

  Widget _buildDarkLoginForm({
    required String title,
    required String subTitle,
    required TextEditingController emailCtrl,
    required TextEditingController pwdCtrl,
    required VoidCallback onLogin,
    required VoidCallback onLogout,
    required bool isLoggedIn,
    required bool isLoading,
    String? token,
  }) {
    const Color cardBg = Color(0xFF333333);
    const Color inputBg = Color(0xFF424242);
    const Color beeYellow = Color(0xFFFFA000);
    const Color textColor = Colors.white;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.hexagon_outlined, size: 50, color: beeYellow),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: textColor,
              letterSpacing: 1.2,
            ),
          ),
          if (subTitle.isNotEmpty)
            Text(
              subTitle,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: beeYellow,
                letterSpacing: 1.0,
              ),
            ),
          const SizedBox(height: 40),

          if (isLoggedIn) ...[
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 10),
                  Text(
                    "已登入 / Authorized",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              "Token: ${(token ?? '').length > 20 ? (token?.substring(0, 20) ?? '') + '...' : token}",
              style: TextStyle(
                color: Colors.grey[400],
                fontFamily: 'monospace',
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 45,
              child: OutlinedButton(
                onPressed: onLogout,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.grey),
                  foregroundColor: Colors.white,
                ),
                child: const Text("登出 (Logout)"),
              ),
            ),
          ] else ...[
            TextField(
              controller: emailCtrl,
              style: const TextStyle(color: Colors.white),
              cursorColor: beeYellow,
              decoration: InputDecoration(
                hintText: "Email",
                hintStyle: TextStyle(color: Colors.grey[400]),
                filled: true,
                fillColor: inputBg,
                prefixIcon: Icon(
                  Icons.email,
                  color: Colors.grey[400],
                  size: 20,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: pwdCtrl,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              cursorColor: beeYellow,
              decoration: InputDecoration(
                hintText: "Password",
                hintStyle: TextStyle(color: Colors.grey[400]),
                filled: true,
                fillColor: inputBg,
                prefixIcon: Icon(Icons.lock, color: Colors.grey[400], size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 45,
              child: ElevatedButton(
                onPressed: isLoading ? null : onLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: beeYellow,
                  foregroundColor: Colors.black87,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
                child: isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.black87,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        "Login",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
