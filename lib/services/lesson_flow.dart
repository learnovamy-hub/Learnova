class LessonFlow {
  int step = 0;

  String nextStep(String topic) {
    switch (step) {
      case 0:
        step++;
        return "Let’s start simple. What do you already know about $topic?";
      case 1:
        step++;
        return "Good. Let me show you a quick example. Can you try something similar?";
      case 2:
        step++;
        return "Nice attempt. Walk me through your first step.";
      case 3:
        step++;
        return "Let’s try a slightly harder question. What would you do next?";
      case 4:
        step++;
        return "You’re getting it. Why does this method work?";
      default:
        return "Good progress. Do you want to try more questions or review the concept again?";
    }
  }
}