//
//  Reader+Converter.swift
//  AudioStreamer
//
//  Created by Syed Haris Ali on 1/7/18.
//  Copyright © 2018 Ausome Apps LLC. All rights reserved.
//

import Foundation
import AVFoundation
import AudioToolbox
import os.log

/// Input storage belongs to the reader and remains valid until the converter's next
/// input callback, including across AudioConverterFillComplexBuffer calls.
func ReaderConverterCallback(_ converter: AudioConverterRef,
                             _ packetCount: UnsafeMutablePointer<UInt32>,
                             _ ioData: UnsafeMutablePointer<AudioBufferList>,
                             _ outPacketDescriptions: UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?,
                             _ context: UnsafeMutableRawPointer?) -> OSStatus {
    let reader = Unmanaged<Reader>.fromOpaque(context!).takeUnretainedValue()
    reader.releaseConverterInput()
    packetCount.pointee = 0
    outPacketDescriptions?.pointee = nil
    ioData.pointee.mBuffers.mData = nil
    ioData.pointee.mBuffers.mDataByteSize = 0

    guard let sourceFormat = reader.parser.dataFormat else {
        return ReaderMissingSourceFormatError
    }

    let isParsingComplete = reader.parser.isParsingComplete
    let packet = reader.parser.withPackets { packets -> (Data, AudioStreamPacketDescription?)? in
        let packetIndex = Int(reader.currentPacket)
        guard packetIndex < packets.count else { return nil }
        let packet = packets[packetIndex]
        reader.currentPacket += 1
        if packetIndex >= 256 {
            packets.removeFirst(256)
            reader.currentPacket -= 256
        }
        return packet
    }
    guard let packet else {
        return isParsingComplete ? ReaderReachedEndOfDataError : ReaderNotEnoughDataError
    }

    let data = packet.0
    let inputData = UnsafeMutableRawPointer.allocate(byteCount: max(data.count, 1), alignment: MemoryLayout<UInt8>.alignment)
    data.withUnsafeBytes { bytes in
        if let address = bytes.baseAddress {
            inputData.copyMemory(from: address, byteCount: data.count)
        }
    }
    reader.converterInputData = inputData
    ioData.pointee.mNumberBuffers = 1
    ioData.pointee.mBuffers.mData = inputData
    ioData.pointee.mBuffers.mDataByteSize = UInt32(data.count)
    ioData.pointee.mBuffers.mNumberChannels = sourceFormat.channelCount

    if sourceFormat.streamDescription.pointee.mFormatID != kAudioFormatLinearPCM,
       let outPacketDescriptions {
        let description = UnsafeMutablePointer<AudioStreamPacketDescription>.allocate(capacity: 1)
        description.initialize(to: AudioStreamPacketDescription(
            mStartOffset: 0,
            mVariableFramesInPacket: packet.1?.mVariableFramesInPacket ?? 0,
            mDataByteSize: UInt32(data.count)))
        reader.converterInputDescription = description
        outPacketDescriptions.pointee = description
    }
    packetCount.pointee = 1
    return noErr
}
