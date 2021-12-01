//
//  NSSound_SystemVolumeExtension.swift
//
//  Created by Marco Binder on 02.01.20.
//
//  based on:
//  ISSoundAdditions.m (ver 1.2 - 2012.10.27)
//
//    Created by Massimo Moiso (2012-09) InerziaSoft
//    based on an idea of Antonio Nunes, SintraWorks
//
// Permission is granted free of charge to use this code without restriction
// and without limitation, with the only condition that the copyright
// notice and this permission shall be included in all copies.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.


import CoreAudioKit


extension NSSound {
    
    //
    // PUBLIC INTERFACE
    // to be swifty, public interface is mostly gettable-settable properties,
    // only few convenience functions
    //
    
    
    // managing the system volume by setting "systemVolume" property (Float between 0 and 1.0)
    public static var systemVolume: Float {
        get {return self.getSystemVolume()}
        set {self.setSystemVolume(theVolume:newValue)}
    }
    
    // getting and setting the "mute" state of the system volume
    // note convenience function "systemVolumeFadeToMute(seconds:Float)" to fade out to mute
    public static var systemVolumeIsMuted: Bool {
        get {return self.getSystemVolumeIsMuted()}
        set {self.systemVolumeSetMuted(newValue)}
    }
    
    // convenience function to fade system volume out to mute over (Float) seconds
    // NOTE: blocking specifies if function returns immediately or only after muting completed!
    // If blocking = false the task will be scheduled in a global queue for asynchronous execution
    // by GDC– any manual volume control while fading out will be overridden! Can be desired or not...
    public class func systemVolumeFadeToMute(seconds: Float = 3, blocking: Bool = true) {
        // return if already muted
        if systemVolumeIsMuted {return}

        if blocking {fadeSystemVolumeToMutePrivate(seconds: seconds)}
        else {DispatchQueue.global().async {self.fadeSystemVolumeToMutePrivate(seconds: seconds)} }
    }
    
    
    
    
    
    
    
    
    
    
    
    //
    // PRIVATE INTERFACE
    // these functions cannot be called publicly but are for internal use only!
    // C-centric CoreAudioKit is hidden behind the above swifty public interface
    //
    
    
    
    //    Return the ID of the default audio device; this is a C routine
    //
    //    IN:        none
    //    OUT:    the ID of the default device or AudioObjectUnknown
    //
    private class func obtainDefaultOutputDevice() -> AudioDeviceID
    {
        var  theAnswer : AudioDeviceID = kAudioObjectUnknown
        var  theSize = UInt32(MemoryLayout.size(ofValue: theAnswer)) // needs to be converted to UInt32?
        var  theAddress : AudioObjectPropertyAddress
            
        theAddress = AudioObjectPropertyAddress.init(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        
        //first be sure that a default device exists
        if (!AudioObjectHasProperty(AudioObjectID(kAudioObjectSystemObject), &theAddress) )    {
            print("Unable to get default audio device")
            return theAnswer
        }
        
        //get the property 'default output device'
        let theError : OSStatus = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &theAddress, UInt32(0), nil, &theSize, &theAnswer)
        if (theError != noErr) {
            print("Unable to get output audio device")
            return theAnswer
        }
        return theAnswer
    }


    //
    //    Return the system sound volume as a float in the range [0...1]
    //
    //    IN:        none
    //    OUT:    (float) the volume of the default device
    //
    private class func getSystemVolume() -> Float
    {
        var defaultDevID: AudioDeviceID = kAudioObjectUnknown
        var theSize = UInt32(MemoryLayout.size(ofValue: defaultDevID))
        var theError: OSStatus
        var theVolume: Float32 = 0
        var theAddress: AudioObjectPropertyAddress
        
        defaultDevID = obtainDefaultOutputDevice()
        if (defaultDevID == kAudioObjectUnknown) {
            print("Audio device not found!")
            return 0.0
        }        //device not found: return 0
        
