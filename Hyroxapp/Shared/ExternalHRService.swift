import Foundation
import Observation
#if canImport(CoreBluetooth)
import CoreBluetooth
#endif

// §20 Path A — CoreBluetooth wrapper for ingesting heart rate from
// external BLE HR sources via the standard Heart Rate Service GATT
// profile. Works with any device that advertises HRS — Garmin
// watches in "Broadcast Heart Rate" mode, Polar H10, Wahoo TICKR,
// Garmin HRM-Pro Plus, Suunto belts, Coros chest straps, etc.
//
// Why this exists:
//   • Apple Watch and AirPods Pro 3 hand HR samples to us through
//     HealthKit + WCSession (and §19's adaptive sourcing handles
//     the fusion). They're well-supported.
//   • A meaningful slice of HYROX athletes wear Garmins and won't
//     buy an Apple Watch. Pre-Path-A those users had no path into
//     Trakrr's coaching layer. With this service, their Garmin
//     in HR broadcast mode acts like any standard BLE heart rate
//     monitor — same code path as a Polar H10 chest strap.
//   • No Garmin SDK, no Connect IQ app, no partner approval. Pure
//     CoreBluetooth talking to a 13-year-old open standard.
//
// Architecture:
//   • Singleton (mirror of HeadphoneMotionService and
//     WatchCompanionService patterns).
//   • `@Observable` so views (the pairing sheet, Settings, etc.)
//     bind to state directly.
//   • CBCentralManagerDelegate + CBPeripheralDelegate via NSObject
//     conformance. Delegate methods are `nonisolated` and hop to
//     MainActor for any observable mutation — same hygiene pattern
//     §8.1 documents for all framework delegate callbacks.
//   • Single `onHeartRate` callback feeds samples into whichever
//     viewmodel is active (RaceViewModel.ingestHeartRate /
//     FreeRunViewModel.ingestHeartRateBPM). Registered by the
//     view layer in onAppear, cleared in onDisappear.
//
// Lifecycle:
//   • App-wide: ExternalHRService.shared is created lazily on first
//     access. CBCentralManager init happens THERE so the
//     "Bluetooth Always" permission prompt fires when the user
//     opens the pairing sheet, not on cold launch.
//   • Per-race: viewmodels call `attemptReconnectToPaired()` on
//     race/free-run start. The service tries to reconnect to the
//     last paired peripheral by UUID. Subsequent HR notifications
//     flow through `onHeartRate`.
//   • Pairing: `startScan()` advertises HRS UUID filter, populates
//     `discoveredDevices`. UI shows the list; user taps one.
//     `pair(device:)` connects, persists the peripheral UUID +
//     name to UserProfile, and the service remembers them for
//     auto-reconnect.
//
// Background behavior caveat: iOS aggressively suspends CoreBluetooth
// for backgrounded apps even with the `bluetooth-central` background
// mode. If the athlete pockets the phone during a long sled push and
// the OS suspends us, HR may drop until the screen wakes. Documented
// in §20.2 — surfaced in the pairing UI as a known trade-off.
@MainActor
@Observable
final class ExternalHRService: NSObject {

    static let shared = ExternalHRService()

    // MARK: - Standard BLE UUIDs

    #if canImport(CoreBluetooth)
    /// Heart Rate Service — defined by the Bluetooth SIG.
    /// https://www.bluetooth.com/specifications/gatt/services/
    private static let hrServiceUUID = CBUUID(string: "180D")

    /// Heart Rate Measurement characteristic. Notify-only; the
    /// peripheral pushes a sample every ~1Hz when subscribed.
    private static let hrMeasurementCharacteristicUUID = CBUUID(string: "2A37")
    #endif

    // MARK: - Public state (observed by views)

    /// Connection lifecycle. Drives the pairing sheet's UI state,
    /// the source-attribution glyph on the live HR chip, and the
    /// pre-race sensor check.
    enum ConnectionState: Equatable {
        /// Default before any user interaction. Also entered after
        /// an explicit disconnect.
        case idle
        /// Bluetooth is unavailable system-wide (airplane mode, BT
        /// turned off in Control Center). User-actionable —
        /// pairing UI shows a "turn on Bluetooth" hint.
        case poweredOff
        /// User declined the Bluetooth permission prompt. Pairing
        /// UI shows a "grant in Settings" deep link.
        case unauthorized
        /// Actively scanning for HRS-advertising peripherals.
        case scanning
        /// In the middle of a connect handshake for a given device.
        case connecting(displayName: String)
        /// Subscribed to HR Measurement and receiving samples.
        case connected(displayName: String)
    }

    private(set) var state: ConnectionState = .idle

