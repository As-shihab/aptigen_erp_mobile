import 'package:flutter/material.dart';
import '../../../core/network/http_client.dart';
import '../../../core/theme/app_theme.dart';
import '../data/auth_service.dart';
import '../models/workplace_model.dart';
import 'auth_meta.dart';
import 'widgets/email_step.dart';
import 'widgets/password_step.dart';
import 'widgets/select_workplace_step.dart';
import 'widgets/workplace_step.dart';

enum AuthMode { signin, signup }

int _maxStepForMode(AuthMode mode) => mode == AuthMode.signup ? 2 : 4;

/// Ported from erp/desktop's WelcomeScreen.tsx auth state machine
/// (email/password only — OAuth is out of scope for v1).
class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final _authService = AuthService(ApiClient());

  AuthMode _authMode = AuthMode.signin;
  int _step = 0;

  String _workplaceName = '';
  String _email = '';
  String _password = '';

  List<WorkplaceOption> _signInWorkplaces = [];
  String _selectedWorkplaceId = '';
  int? _signInUserId;

  bool _isSubmitting = false;
  String? _loginError;

  void _resetForm() {
    setState(() {
      _workplaceName = '';
      _email = '';
      _password = '';
      _signInWorkplaces = [];
      _selectedWorkplaceId = '';
      _signInUserId = null;
      _loginError = null;
    });
  }

  void _goToStep(AuthMode mode, int step) {
    final normalized = step.clamp(0, _maxStepForMode(mode));
    setState(() {
      _authMode = mode;
      _step = normalized;
    });
  }

  bool get _canContinue {
    final emailValid = RegExp(r'^\S+@\S+\.\S+$').hasMatch(_email);
    if (_authMode == AuthMode.signin) {
      if (_step == 1) return emailValid;
      if (_step == 2) return _password.trim().isNotEmpty;
      if (_step == 3) return _signInWorkplaces.any((w) => w.id == _selectedWorkplaceId);
      if (_step == 4) return _workplaceName.trim().length > 1;
      return true;
    }
    if (_step == 0) return _workplaceName.trim().length > 1;
    if (_step == 1) return emailValid;
    if (_step == 2) return _password.trim().isNotEmpty;
    return true;
  }

  String _errorMessage(Object error, [String fallback = 'Request failed. Please try again.']) {
    if (error is ApiException) return error.message.isNotEmpty ? error.message : fallback;
    return fallback;
  }

  Future<void> _handleSignInCredentialsStep() async {
    setState(() => _isSubmitting = true);
    try {
      final user = await _authService.login(_email, _password);
      final userId = int.tryParse(user['id'].toString()) ?? 0;
      _signInUserId = userId;

      List<WorkplaceOption> workplaces = [];
      try {
        workplaces = await _authService.fetchWorkplaces(userId);
      } catch (_) {
        _loginError = 'Signed in, but could not load workplaces. You can create one to continue.';
      }

      setState(() {
        _signInWorkplaces = workplaces;
        if (!workplaces.any((w) => w.id == _selectedWorkplaceId)) {
          _selectedWorkplaceId = workplaces.isNotEmpty ? workplaces.first.id : '';
        }
      });
      _goToStep(AuthMode.signin, 3);
    } catch (error) {
      setState(() {
        _signInWorkplaces = [];
        _selectedWorkplaceId = '';
        _loginError = _errorMessage(error, 'Could not sign in. Please try again.');
      });
      _goToStep(AuthMode.signin, 2);
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  Future<void> _handleSignInWorkplaceStep() async {
    final selected = _signInWorkplaces.where((w) => w.id == _selectedWorkplaceId).firstOrNull;
    if (selected == null) {
      setState(() => _loginError = 'Please select a workplace to continue.');
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await _authService.activateWorkplace(selected);
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/launcher');
    } catch (error) {
      setState(() => _loginError = _errorMessage(error, 'Could not activate workplace. Please try again.'));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _handleCreateWorkplaceStep() async {
    final name = _workplaceName.trim();
    if (name.isEmpty) {
      setState(() => _loginError = 'Please enter a workplace name.');
      return;
    }
    final ownerId = _signInUserId;
    if (ownerId == null) {
      setState(() => _loginError = 'Could not identify your account. Please sign in again.');
      _goToStep(AuthMode.signin, 2);
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final created = await _authService.createWorkplace(name, ownerId);
      setState(() {
        _signInWorkplaces = [
          ..._signInWorkplaces.where((w) => w.id != created.id),
          created,
        ];
        _selectedWorkplaceId = created.id;
        _workplaceName = '';
      });
      _goToStep(AuthMode.signin, 3);
    } catch (error) {
      setState(() => _loginError = _errorMessage(error, 'Could not create workplace. Please try again.'));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _handleSignUpCompleteStep() async {
    final name = _workplaceName.trim();
    final email = _email.trim();
    final password = _password;

    if (name.isEmpty) {
      setState(() => _loginError = 'Please enter a workplace name.');
      _goToStep(AuthMode.signup, 0);
      return;
    }
    if (!RegExp(r'^\S+@\S+\.\S+$').hasMatch(email)) {
      setState(() => _loginError = 'Please enter a valid email.');
      _goToStep(AuthMode.signup, 1);
      return;
    }
    if (password.trim().isEmpty) {
      setState(() => _loginError = 'Please enter a password.');
      _goToStep(AuthMode.signup, 2);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final inferredName = email.split('@').first.replaceAll(RegExp(r'[._-]+'), ' ').trim();
      await _authService.signup(inferredName.isNotEmpty ? inferredName : name, email, password);

      final user = await _authService.login(email, password);
      final userId = int.tryParse(user['id'].toString()) ?? 0;
      if (userId == 0) throw ApiException(0, 'Sign up completed but user information is invalid.');

      final createdWorkplace = await _authService.createWorkplace(name, userId);
      await _authService.activateWorkplace(createdWorkplace);

      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/launcher');
    } catch (error) {
      setState(() => _loginError = _errorMessage(error, 'Sign up failed. Please try again.'));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _nextStep() async {
    setState(() => _loginError = null);

    if (_authMode == AuthMode.signin && _step == 2) return _handleSignInCredentialsStep();
    if (_authMode == AuthMode.signin && _step == 3) return _handleSignInWorkplaceStep();
    if (_authMode == AuthMode.signin && _step == 4) return _handleCreateWorkplaceStep();
    if (_authMode == AuthMode.signup && _step == 2) return _handleSignUpCompleteStep();

    _goToStep(_authMode, _step + 1);
  }

  Widget _buildStepField() {
    if (_authMode == AuthMode.signin) {
      switch (_step) {
        case 1:
          return EmailStep(key: const ValueKey('signin-email'), value: _email, onChanged: (v) => setState(() => _email = v));
        case 2:
          return PasswordStep(
            key: const ValueKey('signin-password'),
            value: _password,
            onChanged: (v) => setState(() => _password = v),
            onSubmitted: _canContinue ? () => _nextStep() : null,
          );
        case 3:
          return SelectWorkplaceStep(
            key: const ValueKey('signin-select-workplace'),
            options: _signInWorkplaces,
            value: _selectedWorkplaceId,
            onChanged: (id) => setState(() => _selectedWorkplaceId = id),
            onCreateWorkplace: () {
              setState(() {
                _loginError = null;
                _selectedWorkplaceId = '';
                _workplaceName = '';
              });
              _goToStep(AuthMode.signin, 4);
            },
          );
        case 4:
          return WorkplaceStep(key: const ValueKey('signin-workplace'), value: _workplaceName, onChanged: (v) => setState(() => _workplaceName = v));
        default:
          return const SizedBox.shrink();
      }
    }

    switch (_step) {
      case 0:
        return WorkplaceStep(key: const ValueKey('signup-workplace'), value: _workplaceName, onChanged: (v) => setState(() => _workplaceName = v));
      case 1:
        return EmailStep(key: const ValueKey('signup-email'), value: _email, onChanged: (v) => setState(() => _email = v));
      case 2:
        return PasswordStep(
          key: const ValueKey('signup-password'),
          value: _password,
          onChanged: (v) => setState(() => _password = v),
          onSubmitted: _canContinue ? () => _nextStep() : null,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _authMode == AuthMode.signup ? SignUpMeta.title() : SignInMeta.title(_step);
    final subtitle = _authMode == AuthMode.signup ? SignUpMeta.subtitle(_step) : SignInMeta.subtitle(_step);
    final primaryLabel = _authMode == AuthMode.signup ? SignUpMeta.primaryActionLabel(_step) : SignInMeta.primaryActionLabel(_step);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Aptigen ERP', style: TextStyle(fontSize: 14, color: AppColors.slate400, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 24),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Column(
                      key: ValueKey('$_authMode-$_step-header'),
                      children: [
                        Text(title, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text(subtitle, style: TextStyle(color: AppColors.slate400)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Container(
                      key: ValueKey('$_authMode-$_step-field'),
                      child: _buildStepField(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_step > 0)
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: OutlinedButton.icon(
                            onPressed: _isSubmitting
                                ? null
                                : () {
                                    if (_authMode == AuthMode.signin && _step == 4) {
                                      _goToStep(AuthMode.signin, 3);
                                      return;
                                    }
                                    _goToStep(_authMode, _step - 1);
                                  },
                            icon: const Icon(Icons.chevron_left, size: 18),
                            label: const Text('Back'),
                          ),
                        ),
                      FilledButton.icon(
                        onPressed: (_canContinue && !_isSubmitting) ? _nextStep : null,
                        icon: _isSubmitting
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.chevron_right, size: 18),
                        label: Text(primaryLabel),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () {
                      _resetForm();
                      _goToStep(_authMode == AuthMode.signup ? AuthMode.signin : AuthMode.signup, 0);
                    },
                    child: Text(
                      _authMode == AuthMode.signup ? 'Already have an account? Sign in' : "Need an account? Sign up",
                    ),
                  ),
                  if (_loginError != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.08),
                        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_loginError!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
