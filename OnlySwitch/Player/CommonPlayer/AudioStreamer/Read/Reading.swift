//
//  Reading.swift
//  AudioStreamer
//
//  Created by Syed Haris Ali on 1/6/18.
//  Copyright © 2018 Ausome Apps LLC. All rights reserved.
//

import Foundation
import AVFoundation

/// The `Reading` protocol provides an interface for defining the behavior we expect of an audio data provider in the context of an engine (`AVAudioEngine`) or graph (`AUGraph`).
public protocol Reading {
    
    /// An `AVAudioPacketCount` representing the current packet index position. Reads are done relative to this position.
    var currentPacket: AVAudioPacketCount { get }
    
    /// A `Parseable` used to read the parsed audio packets. The `Reading` handles converting compressed packets to a LPCM format a graph or engine can use (similar to `AVAudioFile`'s common format)
    var parser: Parsing { get }
    
    /// An `AVAudioFormat` representing the target audio format that the audio data should be converted to for read operations.
    var readFormat: AVAudioFormat { get }
    
    /// Initializes an instance of a `Reading` using a `Parseable` to provide audio packets and an `AVAudioFormat` representing the expected read format needed by the `read(frames:)` method.
    ///
    /// - Parameters:
    ///   - parser: A `Parseable` that has handled parsing binary audio data to audio packets.
    ///   - readFormat: An `AVAudioFormat` of the target audio format that the read method should provide.
    init(parser: Parsing, readFormat: AVAudioFormat) throws
    
    /// Reads the number of frames into a LPCM format. This method should take care of doing any necessary format conversion under the hood.
    ///
    /// - Parameter frames: An `AVAudioFrameCount` representing the total number of
    
    
    /// Reads the number of frames into a LPCM format. This method should take care of doing any necessary format conversion under the hood.
    ///
    /// - Parameter frames: An `AVAudioFrameCount` representing the total number of audio frames to read. The format of the target audio frames should match the input `readFormat` in the `init(parser:,readFormat:)` initializer.
    /// - Throws: A error representing an issue with the read operation.
    func read(_ frames: AVAudioFrameCount) throws -> AVAudioPCMBuffer
    
    /// Should change the current position of the read index to match the packet provided. This effectively performs a seek operation, but should be done in a thread-safe way.
    ///
    /// - Parameter packet: An `AVAudioPacketCount` representing the packet index.
    /// - Throws: A error representing an issue with the seek operation.
    func seek(_ packet: AVAudioPacketCount) throws
}
