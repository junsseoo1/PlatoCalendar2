import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart'; // Connectivity 추가
import '../../Data/etc.dart';
import '../../Data/userData.dart';
import '../../pnu/pnu.dart';
import 'package:flutter/services.dart';

class LoginPage extends StatefulWidget {
  @override
  _LoginPageState createState() => _LoginPageState();
}

Future<void> _triggerVibration() async {
  HapticFeedback.lightImpact();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController idController = TextEditingController();
  final TextEditingController pwController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool isLoading = false;
  String? errorMessage; // 오류 메시지를 저장할 변수
  late AnimationController _animationController;
  late Animation<double> _buttonScaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _buttonScaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    idController.dispose();
    pwController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      isLoading = true;
      errorMessage = null; // 새 로그인 시도 시 오류 메시지 초기화
    });

    // 네트워크 상태 확인
    if (await Connectivity().checkConnectivity() == ConnectivityResult.none) {
      setState(() {
        isLoading = false;
        errorMessage = '인터넷 연결을 확인해주세요.';
      });
      return;
    }

    UserData.id = idController.text.trim();
    UserData.pw = pwController.text.trim();
    await update(force: true);

    if (mounted) {
      if (UserData.lastSyncInfo != null &&
          UserData.lastSyncInfo!.contains("오류")) {
        setState(() {
          isLoading = false;
          if (UserData.lastSyncInfo!.contains("네트워크 오류")) {
            errorMessage = '인터넷 연결을 확인해주세요.';
          } else {
            errorMessage = '아이디 또는 비밀번호가 잘못되었습니다.';
          }
        });
      } else {
        setState(() {
          isLoading = false;
        });
        Navigator.pop(context, true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Color.fromARGB(255, 59, 113, 208);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: isDarkMode ? Colors.grey[850] : Colors.white,
      contentPadding: const EdgeInsets.all(24.0),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: MediaQuery.of(context).size.width * 0.8,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '로그인',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDarkMode ? Colors.white : Colors.black87,
                    ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: idController,
                cursorColor: primaryColor,
                contextMenuBuilder: (context, editableTextState) =>
                    const SizedBox(),
                decoration: InputDecoration(
                  labelText: '아이디',
                  labelStyle: TextStyle(color: primaryColor),
                  filled: true,
                  fillColor: isDarkMode ? Colors.grey[900] : Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: primaryColor, width: 2),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                style:
                    TextStyle(color: isDarkMode ? Colors.white : Colors.black),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '아이디를 입력해주세요.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: pwController,
                obscureText: true,
                cursorColor: primaryColor,
                contextMenuBuilder: (context, editableTextState) =>
                    const SizedBox(),
                decoration: InputDecoration(
                  labelText: '비밀번호',
                  labelStyle: TextStyle(color: primaryColor),
                  filled: true,
                  fillColor: isDarkMode ? Colors.grey[900] : Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: primaryColor, width: 2),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                style:
                    TextStyle(color: isDarkMode ? Colors.white : Colors.black),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '비밀번호를 입력해주세요.';
                  }
                  return null;
                },
              ),
              if (errorMessage != null) // 오류 메시지 표시
                Padding(
                  padding: const EdgeInsets.only(top: 8.0, left: 16.0),
                  child: Text(
                    errorMessage!,
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              Center(
                child: ScaleTransition(
                  scale: _buttonScaleAnimation,
                  child: ElevatedButton(
                    onPressed: isLoading
                        ? null
                        : () async {
                            _triggerVibration();
                            _animationController
                                .forward()
                                .then((_) => _animationController.reverse());
                            await _handleLogin();
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(120, 48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                    ),
                    child: isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('로그인', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
