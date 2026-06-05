import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/constants.dart';

const List<Map<String, dynamic>> kHelpCategories = [
  {
    'id': 'account',
    'title': 'Login & Account',
    'icon': '??',
    'faqs': [
      {'q': 'I forgot my password', 'a': 'Tap Forgot Password on the login screen. A reset link will be sent to your registered email.'},
      {'q': 'How do I change my email?', 'a': 'Go to Profile > Settings > Change Email. You will need to verify the new email address.'},
      {'q': 'My account is locked', 'a': 'Too many failed login attempts locks the account for 15 minutes. Wait and try again, or reset your password.'},
      {'q': 'How do I link my parent account?', 'a': 'Ask your parent to scan the QR code in their Parent Portal, or share the 6-digit link code from your Profile screen.'},
    ],
  },
  {
    'id': 'subjects',
    'title': 'Subjects & Topics',
    'icon': '??',
    'faqs': [
      {'q': 'Why is a topic locked?', 'a': 'Topics unlock in sequence. Complete the previous topic first before moving on.'},
      {'q': 'How do I change my form level?', 'a': 'Go to Profile > Edit Profile > Form Level. Note: this resets your topic progress.'},
      {'q': 'Can I study more than one subject per day?', 'a': 'Yes! You can study multiple subjects. The daily limit is 3 sessions per subject.'},
      {'q': 'What does Refresher mode mean?', 'a': 'Refresher topics are ones you completed but may need to review. Nova will quiz you to confirm mastery.'},
    ],
  },
  {
    'id': 'voice',
    'title': 'Voice & Audio',
    'icon': '???',
    'faqs': [
      {'q': 'Nova voice sounds robotic', 'a': 'This happens when the app uses browser fallback voice. Make sure you have a stable internet connection for Nova AI voice.'},
      {'q': 'Nova is not responding to my voice', 'a': 'Check that your browser has microphone permission enabled for this site. Tap the mic icon to start speaking.'},
      {'q': 'The voice keeps switching male to female', 'a': 'This is a known issue with browser fallback mode. It resolves automatically with a stable connection.'},
      {'q': 'Can I use text instead of voice?', 'a': 'Yes! Type your question in the text box at the bottom and press Send. Voice and text both work.'},
    ],
  },
  {
    'id': 'subscription',
    'title': 'Subscription & Payment',
    'icon': '??',
    'faqs': [
      {'q': 'How much does Learnova cost?', 'a': 'RM40 per subject per month. Subscribe to as many or as few subjects as you need.'},
      {'q': 'How do I cancel my subscription?', 'a': 'Go to Profile > Subscription > Cancel. Your access remains until the end of the billing period.'},
      {'q': 'What is the Pay-It-Forward program?', 'a': 'Parents can sponsor seats for students who cannot afford Learnova. Contact us to learn more.'},
      {'q': 'I paid but my subject is still locked', 'a': 'Payments can take up to 1 hour to reflect. If it has been longer, use Contact Support below to raise a ticket.'},
    ],
  },
  {
    'id': 'technical',
    'title': 'Technical Issues',
    'icon': '??',
    'faqs': [
      {'q': 'The app is slow or not loading', 'a': 'Try a hard refresh (Ctrl+Shift+R on desktop). Clear your browser cache and check your internet connection.'},
      {'q': 'My quiz results are not saving', 'a': 'This usually happens with a weak connection during the quiz. Redo the quiz — results save at the end.'},
      {'q': 'The screen is blank after login', 'a': 'Hard refresh the page (Ctrl+Shift+R). If it persists, log out and log back in.'},
      {'q': 'Nova stopped mid-conversation', 'a': 'Sessions have a 90-minute limit. Start a new session to continue learning.'},
    ],
  },
  {
    'id': 'other',
    'title': 'Other Questions',
    'icon': '??',
    'faqs': [
      {'q': 'How do I earn badges?', 'a': 'Complete topics to earn badges. Your rank improves from Bronze to Diamond as you master more topics.'},
      {'q': 'Can my parent see my chat with Nova?', 'a': 'Parents see session summaries and quiz results, but not the full conversation. Your learning is private.'},
      {'q': 'Is Learnova available in Bahasa Malaysia?', 'a': 'You can ask Nova in BM, English, or Mandarin. Nova responds in the language you use.'},
      {'q': 'How do I report a wrong answer from Nova?', 'a': 'Tap the flag icon next to any Nova response to report it. Our team reviews flagged answers weekly.'},
    ],
  },
];

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});
  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  Map<String, dynamic>? _selectedCategory;
  Map<String, dynamic>? _selectedFaq;
  bool _showAiChat = false;
  bool _escalated = false;
  final TextEditingController _chatController = TextEditingController();
  final List<Map<String, String>> _chatHistory = [];
  bool _aiLoading = false;
  String _issueDescription = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kSurface,
        title: Text(
          _selectedCategory == null ? 'Help Centre' : _selectedCategory!['title'],
          style: const TextStyle(color: kText, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kText),
          onPressed: () {
            if (_showAiChat) {
              setState(() { _showAiChat = false; _selectedFaq = null; });
            } else if (_selectedCategory != null) {
              setState(() { _selectedCategory = null; _selectedFaq = null; });
            } else {
              Navigator.pop(context);
            }
          },
        ),
        elevation: 0,
      ),
      body: _selectedCategory == null
          ? _buildCategoryList()
          : _showAiChat
              ? _buildAiChat()
              : _selectedFaq == null
                  ? _buildFaqList()
                  : _buildFaqAnswer(),
    );
  }

  Widget _buildCategoryList() {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kBorder),
          ),
          child: const Row(
            children: [
              Text('??', style: TextStyle(fontSize: 24)),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Hi! I am Nova. Select a category and I will help you find the answer.',
                  style: TextStyle(color: kText, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: kHelpCategories.length,
            itemBuilder: (context, i) {
              final cat = kHelpCategories[i];
              return GestureDetector(
                onTap: () => setState(() => _selectedCategory = cat),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: kSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kBorder),
                  ),
                  child: Row(
                    children: [
                      Text(cat['icon'], style: const TextStyle(fontSize: 28)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(cat['title'],
                                style: const TextStyle(color: kText, fontWeight: FontWeight.bold, fontSize: 15)),
                            Text('${(cat['faqs'] as List).length} common questions',
                                style: const TextStyle(color: kMuted, fontSize: 12)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: kMuted),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        _buildEscalateButton(),
      ],
    );
  }

  Widget _buildFaqList() {
    final faqs = _selectedCategory!['faqs'] as List;
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: faqs.length,
            itemBuilder: (context, i) {
              return GestureDetector(
                onTap: () => setState(() => _selectedFaq = faqs[i]),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: kSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.help_outline, color: kPrimary, size: 20),
                      const SizedBox(width: 12),
                      Expanded(child: Text(faqs[i]['q'], style: const TextStyle(color: kText, fontSize: 14))),
                      const Icon(Icons.chevron_right, color: kMuted),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GestureDetector(
            onTap: () => setState(() => _showAiChat = true),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: kSurface2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kPrimary.withOpacity(0.4)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat_bubble_outline, color: kPrimary, size: 18),
                  SizedBox(width: 8),
                  Text('My question is not listed — Ask Nova',
                      style: TextStyle(color: kPrimary, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildEscalateButton(),
      ],
    );
  }

  Widget _buildFaqAnswer() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_selectedFaq!['q'],
                    style: const TextStyle(color: kText, fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 12),
                const Divider(color: kBorder),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('??', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_selectedFaq!['a'],
                          style: const TextStyle(color: kText, fontSize: 14, height: 1.5)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('Did this help?', style: TextStyle(color: kMuted, fontSize: 13)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    _logHelpEvent('faq_resolved', _selectedFaq!['q']);
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Glad that helped!')),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: kGreen.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: kGreen.withOpacity(0.4)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.thumb_up_outlined, color: kGreen, size: 18),
                        SizedBox(width: 8),
                        Text('Yes, solved!', style: TextStyle(color: kGreen, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    _logHelpEvent('faq_not_resolved', _selectedFaq!['q']);
                    setState(() => _showAiChat = true);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: kRed.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: kRed.withOpacity(0.4)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.thumb_down_outlined, color: kRed, size: 18),
                        SizedBox(width: 8),
                        Text('Not helpful', style: TextStyle(color: kRed, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          _buildEscalateButton(),
        ],
      ),
    );
  }

  Widget _buildAiChat() {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _chatHistory.length + (_aiLoading ? 1 : 0),
            itemBuilder: (context, i) {
              if (_aiLoading && i == _chatHistory.length) {
                return const Padding(
                  padding: EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Text('??', style: TextStyle(fontSize: 20)),
                      SizedBox(width: 8),
                      SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: kPrimary)),
                    ],
                  ),
                );
              }
              final msg = _chatHistory[i];
              final isUser = msg['role'] == 'user';
              return Align(
                alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                  decoration: BoxDecoration(
                    color: isUser ? kPrimary : kSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: isUser ? null : Border.all(color: kBorder),
                  ),
                  child: Text(msg['content']!,
                      style: TextStyle(color: isUser ? Colors.white : kText, fontSize: 14)),
                ),
              );
            },
          ),
        ),
        if (!_escalated) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kSurface,
              border: Border(top: BorderSide(color: kBorder)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    style: const TextStyle(color: kText),
                    decoration: InputDecoration(
                      hintText: 'Type your question...',
                      hintStyle: TextStyle(color: kMuted),
                      filled: true,
                      fillColor: kSurface2,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    onSubmitted: (_) => _sendHelpMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _sendHelpMessage,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(color: kPrimary, shape: BoxShape.circle),
                    child: const Icon(Icons.send, color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          ),
          _buildEscalateButton(),
        ] else
          Container(
            padding: const EdgeInsets.all(16),
            child: const Text(
              'Your ticket has been raised. Our team will contact you within 24 hours.',
              style: TextStyle(color: kGreen, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }

  Widget _buildEscalateButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: GestureDetector(
        onTap: _escalateToHuman,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: kSurface2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kBorder),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.support_agent, color: kMuted, size: 18),
              SizedBox(width: 8),
              Text('Still need help? Contact Support',
                  style: TextStyle(color: kMuted, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendHelpMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    _chatController.clear();
    setState(() {
      _chatHistory.add({'role': 'user', 'content': text});
      _aiLoading = true;
      _issueDescription = text;
    });
    _logHelpEvent('ai_chat_question', text);
    try {
      final res = await http.post(
        Uri.parse('$kApiUrl/api/help/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'message': text,
          'category': _selectedCategory?['id'] ?? 'general',
          'history': _chatHistory,
        }),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _chatHistory.add({'role': 'assistant', 'content': data['reply']});
          _aiLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _chatHistory.add({
          'role': 'assistant',
          'content': 'I am having trouble connecting right now. Please try again or contact support.',
        });
        _aiLoading = false;
      });
    }
  }

  Future<void> _escalateToHuman() async {
    setState(() => _escalated = true);
    _logHelpEvent('escalated_to_human', _issueDescription);
    try {
      await http.post(
        Uri.parse('$kApiUrl/api/help/ticket'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'category': _selectedCategory?['id'] ?? 'general',
          'issue': _issueDescription.isNotEmpty
              ? _issueDescription
              : _selectedFaq?['q'] ?? 'User requested human support',
          'chat_history': _chatHistory,
        }),
      );
    } catch (_) {}
    setState(() {
      _showAiChat = true;
      _chatHistory.add({
        'role': 'assistant',
        'content': 'I have raised a support ticket for you. Our team will reach out within 24 hours.',
      });
    });
  }

  Future<void> _logHelpEvent(String eventType, String details) async {
    try {
      await http.post(
        Uri.parse('$kApiUrl/api/help/log'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'event_type': eventType,
          'category': _selectedCategory?['id'] ?? 'general',
          'details': details,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );
    } catch (_) {}
  }
}
