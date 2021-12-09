//
//  ReaderError.swift
//  AudioStreamer
//
//  Created by Syed Haris Ali on 1/6/18.
//  Copyright © 2018 Ausome Apps LLC. All rights reserved.
//

import Foundation
import AudioToolbox

// MARK: - Reader OSStatus Error Codes

let ReaderReachedEndOfDataError: OSStatus = 932332581
let ReaderNotEnoughDataError: OSStatus = 932332582
let ReaderMissingSourceFormatError: OSStatus = 932332583

// MARK: - ReaderError

public enum ReaderError: LocalizedError {
    case cannotLockQueue
    case converterFailed(OSStatus)
    case failedToCreateDestinationFormat
    case failedToCreatePCMBuffer
    case notEnoughData
    case parserMissingDataFormat
    case reachedEndOfFile
    case unableToCreateConverter(OSStatus)
    
    public var errorDescription: String? {
        switch self {
        case .cannotLockQueue:
            return "Failed to lock queue"
        case .converterFailed(let status):
            return localizedDescriptionFromConverterError(status)
        case .failedToCreateDestinationFormat:
            return "Failed to create a destination (processing) format"
        case .failedToCreatePCMBuffer:
            return "Failed to create PCM buffer for reading data"
        case .notEnoughData:
            return "Not enough data for read-conversion operation"
        case .parserMissingDataFormat:
            return "Parser is missing a valid data format"
        case .reachedEndOfFile:
            return "Reached the end of the file"
        case .unableToCreateConverter(let status):
            return localizedDescriptionFromConverterError(status)
        }
    }
    
    func localizedDescriptionFromConverterError(_ status: OSStatus) -> String {
        switch status {
        case kAudioConverterErr_FormatNotSupported:
            return "Format not supported"
        case kAudioConverterErr_OperationNotSupported:
            return "Operation not supported"
        case kAudioConverterErr_PropertyNotSupported:
            return "Property not supported"
        case kAudioConverterErr_InvalidInputSize:
            return "Invalid input size"
        case kAudioConverterErr_InvalidOutputSize:
            return "Invalid output size"
        case kAudioConverterErr_BadPropertySizeError:
            return "Bad property size error"
        case kAudioConverterErr_RequiresPacketDescriptionsError:
            return "Requires packet descriptions"
        case kAudioConverterErr_InputSampleRateOutOfRange:
            return "Input sample rate out of range"
        case kAudioConverterErr_OutputSampleRateOutOfRange:
            return "Output sample rate out of range"
#if os(iOS)
        case kAudioConverterErr_HardwareInUse:
            return "Hardware is in use"
        case kAudioConverterErr_NoHardwarePermission:
            return "No hardware permission"
#endif
        default:
            return "Unspecified error"
        }
    }
}
