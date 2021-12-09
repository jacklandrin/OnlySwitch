//
//  ParserError.swift
//  AudioStreamer
//
//  Created by Syed Haris Ali on 1/6/18.
//  Copyright © 2018 Ausome Apps LLC. All rights reserved.
//

import Foundation
import AudioToolbox

/// Possible errors that can result from the `Parser` class.
///
/// - streamCouldNotOpen: The file stream could not be opened. This will only occur if the underlying `AudioFileStreamOpen` method fails.
/// - failedToParseBytes: The parser failed to parse the raw bytes. This will contain an OSStatus that is the return value from the AudioFileParseBytes method that emitted this error.
public enum ParserError: LocalizedError {
    case streamCouldNotOpen
    case failedToParseBytes(OSStatus)
    
    public var errorDescription: String? {
        switch self {
        case .streamCouldNotOpen:
            return "Could not open stream for parsing"
        case .failedToParseBytes(let status):
            return localizedDescriptionFromParseError(status)
        }
    }
    
    func localizedDescriptionFromParseError(_ status: OSStatus) -> String {
        switch status {
        case kAudioFileStreamError_UnsupportedFileType:
            return "The file type is not supported"
        case kAudioFileStreamError_UnsupportedDataFormat:
            return "The data format is not supported by this file type"
        case kAudioFileStreamError_UnsupportedProperty:
            return "The property is not supported"
        case kAudioFileStreamError_BadPropertySize:
            return "The size of the property data was not correct"
        case kAudioFileStreamError_NotOptimized:
            return "It is not possible to produce output packets because the file's packet table or other defining"
        case kAudioFileStreamError_InvalidPacketOffset:
            return "A packet offset was less than zero, or past the end of the file,"
        case kAudioFileStreamError_InvalidFile:
            return "The file is malformed, or otherwise not a valid instance of an audio file of its type, or is not recognized as an audio file"
        case kAudioFileStreamError_ValueUnknown:
            return "The property value is not present in this file before the audio data"
        case kAudioFileStreamError_DataUnavailable:
            return "The amount of data provided to the parser was insufficient to produce any result"
        case kAudioFileStreamError_IllegalOperation:
            return "An illegal operation was attempted"
        default:
            return "An unspecified error occurred"
        }
    }
}
