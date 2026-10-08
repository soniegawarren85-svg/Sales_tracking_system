bool saleBelongsToStaff(Map<String, dynamic> sale, String staffId) {
  final id = staffId.trim();
  return id.isNotEmpty && sale['userId']?.toString() == id;
}
