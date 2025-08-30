import 'package:flutter/material.dart';


// Toilet Provider Option
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
// Clear Screen
  void clearSelection() {
    _selectedToiletId = null;
    _selectedToiletName = null;
    notifyListeners();
  }
}
