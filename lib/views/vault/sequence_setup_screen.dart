import 'package:flutter/material.dart';
import '../../services/auth_service.dart';

class SequenceSetupScreen extends StatefulWidget {
  final List<int> currentSequence;

  const SequenceSetupScreen({Key? key, required this.currentSequence}) : super(key: key);

  @override
  State<SequenceSetupScreen> createState() => _SequenceSetupScreenState();
}

class _SequenceSetupScreenState extends State<SequenceSetupScreen> {
  static const int REQUIRED_COUNT = 4;

  // 1: Verify current sequence, 2: Enter new sequence, 3: Confirm new sequence
  int _currentStep = 1;
  bool _isSaving = false;

  final List<int> _currentVerificationBuffer = [];
  final List<int> _newSequenceBuffer = [];
  final List<int> _confirmSequenceBuffer = [];

  String? _errorMessage;

  void _onDaySelected(int day) {
    setState(() {
      _errorMessage = null;

      if (_currentStep == 1) {
        if (_currentVerificationBuffer.length < REQUIRED_COUNT) {
          _currentVerificationBuffer.add(day);
          if (_currentVerificationBuffer.length == REQUIRED_COUNT) {
            _verifyCurrentSequence();
          }
        }
      } else if (_currentStep == 2) {
        if (_newSequenceBuffer.length < REQUIRED_COUNT) {
          _newSequenceBuffer.add(day);
        }
      } else if (_currentStep == 3) {
        if (_confirmSequenceBuffer.length < REQUIRED_COUNT) {
          _confirmSequenceBuffer.add(day);
        }
      }
    });
  }

  Future<void> _verifyCurrentSequence() async {
    final isMatch = await AuthService.verifyCurrentPassword(_currentVerificationBuffer);

    if (isMatch) {
      setState(() {
        _currentStep = 2;
        _errorMessage = null;
      });
    } else {
      setState(() {
        _errorMessage = 'Incorrect current password. Please try again.';
        _currentVerificationBuffer.clear();
      });
    }
  }

  void _goToConfirmStep() {
    if (_newSequenceBuffer.length == REQUIRED_COUNT) {
      setState(() {
        _currentStep = 3;
        _confirmSequenceBuffer.clear();
        _errorMessage = null;
      });
    }
  }

  Future<void> _saveNewSequence() async {
    setState(() => _isSaving = true);

    final error = await AuthService.changePassword(
      currentPassword: _currentVerificationBuffer,
      newPassword: _newSequenceBuffer,
      confirmPassword: _confirmSequenceBuffer,
    );

    if (error != null) {
      setState(() {
        _isSaving = false;
        _errorMessage = error;
        _confirmSequenceBuffer.clear();
      });
      return;
    }

    // Successfully verified, confirmed, and permanently saved to SecureStorage & SharedPreferences!
    if (mounted) {
      Navigator.pop(context, _newSequenceBuffer);
    }
  }

  void _clearActiveStep() {
    setState(() {
      _errorMessage = null;
      if (_currentStep == 1) _currentVerificationBuffer.clear();
      if (_currentStep == 2) _newSequenceBuffer.clear();
      if (_currentStep == 3) _confirmSequenceBuffer.clear();
    });
  }

  List<int> get _activeBuffer {
    if (_currentStep == 1) return _currentVerificationBuffer;
    if (_currentStep == 2) return _newSequenceBuffer;
    return _confirmSequenceBuffer;
  }

  String get _stepTitle {
    switch (_currentStep) {
      case 1:
        return 'Step 1 of 2: Verify Current Password';
      case 2:
        return 'Step 2 of 2: Set New Combination';
      case 3:
      default:
        return 'Confirm New Combination';
    }
  }

  String get _stepInstruction {
    switch (_currentStep) {
      case 1:
        return 'To change your hidden vault password, first enter your CURRENT 4-date sequence to verify your identity.';
      case 2:
        return 'Identity verified! Now tap your NEW 4 dates in the order you want.';
      case 3:
      default:
        return 'Please re-tap your NEW 4 dates to confirm.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        foregroundColor: Colors.white,
        title: Text(_stepTitle, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _currentStep == 1 ? Colors.amber.withOpacity(0.15) : Colors.indigo.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _currentStep == 1 ? Colors.amber.withOpacity(0.4) : Colors.indigo.withOpacity(0.4),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _currentStep == 1 ? Icons.lock_person_outlined : Icons.verified_user_outlined,
                    color: _currentStep == 1 ? Colors.amber : Colors.indigoAccent,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _stepInstruction,
                      style: const TextStyle(fontSize: 13, color: Colors.white70, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Sequence slots representation
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(REQUIRED_COUNT, (index) {
                final isFilled = index < _activeBuffer.length;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: isFilled ? Colors.indigo : const Color(0xFF242424),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isFilled ? Colors.indigoAccent : Colors.white24,
                      width: isFilled ? 2 : 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    isFilled ? '${_activeBuffer[index]}' : '?',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isFilled ? Colors.white : Colors.white38,
                    ),
                  ),
                );
              }),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ],

            const SizedBox(height: 14),

            // Number/Date picker grid (1 to 31)
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                  childAspectRatio: 1.1,
                ),
                itemCount: 31,
                itemBuilder: (context, index) {
                  final day = index + 1;
                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _onDaySelected(day),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white12),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$day',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                  );
                },
              ),
            ),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _clearActiveStep,
                    child: const Text('Clear'),
                  ),
                ),
                const SizedBox(width: 12),
                if (_currentStep == 2)
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: _newSequenceBuffer.length == REQUIRED_COUNT ? _goToConfirmStep : null,
                      child: const Text('Next: Confirm'),
                    ),
                  )
                else if (_currentStep == 3)
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: (_confirmSequenceBuffer.length == REQUIRED_COUNT && !_isSaving) ? _saveNewSequence : null,
                      child: _isSaving
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Save & Update'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
