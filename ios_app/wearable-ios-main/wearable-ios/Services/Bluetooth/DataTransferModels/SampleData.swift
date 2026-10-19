//
//  SampleData.swift
//  wearable-ios
//
//  Created by Luke Redmore on 2/20/24.
//  Updated by Jade Chng on 10/06/2026
//

import SwiftUI
import Charts

protocol WearableDataType: Plottable, Comparable {}
extension UInt8: WearableDataType { }
extension Float32: WearableDataType { }
extension UInt32: WearableDataType { }


/** This class holds up to one complete row of data that can be collected by the wearble. It also serves as the definition of all types of data that CAN be collected. That is, if a new type of data is added, this file needs to be modified, following the same format as the other data types present */
public class SampleData: CustomStringConvertible {
    // The instance variables holding the data types
    private(set) var waypoints: UInt8? = nil
    private(set) var battery: UInt8? = nil
    private(set) var acc_x: Float32? = nil
    private(set) var acc_y: Float32? = nil
    private(set) var acc_z: Float32? = nil
    private(set) var gyro_x: Float32? = nil
    private(set) var gyro_y: Float32? = nil
    private(set) var gyro_z: Float32? = nil
    private(set) var mag_x: Float32? = nil
    private(set) var mag_y: Float32? = nil
    private(set) var mag_z: Float32? = nil
    private(set) var air_temp: Float32? = nil
    private(set) var thermistor: UInt32? = nil
    private(set) var press: Float32? = nil
    private(set) var humid: Float32? = nil
    private(set) var ppg_r: UInt32? = nil
    private(set) var ppg_b: UInt32? = nil
    private(set) var ppg_ir: UInt32? = nil
    private(set) var ppg_g: UInt32? = nil
    
    /** This function is how new, raw `Data` is decoded into a readable value added to the instance. The position argument to the position in the select bit corresponding to the given data. We set the instance variable to the decoded value, then (for logging purposes) return a `String` with the name + value of what we just decoded */
    func appendNewData(data: Data, position: Int) throws -> String {
        if position == 1 || (position >= 14 && position <= 17), data.uint32 == 4_294_967_295 {
            throw DataTransferError.sensorError
        } else if position >= 2 && position <= 13, data.float32 == -1.0 {
            throw DataTransferError.sensorError
        }
        switch position {
        case 0:
            waypoints = Data(data)[2..<3].uint8
            battery = Data(data)[3..<4].uint8
            return "waypoints(\(waypoints!)), battery(\(battery!))"
        case 1: thermistor = data.uint32
            return "thermistor(\(thermistor!))"
        case 2: air_temp = data.float32
            return "air_temp(\(air_temp!))"
        case 3: press = data.float32
            return "press(\(press!))"
        case 4: humid = data.float32
            return "humid(\(humid!))"
        case 5: gyro_x = data.float32
            return "gyro_x(\(gyro_x!))"
        case 6: gyro_y = data.float32
            return "gyro_y(\(gyro_y!))"
        case 7: gyro_z = data.float32
            return "gyro_z(\(gyro_z!))"
        case 8: mag_x = data.float32
            return "mag_x(\(mag_x!))"
        case 9: mag_y = data.float32
            return "mag_y(\(mag_y!))"
        case 10: mag_z = data.float32
            return "mag_z(\(mag_z!))"
        case 11: acc_x = data.float32
            return "acc_x(\(acc_x!))"
        case 12: acc_y = data.float32
            return "acc_y(\(acc_y!))"
        case 13: acc_z = data.float32
            return "acc_z(\(acc_z!))"
        case 14: ppg_r = data.uint32
            return "ppg_r(\(ppg_r!))"
        case 15: ppg_b = data.uint32
            return "ppg_b(\(ppg_b!))"
        case 16: ppg_ir = data.uint32
            return "ppg_ir(\(ppg_ir!))"
        case 17: ppg_g = data.uint32
            return "ppg_g(\(ppg_g!))"
        default: throw DataTransferError.unknownDataType
        }
    }
    
    /** Defines the column order of the exported CSV. The timestamp is added later and should NOT be added here. Must match with `csvString` */
    static let CSV_COLUMN_ORDER = [
        "waypoints",
        "battery",
        "acc_x",
        "acc_y",
        "acc_z",
        "gyro_x",
        "gyro_y",
        "gyro_z",
        "mag_x",
        "mag_y",
        "mag_z",
        "air_temp",
        "thermistor",
        "press",
        "humid",
        "ppg_r",
        "ppg_b",
        "ppg_ir",
        "ppg_g"
    ]
    
