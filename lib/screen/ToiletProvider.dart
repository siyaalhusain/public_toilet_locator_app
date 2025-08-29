import 'package:flutter/material.dart';
//ToiletProvider
class ToiletProvider with ChangeNotifier {
  String? _selectedToiletId;
  String? _selectedToiletName;

  String? get selectedToiletId => _selectedToiletId;
  String? get selectedToiletName => _selectedToiletName;

  void setToilet(String id, String name) {
    _selectedToiletId = id;
    _selectedToiletName = name;
    notifyListeners(); // Notify UI to update
  }

  void clearSelection() {
    _selectedToiletId = null;
    _selectedToiletName = null;
    notifyListeners();
  }
}
