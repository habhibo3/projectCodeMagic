import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../models/prize.dart';

class PrizeManagementWidget extends StatefulWidget {
  final List<Map<String, dynamic>> initialPrizes;
  final Function(List<Map<String, dynamic>>) onPrizesChanged;

  const PrizeManagementWidget({
    super.key,
    this.initialPrizes = const [],
    required this.onPrizesChanged,
  });

  @override
  State<PrizeManagementWidget> createState() => _PrizeManagementWidgetState();
}

class _PrizeManagementWidgetState extends State<PrizeManagementWidget> {
  late List<Map<String, dynamic>> _prizes;
  final Map<String, TextEditingController> _amountControllers = {};
  final Map<String, TextEditingController> _descControllers = {};

  @override
  void initState() {
    super.initState();
    _prizes = List.from(widget.initialPrizes);
    // If no prizes, add default ones after build phase
    if (_prizes.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _addDefaultPrizes();
        }
      });
    }
  }

  @override
  void dispose() {
    for (var ctrl in _amountControllers.values) {
      ctrl.dispose();
    }
    for (var ctrl in _descControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  TextEditingController _getAmountController(String id, String initialValue) {
    if (!_amountControllers.containsKey(id)) {
      _amountControllers[id] = TextEditingController(text: initialValue);
    }
    return _amountControllers[id]!;
  }

  TextEditingController _getDescController(String id, String initialValue) {
    if (!_descControllers.containsKey(id)) {
      _descControllers[id] = TextEditingController(text: initialValue);
    }
    return _descControllers[id]!;
  }

  void _addDefaultPrizes() {
    setState(() {
      _prizes = [
        ContestPrize(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          rank: 1,
          amount: '\$200',
          type: 'gold',
          description: 'Cash prize',
        ).toMap(),
        ContestPrize(
          id: DateTime.now().millisecondsSinceEpoch.toString() + '1',
          rank: 2,
          amount: '\$100',
          type: 'silver',
          description: 'Cash prize',
        ).toMap(),
        ContestPrize(
          id: DateTime.now().millisecondsSinceEpoch.toString() + '2',
          rank: 3,
          amount: '\$50',
          type: 'bronze',
          description: 'Cash prize',
        ).toMap(),
      ];
    });
    widget.onPrizesChanged(_prizes);
  }

  void _addPrize() {
    final nextRank = _prizes.length + 1;
    final newPrize = ContestPrize(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      rank: nextRank,
      amount: '',
      type: 'recognition',
      description: 'Recognition Prize',
    ).toMap();
    
    setState(() {
      _prizes.add(newPrize);
      widget.onPrizesChanged(_prizes);
    });
  }

  void _removePrize(int index) {
    final prize = _prizes[index];
    final id = prize['id'] as String?;
    if (id != null) {
      _amountControllers[id]?.dispose();
      _amountControllers.remove(id);
      _descControllers[id]?.dispose();
      _descControllers.remove(id);
    }
    setState(() {
      _prizes.removeAt(index);
      // Re-rank remaining prizes
      for (int i = 0; i < _prizes.length; i++) {
        _prizes[i]['rank'] = i + 1;
      }
      widget.onPrizesChanged(_prizes);
    });
  }

  void _updateAmount(int index, String value) {
    String formattedValue = value;
    if (value.isNotEmpty) {
      String clean = value.replaceAll('\$', '').trim();
      if (clean.isNotEmpty) {
        formattedValue = '\$$clean';
      } else {
        formattedValue = '';
      }
    }
    
    final id = _prizes[index]['id'] as String;
    final controller = _amountControllers[id];
    if (controller != null && controller.text != formattedValue) {
      int cursorPosition = controller.selection.baseOffset;
      if (!value.startsWith('\$') && formattedValue.startsWith('\$')) {
        cursorPosition += 1;
      }
      
      controller.value = TextEditingValue(
        text: formattedValue,
        selection: TextSelection.collapsed(
          offset: cursorPosition.clamp(0, formattedValue.length),
        ),
      );
    }
    
    _updatePrize(index, 'amount', formattedValue);
  }

  void _updatePrize(int index, String field, dynamic value) {
    setState(() {
      _prizes[index][field] = value;
      widget.onPrizesChanged(_prizes);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.trophy, color: Colors.amber, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'Prize Configuration',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _prizes.clear();
                            _addDefaultPrizes();
                          });
                        },
                        icon: const Icon(LucideIcons.rotateCcw, size: 16),
                        label: const Text('Reset'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white54,
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _addPrize,
                        icon: const Icon(LucideIcons.plus, size: 16),
                        label: const Text('Add Prize'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber,
                          foregroundColor: Colors.black,
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white24),
          
          // Prize List
          if (_prizes.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'No prizes configured. Click "Add Prize" to add prizes.',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _prizes.length,
              separatorBuilder: (context, index) => const Divider(height: 1, color: Colors.white24),
              itemBuilder: (context, index) {
                final prize = _prizes[index];
                return _buildPrizeRow(index, prize);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildPrizeRow(int index, Map<String, dynamic> prize) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Rank Badge
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _getPrizeTypeColor(prize['type'] ?? 'custom'),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              
              // Type Dropdown
              Expanded(
                child: _buildTypeDropdown(index, prize['type'] ?? 'custom'),
              ),
              
              const SizedBox(width: 12),
              
              // Remove Button
              IconButton(
                onPressed: () => _removePrize(index),
                icon: const Icon(LucideIcons.trash2, size: 18),
                color: Colors.redAccent,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Amount and Description
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  label: 'Amount (optional)',
                  controller: _getAmountController(prize['id'] ?? '', prize['amount'] ?? ''),
                  hintText: '\$200',
                  onChanged: (value) => _updateAmount(index, value),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _buildTextField(
                  label: 'Description',
                  controller: _getDescController(prize['id'] ?? '', prize['description'] ?? ''),
                  hintText: 'Cash prize, Certificate, Gift card...',
                  onChanged: (value) => _updatePrize(index, 'description', value),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTypeDropdown(int index, String currentType) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Prize Type',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white24),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: currentType,
              isExpanded: true,
              dropdownColor: const Color(0xFF2A2A2A),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              items: const [
                DropdownMenuItem(value: 'gold', child: Text('🥇 Gold Prize')),
                DropdownMenuItem(value: 'silver', child: Text('🥈 Silver Prize')),
                DropdownMenuItem(value: 'bronze', child: Text('🥉 Bronze Prize')),
                DropdownMenuItem(value: 'recognition', child: Text('🏅 Recognition Prize')),
                DropdownMenuItem(value: 'custom', child: Text('✨ Custom Prize')),
              ],
              onChanged: (value) {
                if (value != null) {
                  _updatePrize(index, 'type', value);
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required String hintText,
    required Function(String) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: const TextStyle(color: Colors.white30),
            filled: true,
            fillColor: const Color(0xFF2A2A2A),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.white24),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.white24),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.amber),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Color _getPrizeTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'gold':
        return const Color(0xFFFFD700);
      case 'silver':
        return const Color(0xFFC0C0C0);
      case 'bronze':
        return const Color(0xFFCD7F32);
      case 'recognition':
        return const Color(0xFF8B5CF6);
      default:
        return const Color(0xFF6B7280);
    }
  }
}
