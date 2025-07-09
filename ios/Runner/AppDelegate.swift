import UIKit
import Flutter
import WidgetKit
import UserNotifications
import os.log

@UIApplicationMain
class AppDelegate: FlutterAppDelegate {
    private let logger = OSLog(subsystem: "com.junseo.platoCalendar", category: "AppLifecycle")
    
    // MARK: - 애플리케이션 라이프사이클
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // 1. 알림 설정 (UserNotifications 프레임워크)
        UNUserNotificationCenter.current().delegate = self
        setupNotificationPermissions()
        
        // 2. 플러터 메소드 채널 설정
        setupMethodChannel()
        
        // 3. 플러터 플러그인 등록
        GeneratedPluginRegistrant.register(with: self)
        
        os_log("🟢 애플리케이션 시작 완료", log: logger)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    // MARK: - 알림 핸들링
    override func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // 포그라운드 알림 설정
        completionHandler([.banner, .sound, .badge])
        os_log("🔔 포그라운드 알림 수신", log: logger)
    }
    
    // MARK: - 메소드 채널 설정
    private func setupMethodChannel() {
        guard let controller = window?.rootViewController as? FlutterViewController else {
            os_log("🔴 FlutterViewController 초기화 실패", log: logger, type: .error)
            return
        }
        
        let channel = FlutterMethodChannel(
            name: "com.junseo.platoCalendar/userdefaults",
            binaryMessenger: controller.binaryMessenger
        )
        
        channel.setMethodCallHandler { [weak self] (call, result) in
            self?.handleMethodCall(call, result: result)
        }
    }
    
    // MARK: - 메소드 처리
    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        os_log("📞 메소드 호출: %{public}@", log: logger, call.method)
        
        switch call.method {
        case "saveAppointmentCounts":
            handleSaveCounts(call, result: result)
        case "testUserDefaults":
            handleTestUserDefaults(result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - 데이터 저장 처리
    private func handleSaveCounts(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let counts = args["counts"] as? [String: Int] else {
            os_log("🔴 잘못된 파라미터 형식", log: logger, type: .error)
            result(FlutterError(code: "INVALID_ARGS", message: "counts 파라미터 필요", details: nil))
            return
        }
        
        saveCounts(counts) { success in
            if success {
                os_log("🟢 데이터 저장 성공", log: self.logger)
                result(true)
            } else {
                os_log("🔴 모든 저장 방법 실패", log: self.logger, type: .error)
                result(false)
            }
        }
    }
    
    // MARK: - 테스트 메소드
    private func handleTestUserDefaults(_ result: @escaping FlutterResult) {
        guard let userDefaults = UserDefaults(suiteName: "group.com.junseo.platoCalendar") else {
            os_log("🔴 테스트: App Group 접근 실패", log: logger, type: .error)
            result(false)
            return
        }
        
        let testData: [String: Int] = ["test_date": Int.random(in: 1...100)]
        userDefaults.set(testData, forKey: "testCounts")
        
        DispatchQueue.global().async {
            let syncSuccess = userDefaults.synchronize()
            DispatchQueue.main.async {
                os_log("🟢 테스트 데이터 저장: %{public}@ (동기화: %@)", 
                       log: self.logger, 
                       testData.description, 
                       syncSuccess ? "성공" : "실패")
                WidgetCenter.shared.reloadAllTimelines()
                result(syncSuccess)
            }
        }
    }
    
    // MARK: - 저장 로직 (UserDefaults + 파일 폴백)
    private func saveCounts(_ counts: [String: Int], completion: @escaping (Bool) -> Void) {
    guard let groupURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: "group.com.junseo.platoCalendar"
    ) else {
        os_log("🔴 App Group 디렉토리 접근 실패", log: logger, type: .error)
        completion(false)
        return
    }
    
    let fileURL = groupURL.appendingPathComponent("appointmentCounts.json")
    os_log("📂 파일 경로: %{public}@", log: logger, fileURL.path)
    
    do {
        let data = try JSONSerialization.data(
            withJSONObject: counts,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        
        os_log("🟢 JSON 파일 저장 성공: %{public}@", 
               log: logger,
               String(data: data, encoding: .utf8) ?? "데이터 변환 실패")
        
        WidgetCenter.shared.reloadAllTimelines()
        completion(true)
    } catch {
        os_log("🔴 파일 저장 실패: %{public}@", log: logger, type: .error, error.localizedDescription)
        completion(false)
    }
}
    
    // MARK: - 파일 저장
    private func saveToFile(counts: [String: Int], completion: @escaping (Bool) -> Void) {
        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.junseo.platoCalendar"
        ) else {
            os_log("🔴 파일 저장: App Group URL 접근 실패", log: logger, type: .error)
            completion(false)
            return
        }
        
        let fileURL = groupURL.appendingPathComponent("appointmentCounts.json")
        
        do {
            let data = try JSONSerialization.data(withJSONObject: counts, options: [])
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            os_log("🟢 파일 저장 성공: %{public}@", log: logger, fileURL.path)
            WidgetCenter.shared.reloadAllTimelines()
            completion(true)
        } catch {
            os_log("🔴 파일 저장 실패: %{public}@", log: logger, type: .error, error.localizedDescription)
            completion(false)
        }
    }
    
    // MARK: - 알림 권한 설정
    private func setupNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                os_log("🔴 알림 권한 요청 실패: %{public}@", log: self.logger, type: .error, error.localizedDescription)
                return
            }
            os_log("🟢 알림 권한: %@", log: self.logger, granted ? "허용" : "거부")
        }
    }
    
    // MARK: - URL 스킴 핸들링
    override func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey : Any] = [:]
    ) -> Bool {
        os_log("🔗 딥링크 수신: %{public}@", log: logger, url.absoluteString)
        // 여기에 딥링크 처리 로직 추가
        return true
    }
}