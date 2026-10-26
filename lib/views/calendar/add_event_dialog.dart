import 'package:flutter/material.dart';
import '../../models/calendar_event.dart';

class AddEventDialog extends StatefulWidget {
  final DateTime selectedDate;

  const AddEventDialog({Key? key, required this.selectedDate}) : super(key: key);

  @override
  State<AddEventDialog> createState() => _AddEventDialogState();
}

class _AddEventDialogState extends State<AddEventDialog> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  TimeOfDay _selectedTime = const TimeOfDay(hour: 10, minute: 0);

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Calendar Event'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Event Title',
                hintText: 'e.g. Meeting with Sarah',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descController,
              decoration: const InputDecoration(
                labelText: 'Description / Notes',
                hintText: 'e.g. Discuss Q4 roadmap',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.access_time),
              title: Text('Time: ${_selectedTime.format(context)}'),
              onTap: () async {
                final time = await showTimePicker(
                  context: context,
                  initialTime: _selectedTime,
                );
                if (time != null) {
                  setState(() => _selectedTime = time);
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_titleController.text.trim().isEmpty) return;
            final newEvent = CalendarEvent(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              title: _titleController.text.trim(),
              description: _descController.text.trim(),
              date: widget.selectedDate,
              time: _selectedTime.format(context),
            );
            Navigator.pop(context, newEvent);
          },
          child: const Text('Add Event'),
        ),
      ],
    );
  }
}
