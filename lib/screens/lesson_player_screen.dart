import 'package:flutter/material.dart';
// Web support disabled for now
// Web JS disabled for now

class LessonPlayerScreen extends StatefulWidget {
  final String lessonId;
  final String lessonTitle;
  final List<dynamic> steps;
  
  const LessonPlayerScreen({
    Key? key,
    required this.lessonId,
    required this.lessonTitle,
    required this.steps,
  }) : super(key: key);
  
  @override
  _LessonPlayerScreenState createState() => _LessonPlayerScreenState();
}

class _LessonPlayerScreenState extends State<LessonPlayerScreen> {
  int _currentStepIndex = 0;
  int? _selectedAnswer;
  bool _answerRevealed = false;
  bool _showingFeedback = false;
  bool _speaking = false;
  
  @override
  Widget build(BuildContext context) {
    if (widget.steps.isEmpty || _currentStepIndex >= widget.steps.length) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.lessonTitle)),
        body: Center(child: Text('No steps available for this lesson.')),
      );
    }
    
    final step = widget.steps[_currentStepIndex];
    final isCheckIn = step['type'] == 'check_in';
    
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.lessonTitle),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          LinearProgressIndicator(
            value: (_currentStepIndex + 1) / widget.steps.length,
            backgroundColor: Colors.grey[300],
            valueColor: AlwaysStoppedAnimation<Color>(Colors.teal),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStepBadge(step['type']),
                  SizedBox(height: 16),
                  Text(
                    step['content'] ?? step['question'] ?? '',
                    style: TextStyle(fontSize: 18, height: 1.5),
                  ),
                  SizedBox(height: 24),
                  if (isCheckIn && step['options'] != null)
                    _buildCheckInOptions(step['options']),
                  if (_showingFeedback && _selectedAnswer != null)
                    _buildFeedbackCard(step),
                  SizedBox(height: 24),
                  _buildNavigationButtons(isCheckIn),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildStepBadge(String? type) {
    Color color;
    IconData icon;
    String label;
    
    switch(type) {
      case 'objectives':
        color = Colors.blue;
        icon = Icons.flag;
        label = 'Learning Objective';
        break;
      case 'prior_knowledge':
        color = Colors.purple;
        icon = Icons.history_edu;
        label = 'Prior Knowledge';
        break;
      case 'concept':
        color = Colors.teal;
        icon = Icons.lightbulb;
        label = 'Key Concept';
        break;
      case 'formula':
        color = Colors.orange;
        icon = Icons.calculate;
        label = 'Formula';
        break;
      case 'example':
        color = Colors.green;
        icon = Icons.format_quote;
        label = 'Example';
        break;
      case 'working':
        color = Colors.indigo;
        icon = Icons.edit_note;
        label = 'Step-by-Step';
        break;
      case 'mistake':
        color = Colors.red;
        icon = Icons.warning;
        label = 'Common Mistake';
        break;
      case 'connection':
        color = Colors.cyan;
        icon = Icons.share;
        label = 'Real World Connection';
        break;
      case 'summary':
        color = Colors.teal;
        icon = Icons.summarize;
        label = 'Summary';
        break;
      case 'check_in':
        color = Colors.amber;
        icon = Icons.quiz;
        label = 'Check Your Understanding';
        break;
      default:
        color = Colors.grey;
        icon = Icons.menu_book;
        label = type ?? 'Step';
    }
    
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          SizedBox(width: 8),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
  
  Widget _buildCheckInOptions(List<dynamic> options) {
    return Column(
      children: List.generate(options.length, (idx) {
        final isSelected = _selectedAnswer == idx;
        final isCorrect = idx == 0; // Assuming first option is correct
        Color? buttonColor;
        
        if (_answerRevealed) {
          if (isCorrect) buttonColor = Colors.green;
          else if (isSelected && !isCorrect) buttonColor = Colors.red;
        }
        
        return Container(
          margin: EdgeInsets.only(bottom: 12),
          child: ElevatedButton(
            onPressed: _answerRevealed ? null : () {
              setState(() {
                _selectedAnswer = idx;
                _answerRevealed = true;
                _showingFeedback = true;
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: buttonColor ?? Colors.grey[200],
              foregroundColor: buttonColor != null ? Colors.white : Colors.black87,
              minimumSize: Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(options[idx]),
          ),
        );
      }),
    );
  }
  
  Widget _buildFeedbackCard(Map step) {
    final isCorrect = _selectedAnswer == 0;
    return Container(
      margin: EdgeInsets.only(top: 16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isCorrect ? Colors.green[50] : Colors.red[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isCorrect ? Colors.green : Colors.red),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isCorrect ? Icons.check_circle : Icons.error, color: isCorrect ? Colors.green : Colors.red),
              SizedBox(width: 8),
              Text(
                isCorrect ? 'Correct!' : 'Not quite right',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(step['explanation'] ?? step['feedback'] ?? 'Keep practicing!'),
        ],
      ),
    );
  }
  
  Widget _buildNavigationButtons(bool isCheckIn) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (_currentStepIndex > 0)
          ElevatedButton(
            onPressed: () {
              setState(() {
                _currentStepIndex--;
                _selectedAnswer = null;
                _answerRevealed = false;
                _showingFeedback = false;
              });
            },
            child: Text('? Back'),
          )
        else
          SizedBox(width: 80),
        
        ElevatedButton(
          onPressed: () {
            if (isCheckIn && !_showingFeedback) {
              return; // Must answer first
            }
            setState(() {
              if (_currentStepIndex < widget.steps.length - 1) {
                _currentStepIndex++;
                _selectedAnswer = null;
                _answerRevealed = false;
                _showingFeedback = false;
              } else {
                Navigator.pop(context);
              }
            });
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
          ),
          child: Text(_currentStepIndex < widget.steps.length - 1 ? 'Continue ?' : 'Finish'),
        ),
      ],
    );
  }
}

