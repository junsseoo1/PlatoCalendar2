import 'package:flutter/material.dart';
import '../../utility.dart'; // showToastMessageTop 등의 유틸리티 함수 사용
import '../../Data/userData.dart'; // UserData 접근 필요

// Loading Icon
class Loading2 extends AnimatedWidget {
  late AnimationController controller;
  static DateTime _manualUpdateTime = DateTime.utc(0); // 초기값 UTC로 설정

  Loading2({
    Key? key,
    Animation<double>? animation,
    AnimationController? control,
  }) : super(key: key, listenable: animation as Animation<double>) {
    controller = control!;
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
          onPressed: () async {
            if (!controller.isAnimating) {
              if (DateTime.now().difference(_manualUpdateTime).inMinutes > 0) {
                controller.repeat(); // 애니메이션 시작
                try {
                  // Google 계정 연동 체크 없이 바로 새로고침
                  await UserData.googleCalendar.updateCalendarRe();
                  _manualUpdateTime = DateTime.now(); // 한국 시간으로 갱신
                  print("새로고침 진행중 !");
                } catch (e) {
                  print("새로고침 실패 ! : $e");
                } finally {
                  controller.stop();
                  controller.reset(); // 애니메이션 종료
                }
              } else {
                showToastMessageCenter("구글 동기화는 1분에 한 번씩만 가능합니다.");
              }
            }
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
