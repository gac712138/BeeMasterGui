class WorkerImportData {
  final String dasId; // DasID*
  final String workerName; // WorkerName*
  final String gender; // Gender*
  final String? uwbId;
  final String? sim;
  final String? collisionId;
  final String? serialNumber;
  final String? birthday;
  final String? email;
  final String? phone;
  final String? company;
  final String? division;
  final String? trade;
  final String? remark;

  WorkerImportData({
    required this.dasId,
    required this.workerName,
    required this.gender,
    this.uwbId,
    this.sim,
    this.collisionId,
    this.serialNumber,
    this.birthday,
    this.email,
    this.phone,
    this.company,
    this.division,
    this.trade,
    this.remark,
  });
}

extension WorkerValidation on WorkerImportData {
  // 驗證 DasID 是否為 13 碼
  bool get isDasIdValid => dasId.length == 13;

  // 驗證 Gender 是否為 male 或 female
  bool get isGenderValid {
    final g = gender.toLowerCase().trim();
    return g == 'male' || g == 'female';
  }

  // 該筆資料是否完全正確
  bool get hasError => !isDasIdValid || !isGenderValid;
}
