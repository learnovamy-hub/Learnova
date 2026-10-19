import 'package:flutter/material.dart';
import '../screens/feedback_form_screen.dart';
import '../config/constants.dart';

class HelpButton extends StatelessWidget {
  final String? subjectContext;
  final String? pageContext;
  const HelpButton({super.key, this.subjectContext, this.pageContext});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 80,
      right: 16,
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => FeedbackFormScreen(
            subjectContext: subjectContext,
            pageContext: pageContext,
          )),
        ),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [kPrimary, kPrimary2],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: kPrimary.withOpacity(0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.help_outline_rounded, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}
