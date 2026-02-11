// lib/config.dart

class ApiConfig {
  // =========================================================
  // 1. 基礎網址設定 (Base URLs) - 全部從環境變數讀取，不留預設值
  // =========================================================

  // 認證伺服器 (Keycloak)
  static const String authBaseUrl = String.fromEnvironment('AUTH_URL');

  // DSM 後端 API
  static const String dsmApiBaseUrl = String.fromEnvironment('DSM_API_URL');

  // OPS 後端 API
  static const String opsApiBaseUrl = String.fromEnvironment('OPS_API_URL');

  // =========================================================
  // 2. 衍生網址 (Derived URLs)
  // =========================================================

  // 完整的 Token 交換網址
  static const String tokenUrl =
      "$authBaseUrl/auth/realms/dasiot/protocol/openid-connect/token";

  // =========================================================
  // 3. Client IDs
  // =========================================================

  static const String dsmClientId = String.fromEnvironment('DSM_CLIENT_ID');
  static const String opsClientId = String.fromEnvironment('OPS_CLIENT_ID');
}
