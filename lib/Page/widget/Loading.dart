
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:connectivity_plus/connectivity_plus.dart'; // 네트워크 체크 추가
import '../../utility.dart';
import '../../pnu/pnu.dart';
import 'package:plato_calendar/notify.dart';
import '../sfCalendar.dart';

class Loading extends AnimatedWidget {
  late AnimationController controller;
  final InterstitialAd? interstitialAd;
  final bool isInterstitialAdReady;
  static DateTime _manualUpdateTime = DateTime.utc(0);

  int get remainingMinutes =>
      5 - DateTime.now().difference(_manualUpdateTime).inMinutes;

  Loading({
    Key? key,
    Animation<double>? animation,
    AnimationController? control,
    this.interstitialAd,
    required this.isInterstitialAdReady,
  }) : super(key: key, listenable: animation as Animation<double>) {
    controller = control!;
  }

  void _showInterstitialAd() async {
    if (!controller.isAnimating) {
      if (DateTime.now().difference(_manualUpdateTime).inMinutes <= 4) {
        showToastMessageCenter(
            "플라토 새로고침은 5분에 한 번씩만 가능합니다.\n(남은 시간 : $remainingMinutes분)");
        return;
      }

      if (isInterstitialAdReady && interstitialAd != null) {
        interstitialAd!.show();
        await _handleRefresh();
      } else {
        await _handleRefresh();
      }
    }
  }

  Future<void> _handleRefresh() async {
    controller.repeat();
    try {
      await refresh(); // 공통 새로고침 로직 호출
      _manualUpdateTime = DateTime.now();
      print("새로고침 진행중!");
    } catch (e) {
      print("새로고침 실패!: $e");
    } finally {
      controller.stop();
      controller.reset();
    }
  }

  // 백그라운드 및 UI 호출용 정적 메서드
  static Future<void> refresh() async {
    try {
      // 네트워크 연결 확인
      var connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        print("⚠️ 네트워크 연결 없음: 새로고침 스킵");
        return;
      }

      await update(force: true);
      print("✅ 백그라운드 새로고침 완료");
      await Notify.scheduleEventReminderNotifications();
      Calendar.saveAppointmentCounts();
    } catch (e) {
      print("⚠️ 백그라운드 새로고침 실패: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final animation = listenable as Animation<double>;
    return Transform.rotate(
      angle: animation.value,
      child: Container(
        padding: EdgeInsets.zero,
        child: IconButton(
          iconSize: 28,
          padding: EdgeInsets.zero,
          onPressed: () {
            _showInterstitialAd();
          },
          icon: Icon(
            Icons.refresh_rounded,
            color: Color.fromARGB(255, 40, 100, 200),
          ),
        ),
      ),
    );
  }
}