        theAddress = AudioObjectPropertyAddress.init(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        
        
        //be sure that the default device has the volume property
        if (!AudioObjectHasProperty(defaultDevID, &theAddress) ) {
            print("No volume control for device 0x%0x",defaultDevID)
            return 0.0
        }
        
        //now read the property and correct it, if outside [0...1]
        theError = AudioObjectGetPropertyData(defaultDevID, &theAddress, 0, nil, &theSize, &theVolume)
        if ( theError != noErr )    {
            print("Unable to read volume for device 0x%0x", defaultDevID)
            return 0.0
        }
        
        theVolume = theVolume > 1.0 ? 1.0 : (theVolume < 0.0 ? 0.0 : theVolume)
        
        return theVolume
    }

    
    
    //
    //    Set the volume of the default device
    //
    //    IN:        (float)the new volume
    //    OUT:    none
    //
    private class func setSystemVolume(theVolume: Float, muteOff: Bool = true)
    {
        var newValue: Float = theVolume
        var theAddress: AudioObjectPropertyAddress
        var defaultDevID: AudioDeviceID
        var theError: OSStatus = noErr
        var muted: UInt32
        var canSetVol: DarwinBoolean = true
        var muteValue: Bool
        var hasMute:Bool = true
        var canMute: DarwinBoolean = true
        
        defaultDevID = obtainDefaultOutputDevice()
        if (defaultDevID == kAudioObjectUnknown) {
            //device not found: return without trying to set
            print("Audio Device unknown")
            return
        }
        
        //check if the new value is in the correct range - normalize it if not
        newValue = theVolume > 1.0 ? 1.0 : (theVolume < 0.0 ? 0.0 : theVolume)
        if (newValue != theVolume) {
            print("Tentative volume (%5.2f) was out of range; reset to %5.2f", theVolume, newValue)
        }
        
        theAddress = AudioObjectPropertyAddress.init(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        
        //set the selector to mute or not by checking if under threshold (5% here)
        //and check if a mute command is available
        muteValue = (newValue < 0.05)
        if (muteValue) {
            theAddress.mSelector = kAudioDevicePropertyMute
            hasMute = AudioObjectHasProperty(defaultDevID, &theAddress)
            if (hasMute) {
                theError = AudioObjectIsPropertySettable(defaultDevID, &theAddress, &canMute)
                if (theError != noErr || !(canMute.boolValue))
                {
                    canMute = false
                    print("Should mute device 0x%0x but did not succeed",defaultDevID)
                }
            }
            else {canMute = false}
        } else {
            theAddress.mSelector = kAudioHardwareServiceDeviceProperty_VirtualMainVolume
        }
        
        // **** now manage the volume following the what we found ****
        
        //be sure the device has a volume command
        if (!AudioObjectHasProperty(defaultDevID, &theAddress)) {
            print("The device 0x%0x does not have a volume to set", defaultDevID)
            return
        }
        
        //be sure the device can set the volume
        theError = AudioObjectIsPropertySettable(defaultDevID, &theAddress, &canSetVol)
        if ( theError != noErr || !canSetVol.boolValue ) {
            print("The volume of device 0x%0x cannot be set", defaultDevID)
            return
        }
        
        //if under the threshold then mute it, only if possible - done/exit
        if (muteValue && hasMute && canMute.boolValue) {
            muted = 1
            theError = AudioObjectSetPropertyData(defaultDevID, &theAddress, 0, nil, UInt32(MemoryLayout.size(ofValue: muted)), &muted)
            
            if (theError != noErr) {
                print("The device 0x%0x was not muted",defaultDevID)
                return
            }
        } else {       //else set it
            theError = AudioObjectSetPropertyData(defaultDevID, &theAddress, 0, nil, UInt32(MemoryLayout.size(ofValue: newValue)), &newValue)
            if (theError != noErr) {
                print("The device 0x%0x was unable to set volume", defaultDevID)
            }
            //if device is able to handle muting, maybe it was muted, so unlock it
            if (muteOff && hasMute && canMute.boolValue) {
                theAddress.mSelector = kAudioDevicePropertyMute
                muted = 0
                theError = AudioObjectSetPropertyData(defaultDevID, &theAddress, 0, nil, UInt32(MemoryLayout.size(ofValue: muted)), &muted)
            }
        }
        if (theError != noErr) {
            print("Unable to set volume for device 0x%0x", defaultDevID)
        }
    }



