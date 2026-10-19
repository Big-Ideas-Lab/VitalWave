//
//  v0Command.swift
//  wearable-ios
//
//  Created by Jade Chng on 10/6/26.
//

import Foundation

enum V0Command {
    enum Operation: UInt8 {
        case start = 1
        case stop = 2
        case keepalive = 3
        case configure = 4
    }

    static let accelerometer: UInt32 = 1
    static let temperatureHumidity: UInt32 = 2
    static let ppg: UInt32 = 4
    static let gyroscope: UInt32 = 8

    // Firmware argument bytes: IMU Hz, temperature period /100ms, PPG Hz, LED mask.
    // 25 Hz IMU; 1 second temperature period; 50 Hz PPG; IR/red/green/blue enabled.
    static let liveConfiguration: UInt32 = 25 | (10 << 8) | (50 << 16) | (15 << 24)

    static func encode(operation: Operation, requestID: UInt16,
        sessionID: UInt32, sensorMask: UInt32 = 0,
        configuration: UInt32 = liveConfiguration
    ) -> Data {
        precondition(sessionID != 0 && requestID != 0)
        let argument: UInt32
        switch operation {
        case .start: argument = sensorMask
        case .configure: argument = configuration
        default: argument = 0
        }
        var data = Data([3, operation.rawValue])
        appendLittleEndian(requestID, to: &data)
        appendLittleEndian(argument, to: &data)
        appendLittleEndian(sessionID, to: &data)
        return data
    }

    private static func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { data.append(contentsOf: $0) }
    }
}

/// Choices supported by the v0 firmware. These describe streamed output rates.
struct V0SensorSettings {
    var infrared = true
    var red = true
    var green = true
    var blue = true
    var imu = true
    var temperatureHumidity = false
    var imuHz = 25
    var ppgHz = 50
    var temperaturePeriod = 10 // Units of 100 ms.

    var colourCount: Int { [infrared, red, green, blue].filter { $0 }.count }
    var ledMask: UInt32 {
        (infrared ? 1 : 0) | (red ? 2 : 0) | (green ? 4 : 0) | (blue ? 8 : 0)
    }
    var sensorMask: UInt8 {
        (imu ? 9 : 0) | (temperatureHumidity ? 2 : 0) | (colourCount > 0 ? 4 : 0)
    }
    var effectivePPGHz: Int { colourCount > 1 ? 50 : ppgHz }
    var valid: Bool {
        sensorMask != 0 && [10, 25, 50].contains(imuHz) &&
        [5, 10, 20].contains(temperaturePeriod) && [50, 100].contains(ppgHz)
    }
    var configurationWord: UInt32 {
        UInt32(imuHz) | (UInt32(temperaturePeriod) << 8) |
        (UInt32(effectivePPGHz) << 16) | (ledMask << 24)
    }
}