    /** Defines each row of the exported CSV. The timestamp is added later and should NOT be added here.  Must match with `CSV_COLUMN_ORDER` */
    var csvString: String { [
        valOrBlank(waypoints),
        valOrBlank(battery),
        valOrBlank(acc_x),
        valOrBlank(acc_y),
        valOrBlank(acc_z),
        valOrBlank(gyro_x),
        valOrBlank(gyro_y),
        valOrBlank(gyro_z),
        valOrBlank(mag_x),
        valOrBlank(mag_y),
        valOrBlank(mag_z),
        valOrBlank(air_temp),
        valOrBlank(thermistor),
        valOrBlank(press),
        valOrBlank(humid),
        valOrBlank(ppg_r),
        valOrBlank(ppg_b),
        valOrBlank(ppg_ir),
        valOrBlank(ppg_g),
    ].joined(separator: ",")
    }
    
    /** This function is used to combine 2 `SampleData` objects into this instance (not the instance of the argument). It is used to make sure samples with duplicate timestamps end up in the same CSV row, as well as keep the` SampleData` instance used as the live, displayed data up to date without recreating it each time.  */
    func merge(from: SampleData) {
        self.waypoints = from.waypoints ?? self.waypoints
        self.battery = from.battery ?? self.battery
        self.acc_x = from.acc_x ?? self.acc_x
        self.acc_y = from.acc_y ?? self.acc_y
        self.acc_z = from.acc_z ?? self.acc_z
        self.gyro_x = from.gyro_x ?? self.gyro_x
        self.gyro_y = from.gyro_y ?? self.gyro_y
        self.gyro_z = from.gyro_z ?? self.gyro_z
        self.mag_x = from.mag_x ?? self.mag_x
        self.mag_y = from.mag_y ?? self.mag_y
        self.mag_z = from.mag_z ?? self.mag_z
        self.air_temp = from.air_temp ?? self.air_temp
        self.thermistor = from.thermistor ?? self.thermistor
        self.press = from.press ?? self.press
        self.humid = from.humid ?? self.humid
        self.ppg_r = from.ppg_r ?? self.ppg_r
        self.ppg_b = from.ppg_b ?? self.ppg_b
        self.ppg_ir = from.ppg_ir ?? self.ppg_ir
        self.ppg_g = from.ppg_g ?? self.ppg_g
    }
    
    /** If adding a new data type, the last thing that would need to be done is add another row in `LiveDataViewSingle.swift` with the new data type */
    
    /* --- NOTHING BELOW THIS POINT NEEDS TO BE MODIFIED WHEN ADDING A NEW DATA TYPE --- */
    
    private func valOrBlank(_ val: CustomStringConvertible?) -> String {
        guard let present = val else { return "" }
        return present.description
    }
    
    public var description: String {
        var toRet = "SampleData(\n"
        let data = csvString.split(separator: ",", omittingEmptySubsequences: false)
        for i in 0..<SampleData.CSV_COLUMN_ORDER.count where data[i] != "" {
            toRet += "\t\(SampleData.CSV_COLUMN_ORDER[i]): \(data[i])\n"
        }
        toRet += ")"
        return toRet
    }
}


// Maps v0 frames into the original UI's model without its legacy sentinel rules.
// Keep this extension in SampleData.swift so it can set private(set) fields.
extension SampleData {
    static func fromV0Frame(_ b: [UInt8]) -> SampleData? {
        guard b.count == 20, b[0] == 3 else { return nil }
        func u16(_ i: Int) -> UInt16 { UInt16(b[i]) | UInt16(b[i + 1]) << 8 }
        guard u16(18) == 1 else { return nil }
        let x = Float32(Int16(bitPattern: u16(12)))
        let y = Float32(Int16(bitPattern: u16(14)))
        let z = Float32(Int16(bitPattern: u16(16)))
        let sample = SampleData()
        switch b[1] {
        case 1:
            sample.acc_x = x * 0.000061
            sample.acc_y = y * 0.000061
            sample.acc_z = z * 0.000061
        case 2:
            sample.gyro_x = x * 0.00875
            sample.gyro_y = y * 0.00875
            sample.gyro_z = z * 0.00875
        case 3:
            sample.air_temp = x / 100
            sample.humid = y / 100
        case 4...7:
            guard u16(14) <= 7, u16(16) == 0 else { return nil }
            let raw = UInt32(u16(12)) | UInt32(u16(14)) << 16
            switch b[1] {
            case 4: sample.ppg_ir = raw
            case 5: sample.ppg_r = raw
            case 6: sample.ppg_g = raw
            default: sample.ppg_b = raw
            }
        default: return nil
        }
        return sample
    }
}