    //
    //    IN:        (Boolean) if true the device is muted, false it is unmated
    //    OUT:        none
    //
    private class func systemVolumeSetMuted(_ m:Bool) {
        var defaultDevID: AudioDeviceID = kAudioObjectUnknown
        var theAddress: AudioObjectPropertyAddress
        var hasMute: Bool
        var canMute: DarwinBoolean = true
        var theError: OSStatus = noErr
        var muted: UInt32 = 0
        
        defaultDevID = obtainDefaultOutputDevice()
        if (defaultDevID == kAudioObjectUnknown) {
            //device not found
            print("Audio device unknown")
            return
        }
        
        theAddress = AudioObjectPropertyAddress.init(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)

        muted = m ? 1 : 0
        
        hasMute = AudioObjectHasProperty(defaultDevID, &theAddress)
        
        if (hasMute)
        {
            theError = AudioObjectIsPropertySettable(defaultDevID, &theAddress, &canMute)
            if (theError == noErr && canMute.boolValue)
            {
                theError = AudioObjectSetPropertyData(defaultDevID, &theAddress, 0, nil, UInt32(MemoryLayout.size(ofValue: muted)), &muted)
                if (theError != noErr) {
                    print("Cannot change mute status of device 0x%0x", defaultDevID)
                }
            }
        }
    }

    
    
    //
    //    IN:        (float) number of seconds during which volume is faded out to mute
    //    OUT:        none
    //
    private class func fadeSystemVolumeToMutePrivate(seconds:Float) {

        // prevent muting times longer than 10 seconds
        var secs = (seconds > 0) ? seconds : (seconds*(-1.0))
        secs = (secs > 10.0) ? 10.0 : secs

        let currentVolume = self.systemVolume
        let delta = currentVolume / (seconds*2)
        var secondsLeft = secs
        
        while (secondsLeft > 0) {
            self.systemVolume -= delta
            Thread.sleep(forTimeInterval: 0.5)
            secondsLeft -= 0.5
        }
        systemVolumeIsMuted = true
        setSystemVolume(theVolume: currentVolume, muteOff: false)
    }

    
    //
    //    IN:        none
    //    OUT:       (Bool) state of system mute (NOTE: this is different from system volume = 0!
    //
    private class func getSystemVolumeIsMuted() -> Bool
    {
        var defaultDevID: AudioDeviceID = kAudioObjectUnknown
        var theAddress: AudioObjectPropertyAddress
        var hasMute: Bool
        var canMute: DarwinBoolean = true
        var theError: OSStatus = noErr
        var muted: UInt32 = 0
        var mutedSize = UInt32(MemoryLayout.size(ofValue: muted))
        
        defaultDevID = obtainDefaultOutputDevice()
        if (defaultDevID == kAudioObjectUnknown) {
            //device not found
            print("Audio device unknown")
            return false                       // works, but not the best return code for this
        }
        
        theAddress = AudioObjectPropertyAddress.init(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        
        hasMute = AudioObjectHasProperty(defaultDevID, &theAddress)
        
        if (hasMute) {
            theError = AudioObjectIsPropertySettable(defaultDevID, &theAddress, &canMute)
            if (theError == noErr && canMute.boolValue) {
                theError = AudioObjectGetPropertyData(defaultDevID, &theAddress, 0, nil, &mutedSize, &muted)
                if (muted != 0) {
                    return true
                }
            }
        }
        return false
    }

}
