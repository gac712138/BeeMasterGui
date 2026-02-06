// lib/config.dart

class ApiConfig {
  // =========================================================
  // 1. 基礎網址設定 (Base URLs)
  // =========================================================

  // 認證伺服器 (Keycloak) - 預設為測式機
  static const String authBaseUrl = String.fromEnvironment(
    'AUTH_URL',
    defaultValue: "https://auth.dev.dasiot.site",
  );

  // DSM 後端 API - 預設為測式機
  static const String dsmApiBaseUrl = String.fromEnvironment(
    'DSM_API_URL',
    defaultValue: "https://api.dsm.app.dev.dasiot.site/v1",
  );

  // OPS 後端 API (如果有獨立的，預留位置)
  static const String opsApiBaseUrl = String.fromEnvironment(
    'OPS_API_URL',
    defaultValue: "https://api.dsm-ops.app.dev.dasiot.site/v1", // 假設的，依實際情況修改
  );

  // =========================================================
  // 2. 衍生網址 (Derived URLs)
  // =========================================================

  // 完整的 Token 交換網址
  static const String tokenUrl =
      "$authBaseUrl/auth/realms/dasiot/protocol/openid-connect/token";

  // =========================================================
  // 3. Client IDs
  // =========================================================

  static const String dsmClientId = "dasiot-app-dsm-frontend";
  static const String opsClientId = "dasiot-app-dsm-ops-frontend";
}
