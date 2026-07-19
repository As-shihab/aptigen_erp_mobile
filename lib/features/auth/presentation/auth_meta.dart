/// Ported verbatim from erp/desktop's signInMeta.ts / signUpMeta.ts.
class SignInMeta {
  static String title(int step) {
    if (step == 3) return 'Select workplace';
    if (step == 4) return 'Create workplace';
    return step == 0 ? 'Welcome' : 'Sign in';
  }

  static String subtitle(int step) {
    if (step == 3) return 'Choose your workplace to finish login';
    if (step == 4) return 'Create workplace to finish login';
    return step == 0 ? 'Sign in to continue' : 'Enter your credentials';
  }

  static String primaryActionLabel(int step) {
    if (step == 3) return 'Continue';
    if (step == 4) return 'Create and continue';
    return step == 2 ? 'Sign in' : 'Next';
  }
}

class SignUpMeta {
  static String title() => 'Sign up';

  static String subtitle(int step) {
    if (step == 0) return 'Start by naming your workplace';
    if (step == 1) return 'Add your work email';
    return 'Create your password to finish signup';
  }

  static String primaryActionLabel(int step) => step == 2 ? 'Create account' : 'Next';
}