    /// Devices discovered during the current scan. Cleared on
    /// `startScan()` so a re-scan starts fresh. View renders this
    /// as a tappable list.
    private(set) var discoveredDevices: [DiscoveredDevice] = []

    /// Most recent HR sample received from the connected
    /// peripheral, with timestamp. Set on every notification;
    /// nil after disconnect. Views CAN read this directly (the
    /// pairing sheet uses it to render "159 bpm" once a connection
    /// is live, as confidence the pairing works), but the canonical
    /// race-time consumer is the `onHeartRate` callback below.
    private(set) var lastSample: (bpm: Double, sampledAt: Date)?

    /// Identifiable record for the SwiftUI ForEach in the pairing
    /// sheet. `id` is the peripheral's CBPeripheral.identifier
    /// (a stable UUID that survives Bluetooth restarts).
    struct DiscoveredDevice: Identifiable, Equatable {
        let id: UUID
        let displayName: String
        let rssi: Int
    }

    // MARK: - HR ingest callback

    /// Registered by the active surface (RaceView, FreeRunView)
    /// in onAppear; cleared in onDisappear. Fires on every
    /// validated HR Measurement notification. Same shape as
    /// `WatchCompanionService.onHeartRate` and
    /// `HeadphoneMotionService`'s callback contracts.
    ///
    /// Closure receives bpm + the moment we parsed the
    /// notification. BLE doesn't carry a sensor-side timestamp
    /// in the standard HR Measurement frame, so "now" is the
    /// best we have (≤100ms latency in practice).
    var onHeartRate: (@MainActor @Sendable (Double, Date) -> Void)?

    // MARK: - CoreBluetooth handles

    #if canImport(CoreBluetooth)
    private var centralManager: CBCentralManager?

    /// The peripheral we're currently connected (or connecting) to.
    /// Held strongly so iOS doesn't deallocate it mid-flight.
    private var connectedPeripheral: CBPeripheral?

    /// HR Measurement characteristic on the connected peripheral.
    /// Cached so disconnect can `setNotifyValue(false, for:)` it
    /// before tearing down.
    private var hrMeasurementCharacteristic: CBCharacteristic?

    /// UUID of the most recently paired peripheral. Loaded from
    /// UserProfile on app start; used by `attemptReconnectToPaired()`.
    /// nil when the user has never paired (or unpaired).
    private var pairedPeripheralUUID: UUID?

    /// Display name of the paired peripheral. Cached locally so the
    /// pre-race sensor check can show "Forerunner 265" even before
    /// the actual reconnect lands.
    private var pairedPeripheralName: String?
    #endif

    // MARK: - Init

    private override init() {
        super.init()
        // CBCentralManager init is deferred until the user explicitly
        // taps "Pair external HR monitor" — that's when the OS
        // permission prompt fires. Initializing on cold launch
        // would prompt every athlete who doesn't even have a BLE
        // strap, which is bad UX.
    }

    // MARK: - Public API

    /// Load a previously-saved pairing record. Called by
    /// ContentView.bootstrap (or similar) on app launch so
    /// auto-reconnect knows which device to reach for. UUID +
    /// name typically come from UserProfile.pairedHRDeviceUUID /
    /// pairedHRDeviceName.
    ///
    /// Calling this does NOT initiate a connection — that's
    /// `attemptReconnectToPaired()`. Separation is deliberate:
    /// we want the registry to know the pairing record exists
    /// even when the user isn't actively racing.
    func loadPaired(uuid: UUID?, name: String?) {
        #if canImport(CoreBluetooth)
        pairedPeripheralUUID = uuid
        pairedPeripheralName = name
        // Reflect the paired record into the registry so the
        // TrainHub sensor row can show "Paired: Forerunner 265"
        // even before the reconnect lands. The actual connected
        // flag (`hasExternalHR`) flips later, on connect.
        // Intentionally don't set hasExternalHR here.
        #endif
    }

