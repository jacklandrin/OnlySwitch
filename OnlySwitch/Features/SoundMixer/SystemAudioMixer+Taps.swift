import AudioToolbox
import CoreAudio
import CSoundMixerEQ
import Darwin
import SoundMixerEQ

@available(macOS 14.4, *)
extension SystemAudioMixer {
    nonisolated static func makeAppTap(pid: pid_t, processObjectIDs: [AudioObjectID], gain: Float,
                                               settings: EqualizerSettings, outputs: [SoundMixerService.OutputEndpoint],
                                               outputSignature: Int) -> AppTap? {
        let description = CATapDescription(stereoMixdownOfProcesses: processObjectIDs.map { $0 })
        description.muteBehavior = .muted
        description.name = "OnlySwitch-audio-\(pid)"
        description.isPrivate = true
        var tapID = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr, tapID != kAudioObjectUnknown else { return nil }
        guard let tapUID = stringProperty(kAudioTapPropertyUID, of: tapID),
              let outputUID = outputs.first?.device.id,
              let format = tapFormat(of: tapID), supported(format) else {
            AudioHardwareDestroyProcessTap(tapID); return nil
        }
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "OnlySwitch Audio \(pid)",
            kAudioAggregateDeviceUIDKey: "com.onlyswitch.audio.\(pid).\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: outputs.enumerated().map { index, endpoint in
                [kAudioSubDeviceUIDKey: endpoint.device.id, kAudioSubDeviceDriftCompensationKey: index == 0 ? 0 : 1] as [String: Any]
            },
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: tapUID]],
        ]
        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID) == noErr,
              aggregateID != kAudioObjectUnknown else { AudioHardwareDestroyProcessTap(tapID); return nil }
        // An output device can also expose a microphone. Never interpret those hardware
        // input channels as the process tap or accidentally play them through the speakers.
        guard let inputFormat = stereoInputFormat(aggregateID),
              let layout = outputLayout(aggregateID, selected: outputs, sampleRate: inputFormat.mSampleRate),
              let state = layout.ranges.withUnsafeBufferPointer({
                  OSEQCreateRouted(inputFormat.mSampleRate, 2, $0.baseAddress, UInt32($0.count), UInt32(layout.channelCount))
              }) else {
            AudioHardwareDestroyAggregateDevice(aggregateID); AudioHardwareDestroyProcessTap(tapID); return nil
        }
        OSEQSetGain(state, gain)
        EqualizerDSP.publish(settings, sampleRate: inputFormat.mSampleRate, to: state)
        var procID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) { _, input, _, output, _ in
            OSEQProcessAudioBuffers(state, input, output)
        }
        guard status == noErr, let procID else {
            retire(state); AudioHardwareDestroyAggregateDevice(aggregateID); AudioHardwareDestroyProcessTap(tapID); return nil
        }
        guard AudioDeviceStart(aggregateID, procID) == noErr else {
            retire(state); AudioDeviceDestroyIOProcID(aggregateID, procID)
            AudioHardwareDestroyAggregateDevice(aggregateID); AudioHardwareDestroyProcessTap(tapID); return nil
        }
        return AppTap(tapID: tapID, aggregateID: aggregateID, procID: procID, state: state,
                      processSignature: signature(of: processObjectIDs), outputSignature: outputSignature,
                      sampleRate: inputFormat.mSampleRate)
    }

    private nonisolated static func supported(_ format: AudioStreamBasicDescription) -> Bool {
        format.mFormatID == kAudioFormatLinearPCM && format.mFormatFlags & kAudioFormatFlagIsFloat != 0
        && format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0 && format.mBitsPerChannel == 32
        && format.mChannelsPerFrame == 2 && format.mSampleRate.isFinite && format.mSampleRate > 0
        && format.mBytesPerFrame == (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0 ? 4 : 8)
    }

    /// Accept only an unambiguous stereo tap input. Full-duplex devices whose hardware inputs
    /// are included in the aggregate fail setup and retain their original audio routing.
    private nonisolated static func stereoInputFormat(_ device: AudioObjectID) -> AudioStreamBasicDescription? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                 mScope: kAudioDevicePropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioBufferList>.size else { return nil }
        let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, storage) == noErr else { return nil }
        let list = storage.assumingMemoryBound(to: AudioBufferList.self)
        let count = Int(list.pointee.mNumberBuffers)
        guard count > 0, count <= 2,
              Int(size) >= MemoryLayout<AudioBufferList>.size + (count - 1) * MemoryLayout<AudioBuffer>.size else { return nil }
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        guard buffers.allSatisfy({ $0.mNumberChannels > 0 }),
              buffers.reduce(0, { $0 + $1.mNumberChannels }) == 2 else { return nil }
        address.mSelector = kAudioDevicePropertyStreamFormat
        var format = AudioStreamBasicDescription()
        size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &format) == noErr,
              supported(format) else { return nil }
        return format
    }

    /// Confirm the actual active-subdevice order and aggregate streams before freezing the C map.
    /// A list with the right total but unknown device ordering is not enough to safely fan out.
    private nonisolated static func outputLayout(_ aggregate: AudioObjectID,
                                                  selected: [SoundMixerService.OutputEndpoint],
                                                  sampleRate: Double) -> (ranges: [OSEQOutputRange], channelCount: Int)? {
        guard !selected.isEmpty, selected.count <= 16,
              let active = objectList(kAudioAggregateDevicePropertyActiveSubDeviceList, of: aggregate,
                                      scope: kAudioObjectPropertyScopeGlobal), active.count == selected.count else { return nil }
        var ranges: [OSEQOutputRange] = []
        var total = 0
        var seen = Set<String>()
        for id in active {
            guard let uid = stringProperty(kAudioDevicePropertyDeviceUID, of: id),
                  let endpoint = selected.first(where: { $0.objectID == id && $0.device.id == uid }),
                  seen.insert(uid).inserted, (1...64).contains(endpoint.device.channelCount) else { return nil }
            ranges.append(OSEQOutputRange(firstChannel: UInt32(total), channelCount: UInt32(endpoint.device.channelCount)))
            total += endpoint.device.channelCount
        }
        guard total > 0, total <= 1024 else { return nil }
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                 mScope: kAudioDevicePropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(aggregate, &address, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioBufferList>.size, size <= 65_536 else { return nil }
        let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        guard AudioObjectGetPropertyData(aggregate, &address, 0, nil, &size, storage) == noErr else { return nil }
        let list = storage.assumingMemoryBound(to: AudioBufferList.self)
        let count = Int(list.pointee.mNumberBuffers)
        guard count > 0, count <= 1024,
              Int(size) >= MemoryLayout<AudioBufferList>.size + (count - 1) * MemoryLayout<AudioBuffer>.size else { return nil }
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        guard buffers.allSatisfy({ (1...64).contains($0.mNumberChannels) }),
              buffers.reduce(0, { $0 + Int($1.mNumberChannels) }) == total,
              let streams = objectList(kAudioDevicePropertyStreams, of: aggregate, scope: kAudioDevicePropertyScopeOutput),
              !streams.isEmpty else { return nil }
        var streamChannels = 0
        for stream in streams {
            address = AudioObjectPropertyAddress(mSelector: kAudioStreamPropertyVirtualFormat,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
            var format = AudioStreamBasicDescription()
            size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            guard AudioObjectGetPropertyData(stream, &address, 0, nil, &size, &format) == noErr,
                  format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                  format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0, format.mBitsPerChannel == 32,
                  (1...64).contains(format.mChannelsPerFrame), format.mSampleRate == sampleRate,
                  format.mBytesPerFrame == (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
                    ? 4 : 4 * format.mChannelsPerFrame) else { return nil }
            streamChannels += Int(format.mChannelsPerFrame)
        }
        guard streamChannels == total else { return nil }
        return (ranges, total)
    }

    private nonisolated static func objectList(_ selector: AudioObjectPropertySelector, of object: AudioObjectID,
                                               scope: AudioObjectPropertyScope) -> [AudioObjectID]? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr,
              size > 0, size <= 65_536 else { return nil }
        var result = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard !result.isEmpty, AudioObjectGetPropertyData(object, &address, 0, nil, &size, &result) == noErr else { return nil }
        return result
    }

    nonisolated static func sampleRate(of device: AudioObjectID) -> Double? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var rate: Double = 0
        var size = UInt32(MemoryLayout<Double>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &rate) == noErr, rate.isFinite, rate > 0 else { return nil }
        return rate
    }

    nonisolated static func teardown(_ tap: AppTap) {
        retire(tap.state)
        AudioDeviceStop(tap.aggregateID, tap.procID)
        AudioDeviceDestroyIOProcID(tap.aggregateID, tap.procID)
        AudioHardwareDestroyAggregateDevice(tap.aggregateID)
        AudioHardwareDestroyProcessTap(tap.tapID)
    }
    private nonisolated static func retire(_ state: OpaquePointer) {
        OSEQRetire(state)
        retiredStatesLock.lock(); retiredStates.append(state); retiredStatesLock.unlock()
    }
}
