import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AssignTaskPage extends StatefulWidget {
  final String maintainerId;
  final String maintainerName;
  final String maintainerEmail;

  const AssignTaskPage({
    Key? key,
    required this.maintainerId,
    required this.maintainerName,
    required this.maintainerEmail,
  }) : super(key: key);

  @override
  _AssignTaskPageState createState() => _AssignTaskPageState();
}

class _AssignTaskPageState extends State<AssignTaskPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _toiletIdController = TextEditingController();
  DateTime? _dueDate;
  String? _priority;
  String? _selectedToiletId;
  List<Map<String, dynamic>> _availableToilets = [];
  bool _isLoading = false;

  final CollectionReference tasksCollection =
      FirebaseFirestore.instance.collection('maintenanceTasks');
  final CollectionReference toiletsCollection =
      FirebaseFirestore.instance.collection('toilets');

  @override
  void initState() {
    super.initState();
    _fetchAvailableToilets();
  }

  Future<void> _fetchAvailableToilets() async {
    setState(() {
      _isLoading = true;
    });

    try {
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      QuerySnapshot snapshot = await toiletsCollection
          .where('ownerId', isEqualTo: currentUser.uid)
          .get();

      setState(() {
        _availableToilets = snapshot.docs.map((doc) {
          return {
            'id': doc.id,
            'name': doc['name'] ?? 'Unnamed Toilet',
            'location': doc['location'] ?? 'Unknown location',
          };
        }).toList();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error fetching toilets: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _selectDueDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null && picked != _dueDate) {
      setState(() {
        _dueDate = picked;
      });
    }
  }

  Future<void> _assignTask() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      await tasksCollection.add({
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'toiletId': _selectedToiletId,
        'toiletName': _availableToilets
            .firstWhere((toilet) => toilet['id'] == _selectedToiletId)['name'],
        'maintainerId': widget.maintainerId,
        'maintainerName': widget.maintainerName,
        'maintainerEmail': widget.maintainerEmail,
        'ownerId': currentUser.uid,
        'dueDate': _dueDate,
        'priority': _priority ?? 'Medium',
        'status': 'Assigned',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Task assigned successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.of(context).pop();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to assign task: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _toiletIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assign New Task'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Assigning task to: ${widget.maintainerName}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _titleController,
                        decoration: const InputDecoration(
                          labelText: 'Task Title*',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter a task title';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _descriptionController,
                        decoration: const InputDecoration(
                          labelText: 'Description*',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 3,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter a description';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _priority,
                        decoration: const InputDecoration(
                          labelText: 'Priority*',
                          border: OutlineInputBorder(),
                          isCollapsed: false,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'Low',
                            child: Text('Low'),
                          ),
                          DropdownMenuItem(
                            value: 'Medium',
                            child: Text('Medium'),
                          ),
                          DropdownMenuItem(
                            value: 'High',
                            child: Text('High'),
                          ),
                          DropdownMenuItem(
                            value: 'Urgent',
                            child: Text('Urgent'),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _priority = value;
                          });
                        },
                        validator: (value) {
                          if (value == null) {
                            return 'Please select a priority';
                          }
                          return null;
                        },
                        isExpanded: true,
                      ),
                      const SizedBox(height: 16),
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Due Date*',
                          border: OutlineInputBorder(),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                _dueDate == null
                                    ? 'Select a date'
                                    : '${_dueDate!.day}/${_dueDate!.month}/${_dueDate!.year}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.calendar_today),
                              onPressed: () => _selectDueDate(context),
                              constraints: const BoxConstraints(),
                              padding: EdgeInsets.zero,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _selectedToiletId,
                        decoration: const InputDecoration(
                          labelText: 'Select Toilet*',
                          border: OutlineInputBorder(),
                        ),
                        items: _availableToilets
                            .map<DropdownMenuItem<String>>((toilet) {
                          return DropdownMenuItem<String>(
                            value: toilet['id'] as String,
                            child: Text(
                              '${toilet['name']} (${toilet['location']})',
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedToiletId = value;
                          });
                        },
                        validator: (value) {
                          if (value == null) {
                            return 'Please select a toilet';
                          }
                          return null;
                        },
                        isExpanded: true,
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _assignTask,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text(
                            'Assign Task',
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
