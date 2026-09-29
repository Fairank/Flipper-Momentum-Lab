import Foundation
@preconcurrency import CoreLocation

/// Location belongs to an explicitly enabled foreground companion session.
/// This provider never requests Always access or keeps the app alive in background.
@MainActor
final class PhoneLocationProvider: NSObject, CLLocationManagerDelegate {
    var onLocation: ((CLLocation?, UInt32) async -> Void)?
    var onStatus: ((String) -> Void)?
    private var manager: CLLocationManager?
    private var sharing = false
    private var frequency: UInt32?
    private var waitingOnce = false
    private var lastDelivery = Date.distantPast
    private var requestedAfter = Date.distantPast
    private var deadline: Task<Void, Never>?
    private var delivery: Task<Void, Never>?
    private var latest: (CLLocation?, UInt32)?
    private var deliveryGeneration = UUID()
    private var streamGeneration = UUID()

    func setSharing(_ enabled: Bool) {
        if !enabled {
            sharing = false
            stopRequests()
            onStatus?("定位共享已关闭")
            return
        }
        sharing = true
        if manager == nil {
            let value = CLLocationManager()
            value.delegate = self
            value.desiredAccuracy = kCLLocationAccuracyBest
            value.distanceFilter = kCLDistanceFilterNone
            value.pausesLocationUpdatesAutomatically = true
            manager = value
        }
        guard let manager else { return }
        if manager.authorizationStatus == .notDetermined {
            onStatus?("请允许在使用 App 时访问位置")
            manager.requestWhenInUseAuthorization()
        } else {
            authorizationChanged()
        }
    }

    func requestOnce() async {
        guard await accessReady() else { return }
        waitingOnce = true
        requestedAfter = Date()
        manager?.requestLocation()
        deadline?.cancel()
        deadline = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, let self, self.waitingOnce else { return }
            self.waitingOnce = false
            self.onStatus?("暂时无法取得有效位置")
            self.deliver(nil, status: 63)
        }
    }

    func startStream(frequency: UInt32) async {
        guard (1...10).contains(frequency) else { deliver(nil, status: 63); return }
        let stream = streamGeneration
        guard await accessReady() else { return }
        guard streamGeneration == stream else { return }
        self.frequency = frequency
        requestedAfter = Date()
        lastDelivery = .distantPast
        manager?.startUpdatingLocation()
        onStatus?("正在共享定位，更新速度取决于手机定位服务")
    }

    func stopStream() {
        streamGeneration = UUID()
        frequency = nil
        manager?.stopUpdatingLocation()
        // requestLocation and startUpdatingLocation share one manager. Restart a
        // still-pending one-shot after stopping only the streaming subscription.
        if waitingOnce { manager?.requestLocation() }
        onStatus?(sharing ? "定位共享已就绪，等待设备请求" : "定位共享已关闭")
    }

    private func stopRequests() {
        deliveryGeneration = UUID()
        streamGeneration = UUID()
        manager?.stopUpdatingLocation()
        frequency = nil; waitingOnce = false; latest = nil
        deadline?.cancel(); deadline = nil
        delivery?.cancel(); delivery = nil
    }

    private func accessReady() async -> Bool {
        guard sharing else { deliver(nil, status: 62); return false }
        guard let manager else { deliver(nil, status: 60); return false }
        let generation = deliveryGeneration
        let servicesEnabled = await Task.detached { CLLocationManager.locationServicesEnabled() }.value
        guard !Task.isCancelled, sharing, deliveryGeneration == generation else { return false }
        guard servicesEnabled else {
            onStatus?("iPhone 系统定位服务已关闭")
            deliver(nil, status: 62); return false
        }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: return true
        case .denied, .restricted, .notDetermined:
            deliver(nil, status: 61); return false
        @unknown default:
            deliver(nil, status: 63); return false
        }
    }

    private func authorizationChanged() {
        guard sharing, let manager else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            onStatus?("定位共享已就绪，等待设备请求")
        case .denied, .restricted:
            let hadRequest = waitingOnce || frequency != nil
            stopRequests()
            onStatus?("定位权限未开放，可在 iPhone 设置中修改")
            if hadRequest { deliver(nil, status: 61) }
        case .notDetermined:
            onStatus?("等待定位权限选择")
        @unknown default:
            stopRequests(); onStatus?("定位服务暂不可用")
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationChanged()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard sharing, waitingOnce || frequency != nil, let location = locations.last,
              location.horizontalAccuracy >= 0, location.horizontalAccuracy.isFinite,
              CLLocationCoordinate2DIsValid(location.coordinate),
              location.timestamp.timeIntervalSince(requestedAfter) >= -5,
              abs(location.timestamp.timeIntervalSinceNow) <= 15 else { return }
        let now = Date()
        guard waitingOnce || now.timeIntervalSince(lastDelivery) >= 1.0 / Double(frequency ?? 1) else { return }
        waitingOnce = false; deadline?.cancel(); deadline = nil
        lastDelivery = now
        // Coalesce while BLE is slow: the newest sensor value matters, not a
        // growing backlog of old coordinates. There is only one delivery task.
        deliver(location, status: 0)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard sharing, waitingOnce || frequency != nil else { return }
        if let value = error as? CLError, value.code == .locationUnknown {
            onStatus?("正在等待有效定位")
            return // keep the one-shot deadline active
        }
        let status: UInt32 = (error as? CLError)?.code == .denied ? 61 : 63
        stopRequests()
        onStatus?(status == 61 ? "定位权限未开放" : "定位服务暂不可用")
        deliver(nil, status: status)
    }

    private func deliver(_ location: CLLocation?, status: UInt32) {
        latest = (location, status)
        guard delivery == nil else { return }
        let generation = deliveryGeneration
        delivery = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.deliveryGeneration == generation, let next = self.latest {
                self.latest = nil
                await self.onLocation?(next.0, next.1)
            }
            if self.deliveryGeneration == generation { self.delivery = nil }
        }
    }
}