    /// Begin scanning for HRS-advertising peripherals. Lazily
    /// initializes the CBCentralManager on first call so the
    /// Bluetooth permission prompt fires at the right time.
    ///
    /// Clears any existing discovered list. Caller should
    /// `stopScan()` when the pairing sheet closes so the radio
    /// goes quiet.
    func startScan() {
        #if canImport(CoreBluetooth)
        ensureCentralManager()
        discoveredDevices = []
        guard let central = centralManager else { return }
        guard central.state == .poweredOn else {
            // Will start scanning automatically once the central
            // transitions to poweredOn via the delegate callback.
            return
        }
        state = .scanning
        central.scanForPeripherals(
            withServices: [Self.hrServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        #endif
    }

    /// Stop the active scan. Idempotent — no-op when not scanning.
    func stopScan() {
        #if canImport(CoreBluetooth)
        centralManager?.stopScan()
        if case .scanning = state {
            state = .idle
        }
        #endif
    }

    /// Connect to a discovered device. Persists the peripheral
    /// UUID + name so future race starts can auto-reconnect.
    /// The persisted record lives on UserProfile (the caller is
    /// responsible for writing it after this method confirms a
    /// successful connection — typically via the `state ==
    /// .connected` transition).
    func pair(device: DiscoveredDevice) {
        #if canImport(CoreBluetooth)
        guard let central = centralManager else { return }
        guard let peripheral = central.retrievePeripherals(
            withIdentifiers: [device.id]
        ).first else { return }

        stopScan()
        connectedPeripheral = peripheral
        peripheral.delegate = self
        state = .connecting(displayName: device.displayName)
        central.connect(peripheral, options: nil)
        #endif
    }

    /// Disconnect from the currently-connected peripheral.
    /// Idempotent. Also clears the paired-record cache so the
    /// next reconnect attempt picks up a freshly-stored UUID.
    func disconnect() {
        #if canImport(CoreBluetooth)
        guard let central = centralManager,
              let peripheral = connectedPeripheral else {
            state = .idle
            return
        }
        if let characteristic = hrMeasurementCharacteristic {
            peripheral.setNotifyValue(false, for: characteristic)
        }
        central.cancelPeripheralConnection(peripheral)
        connectedPeripheral = nil
        hrMeasurementCharacteristic = nil
        state = .idle
        lastSample = nil
        SensorSourceRegistry.shared.recordExternalHRConnection(nil)
        #endif
    }

    /// Forget the paired peripheral entirely. Caller should also
    /// clear UserProfile.pairedHRDeviceUUID / Name. Useful for the
    /// "Unpair device" button in Settings → Devices.
    func unpair() {
        #if canImport(CoreBluetooth)
        disconnect()
        pairedPeripheralUUID = nil
        pairedPeripheralName = nil
        #endif
    }

    /// Try to reconnect to the previously-paired peripheral.
    /// Called by viewmodels on race / free-run start so HR begins
    /// streaming as soon as the cathedral comes up. Bails silently
    /// when no pairing record exists.
    func attemptReconnectToPaired() {
        #if canImport(CoreBluetooth)
        guard let uuid = pairedPeripheralUUID,
              let displayName = pairedPeripheralName else { return }
        ensureCentralManager()
        guard let central = centralManager else { return }
        guard central.state == .poweredOn else {
            // Will reconnect via the delegate callback when BT
            // comes back online (already on, low power, etc.).
            return
        }
        let candidates = central.retrievePeripherals(withIdentifiers: [uuid])
        guard let peripheral = candidates.first else { return }
        connectedPeripheral = peripheral
        peripheral.delegate = self
        state = .connecting(displayName: displayName)
        central.connect(peripheral, options: nil)
        #endif
    }

    // MARK: - Internal

    #if canImport(CoreBluetooth)
    /// Create the CBCentralManager on first need. The init call
    /// triggers the OS-level Bluetooth permission prompt (governed
    /// by `NSBluetoothAlwaysUsageDescription` in Info.plist).
    private func ensureCentralManager() {
        if centralManager == nil {
            centralManager = CBCentralManager(
                delegate: self,
                queue: nil,  // delegate callbacks come on main queue
                options: [CBCentralManagerOptionShowPowerAlertKey: true]
            )
        }
    }

    /// Parse a single HR Measurement notification payload per the
    /// Bluetooth SIG spec:
    ///   • Byte 0: Flags
    ///     - Bit 0: HR value format (0 = uint8, 1 = uint16)
    ///     - Bits 1-2: Sensor contact status (ignored)
    ///     - Bit 3: Energy expended present (ignored)
    ///     - Bit 4: RR-interval present (ignored — future HRV)
    ///   • Byte 1[+2]: HR value, little-endian uint8 or uint16
    ///   • Optional bytes: energy, RR-intervals (skipped)
    ///
    /// Returns nil for malformed payloads.
    fileprivate static func parseHRMeasurement(_ data: Data) -> Double? {
        guard data.count >= 2 else { return nil }
        let flags = data[0]
        let is16BitFormat = (flags & 0x01) != 0
        if is16BitFormat {
            guard data.count >= 3 else { return nil }
            let lo = UInt16(data[1])
            let hi = UInt16(data[2])
            return Double(lo | (hi << 8))
        } else {
            return Double(data[1])
        }
    }
    #endif
}

// MARK: - CBCentralManagerDelegate

#if canImport(CoreBluetooth)
extension ExternalHRService: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // CBCentralManager hands us state changes on its own queue;
        // hop to MainActor before mutating any @Observable state.
        let newState = central.state
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch newState {
            case .poweredOn:
                // If we were waiting on Bluetooth (idle after a
                // permission denial that was later granted, or
                // after the user toggled BT back on), kick off a
                // reconnect attempt for the paired device.
                if case .idle = self.state, self.pairedPeripheralUUID != nil {
                    self.attemptReconnectToPaired()
                }
            case .poweredOff:
                self.state = .poweredOff
                self.connectedPeripheral = nil
                self.hrMeasurementCharacteristic = nil
                self.lastSample = nil
                SensorSourceRegistry.shared.recordExternalHRConnection(nil)
            case .unauthorized:
                self.state = .unauthorized
            case .unsupported, .resetting, .unknown:
                self.state = .idle
            @unknown default:
                self.state = .idle
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        // Capture Sendable values before the actor hop —
        // CBPeripheral is not Sendable, so we extract what we
        // need (identifier + name) on the framework's queue.
        let id = peripheral.identifier
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let peripheralName = peripheral.name
        let displayName = advertisedName ?? peripheralName ?? "Unknown device"
        let rssi = RSSI.intValue

        Task { @MainActor [weak self] in
            guard let self else { return }
            let device = DiscoveredDevice(
                id: id,
                displayName: displayName,
                rssi: rssi
            )
            // De-dupe by id — same device can advertise multiple
            // times during a scan. Replace the prior entry so the
            // RSSI / name reflect the latest packet.
            if let existing = self.discoveredDevices.firstIndex(where: { $0.id == id }) {
                self.discoveredDevices[existing] = device
            } else {
                self.discoveredDevices.append(device)
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        let displayName = peripheral.name ?? "External HR monitor"
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.state = .connecting(displayName: displayName)
            // Cache the paired-name even if we're auto-reconnecting
            // (the cached name might be stale after a firmware
            // rename).
            self.pairedPeripheralName = displayName
        }
        // Service discovery is what eventually triggers the
        // .connected state once we find HRS + subscribe to HR
        // Measurement. Initiate it here.
        peripheral.discoverServices([Self.hrServiceUUID])
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.state = .idle
            self.connectedPeripheral = nil
            self.hrMeasurementCharacteristic = nil
            SensorSourceRegistry.shared.recordExternalHRConnection(nil)
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.state = .idle
            self.connectedPeripheral = nil
            self.hrMeasurementCharacteristic = nil
            self.lastSample = nil
            SensorSourceRegistry.shared.recordExternalHRConnection(nil)
        }
    }
}

// MARK: - CBPeripheralDelegate

extension ExternalHRService: CBPeripheralDelegate {

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        guard error == nil,
              let services = peripheral.services else { return }
        for service in services where service.uuid == Self.hrServiceUUID {
            // Discover the HR Measurement characteristic on the
            // HRS service. didDiscoverCharacteristicsFor will
            // subscribe to notifications.
            peripheral.discoverCharacteristics(
                [Self.hrMeasurementCharacteristicUUID],
                for: service
            )
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil,
              let characteristics = service.characteristics else { return }

        var foundCharacteristic: CBCharacteristic?
        for characteristic in characteristics
            where characteristic.uuid == Self.hrMeasurementCharacteristicUUID {
            peripheral.setNotifyValue(true, for: characteristic)
            foundCharacteristic = characteristic
        }

        if let characteristic = foundCharacteristic {
            let displayName = peripheral.name ?? "External HR monitor"
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.hrMeasurementCharacteristic = characteristic
                self.state = .connected(displayName: displayName)
                // Persist the now-paired peripheral UUID so future
                // launches can auto-reconnect. UserProfile mirror
                // lives at the call site (Settings sheet / pairing
                // sheet); we cache locally for the rest of this
                // app session.
                self.pairedPeripheralUUID = peripheral.identifier
                self.pairedPeripheralName = displayName
                SensorSourceRegistry.shared.recordExternalHRConnection(displayName)
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil,
              characteristic.uuid == Self.hrMeasurementCharacteristicUUID,
              let data = characteristic.value else { return }

        guard let bpm = ExternalHRService.parseHRMeasurement(data) else { return }
        guard bpm >= 30, bpm <= 230 else { return }
        let sampledAt = Date()

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.lastSample = (bpm: bpm, sampledAt: sampledAt)
            // Mark the source so the live HR chip's attribution
            // glyph shows the external-BLE radio icon instead of
            // applewatch / airpodspro. Display name comes from the
            // cached pairing record.
            let name = self.pairedPeripheralName ?? "External HR monitor"
            SensorSourceRegistry.shared.recordHRSource(
                .externalBLE(displayName: name)
            )
            self.onHeartRate?(bpm, sampledAt)
        }
    }
}
#endif
