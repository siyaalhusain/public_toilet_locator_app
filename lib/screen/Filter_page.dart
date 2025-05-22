import 'package:flutter/material.dart';

class FilterPage extends StatefulWidget {
  final Function(String, List<String>) onApplyFilter;

  FilterPage({required this.onApplyFilter});

  @override
  _FilterPageState createState() => _FilterPageState();
}

class _FilterPageState extends State<FilterPage> {
  String selectedRating = "Any";
  final List<String> ratingOptions = [
    "Any",
    "3.0 and up",
    "4.0 and up",
    "5.0 and up"
  ];

  final List<Map<String, dynamic>> amenities = [
    {"name": "Accessible", "icon": Icons.accessible, "color": Colors.blue},
    {"name": "Men Only", "icon": Icons.male, "color": Colors.indigo},
    {"name": "Female Only", "icon": Icons.female, "color": Colors.pink},
    {"name": "Two Genders", "icon": Icons.wc, "color": Colors.purple},
    {
      "name": "Baby Station",
      "icon": Icons.baby_changing_station,
      "color": Colors.orange
    },
    {"name": "Bathing", "icon": Icons.shower, "color": Colors.cyan},
    {"name": "Private", "icon": Icons.visibility_off, "color": Colors.red},
    {"name": "Open to Public", "icon": Icons.public, "color": Colors.green},
    {"name": "All", "icon": Icons.all_inbox, "color": Colors.amber},
  ];

  Set<String> selectedAmenities = {};
  bool hasChanges = false;

  void applyFilters() {
    widget.onApplyFilter(selectedRating, selectedAmenities.toList());
  }

  void _resetFilters() {
    selectedRating = "Any";
    selectedAmenities.clear();
    hasChanges = true;
    widget.onApplyFilter(selectedRating, []);
  }

  void _updateHasChanges() {
    setState(() {
      hasChanges = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text("Filter Toilets",
            style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader(
                        "Cleanliness Rating", Icons.cleaning_services),
                    SizedBox(height: 16),
                    _buildRatingOptions(),
                    SizedBox(height: 24),
                    Divider(),
                    SizedBox(height: 24),
                    _buildSectionHeader("Amenities", Icons.room_preferences),
                    SizedBox(height: 16),
                    _buildAmenitiesGrid(),
                    SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.blue[700]),
        SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.grey[800],
          ),
        ),
      ],
    );
  }

  Widget _buildRatingOptions() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        children: List.generate(ratingOptions.length, (index) {
          bool isSelected = selectedRating == ratingOptions[index];
          return InkWell(
            onTap: () {
              setState(() {
                selectedRating = ratingOptions[index];
                _updateHasChanges();
              });
            },
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              decoration: BoxDecoration(
                border: index < ratingOptions.length - 1
                    ? Border(bottom: BorderSide(color: Colors.grey[200]!))
                    : null,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      ratingOptions[index],
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? Colors.blue : Colors.grey[800],
                      ),
                    ),
                  ),
                  if (isSelected)
                    Icon(Icons.check_circle, color: Colors.blue, size: 24)
                  else if (ratingOptions[index] != "Any")
                    _buildRatingStars(
                        double.parse(ratingOptions[index].split(" ")[0])),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildRatingStars(double rating) {
    return Row(
      children: List.generate(5, (starIndex) {
        Color color = starIndex < rating ? Colors.amber : Colors.grey[300]!;
        return Icon(Icons.star, color: color, size: 16);
      }),
    );
  }

  Widget _buildAmenitiesGrid() {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: List.generate(amenities.length, (index) {
        final amenity = amenities[index];
        final isSelected = selectedAmenities.contains(amenity["name"]);

        return InkWell(
          onTap: () {
            setState(() {
              if (isSelected) {
                selectedAmenities.remove(amenity["name"]);
              } else {
                selectedAmenities.add(amenity["name"]);
              }
              _updateHasChanges();
            });
          },
          child: Container(
            width: (MediaQuery.of(context).size.width - 48) / 2,
            padding: EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            decoration: BoxDecoration(
              color:
                  isSelected ? amenity["color"].withOpacity(0.1) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? amenity["color"] : Colors.grey[300]!,
                width: isSelected ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: isSelected
                      ? amenity["color"].withOpacity(0.2)
                      : Colors.black.withOpacity(0.05),
                  blurRadius: isSelected ? 8 : 5,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? amenity["color"]
                        : amenity["color"].withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    amenity["icon"],
                    color: isSelected ? Colors.white : amenity["color"],
                    size: 20,
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    amenity["name"],
                    style: TextStyle(
                      color: isSelected ? amenity["color"] : Colors.grey[800],
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 5,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: _resetFilters,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.blue,
                  padding: EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  side: BorderSide(color: Colors.blue),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text('Reset'),
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: applyFilters,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 14),
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.filter_alt),
                    SizedBox(width: 8),
                    Text(
                      'Apply Filters',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
