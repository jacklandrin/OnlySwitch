//
//  Parser+Packets.swift
//  AudioStreamer
//
//  Created by Syed Haris Ali on 1/6/18.
//  Copyright © 2018 Ausome Apps LLC. All rights reserved.
//

import Foundation
import AVFoundation
import os.log

let parserQueue = DispatchQueue(label: "com.fastlearner.streamer.parser",attributes: .concurrent)

func ParserPacketCallback(_ context: UnsafeMutableRawPointer, _ byteCount: UInt32, _ packetCount: UInt32, _ data: UnsafeRawPointer, _ packetDescriptions: UnsafeMutablePointer<AudioStreamPacketDescription>) {
    let decriptions:UnsafeMutablePointer<AudioStreamPacketDescription>? = packetDescriptions
    ParserPacketCallback(context, byteCount, packetCount, data, decriptions)
}

func ParserPacketCallback(_ context: UnsafeMutableRawPointer, _ byteCount: UInt32, _ packetCount: UInt32, _ data: UnsafeRawPointer, _ packetDescriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?) {
    let parser = Unmanaged<Parser>.fromOpaque(context).takeUnretainedValue()
    let packetDescriptionsOrNil: UnsafeMutablePointer<AudioStreamPacketDescription>? = packetDescriptions
    let isCompressed = packetDescriptionsOrNil != nil
//    os_log("%@ - %d [bytes: %i, packets: %i, compressed: %@]", log: Parser.loggerPacketCallback, type: .debug, #function, #line, byteCount, packetCount, "\(isCompressed)")
    
    /// At this point we should definitely have a data format
    guard let dataFormat = parser.dataFormat else {
        return
    }
    
    
    parserQueue.sync {
        /// Iterate through the packets and store the data appropriately
        if isCompressed {
            for i in 0 ..< Int(packetCount) {
                let packetDescription = packetDescriptions![i]
                let packetStart = Int(packetDescription.mStartOffset)
                let packetSize = Int(packetDescription.mDataByteSize)
                let packetData = Data(bytes: data.advanced(by: packetStart), count: packetSize)
                parser.packets.append((packetData, packetDescription))
            }
        } else {
            let format = dataFormat.streamDescription.pointee
            let bytesPerPacket = Int(format.mBytesPerPacket)
            for i in 0 ..< Int(packetCount) {
                let packetStart = i * bytesPerPacket
                let packetSize = bytesPerPacket
                let packetData = Data(bytes: data.advanced(by: packetStart), count: packetSize)
                parser.packets.append((packetData, nil))
            }
        }
        
        
    }
        

}
