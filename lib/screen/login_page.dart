import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart'; // 記得在 pubspec.yaml 加入這個
import 'package:beemaster_ui/utils/app_state.dart';
import 'package:beemaster_ui/utils/config.dart';

// 定義一個簡單的帳號資料結構
class SavedAccount {
  final String email;
  final String password;
  SavedAccount(this.email, this.password);

  Map<String, dynamic> toJson() => {'email': email, 'password': password};

  factory SavedAccount.fromJson(Map<String, dynamic> json) {
    return SavedAccount(json['email'], json['password']);
  }
}

class LoginPage extends StatefulWidget {
  final VoidCallback onLoginSuccess;
  const LoginPage({super.key, required this.onLoginSuccess});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // 1. 移除預設帳密 (清空 text)
  final _opsEmailCtrl = TextEditingController();
  final _opsPwdCtrl = TextEditingController();

  final _dsmEmailCtrl = TextEditingController();
  final _dsmPwdCtrl = TextEditingController();

  bool _isOpsLoading = false;
  bool _isDsmLoading = false;

  // 用來儲存歷史帳號列表 (Key: "ops_accounts" / "dsm_accounts")
  List<SavedAccount> _savedOpsAccounts = [];
  List<SavedAccount> _savedDsmAccounts = [];

  @override
  void initState() {
    super.initState();
    _loadSavedAccounts(); // 啟動時讀取紀錄
  }

  // --- 讀取歷史帳號 ---
  Future<void> _loadSavedAccounts() async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      _savedOpsAccounts = _parseAccounts(prefs.getString('ops_accounts'));
      _savedDsmAccounts = _parseAccounts(prefs.getString('dsm_accounts'));
    });
  }

  List<SavedAccount> _parseAccounts(String? jsonString) {
    if (jsonString == null) return [];
    try {
      final List<dynamic> list = jsonDecode(jsonString);
      return list.map((e) => SavedAccount.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  // --- 儲存帳號 ---
  Future<void> _saveAccountLocal(String key, String email, String pwd) async {
    final prefs = await SharedPreferences.getInstance();
    List<SavedAccount> currentList = key == 'ops_accounts'
        ? _savedOpsAccounts
        : _savedDsmAccounts;

    // 檢查是否已存在 (若有則更新密碼，若無則新增)
    final index = currentList.indexWhere((acc) => acc.email == email);
    if (index >= 0) {
      currentList[index] = SavedAccount(email, pwd);
    } else {
      currentList.add(SavedAccount(email, pwd));
    }

    // 存回硬碟
    final String jsonString = jsonEncode(
      currentList.map((e) => e.toJson()).toList(),
    );
    await prefs.setString(key, jsonString);

    // 更新 UI 下拉選單
    setState(() {
      if (key == 'ops_accounts')
        _savedOpsAccounts = currentList;
      else
        _savedDsmAccounts = currentList;
    });
  }

  // --- Keycloak 登入核心 ---
  Future<String?> _performKeycloakLogin(
    String clientId,
    String username,
    String password,
  ) async {
    try {
      // debugPrint("🚀 連線到: ${ApiConfig.tokenUrl}");
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

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
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
    final email = _opsEmailCtrl.text;
    final pwd = _opsPwdCtrl.text;

    final token = await _performKeycloakLogin(
      ApiConfig.opsClientId,
      email,
      pwd,
    );

    setState(() => _isOpsLoading = false);

    if (token != null) {
      // 🔥 登入成功：儲存帳密
      await _saveAccountLocal('ops_accounts', email, pwd);

      AppState.opsToken = token;
      AppState.opsEmail = email;
      widget.onLoginSuccess();
      _showMsg("✅ OPS 平台登入成功", Colors.green);
    } else {
      _showMsg("❌ OPS 登入失敗", Colors.red);
    }
  }

  Future<void> _loginDsm() async {
    setState(() => _isDsmLoading = true);
    final email = _dsmEmailCtrl.text;
    final pwd = _dsmPwdCtrl.text;

    final token = await _performKeycloakLogin(
      ApiConfig.dsmClientId,
      email,
      pwd,
    );

    setState(() => _isDsmLoading = false);

    if (token != null) {
      // 🔥 登入成功：儲存帳密
      await _saveAccountLocal('dsm_accounts', email, pwd);

      AppState.dsmToken = token;
      AppState.dsmEmail = email;
      widget.onLoginSuccess();
      _showMsg("✅ DSM 登入成功", Colors.green);
    } else {
      _showMsg("❌ DSM 登入失敗", Colors.red);
    }
  }

  void _showMsg(String msg, Color color) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
    }
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
            subTitle: "OPS",
            emailCtrl: _opsEmailCtrl,
            pwdCtrl: _opsPwdCtrl,
            savedAccounts: _savedOpsAccounts, // 傳入歷史帳號
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
            subTitle: "",
            emailCtrl: _dsmEmailCtrl,
            pwdCtrl: _dsmPwdCtrl,
            savedAccounts: _savedDsmAccounts, // 傳入歷史帳號
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
    required List<SavedAccount> savedAccounts, // 新增參數
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
            // ... 已登入狀態的 UI 保持不變 ...
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
            // 🔥 使用 LayoutBuilder + Autocomplete 實作「下拉選單」效果
            LayoutBuilder(
              builder: (context, constraints) {
                return Autocomplete<SavedAccount>(
                  // 1. 設定選項來源
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    if (textEditingValue.text == '') {
                      return savedAccounts; // 沒打字時顯示所有
                    }
                    return savedAccounts.where((SavedAccount option) {
                      return option.email.toLowerCase().contains(
                        textEditingValue.text.toLowerCase(),
                      );
                    });
                  },
                  // 2. 設定選中後的行為 (填入 Email 和 密碼)
                  onSelected: (SavedAccount selection) {
                    emailCtrl.text = selection.email;
                    pwdCtrl.text = selection.password;
                  },
                  // 3. 設定顯示字串
                  displayStringForOption: (SavedAccount option) => option.email,

                  // 4. 自定義輸入框外觀 (保持原本的深色風格)
                  fieldViewBuilder:
                      (
                        context,
                        textEditingController,
                        focusNode,
                        onFieldSubmitted,
                      ) {
                        // 同步 controller (重要！讓外部的 _opsEmailCtrl 也能拿到值)
                        if (textEditingController.text != emailCtrl.text) {
                          textEditingController.text = emailCtrl.text;
                        }
                        // 綁定監聽，讓 textEditingController 更新時寫回 emailCtrl
                        textEditingController.addListener(() {
                          emailCtrl.text = textEditingController.text;
                        });

                        return TextField(
                          controller: textEditingController,
                          focusNode: focusNode,
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
                            // 🔥 如果有歷史紀錄，顯示下拉箭頭提示
                            suffixIcon: savedAccounts.isNotEmpty
                                ? const Icon(
                                    Icons.arrow_drop_down,
                                    color: Colors.grey,
                                  )
                                : null,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                        );
                      },
                  // 5. 自定義下拉選單外觀 (Dark Mode)
                  optionsViewBuilder: (context, onSelected, options) {
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 4.0,
                        color: inputBg, // 下拉選單背景色
                        child: SizedBox(
                          width: constraints.maxWidth, // 跟輸入框一樣寬
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemCount: options.length,
                            itemBuilder: (BuildContext context, int index) {
                              final SavedAccount option = options.elementAt(
                                index,
                              );
                              return ListTile(
                                title: Text(
                                  option.email,
                                  style: const TextStyle(color: Colors.white),
                                ),
                                onTap: () => onSelected(option),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),

            const SizedBox(height: 20),

            // 密碼框保持不變
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
