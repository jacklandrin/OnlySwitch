//
//  Parser.swift
//  AudioStreamer
//
//  Created by Syed Haris Ali on 1/6/18.
//  Copyright © 2018 Ausome Apps LLC. All rights reserved.
//

import Foundation
import AVFoundation
import os.log

/// The `Parser` is a concrete implementation of the `Parsing` protocol used to convert binary data into audio packet data. This class uses the Audio File Stream Services to progressively parse the properties and packets of the incoming audio data.
public class Parser: Parsing {
    static let logger = OSLog(subsystem: "com.fastlearner.streamer", category: "Parser")
    static let loggerPacketCallback = OSLog(subsystem: "com.fastlearner.streamer", category: "Parser.Packets")
    static let loggerPropertyListenerCallback = OSLog(subsystem: "com.fastlearner.streamer", category: "Parser.PropertyListener")
    
    // MARK: - Parsing props
    
    // Protect packet storage and parser metadata on the download and playback threads.
    private let stateLock = NSLock()
    private let parseLock = NSLock()
    private var storedDataFormat: AVAudioFormat?
    private var storedPackets = [(Data, AudioStreamPacketDescription?)]()
    private var storedFrameCount: UInt64 = 0
    private var storedPacketCount: UInt64 = 0

    private func withState<Result>(_ body: () -> Result) -> Result {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }

    public internal(set) var dataFormat: AVAudioFormat? {
        get { withState { storedDataFormat } }
        set { withState { storedDataFormat = newValue } }
    }
    public var packets: [(Data, AudioStreamPacketDescription?)] {
        get { withState { storedPackets } }
        set { withState { storedPackets = newValue } }
    }
    public func withPackets<Result>(_ body: (inout [(Data, AudioStreamPacketDescription?)]) -> Result) -> Result {
        withState { body(&storedPackets) }
    }
    public var totalPacketCount: AVAudioPacketCount? {
        withState {
            guard storedDataFormat != nil else { return nil }
            return max(AVAudioPacketCount(storedPacketCount), AVAudioPacketCount(storedPackets.count))
        }
    }
    
    // MARK: - Properties
    
    /// A `UInt64` corresponding to the total frame count parsed by the Audio File Stream Services
    public internal(set) var frameCount: UInt64 {
        get { withState { storedFrameCount } }
        set { withState { storedFrameCount = newValue } }
    }
    
    /// A `UInt64` corresponding to the total packet count parsed by the Audio File Stream Services
    public internal(set) var packetCount: UInt64 {
        get { withState { storedPacketCount } }
        set { withState { storedPacketCount = newValue } }
    }
    
    /// The `AudioFileStreamID` used by the Audio File Stream Services for converting the binary data into audio packets
    fileprivate var streamID: AudioFileStreamID?
    
    // MARK: - Lifecycle
    
    /// Initializes an instance of the `Parser`
    ///
    /// - Throws: A `ParserError.streamCouldNotOpen` meaning a file stream instance could not be opened
    public init() throws {
        let context = unsafeBitCast(self, to: UnsafeMutableRawPointer.self)
        guard AudioFileStreamOpen(context, ParserPropertyChangeCallback, ParserPacketCallback, kAudioFileMP3Type, &streamID) == noErr else {
            throw ParserError.streamCouldNotOpen
        }
    }

    deinit {
        if let streamID { AudioFileStreamClose(streamID) }
    }
    
    // MARK: - Methods
    
    public func parse(data: Data) throws {
        guard !data.isEmpty else { return }
        parseLock.lock()
        defer { parseLock.unlock() }
//        os_log("%@ - %d", log: Parser.logger, type: .debug, #function, #line)
        
        let streamID = self.streamID!
        let count = data.count
        _ = try data.withUnsafeBytes { bytes in
//            guard let bytes = bytes as? UnsafeRawPointer else {return}
            let unsafeBufferPointer = bytes.bindMemory(to: UInt8.self)
            let unsafePointer = unsafeBufferPointer.baseAddress!
            let result = AudioFileStreamParseBytes(streamID, UInt32(count), unsafePointer, [])
            guard result == noErr else {
                os_log("Failed to parse bytes", log: Parser.logger, type: .error)
                throw ParserError.failedToParseBytes(result)
            }
        }
    }

}
