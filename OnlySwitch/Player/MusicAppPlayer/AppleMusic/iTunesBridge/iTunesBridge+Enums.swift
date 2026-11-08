import AppKit
import ScriptingBridge

// MARK: iTunesEKnd
@objc public enum iTunesEKnd : AEKeyword {
    case trackListing = 0x6b54726b /* 'kTrk' */
    case albumListing = 0x6b416c62 /* 'kAlb' */
    case cdInsert = 0x6b434469 /* 'kCDi' */
}

// MARK: iTunesEnum
@objc public enum iTunesEnum : AEKeyword {
    case standard = 0x6c777374 /* 'lwst' */
    case detailed = 0x6c776474 /* 'lwdt' */
}

// MARK: iTunesEPlS
@objc public enum iTunesEPlS : AEKeyword {
    case stopped = 0x6b505353 /* 'kPSS' */
    case playing = 0x6b505350 /* 'kPSP' */
    case paused = 0x6b505370 /* 'kPSp' */
    case fastForwarding = 0x6b505346 /* 'kPSF' */
    case rewinding = 0x6b505352 /* 'kPSR' */
}

// MARK: iTunesERpt
@objc public enum iTunesERpt : AEKeyword {
    case off = 0x6b52704f /* 'kRpO' */
    case one = 0x6b527031 /* 'kRp1' */
    case all = 0x6b416c6c /* 'kAll' */
}

// MARK: iTunesEShM
@objc public enum iTunesEShM : AEKeyword {
    case songs = 0x6b536853 /* 'kShS' */
    case albums = 0x6b536841 /* 'kShA' */
    case groupings = 0x6b536847 /* 'kShG' */
}

// MARK: iTunesEVSz
@objc public enum iTunesEVSz : AEKeyword {
    case small = 0x6b565353 /* 'kVSS' */
    case medium = 0x6b56534d /* 'kVSM' */
    case large = 0x6b56534c /* 'kVSL' */
}

// MARK: iTunesESrc
@objc public enum iTunesESrc : AEKeyword {
    case library = 0x6b4c6962 /* 'kLib' */
    case iPod = 0x6b506f64 /* 'kPod' */
    case audioCD = 0x6b414344 /* 'kACD' */
    case mp3CD = 0x6b4d4344 /* 'kMCD' */
    case radioTuner = 0x6b54756e /* 'kTun' */
    case sharedLibrary = 0x6b536864 /* 'kShd' */
    case iTunesStore = 0x6b495453 /* 'kITS' */
    case unknown = 0x6b556e6b /* 'kUnk' */
}

// MARK: iTunesESrA
@objc public enum iTunesESrA : AEKeyword {
    case albums = 0x6b53724c /* 'kSrL' */
    case all = 0x6b416c6c /* 'kAll' */
    case artists = 0x6b537252 /* 'kSrR' */
    case composers = 0x6b537243 /* 'kSrC' */
    case displayed = 0x6b537256 /* 'kSrV' */
    case songs = 0x6b537253 /* 'kSrS' */
}

// MARK: iTunesESpK
@objc public enum iTunesESpK : AEKeyword {
    case none = 0x6b4e6f6e /* 'kNon' */
    case books = 0x6b537041 /* 'kSpA' */
    case folder = 0x6b537046 /* 'kSpF' */
    case genius = 0x6b537047 /* 'kSpG' */
    case iTunesU = 0x6b537055 /* 'kSpU' */
    case library = 0x6b53704c /* 'kSpL' */
    case movies = 0x6b537049 /* 'kSpI' */
    case music = 0x6b53705a /* 'kSpZ' */
    case podcasts = 0x6b537050 /* 'kSpP' */
    case purchasedMusic = 0x6b53704d /* 'kSpM' */
    case tvShows = 0x6b537054 /* 'kSpT' */
}

// MARK: iTunesEMdK
@objc public enum iTunesEMdK : AEKeyword {
    case alertTone = 0x6b4d644c /* 'kMdL' */
    case audiobook = 0x6b4d6441 /* 'kMdA' */
    case book = 0x6b4d6442 /* 'kMdB' */
    case homeVideo = 0x6b4d6448 /* 'kMdH' */
    case iTunesU = 0x6b4d6449 /* 'kMdI' */
    case movie = 0x6b4d644d /* 'kMdM' */
    case music = 0x6b4d6453 /* 'kMdS' */
    case musicVideo = 0x6b4d6456 /* 'kMdV' */
    case podcast = 0x6b4d6450 /* 'kMdP' */
    case ringtone = 0x6b4d6452 /* 'kMdR' */
    case tvShow = 0x6b4d6454 /* 'kMdT' */
    case voiceMemo = 0x6b4d644f /* 'kMdO' */
    case unknown = 0x6b556e6b /* 'kUnk' */
}

// MARK: iTunesEVdK
@objc public enum iTunesEVdK : AEKeyword {
    case none = 0x6b4e6f6e /* 'kNon' */
    case homeVideo = 0x6b566448 /* 'kVdH' */
    case movie = 0x6b56644d /* 'kVdM' */
    case musicVideo = 0x6b566456 /* 'kVdV' */
    case tvShow = 0x6b566454 /* 'kVdT' */
}

// MARK: iTunesERtK
@objc public enum iTunesERtK : AEKeyword {
    case user = 0x6b527455 /* 'kRtU' */
    case computed = 0x6b527443 /* 'kRtC' */
}

// MARK: iTunesEAPD
@objc public enum iTunesEAPD : AEKeyword {
    case computer = 0x6b415043 /* 'kAPC' */
    case airPortExpress = 0x6b415058 /* 'kAPX' */
    case appleTV = 0x6b415054 /* 'kAPT' */
    case airPlayDevice = 0x6b41504f /* 'kAPO' */
    case unknown = 0x6b415055 /* 'kAPU' */
}

// MARK: iTunesEClS
@objc public enum iTunesEClS : AEKeyword {
    case unknown = 0x6b556e6b /* 'kUnk' */
    case purchased = 0x6b507572 /* 'kPur' */
    case matched = 0x6b4d6174 /* 'kMat' */
    case uploaded = 0x6b55706c /* 'kUpl' */
    case ineligible = 0x6b52656a /* 'kRej' */
    case removed = 0x6b52656d /* 'kRem' */
    case error = 0x6b457272 /* 'kErr' */
    case duplicate = 0x6b447570 /* 'kDup' */
    case subscription = 0x6b537562 /* 'kSub' */
    case noLongerAvailable = 0x6b526576 /* 'kRev' */
    case notUploaded = 0x6b557050 /* 'kUpP' */
}
